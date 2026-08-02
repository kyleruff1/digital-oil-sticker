defmodule DigitalOilStickerWeb.ReminderPanelTest do
  @moduledoc """
  The reminder panel on the vehicle page: the lead time the user picks becomes
  a VALARM in a calendar file, built from the SAME due calculation the sticker
  shows. What matters here is that the file carries the chosen lead, that the
  choice persists to the reminders store, and that no personal value ever
  rides in a URL to get there.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @vehicle_id "11111111-1111-4111-8111-111111111111"

  defp vehicle do
    %{
      "vehicle_id" => @vehicle_id,
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => %{"interval_months" => 6, "interval_miles" => 5000}
    }
  end

  defp event do
    %{
      "event_id" => "22222222-2222-4222-8222-222222222222",
      "vehicle_id" => @vehicle_id,
      "performed_at" => "2026-06-15",
      "odometer_m" => 80_467_200,
      "input_unit" => "mi",
      "oil_base_stock" => "full_synthetic",
      "provenance_mode" => "manual"
    }
  end

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
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
          data
        ),
      "storage" => %{"mode" => "idb", "boot_hint" => "never"}
    })
  end

  test "with a logged change, the calendar button carries the alarm inline", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")
    html = hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

    assert html =~ "data-test=\"reminder-panel\""
    assert html =~ "data-test=\"calendar-download\""

    # The file rides in the element, not behind a URL: a download route would
    # put the due date and mileage into a request line and its access log.
    assert html =~ "data-ics="
    assert html =~ "BEGIN:VCALENDAR"
    # Due: 2026-06-15 + 6 months (user interval is shorter than the model's 12).
    assert html =~ "DTSTART;VALUE=DATE:20261215"
    # Default lead: one week — at nine in the morning, not midnight. An
    # all-day event's relative trigger counts from local midnight, so a plain
    # -P7D would fire at 00:00. 7*24-9 = 159 hours.
    assert html =~ "TRIGGER:-PT159H"
  end

  test "changing the lead persists the choice and rebuilds the alarm", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")
    hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

    html = render_change(view, "reminder_lead_change", %{"lead_days" => "14"})

    assert_push_event(view, "local_store:put", payload)
    assert [%{"store" => "reminders", "record" => record}] = payload["upserts"]
    assert record["vehicle_id"] == @vehicle_id
    assert record["kind"] == "oil_change"
    assert record["lead_value"] == 14
    assert record["lead_unit"] == "days"

    # 14 * 24 - 9 = 327.
    assert html =~ "TRIGGER:-PT327H"

    # And SEQUENCE advanced past the day-count fallback: the reminder record's
    # updated_at now drives it, so a client that honors SEQUENCE treats the
    # re-download as a replacement instead of ignoring it.
    [_, seq] = Regex.run(~r/SEQUENCE:(\d+)/, html)
    assert String.to_integer(seq) > 100_000
  end

  test "a stored lead is what the panel and the file start from", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")

    html =
      hydrate(view, %{
        "vehicles" => [vehicle()],
        "events" => [event()],
        "reminders" => [
          %{
            "reminder_id" => "55555555-5555-4555-8555-555555555555",
            "vehicle_id" => @vehicle_id,
            "kind" => "oil_change",
            "lead_value" => 30,
            "lead_unit" => "days",
            "enabled" => true
          }
        ]
      })

    # 30 * 24 - 9 = 711.
    assert html =~ "TRIGGER:-PT711H"
  end

  test "a lead we do not offer is refused, not stored", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")
    hydrate(view, %{"vehicles" => [vehicle()], "events" => [event()]})

    render_change(view, "reminder_lead_change", %{"lead_days" => "9999"})

    refute_push_event(view, "local_store:put", %{})
  end

  test "without a logged change there is no file, and the panel says why", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")
    html = hydrate(view, %{"vehicles" => [vehicle()], "events" => []})

    assert html =~ "data-test=\"reminder-panel\""
    refute html =~ "data-test=\"calendar-download\""
    assert html =~ Copy.reminder_needs_change()
  end
end
