defmodule DigitalOilStickerWeb.SecurityHeadersExploreTest do
  use DigitalOilStickerWeb.ConnCase, async: false

  test "explore", %{conn: conn} do
    conn = get(conn, "/no-such-path")
    IO.inspect({conn.status, conn.resp_headers}, label: "404", limit: :infinity)
  end
end
