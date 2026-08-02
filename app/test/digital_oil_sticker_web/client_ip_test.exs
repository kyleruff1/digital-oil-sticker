defmodule DigitalOilStickerWeb.Plugs.ClientIPTest do
  @moduledoc """
  Client identification for rate limiting, and its privacy properties
  (DOS-M09-007 FR-8, INV-26).

  Two failure modes worth guarding, in opposite directions. Trusting a
  forwarded header when nothing overwrites it lets any caller forge a fresh
  identity and bypass every limit. Storing the real address, or deriving a key
  that outlives a deploy, turns a rate-limit control into a tracking key for an
  app that promises it holds nothing about anyone.
  """
  use DigitalOilStickerWeb.ConnCase, async: false

  alias DigitalOilStickerWeb.Plugs.ClientIP

  setup do
    original = System.get_env("FLY_APP_NAME")

    on_exit(fn ->
      if original,
        do: System.put_env("FLY_APP_NAME", original),
        else: System.delete_env("FLY_APP_NAME")
    end)

    :ok
  end

  defp conn_from(ip, headers) do
    Enum.reduce(headers, %{Phoenix.ConnTest.build_conn() | remote_ip: ip}, fn {k, v}, acc ->
      Plug.Conn.put_req_header(acc, k, v)
    end)
  end

  describe "off Fly" do
    setup do
      System.delete_env("FLY_APP_NAME")
      :ok
    end

    test "a forwarded header is ignored, because nothing is overwriting it" do
      # The header is only trustworthy because Fly's proxy replaces it. Running
      # anywhere else, believing it would let a caller mint a new identity per
      # request and walk straight through every limit.
      spoofed = conn_from({203, 0, 113, 9}, [{"fly-client-ip", "198.51.100.1"}])
      honest = conn_from({203, 0, 113, 9}, [])

      assert ClientIP.raw_address(spoofed) == ClientIP.raw_address(honest)
      assert ClientIP.raw_address(spoofed) == "203.0.113.9"
    end
  end

  describe "behind the Fly proxy" do
    setup do
      System.put_env("FLY_APP_NAME", "digital-oil-sticker")
      :ok
    end

    test "the real peer is used, not the proxy" do
      # Without this every request looks like it came from Fly's proxy, so the
      # whole internet would share one bucket.
      conn = conn_from({172, 16, 0, 1}, [{"fly-client-ip", "198.51.100.1"}])

      assert ClientIP.raw_address(conn) == "198.51.100.1"
    end

    test "a missing header falls back rather than crashing" do
      conn = conn_from({172, 16, 0, 1}, [])

      assert ClientIP.raw_address(conn) == "172.16.0.1"
    end
  end

  describe "the derived key" do
    test "is not the address, and does not contain it" do
      conn = conn_from({198, 51, 100, 77}, [])

      key = ClientIP.client_key(conn)

      refute key =~ "198"
      refute key =~ "51.100"
      assert String.match?(key, ~r/^[0-9a-f]{32}$/)
    end

    test "is stable within a boot, so it can actually rate limit" do
      conn = conn_from({198, 51, 100, 77}, [])

      assert ClientIP.client_key(conn) == ClientIP.client_key(conn)
    end

    test "separates different clients" do
      a = conn_from({198, 51, 100, 1}, [])
      b = conn_from({198, 51, 100, 2}, [])

      refute ClientIP.client_key(a) == ClientIP.client_key(b)
    end

    test "does not survive a boot, so it cannot become a tracking identifier" do
      conn = conn_from({198, 51, 100, 77}, [])
      before = ClientIP.client_key(conn)

      # Simulate a redeploy: a fresh process gets a fresh salt.
      :persistent_term.erase({ClientIP, :salt})

      refute ClientIP.client_key(conn) == before
    end
  end
end
