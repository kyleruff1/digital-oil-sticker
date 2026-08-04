defmodule DigitalOilStickerWeb.LiveBootRateLimitTest do
  @moduledoc """
  End-to-end proof that the endpoint plug chain enforces the per-IP HTTP rate
  limit on the initial LiveView boot GET (DOS-M09-007 AC-6, INV-26).

  ## Why this suite exists — the "wrong target" gap it patches

  `DigitalOilStickerWeb.Plugs.RateLimitTest` proves the rate-limit plug's
  arithmetic in isolation. `DigitalOilStickerWeb.SocketConnectLimitTest`
  proves the `ConnectLimiter` module's counter arithmetic in isolation.
  Neither of those, on their own, proves that anything on the LiveView boot
  path actually consults a limiter — a correct plug that the endpoint forgot
  to install, or a correct connect-limiter module with no caller, passes both
  suites unchanged while the real request path leaks.

  This suite hits the endpoint through `Phoenix.ConnTest.get/2`, which pumps
  a request through the full plug chain the deployment uses, and asserts
  that the plug refuses the (capacity + 1)-th request from the same client
  with the 429 the rate-limit plug produces. A missing or mis-ordered plug
  fails this test loudly; a plug that never runs on `"/"` (the LiveView
  boot route) fails it loudly; a plug that runs but does not decide fails
  it loudly.

  ## Relationship to AC-6-socket

  A WebSocket handshake to `"/live/websocket"` cannot happen without a CSRF
  token, and the CSRF token is minted only by the HTTP GET that renders the
  LiveView shell. Every real socket connect is therefore preceded by an HTTP
  GET through this chain, so throttling the boot GET throttles the socket
  connect at one remove. That is not the same as a per-client concurrent-
  connect ceiling on the socket itself (`ConnectLimiter` covers that shape,
  and its wiring into the socket path is deferred — see the moduledoc of
  `SocketConnectLimitTest`), but it is the layer of AC-6 that is actually
  wired today, and this suite is what proves the wiring is real.

  ## Test-config gymnastics

  `config/test.exs` sets the plug to `capacity: 1_000_000,
  refill_per_second: 1_000_000` so that the rest of the suite — every
  ConnCase test hitting `127.0.0.1` — does not share one drained bucket.
  Each test here overrides that inline to a shape the assertion needs
  (crisp boundary, negligible refill) and restores the suite-wide values
  on exit. `async: false` because the override is application-global.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Plugs.{ClientIP, RateLimit, RateLimitStore}

  # A LiveView route from the router. `/` is the sticker LiveView; the boot
  # GET renders its shell and returns the CSRF token any subsequent socket
  # connect would carry.
  @route "/"

  # TEST-NET-3 addresses so the buckets we drain here cannot collide with
  # `127.0.0.1` (the ConnCase default) or any real routable address.
  @client_ip {203, 0, 113, 77}
  @other_ip {203, 0, 113, 78}

  setup do
    # AC-5 branch: off-Fly, `fly-client-ip` is untrusted and `remote_ip`
    # decides the bucket. Setting a distinct `remote_ip` per test is what
    # gives each test a fresh bucket — see `RateLimitTest` for the same
    # regime.
    original_fly = System.get_env("FLY_APP_NAME")
    System.delete_env("FLY_APP_NAME")

    original_env = Application.get_env(:digital_oil_sticker, RateLimit)

    clear_buckets([@client_ip, @other_ip])

    on_exit(fn ->
      case original_env do
        nil -> Application.delete_env(:digital_oil_sticker, RateLimit)
        opts -> Application.put_env(:digital_oil_sticker, RateLimit, opts)
      end

      if original_fly,
        do: System.put_env("FLY_APP_NAME", original_fly),
        else: System.delete_env("FLY_APP_NAME")

      clear_buckets([@client_ip, @other_ip])
    end)

    :ok
  end

  defp clear_buckets(ips) do
    table = RateLimitStore.table()

    for ip <- ips do
      key = ClientIP.client_key(%{Phoenix.ConnTest.build_conn() | remote_ip: ip})
      :ets.delete(table, key)
    end
  end

  defp with_limits(capacity, refill_per_second) do
    Application.put_env(:digital_oil_sticker, RateLimit,
      capacity: capacity,
      refill_per_second: refill_per_second
    )
  end

  defp boot_conn(ip) do
    # `dispatch/5` is what runs the request through the endpoint (plugs
    # included), not just the router. This is the load-bearing distinction:
    # `Router.call/2` would skip every endpoint-level plug and prove
    # nothing about the deployment's plug order.
    conn = %{Phoenix.ConnTest.build_conn() | remote_ip: ip}
    Phoenix.ConnTest.dispatch(conn, DigitalOilStickerWeb.Endpoint, :get, @route)
  end

  test "the (capacity + 1)-th LiveView boot GET from one IP is refused with 429" do
    # Tight bucket with negligible refill so the boundary is crisp — every
    # pass under the limit spends a real token, and the refusal cannot be
    # attributed to a mid-test refill top-up.
    with_limits(3, 0.001)

    for i <- 1..3 do
      conn = boot_conn(@client_ip)

      assert conn.status == 200,
             "LiveView boot GET ##{i} of 3 returned #{inspect(conn.status)}; the endpoint " <>
               "chain refused a request the plug still had budget for — a mis-configured " <>
               "capacity or a plug that ran before ClientIP populated the key"
    end

    rejected = boot_conn(@client_ip)

    assert rejected.status == 429,
           "the 4th LiveView boot GET returned #{inspect(rejected.status)}; the endpoint " <>
             "chain does not enforce a per-IP HTTP limit on the LiveView boot route, so " <>
             "AC-6's HTTP half is not actually wired even though `RateLimit.call/2` passes " <>
             "in isolation"
  end

  test "the 429 carries a Retry-After header the browser can honour" do
    # A 429 without Retry-After is a rejection the client cannot back off
    # from except by guessing. The plug promises one; assert the endpoint
    # chain preserves it end-to-end (no downstream plug strips it, no
    # errored render clobbers it).
    with_limits(3, 0.001)

    for _ <- 1..3, do: boot_conn(@client_ip)

    rejected = boot_conn(@client_ip)

    assert rejected.status == 429

    retry_after = Plug.Conn.get_resp_header(rejected, "retry-after")

    assert retry_after != [],
           "the 429 response has no Retry-After header — the client has no signal for when " <>
             "to try again, and FR-10's temporary-limit UI has nothing to render a countdown " <>
             "from"

    [value] = retry_after

    assert {n, ""} = Integer.parse(value)
    assert n >= 1, "Retry-After should be a positive whole-second value, got #{inspect(value)}"
  end

  test "one drained IP does not lock a different IP out of the LiveView boot" do
    # The complementary assertion to the "wrong target" verdict: the plug
    # must run *and* it must key correctly. If the plug ran but keyed on
    # something request-scoped (the request id, the process pid) two IPs
    # would still share a bucket and this test would 429 in the second
    # loop. If it keyed on the proxy header off-Fly, the same. The two-IP
    # shape here is what turns "the plug runs" into "the plug isolates".
    with_limits(3, 0.001)

    for _ <- 1..3, do: boot_conn(@client_ip)

    drained = boot_conn(@client_ip)
    assert drained.status == 429, "expected the first IP to be drained by now"

    for i <- 1..3 do
      conn = boot_conn(@other_ip)

      assert conn.status == 200,
             "boot GET ##{i} from a second IP returned #{inspect(conn.status)}; the endpoint " <>
               "plug chain is bucketing distinct IPs together on the LiveView boot route"
    end
  end
end
