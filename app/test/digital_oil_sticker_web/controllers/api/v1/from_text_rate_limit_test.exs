defmodule DigitalOilStickerWeb.Api.V1.FromTextRateLimitTest do
  @moduledoc """
  Prove the Grok-backed /api/v1/stickers/from-text endpoint has its own
  rate-limit bucket, independent from /api/v1/stickers. A shared bucket
  would let an attacker drain the whole 60/min quota through /from-text
  and burn Grok budget along the way.

  async: false — mutates application env and the per-table ETS bucket.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Plugs.{ClientIP, RateLimitStore}

  @key "11111111-2222-4333-8444-555555555555"

  @from_text_body %{
    "configuration_key" => @key,
    "text" => "5W-30 full synthetic, 45,000 miles"
  }

  @stickers_body %{
    "configuration_key" => @key,
    "changed_on" => "2026-11-01",
    "odometer_m" => 72_420_480,
    "grade" => "5W-30",
    "base_stock" => "full_synthetic"
  }

  @strict_table DigitalOilStickerWeb.Plugs.RateLimitStore.GrokBucket
  @strict_key DigitalOilStickerWeb.Plugs.RateLimit.GrokBucket

  @ip_a {203, 0, 113, 60}
  @ip_b {203, 0, 113, 61}
  @used_ips [@ip_a, @ip_b]

  setup do
    # Off-Fly: remote_ip decides the client key.
    original_fly = System.get_env("FLY_APP_NAME")
    System.delete_env("FLY_APP_NAME")

    original_strict = Application.get_env(:digital_oil_sticker, @strict_key)

    # Grok call is stubbed via Req.Test — happy path returns a tool_call
    # so the pipeline completes through to the renderer. The rate limiter
    # runs BEFORE the controller, so even a stubbed Grok is not needed
    # for the 429 cases; set a stub up front so the tests that do reach
    # the controller don't trip the no-api-key branch.
    original_xai = System.get_env("XAI_API_KEY")
    System.put_env("XAI_API_KEY", "test-key")

    Req.Test.stub(DigitalOilSticker.Grok.Client, fn conn ->
      body = %{
        "choices" => [
          %{
            "message" => %{
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_1",
                  "type" => "function",
                  "function" => %{
                    "name" => "record_service",
                    "arguments" =>
                      Jason.encode!(%{
                        "grade" => "5W-30",
                        "base_stock" => "full_synthetic"
                      })
                  }
                }
              ]
            }
          }
        ]
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, Jason.encode!(body))
    end)

    clear_buckets(@used_ips)

    on_exit(fn ->
      case original_strict do
        nil -> Application.delete_env(:digital_oil_sticker, @strict_key)
        opts -> Application.put_env(:digital_oil_sticker, @strict_key, opts)
      end

      if original_fly,
        do: System.put_env("FLY_APP_NAME", original_fly),
        else: System.delete_env("FLY_APP_NAME")

      if original_xai,
        do: System.put_env("XAI_API_KEY", original_xai),
        else: System.delete_env("XAI_API_KEY")

      clear_buckets(@used_ips)
    end)

    :ok
  end

  defp clear_buckets(ips) do
    for ip <- ips do
      conn = %{Phoenix.ConnTest.build_conn() | remote_ip: ip}
      key = ClientIP.client_key(conn)

      try do
        :ets.delete(@strict_table, key)
      rescue
        ArgumentError -> :ok
      end

      try do
        :ets.delete(RateLimitStore.table(), key)
      rescue
        ArgumentError -> :ok
      end
    end
  end

  defp set_strict_limits(capacity, refill_per_second) do
    Application.put_env(:digital_oil_sticker, @strict_key,
      capacity: capacity,
      refill_per_second: refill_per_second
    )
  end

  defp conn_from(ip), do: %{Phoenix.ConnTest.build_conn() | remote_ip: ip}

  describe "the strict bucket throttles /from-text independently" do
    test "N requests pass, N+1 returns 429 with Retry-After" do
      set_strict_limits(3, 0.001)

      for i <- 1..3 do
        conn = post(conn_from(@ip_a), ~p"/api/v1/stickers/from-text", @from_text_body)

        assert conn.status == 200,
               "/from-text request ##{i} returned #{inspect(conn.status)}; the strict bucket should still have tokens"
      end

      rejected = post(conn_from(@ip_a), ~p"/api/v1/stickers/from-text", @from_text_body)

      assert rejected.status == 429,
             "the 4th /from-text request from the same IP returned #{inspect(rejected.status)}; expected 429"

      assert [retry_after] = get_resp_header(rejected, "retry-after")
      assert {n, ""} = Integer.parse(retry_after)
      assert n >= 1
    end
  end

  describe "bucket isolation from /api/v1/stickers" do
    test "draining /from-text does not block /stickers from the same IP" do
      # Drain the strict (/from-text) bucket completely.
      set_strict_limits(3, 0.001)

      for _ <- 1..3, do: post(conn_from(@ip_b), ~p"/api/v1/stickers/from-text", @from_text_body)

      drained = post(conn_from(@ip_b), ~p"/api/v1/stickers/from-text", @from_text_body)
      assert drained.status == 429, "/from-text bucket should be drained"

      # /stickers uses the loose bucket, which still has ~1M tokens in
      # test env. A shared bucket would starve this call; a separate
      # bucket lets it through.
      conn = post(conn_from(@ip_b), ~p"/api/v1/stickers", @stickers_body)

      assert conn.status == 200,
             "/stickers was rate-limited by /from-text's spend — the two endpoints share a bucket"
    end
  end
end
