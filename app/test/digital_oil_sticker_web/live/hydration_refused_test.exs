defmodule DigitalOilStickerWeb.HydrationRefusedTest do
  @moduledoc """
  A refused payload is not data loss (DOS-M09-007 FR-9, FR-10).

  A cap rejection is a security control firing. It used to render as
  `:storage_unavailable`, whose copy tells the user "we cannot tell whether any
  records are stored here" — which is false twice over: we know exactly what
  happened because we refused it, and their records are untouched in the
  browser. FR-10 forbids precisely this, so that a control can never masquerade
  as data loss.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.LocalStore.Caps
  alias DigitalOilStickerWeb.Copy

  defp hydrate_over_cap(view, vehicles) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
      "tab_id" => "t",
      "generated_at" => "2026-08-02T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => vehicles,
        "events" => [],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
    })
  end

  defp too_many_vehicles do
    for i <- 1..(Caps.max_vehicles() + 1) do
      %{
        "vehicle_id" =>
          "1111111#{rem(i, 10)}-1111-4111-8111-#{String.pad_leading("#{i}", 12, "0")}",
        "archived" => false
      }
    end
  end

  test "an over-cap payload says what happened, not that storage failed", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = hydrate_over_cap(view, too_many_vehicles())

    assert html =~ Copy.hydration_refused_heading()

    # The specific lie this guards: claiming we cannot tell what is stored.
    refute html =~ Copy.storage_unavailable_heading()
    refute html =~ "we cannot tell whether"
  end

  test "it reassures that nothing was lost, because nothing was", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = hydrate_over_cap(view, too_many_vehicles())

    assert html =~ "still in this browser"
    assert html =~ "Export a file"
  end

  test "it is not confused with a genuinely evicted store", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = hydrate_over_cap(view, too_many_vehicles())

    # :data_missing means the records really are gone. A refusal must not
    # borrow that copy either.
    refute html =~ Copy.data_missing_heading()
  end

  test "it never renders as an empty garage", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = hydrate_over_cap(view, too_many_vehicles())

    # INV-24.3 and FR-10: a refusal that reads as "no vehicles yet" would
    # invite the user to start over on top of records they still have.
    refute html =~ Copy.empty_heading()
  end

  test "mutations are disabled while a payload stands refused", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    hydrate_over_cap(view, too_many_vehicles())

    # We did not load their records, so we must not let a write land on top of
    # a garage we never read.
    refute render(view) =~ "Log an oil change"
  end
end
