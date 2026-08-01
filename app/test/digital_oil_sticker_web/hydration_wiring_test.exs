defmodule DigitalOilStickerWeb.HydrationWiringTest do
  @moduledoc """
  Regression guard for the wiring bug that shipped to production: the
  LocalStore hook element lives in Layouts.app, so a LiveView that does not
  wrap its render in `<Layouts.app>` never mounts the hook, hydration never
  runs, and the 5s deadline reports storage_unavailable on a browser whose
  storage is perfectly fine.
  """
  use DigitalOilStickerWeb.ConnCase, async: true

  @routes ["/", "/vehicle", "/vehicle/select", "/service/new", "/history", "/settings/storage"]

  for route <- @routes do
    test "#{route} renders the LocalStore hook element", %{conn: conn} do
      html = conn |> get(unquote(route)) |> html_response(200)

      assert html =~ ~s(id="local-store"),
             "#{unquote(route)} is missing the LocalStore hook element — is its render wrapped in <Layouts.app>?"

      assert html =~ ~s(phx-hook="LocalStore")
    end
  end
end
