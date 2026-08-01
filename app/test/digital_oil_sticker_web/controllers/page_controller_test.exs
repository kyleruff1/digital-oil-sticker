defmodule DigitalOilStickerWeb.PageControllerTest do
  use DigitalOilStickerWeb.ConnCase

  test "GET / renders the app shell with the brand head block", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Digital Oil Sticker"
    assert html =~ ~s(<meta name="theme-color" content="#159447")
    # No web app manifest. The brand pack shipped one and it was linked here
    # until the conformance suite caught it: a manifest makes the app
    # installable, which is a promise about offline behaviour that INV-6,
    # INV-17, and INV-19 defer until DOS-M09-009 decides it.
    refute html =~ "webmanifest"
    refute html =~ ~s(rel="manifest")

    # Icon-only theme controls need accessible names (axe button-name).
    assert html =~ ~s(aria-label="Follow the system theme")
    assert html =~ ~s(aria-label="Use the light theme")
    assert html =~ ~s(aria-label="Use the dark theme")

    # INV-24.3: no empty-garage claim may ever appear in a static render.
    refute html =~ "no vehicles"
    refute html =~ "add your first vehicle"
  end
end
