defmodule DigitalOilStickerWeb.LocalStore.LogScanTest do
  @moduledoc """
  AC-3 / DOS-M09-002 FR-11: a scripted session that drives a real LiveView
  through hydrate → stage_mutation → export must not emit any of the personal
  values it carried into the log.

  `ProductionPostureTest` already scans lib/ for log calls that name a payload
  ("params", "assigns", "garage", "envelope", "payload") — a source-level check
  that catches a call the developer wrote. It does NOT catch a value that a
  framework, hook, or middleware emits at runtime under keys the scan cannot
  predict (a Logger metadata bag, a Plug's error report, a Phoenix
  handle_event trace). Nothing but running the interaction and reading the
  captured log will notice that.

  So this is the runtime companion to that static scan: it plants distinctive
  markers in every field the client can send (VIN, odometer, notes, a custom
  nickname, and the tab_id itself), drives the whole round trip inside a
  `ExUnit.CaptureLog.capture_log/1`, then refutes every marker. A future
  framework upgrade that starts logging one of these values at any level
  fails this test on the way in.

  `capture_log` with its default `level: nil` temporarily enables every
  Logger level for the duration of the function, so `:debug` output that the
  test env's `:warning` filter would normally drop is still captured — a
  developer who dropped a `Logger.debug(inspect: params)` into a handler
  during debugging would trip this.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  # Each marker is deliberately distinctive: a base64 or UUID-shaped string
  # would collide with mutation ids and secret_key_base fragments the
  # framework legitimately emits, and a common word ("Truck") would collide
  # with copy. The literal-sentinel style also matches the CSP-report scan.
  @vin "1HGBH41JXMN109186"
  @odometer 123_456
  @note "test-secret-note"
  @nickname "MyBelovedTruck"
  @tab_id "tab-secretmarker"
  # `performed_at` is a service date the user recorded — one of the
  # values AC-3 names explicitly. A leak here is the "date the user
  # last changed oil" surfacing in server logs (INV-4).
  @service_date "2026-07-01"
  # An arbitrary payload fragment sentinel embedded in a schema-preserved
  # field. If any handler dumps the envelope map, this literal appears.
  @payload_marker "sentinel-payload-fragment-nb17q"

  @vehicle_id "11111111-1111-4111-8111-111111111111"

  # A full valid envelope carrying every marker in a field the schema keeps.
  # The vehicle name and vin_last6 live on the vehicle record, notes and
  # odometer on the event, and the tab_id on the envelope itself.
  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 4,
    "tab_id" => @tab_id,
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 4},
      "vehicles" => [
        %{
          "vehicle_id" => @vehicle_id,
          "nickname" => @nickname,
          "vin_last6" => @vin,
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{
            "year" => 2020,
            "make" => "Toyota",
            "model" => "Camry",
            "build" => "LE"
          },
          "support_status" => "identity_only",
          "engine_class_code" => "gas_direct_injection",
          "maintenance_plan" => nil
        }
      ],
      "events" => [
        %{
          "event_id" => "22222222-2222-4222-8222-222222222222",
          "vehicle_id" => @vehicle_id,
          "performed_at" => "2026-07-01T00:00:00Z",
          "odometer_m" => @odometer,
          "input_unit" => "mi",
          "provenance_mode" => "manual",
          "notes" => @note,
          # Unknown-key carry-through preserves this in __unknown__, so a
          # handler that dumps the record map or the envelope surfaces the
          # marker verbatim.
          "custom_payload_marker" => @payload_marker
        }
      ],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  test "a full hydrate → stage_mutation → export round trip emits no PII into logs",
       %{conn: conn} do
    log =
      capture_log(fn ->
        # 1. Hydrate the vehicle profile page. The envelope carries every
        #    marker; if hydrate params are logged (Phoenix does at :debug,
        #    LiveView too), the VIN/nickname/odometer/note/tab_id are all
        #    in one place ready to leak.
        {:ok, vehicle_view, _html} = live(conn, ~p"/vehicle")
        render_hook(vehicle_view, "local_store:hydrate", @envelope)

        # 2. Stage a real mutation via a UI event. `interval_save` calls
        #    Session.stage_mutation/3 which touches the pending-writes
        #    ledger, applies the write to garage, and pushes local_store:put
        #    — the exact code paths a debug line most naturally sits on.
        render_change(vehicle_view, "interval_change", %{
          "interval" => %{"months" => "6", "miles" => "5000"}
        })

        render_submit(vehicle_view, "interval_save", %{})

        # 3. Synthesize the browser's ack for the write we just staged. We
        #    do not know the generated mutation_id (Session generates it),
        #    so we ack a fabricated id — this exercises the mark_unsaved
        #    path (an unknown id acks as unsaved), which is the branch a
        #    "write refused, reason: X" log line would live on if one ever
        #    existed. The reason "quota" travels through Session.handle_ack
        #    and would be a natural companion for a payload dump.
        render_hook(vehicle_view, "local_store:ack", %{
          "mutation_id" => "33333333-3333-4333-8333-333333333333",
          "status" => "error",
          "reason" => "quota"
        })

        # 4. Export. The button lives only on the storage page. Mounting
        #    it here re-runs the whole hydrate path (a second time, with
        #    the same PII), then fires the export event that a user takes
        #    to spill their records back out — the request-log entry for
        #    this event is the single most tempting place for a debug line
        #    to include what was exported.
        {:ok, storage_view, _html} = live(conn, ~p"/settings/storage")
        render_hook(storage_view, "local_store:hydrate", @envelope)
        render_click(storage_view, "export", %{})

        # 5. Erase. Confirm the modal to fire local_store:erase — the
        #    same handler that clears the browser after import-replace.
        #    A `Logger.info("erasing tab=#{tab_id} last_event=#{date}")`
        #    line would leak the tab_id and service date on this path.
        render_click(storage_view, "ask_erase", %{})
        render_click(storage_view, "confirm_erase", %{})

        # 6. A SECOND, dependent mutation. AC-3 explicitly names "several
        #    mutations". A regression that only leaked on the mutation-
        #    sequencing path (e.g. a "seq bumped from N to N+1, previous
        #    odometer=X" debug line) would slip past a single-mutation
        #    test. Re-hydrate on a fresh page and stage another interval
        #    save — the code path is the same but the seq is different.
        {:ok, second_view, _html} = live(conn, ~p"/vehicle")
        render_hook(second_view, "local_store:hydrate", %{@envelope | "seq" => 5})

        render_change(second_view, "interval_change", %{
          "interval" => %{"months" => "12", "miles" => "10000"}
        })

        render_submit(second_view, "interval_save", %{})
      end)

    # None of the markers may appear anywhere in the captured log — not
    # once, not obfuscated, not in metadata. A separate assertion per
    # marker so a failure message names the field that leaked.
    refute log =~ @vin,
           "log carries the VIN marker — a hydrate or mutation path emitted a vin_last6 value"

    refute log =~ to_string(@odometer),
           "log carries the odometer marker — a hydrate or mutation path emitted an odometer_m value"

    refute log =~ @note,
           "log carries the note marker — a hydrate or mutation path emitted an event's notes field"

    refute log =~ @nickname,
           "log carries the nickname marker — a hydrate or mutation path emitted a vehicle nickname"

    refute log =~ @tab_id,
           "log carries the tab_id marker — a hydrate emitted the envelope's tab_id"

    refute log =~ @service_date,
           "log carries a service_date marker — an event's performed_at leaked into logs (INV-4)"

    refute log =~ @payload_marker,
           "log carries the payload-fragment marker — a handler dumped a hydrate/mutation record verbatim"
  end
end
