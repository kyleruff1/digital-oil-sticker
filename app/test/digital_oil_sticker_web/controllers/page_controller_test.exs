defmodule DigitalOilStickerWeb.PageControllerTest do
  use DigitalOilStickerWeb.ConnCase

  test "GET / renders the app shell with the brand head block", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Digital Oil Sticker"
    assert html =~ ~s(<meta name="theme-color" content="#159447")
    assert html =~ "site.webmanifest"
    # INV-24.3: no empty-garage claim may ever appear in a static render.
    refute html =~ "no vehicles"
    refute html =~ "add your first vehicle"
  end
end
