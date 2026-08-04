defmodule DigitalOilStickerWeb.LocalStore.QuarantineTest do
  @moduledoc """
  DOS-M09-002 AC-8 / FR-8: Validation.validate/2 mixed-payload behavior.

  A hydrate that mixes valid and invalid records must not kill the session
  and must not silently drop the bad ones. The valid subset hydrates as
  canonical data (`:loaded`), each rejected record moves to a quarantine
  entry naming the store and the violated rule, and the raw payload stays
  exportable — a per-record rejection is never fatal to the tab and never
  silent.

  Rules exercised end-to-end here:
    * `:orphan_vehicle_id`  — a vehicle-scoped record referencing a
      `vehicle_id` that is not among the validated vehicles (referential
      pass in `DigitalOilSticker.LocalStore.Validation`).
    * `:invalid_odometer`   — an event whose `odometer_m` is not a
      non-negative integer (`Schema.V1.validate_event/1`).

  The test drives the whole path through `Session.handle_hydrate/2` at
  `/settings/storage`, where `StorageStatusLive` is the surface that
  renders the quarantine count and the export offer that must survive
  quarantine.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @vehicle_id "11111111-1111-4111-8111-111111111111"
  @orphan_vehicle_id "99999999-9999-4999-8999-999999999999"

  @valid_event_id "22222222-2222-4222-8222-222222222222"
  @orphan_event_id "33333333-3333-4333-8333-333333333333"
  @bad_odometer_event_id "44444444-4444-4444-8444-444444444444"

  @mixed_envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 7,
    "tab_id" => "tab-mixed",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => nil,
      "vehicles" => [
        %{"vehicle_id" => @vehicle_id, "archived" => false}
      ],
      "events" => [
        # (a) Valid event on the valid vehicle — this one must land in
        # :garage.events.
        %{
          "event_id" => @valid_event_id,
          "vehicle_id" => @vehicle_id,
          "performed_at" => "2026-07-01T00:00:00Z",
          "odometer_m" => 100_000,
          "input_unit" => "mi",
          "provenance_mode" => "manual"
        },
        # (b) Event referencing a vehicle_id that is not among the
        # validated vehicles — must quarantine with :orphan_vehicle_id
        # (referential pass).
        %{
          "event_id" => @orphan_event_id,
          "vehicle_id" => @orphan_vehicle_id,
          "performed_at" => "2026-07-01T00:00:00Z",
          "odometer_m" => 100_000,
          "input_unit" => "mi",
          "provenance_mode" => "manual"
        },
        # (c) Event with a negative odometer — must quarantine with
        # :invalid_odometer (Schema.V1.validate_event/1). Note: the
        # per-record pass runs before the referential pass, so this
        # event is quarantined for :invalid_odometer and never reaches
        # the referential check.
        %{
          "event_id" => @bad_odometer_event_id,
          "vehicle_id" => @vehicle_id,
          "performed_at" => "2026-07-01T00:00:00Z",
          "odometer_m" => -1,
          "input_unit" => "mi",
          "provenance_mode" => "manual"
        }
      ],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp socket(view), do: :sys.get_state(view.pid).socket
  defp assigns(view), do: socket(view).assigns

  test "mixed hydrate at /settings/storage: valid subset loads, invalid quarantines",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    html = render_hook(view, "local_store:hydrate", @mixed_envelope)

    a = assigns(view)

    # (3) Session stays alive — the mixed payload is :loaded, not any
    # error state. FR-8: per-record rejection is never fatal.
    assert a.local_state == :loaded

    # (4) The valid event is the ONLY event in the canonical garage.
    assert length(a.garage.events) == 1
    [only_event] = a.garage.events
    assert only_event["event_id"] == @valid_event_id
    assert only_event["vehicle_id"] == @vehicle_id

    # The valid vehicle survived the per-record pass.
    assert length(a.garage.vehicles) == 1
    [only_vehicle] = a.garage.vehicles
    assert only_vehicle["vehicle_id"] == @vehicle_id

    # (5) Exactly two quarantine entries, one per rule; both entries
    # name the "events" store. Content of the failing records is never
    # carried (INV-4) — only store, id, rule.
    assert length(a.quarantine) == 2

    rules = Enum.map(a.quarantine, & &1.rule) |> Enum.sort()
    assert rules == Enum.sort([:orphan_vehicle_id, :invalid_odometer])

    Enum.each(a.quarantine, fn entry -> assert entry.store == "events" end)

    orphan_entry = Enum.find(a.quarantine, &(&1.rule == :orphan_vehicle_id))
    assert orphan_entry.id == @orphan_event_id

    bad_odo_entry = Enum.find(a.quarantine, &(&1.rule == :invalid_odometer))
    assert bad_odo_entry.id == @bad_odometer_event_id

    # (6) StorageStatusLive renders the quarantine notice and body when
    # quarantine is non-empty. Body includes count of quarantined
    # records and total.
    assert html =~ Copy.quarantine_notice()
    assert html =~ "2 of"

    # (7) Export is still offered — the raw-payload export path must
    # survive quarantine so users can recover the rejected records.
    assert html =~ "Export a file"

    # Mutations remain enabled: :loaded with default storage_mode is
    # not read_only and not session_only.
    assert Session.mutations_enabled?(socket(view))
  end
end
