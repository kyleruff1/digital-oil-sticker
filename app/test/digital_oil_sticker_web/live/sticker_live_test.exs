defmodule DigitalOilStickerWeb.StickerLiveTest do
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @forbidden ["no vehicles", "add your first vehicle", "empty garage", "welcome, let"]

  defp hydrate(view, data, storage \\ %{"mode" => "idb", "boot_hint" => "never"}) do
    payload = %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => Map.get(data, "seq", 0),
      "tab_id" => "test-tab",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" =>
        Map.merge(
          %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          Map.delete(data, "seq")
        ),
      "storage" => storage
    }

    render_hook(view, "local_store:hydrate", payload)
  end

  test "static render shows the sticker skeleton and never an empty-garage claim", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    for phrase <- @forbidden, do: refute(html =~ phrase, "static render leaked: #{phrase}")
    assert html =~ "dos-sticker"
  end

  test "connected pre-hydrate render stays skeleton with no empty-garage words", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    for phrase <- @forbidden, do: refute(html =~ phrase)
    assert html =~ "dos-skeleton"
    # Still hydrating — no claims either way.
    assert render(view) =~ "dos-skeleton"
  end

  test "hydrating with a genuine first visit shows setup, not the sticker", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = hydrate(view, %{})
    assert html =~ "Set up your first vehicle"
    assert html =~ "stored in this browser"
  end

  test "cleared storage is distinguished from a first visit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = hydrate(view, %{}, %{"mode" => "idb", "boot_hint" => "has_data"})
    assert html =~ "stored records are gone"
    refute html =~ "Set up your first vehicle"
  end

  test "session-only storage shows the honest storage-unavailable state", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    html = hydrate(view, %{}, %{"mode" => "session_only", "reason" => "unavailable"})
    assert html =~ "storage could not be used"
  end

  test "a hydrated garage renders the sticker with DATE, MILEAGE, and GRADE", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    vehicle = %{
      "vehicle_id" => "11111111-1111-4111-8111-111111111111",
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "maintenance_plan" => %{
        "basis" => "user_entered",
        "interval_months" => 6,
        "interval_miles" => 5000
      }
    }

    event = %{
      "event_id" => "22222222-2222-4222-8222-222222222222",
      "vehicle_id" => "11111111-1111-4111-8111-111111111111",
      "performed_at" => "2026-06-15",
      "odometer_m" => 80_467_200,
      "odometer_input_value" => "50,000",
      "input_unit" => "mi",
      "oil_viscosity" => "5W-30",
      "provenance_mode" => "manual"
    }

    html = hydrate(view, %{"seq" => 3, "vehicles" => [vehicle], "events" => [event]})

    assert html =~ "data-test=\"sticker-date\""
    assert html =~ "Dec 15, 2026"
    assert html =~ "55,000 mi"
    assert html =~ "5W-30"
    assert html =~ "Estimated due date"
    assert html =~ "Your interval"
    refute html =~ "manufacturer guidance</span> says"
  end

  test "the newer-schema payload turns the session read-only without crashing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    payload = %{
      "envelope" => "dos_local",
      "schema_version" => 999,
      "seq" => 1,
      "tab_id" => "t",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{}
    }

    render_hook(view, "local_store:hydrate", payload)
    assert render(view)
  end
end
