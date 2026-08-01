defmodule DigitalOilStickerWeb.RouteSmokeTest do
  @moduledoc "Every user-facing route must render its static and connected states without crashing."
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @routes ["/", "/vehicle", "/vehicle/select", "/service/new", "/history", "/settings/storage"]

  for route <- @routes do
    test "GET #{route} renders statically and mounts connected", %{conn: conn} do
      conn = get(conn, unquote(route))
      assert html_response(conn, 200)
      {:ok, _view, _html} = live(build_conn(), unquote(route))
    end
  end
end
