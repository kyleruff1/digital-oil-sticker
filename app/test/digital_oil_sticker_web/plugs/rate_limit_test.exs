defmodule DigitalOilStickerWeb.Plugs.RateLimitTest do
  @moduledoc """
  Per-IP HTTP rate limiting, asserted as a plug in isolation
  (DOS-M09-007 FR-8, FR-10, AC-6, INV-26).

  Two failure modes matter here, in opposite directions. A limit that never
  trips is not a limit — a scraper drains the catalog and the "mitigation"
  never noticed. A limit that trips on the wrong key trips on everyone:
  bucket the whole internet under one shared identity (the Fly proxy's IP,
  or a forwarded header the plug believed off-Fly) and one caller's burst
  locks every real user out.

  The plug is exercised directly through `call/2` rather than through the
  endpoint. Wiring is asserted elsewhere; here the point is the arithmetic
  and the keying, both of which have to be exactly right or the control is
  either theatre or an outage.

  ## What these tests do — and do not — inject

  The plug reads its limits from application env at call time (`resolve/1`),
  so each test overrides that env inline for the shape it needs — a tight
  bucket with essentially no refill for the "at the limit" cases, a small
  bucket with fast refill for the recovery case. That override is what
  makes the assertions load-bearing: without it, config/test.exs's
  `capacity: 1_000_000, refill_per_second: 1_000_000` would let every loop
  through and every assertion pass vacuously.

  Time is real. The plug calls `System.monotonic_time(:millisecond)`
  directly, so the recovery test sleeps rather than mocking a clock. Refill
  is tuned so that even Windows' coarse sleep granularity gives back
  multiple tokens' worth of credit, and the "at the limit" tests use a
  refill of one token per 1000 seconds so that no test-scale delay between
  requests can silently top the bucket back up.

  The buckets live in the process-wide ETS table owned by
  `RateLimitStore`. `async: false` protects against cross-module traffic
  (test-env limits are huge, so those entries do not decide anything
  here), and the setup clears the specific keys this module uses so a
  rerun in the same BEAM does not carry state forward.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Plugs.{ClientIP, RateLimit, RateLimitStore}

  # Every IP this file exercises. Cleared in setup and on_exit so no run
  # inherits bucket state from an earlier one — the "N succeed" assertion
  # otherwise starts at (N - k) tokens and fails for a reason that has
  # nothing to do with the plug.
  #
  # All in TEST-NET-2 (198.51.100.0/24) or TEST-NET-3 (203.0.113.0/24) so
  # they cannot collide with `127.0.0.1` — the address every other test in
  # the suite hits the endpoint from — or with real routable space.
  @used_ips [
    {203, 0, 113, 1},
    {203, 0, 113, 2},
    {203, 0, 113, 7},
    {203, 0, 113, 9},
    {203, 0, 113, 20},
    {203, 0, 113, 21},
    {198, 51, 100, 1},
    {198, 51, 100, 2},
    {198, 51, 100, 10}
  ]

  setup do
    # AC-5 hinges on the off-Fly branch of ClientIP: with `FLY_APP_NAME`
    # unset, `fly-client-ip` is untrusted and `conn.remote_ip` decides the
    # key. Every test in this file wants that regime, because the plug is
    # being asserted against forged forwarded-headers and against distinct
    # `remote_ip` values.
    original_fly = System.get_env("FLY_APP_NAME")
    System.delete_env("FLY_APP_NAME")

    # Save whatever config/test.exs installed. Each test replaces it inline
    # with the shape it needs; on_exit restores.
    original_env = Application.get_env(:digital_oil_sticker, RateLimit)

    clear_buckets(@used_ips)

    on_exit(fn ->
      case original_env do
        nil -> Application.delete_env(:digital_oil_sticker, RateLimit)
        opts -> Application.put_env(:digital_oil_sticker, RateLimit, opts)
      end

      if original_fly,
        do: System.put_env("FLY_APP_NAME", original_fly),
        else: System.delete_env("FLY_APP_NAME")

      clear_buckets(@used_ips)
    end)

    :ok
  end

  # Build a conn with `remote_ip` set. Off-Fly (setup above), the client
  # key is derived from `remote_ip` alone, so a distinct `remote_ip` per
  # test is a distinct bucket.
  defp conn_from(ip, headers \\ []) do
    Enum.reduce(headers, %{Phoenix.ConnTest.build_conn() | remote_ip: ip}, fn {k, v}, acc ->
      Plug.Conn.put_req_header(acc, k, v)
    end)
  end

  # Drop the specific bucket entries this module writes to, so a rerun
  # starts each test at a full capacity rather than at whatever tokens
  # the previous run left behind.
  defp clear_buckets(ips) do
    table = RateLimitStore.table()

    for ip <- ips do
      key = ClientIP.client_key(conn_from(ip))
      :ets.delete(table, key)
    end
  end

  # Override the runtime config the plug reads on every `call/2`. Returns
  # freshly-initialised plug opts; init opts are validated but the runtime
  # override wins over them, so `init([])` is enough here.
  defp with_limits(capacity, refill_per_second) do
    Application.put_env(:digital_oil_sticker, RateLimit,
      capacity: capacity,
      refill_per_second: refill_per_second
    )

    RateLimit.init([])
  end

  describe "under the limit" do
    test "the first N requests from one client pass through" do
      # Refill of one token per 1000 seconds — effectively zero over the
      # microseconds this loop takes. Any pass here has to be spent tokens,
      # not silent top-ups.
      opts = with_limits(3, 0.001)

      # Same conn every time — same `remote_ip`, same key, same bucket. If
      # the plug keyed on something request-scoped (the request id, the
      # process it happens to run in) this loop would still pass while the
      # real deployment let every request through: the bucket would never
      # accumulate spend. The next test spends N+1 through the same
      # fixture, which is what makes this one meaningful.
      for i <- 1..3 do
        conn = RateLimit.call(conn_from({203, 0, 113, 1}), opts)

        refute conn.halted, "request ##{i} of 3 halted; the bucket should still have tokens"

        assert conn.status == nil,
               "request ##{i} sent a response; the plug should be pass-through"
      end
    end
  end

  describe "at the limit" do
    test "request N+1 from the same client is rejected with 429" do
      opts = with_limits(3, 0.001)

      # Spend the bucket. Refill contributes essentially zero tokens
      # between requests at 0.001/s, so the boundary is crisp.
      for _ <- 1..3, do: RateLimit.call(conn_from({203, 0, 113, 2}), opts)

      rejected = RateLimit.call(conn_from({203, 0, 113, 2}), opts)

      assert rejected.status == 429,
             "N+1 from the same key returned #{inspect(rejected.status)}; " <>
               "429 is what FR-10's temporary-limit UI state is derived from"

      assert rejected.halted,
             "the plug set 429 but did not halt the pipeline — the router and LiveView will still run"
    end

    test "the rejection body does not carry the client's address" do
      # INV-26 / FR-8: the whole point of hashing the IP is that it does
      # not leave memory. A 429 body that helpfully echoes "203.0.113.9 is
      # rate limited" undoes it on the one response most likely to be
      # captured verbatim in a bug report or a screenshot.
      opts = with_limits(3, 0.001)

      for _ <- 1..3, do: RateLimit.call(conn_from({203, 0, 113, 9}), opts)

      rejected = RateLimit.call(conn_from({203, 0, 113, 9}), opts)

      body = rejected.resp_body || ""

      refute body =~ "203.0.113.9",
             "the 429 response body contains the caller's IP: #{inspect(body)}"

      refute body =~ "203.0.113",
             "the 429 response body contains a fragment of the caller's IP: #{inspect(body)}"
    end
  end

  describe "across clients" do
    test "different IPs have independent buckets" do
      opts = with_limits(3, 0.001)

      # Drain client A entirely, then drive client B through a full N. If
      # the plug used a single shared bucket (a global counter, a key of
      # `:global`, or the Fly proxy IP because the trusted-proxy branch
      # was mis-selected) A's spend would leave B with two tokens instead
      # of three, and B's third request would 429.
      for _ <- 1..3, do: RateLimit.call(conn_from({198, 51, 100, 1}), opts)
      drained_a = RateLimit.call(conn_from({198, 51, 100, 1}), opts)
      assert drained_a.status == 429, "client A should be drained by now"

      for i <- 1..3 do
        conn = RateLimit.call(conn_from({198, 51, 100, 2}), opts)

        refute conn.halted,
               "client B request ##{i} halted while A was the one that spent the tokens — " <>
                 "the plug is not isolating buckets by client"
      end
    end
  end

  describe "over time" do
    test "after the refill interval the same client can send again" do
      # Bucket: capacity 2, 100 tokens/s → one token every 10 ms. A 60 ms
      # sleep gives back six tokens' worth of credit (capped at capacity),
      # which is well above the coarse Windows sleep granularity that
      # smaller intervals fall inside of.
      opts = with_limits(2, 100)

      for _ <- 1..2, do: RateLimit.call(conn_from({198, 51, 100, 10}), opts)

      # Prove the bucket is actually empty before the wait — the "after
      # refill" success below can then only be attributed to refill.
      drained = RateLimit.call(conn_from({198, 51, 100, 10}), opts)
      assert drained.status == 429, "expected the bucket to be empty before sleeping"

      Process.sleep(60)

      recovered = RateLimit.call(conn_from({198, 51, 100, 10}), opts)

      refute recovered.halted,
             "60 ms after the bucket drained (well past the 10 ms refill interval), " <>
               "the same client is still rejected — refill is either not running or is " <>
               "keyed off a clock the plug is not reading"

      assert recovered.status == nil
    end
  end

  describe "keying: what the plug treats as 'the same client'" do
    test "a spoofed forwarded-header off-Fly does not mint a fresh identity" do
      # AC-5. Off-Fly (setup deletes FLY_APP_NAME), `ClientIP` ignores
      # `fly-client-ip` because nothing is overwriting it — trusting it
      # here would let any caller send a different fake IP on every
      # request and walk straight through the limit. The plug reads the
      # client key through `ClientIP`, so it inherits that guarantee; this
      # test proves the inheritance is actually wired, not just claimed.
      opts = with_limits(3, 0.001)

      # Drain the bucket for `remote_ip = 203.0.113.7`.
      for _ <- 1..3, do: RateLimit.call(conn_from({203, 0, 113, 7}), opts)

      # Same `remote_ip`, but a forwarded header that claims to be
      # someone else entirely. Both `fly-client-ip` and `x-forwarded-for`
      # are set because the task language names the latter explicitly —
      # neither should shift the effective key off-Fly, because neither
      # is being overwritten by a trusted proxy.
      spoofed =
        conn_from({203, 0, 113, 7}, [
          {"fly-client-ip", "198.51.100.42"},
          {"x-forwarded-for", "198.51.100.99"}
        ])

      rejected = RateLimit.call(spoofed, opts)

      assert rejected.status == 429,
             "a forwarded header changed the plug's effective client key off-Fly — every " <>
               "caller can now cycle headers to defeat the limit. Got status " <>
               "#{inspect(rejected.status)}"

      assert rejected.halted
    end

    test "two clients that differ only in remote_ip are treated as distinct" do
      # The mirror of the previous test: the header does not decide the
      # key, but `remote_ip` does. If the plug ignored `remote_ip` too
      # (say, keying everyone under a constant off-Fly), the two clients
      # would share a bucket and this test would 429 in the second loop.
      opts = with_limits(3, 0.001)

      for _ <- 1..3, do: RateLimit.call(conn_from({203, 0, 113, 20}), opts)

      other =
        conn_from({203, 0, 113, 21}, [
          {"fly-client-ip", "198.51.100.42"}
        ])

      conn = RateLimit.call(other, opts)

      refute conn.halted,
             "a second client with a distinct remote_ip was rate-limited by the first client's " <>
               "spend — the plug is bucketing distinct IPs together"
    end
  end
end
