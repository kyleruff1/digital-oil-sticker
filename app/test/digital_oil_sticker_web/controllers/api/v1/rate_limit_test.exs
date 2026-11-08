defmodule DigitalOilStickerWeb.Api.V1.RateLimitTest do
  @moduledoc """
  Prove the per-IP rate limit is wired into the `/api/v1/*` endpoint, not
  just available as an isolated plug. The plug has its own unit test in
  `test/digital_oil_sticker_web/plugs/rate_limit_test.exs`; this one
  exercises it through `Phoenix.ConnTest.post/3` so a mis-ordered
  pipeline entry would fail here.

  async: false — mutates application env and the process-wide ETS table
  that backs the plug.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Plugs.{ClientIP, RateLimit, RateLimitStore}

  @key "11111111-2222-4333-8444-555555555555"

  @body %{
    "configuration_key" => @key,
    "changed_on" => "2026-11-01",
    "odometer_m" => 72_420_480,
    "grade" => "5W-30",
    "base_stock" => "full_synthetic"
  }

  # Keep the IPs this file writes to in TEST-NET-3 so they never collide
  # with 127.0.0.1 (every other test in the suite) or real routable space.
  @ip_a {203, 0, 113, 50}
  @ip_b {203, 0, 113, 51}
  @ip_refill {203, 0, 113, 52}
  @used_ips [@ip_a, @ip_b, @ip_refill]

  setup do
    # Off-Fly: ClientIP's trusted-proxy branch is bypassed, so `remote_ip`
    # decides the key. Same discipline as plugs/rate_limit_test.exs:65-73.
    original_fly = System.get_env("FLY_APP_NAME")
    System.delete_env("FLY_APP_NAME")

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

  defp clear_buckets(ips) do
    table = RateLimitStore.table()

    for ip <- ips do
      key = ClientIP.client_key(%{Phoenix.ConnTest.build_conn() | remote_ip: ip})
      :ets.delete(table, key)
    end
  end

  defp conn_from(ip), do: %{Phoenix.ConnTest.build_conn() | remote_ip: ip}

  defp set_limits(capacity, refill_per_second) do
    Application.put_env(:digital_oil_sticker, RateLimit,
      capacity: capacity,
      refill_per_second: refill_per_second
    )
  end

  describe "endpoint-level rate limit on POST /api/v1/stickers" do
    test "first N requests from the same IP succeed, N+1 returns 429 with Retry-After" do
      # Capacity 3, essentially no refill — a crisp boundary for the N+1 case.
      set_limits(3, 0.001)

      for i <- 1..3 do
        conn = post(conn_from(@ip_a), ~p"/api/v1/stickers", @body)

        assert conn.status == 200,
               "request ##{i} of 3 returned #{inspect(conn.status)}; the bucket should still have tokens"
      end

      rejected = post(conn_from(@ip_a), ~p"/api/v1/stickers", @body)

      assert rejected.status == 429,
             "the 4th request from the same IP returned #{inspect(rejected.status)}; expected 429"

      assert [retry_after] = get_resp_header(rejected, "retry-after")
      assert {n, ""} = Integer.parse(retry_after)
      assert n >= 1, "Retry-After must be an integer >= 1 second, got #{inspect(retry_after)}"
    end

    test "a different IP has its own bucket (buckets are per-client)" do
      set_limits(3, 0.001)

      # Drain IP A.
      for _ <- 1..3, do: post(conn_from(@ip_a), ~p"/api/v1/stickers", @body)
      rejected = post(conn_from(@ip_a), ~p"/api/v1/stickers", @body)
      assert rejected.status == 429, "IP A should be drained by now"

      # IP B still has a full bucket.
      conn = post(conn_from(@ip_b), ~p"/api/v1/stickers", @body)

      assert conn.status == 200,
             "IP B was rate-limited by IP A's spend — buckets are not per-client"
    end
  end

  describe "endpoint-level rate limit recovery" do
    test "after the refill interval the same IP can send again" do
      # Each endpoint request takes tens of ms (controller + QR render), so
      # a fast refill during the drain phase would top the bucket back up
      # between requests. Drain with effectively no refill, then bump the
      # refill rate and sleep for recovery. The plug reads config on every
      # call, so the rate change takes effect immediately.
      set_limits(2, 0.001)

      for _ <- 1..2, do: post(conn_from(@ip_refill), ~p"/api/v1/stickers", @body)

      drained = post(conn_from(@ip_refill), ~p"/api/v1/stickers", @body)
      assert drained.status == 429, "expected the bucket to be empty before sleeping"

      # Fast refill for the recovery phase: 100 tokens/s, one every 10 ms.
      # A 60 ms sleep gives back six tokens' worth (capped at capacity 2).
      set_limits(2, 100)
      Process.sleep(60)

      recovered = post(conn_from(@ip_refill), ~p"/api/v1/stickers", @body)

      assert recovered.status == 200,
             "60 ms after the refill rate was raised, the same IP is still rejected — " <>
               "refill is not reaching the endpoint path"
    end
  end
end
