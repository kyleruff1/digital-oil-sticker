defmodule DigitalOilStickerWeb.LocalStore.LogScanInducedCrashTest do
  @moduledoc """
  DOS-M09-007 AC-10 (induced-crash extension) / FR-12 / AC-13: the runtime
  log-safety property must hold even under failing input at each protocol
  handler. FR-12 requires "error output ... free of personal data under
  induced failures at each event handler," and AC-10 explicitly names
  "including under induced crashes."

  `LocalStore.LogScanTest` covers the happy path — a full hydrate →
  mutate → export → clear round trip. This companion covers the OTHER half
  of the same invariant: the failure paths. Even if a handler receives a
  malformed payload (a client bug, a protocol drift, a hostile client), or
  if an unknown `catalog:*` event slips through the hook fallback into a
  LiveView with no matching `handle_event/3` clause and crashes with a
  `FunctionClauseError`, the resulting error output — Phoenix's crash
  logger, the Logger's own error line, any middleware emission — must
  contain none of the personal markers the socket held.

  The scenario shape is deliberate: each of the four handlers named in
  `LocalStoreHook.handle_protocol_event/3` gets its own fresh view, primed
  with the SAME PII-laden envelope `log_scan_test.exs` uses, and then hit
  with a payload the handler cannot process. If the current code handles
  the input gracefully (most do — `Envelope.decode/1` and `handle_ack/2`
  have defensive fallbacks) the log capture is empty and the test still
  serves as the regression guard the next hardening pass will need. If a
  future change removes the defense and a real crash surfaces, the crash
  logger's stacktrace and message must still be sentinel-free.

  `capture_log` runs at `level: nil` so `:debug` output the `:test` env's
  `:warning` filter would normally drop still surfaces — a developer who
  dropped a `Logger.debug(inspect: params)` on any handler's error branch
  during debugging would trip this on the way in.

  Each induced call is wrapped in `swallow/1` because a genuine crash
  raises through `render_hook/3` (the LiveView process exits and the test
  process receives it via GenServer.call). Swallowing preserves the
  outer `capture_log/1` boundary so the remaining scenarios still run and
  every refute runs against the combined stream.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  # Same sentinel set as `log_scan_test.exs` on purpose: a leak here means
  # the same thing a leak there means — one of these markers escaped from
  # PII-laden socket state into a log line — and the refute-by-marker
  # style names the leaking field on failure the same way.
  @vin "1HGBH41JXMN109186"
  @odometer 123_456
  @note "test-secret-note"
  @nickname "MyBelovedTruck"
  @tab_id "tab-secretmarker"
  @service_date "2026-07-01"
  @payload_marker "sentinel-payload-fragment-nb17q"

  @vehicle_id "11111111-1111-4111-8111-111111111111"

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

  # A LiveView `handle_event` clause that raises causes the process to
  # exit; `render_hook/3` propagates that exit to the test process
  # through GenServer.call. Swallowing rescues AND catches :exit so a
  # genuine crash on one scenario does not skip the remaining ones —
  # every scenario contributes to the combined log we assert against.
  # `rescue`/`catch` here is scoped to the induced call only; the test's
  # own assertions still run outside `capture_log/1`.
  defp swallow(fun) do
    try do
      fun.()
    rescue
      _ -> :ok
    catch
      :exit, _ -> :ok
      _kind, _reason -> :ok
    end
  end

  test "induced failures at each protocol handler emit no PII into logs",
       %{conn: conn} do
    # `Phoenix.LiveViewTest.live/2` links the LiveView process to the test
    # process. A `FunctionClauseError` from the catalog-unknown scenario
    # (below) would otherwise propagate as an EXIT signal and terminate the
    # test itself before the refutes ran. Trapping exits converts the
    # signal into a message the test simply ignores, so every scenario
    # contributes to the combined log and every marker gets asserted.
    Process.flag(:trap_exit, true)

    log =
      capture_log(fn ->
        # 1. Malformed local_store:hydrate — a payload missing the
        #    required "schema_version" key. `Envelope.decode/1` rejects
        #    it with `{:error, :not_an_envelope}` and `handle_hydrate/2`
        #    moves to :storage_unavailable. The rejected payload still
        #    carries every PII marker (@vin, @odometer, @note, @nickname,
        #    @tab_id, @service_date, @payload_marker) so a handler that
        #    logged its params on rejection would surface them here.
        {:ok, hydrate_view, _html} = live(conn, ~p"/vehicle")
        render_hook(hydrate_view, "local_store:hydrate", @envelope)

        swallow(fn ->
          render_hook(
            hydrate_view,
            "local_store:hydrate",
            Map.delete(@envelope, "schema_version")
          )
        end)

        # 2. local_store:ack with a bad payload — no "mutation_id" key
        #    (all three specific `handle_ack/2` clauses require it), so it
        #    falls through to the `def handle_ack(socket, _), do: socket`
        #    catchall silently. The payload is stuffed with sentinels so
        #    if a future change replaces that catchall with a
        #    `Logger.warning("unroutable ack: #{inspect(params)}")` — the
        #    obvious debugging hook a next-pass author would add — every
        #    marker in the params would leak. This test fails first.
        {:ok, ack_view, _html} = live(conn, ~p"/vehicle")
        render_hook(ack_view, "local_store:hydrate", @envelope)

        swallow(fn ->
          render_hook(ack_view, "local_store:ack", %{
            "vin" => @vin,
            "odometer" => to_string(@odometer),
            "notes" => @note,
            "nickname" => @nickname,
            "tab_id" => @tab_id,
            "performed_at" => @service_date,
            "custom_marker" => @payload_marker
          })
        end)

        # 3. local_store:conflict with bad params — `handle_conflict/2`
        #    ignores its params by design (only its side-effects matter:
        #    re-arm deadline, set :conflict_notice, push rehydrate). A
        #    log line that dumped `params` "for the record" would leak
        #    every marker below. Same stuffing pattern as scenario 2.
        {:ok, conflict_view, _html} = live(conn, ~p"/vehicle")
        render_hook(conflict_view, "local_store:hydrate", @envelope)

        swallow(fn ->
          render_hook(conflict_view, "local_store:conflict", %{
            "vin" => @vin,
            "odometer" => to_string(@odometer),
            "notes" => @note,
            "nickname" => @nickname,
            "tab_id" => @tab_id,
            "performed_at" => @service_date,
            "custom_marker" => @payload_marker
          })
        end)

        # 4. local_store:persist_result with an unrecognized "result" value.
        #    `handle_protocol_event/3`'s persist_result clause only branches
        #    on "granted" / "denied"; any other string (here "unknown-probe")
        #    falls through the `if` cascade and sets `:persist_granted` to
        #    `nil` — the exact edge a debugging author would be tempted to
        #    log ("hm, unexpected persist result, let me see what came in").
        #    The payload is stuffed with the same sentinels so a
        #    `Logger.warning("unknown persist result: #{inspect(params)}")`
        #    would surface every marker here. This closes the fourth handler
        #    named in `LocalStoreHook.handle_protocol_event/3`.
        {:ok, persist_view, _html} = live(conn, ~p"/vehicle")
        render_hook(persist_view, "local_store:hydrate", @envelope)

        swallow(fn ->
          render_hook(persist_view, "local_store:persist_result", %{
            "result" => "unknown-probe",
            "vin" => @vin,
            "odometer" => to_string(@odometer),
            "notes" => @note,
            "nickname" => @nickname,
            "tab_id" => @tab_id,
            "performed_at" => @service_date,
            "custom_marker" => @payload_marker
          })
        end)

        # 5. Unknown catalog:* event. Driven through `CatalogEvents.handle/4`
        #    directly — the same seam `catalog/log_scan_test.exs` uses, and
        #    the seam a future LiveView `handle_event("catalog:" <> _, ...)`
        #    binding will delegate to. Bypasses `render_hook/3` because no
        #    LiveView is currently wired to receive `catalog:*` events (that
        #    binding is later M09 work), so a `render_hook/3` in this suite
        #    would crash via the LiveView's absent `handle_event/3` clause
        #    rather than exercising the catalog edge. The bucket-carrying
        #    payload is stuffed with the same sentinels so a rejection path
        #    that logged its params would surface every marker here.
        bucket = DigitalOilSticker.Catalog.RateLimit.new()

        swallow(fn ->
          DigitalOilStickerWeb.CatalogEvents.handle(
            "catalog:unknown_probe",
            %{
              "vin" => @vin,
              "odometer" => to_string(@odometer),
              "notes" => @note,
              "nickname" => @nickname,
              "tab_id" => @tab_id,
              "performed_at" => @service_date,
              "custom_marker" => @payload_marker
            },
            bucket,
            0
          )
        end)
      end)

    # Per-marker refutes with named messages so a failure names the
    # field that leaked and which surface it likely came from (the
    # induced-crash path is the tempting one to log against). Matches
    # `log_scan_test.exs`'s style so a regression in either file is
    # diagnosed the same way.
    refute log =~ @vin,
           "induced-failure log carries the VIN marker — an error path emitted a vin_last6 value"

    refute log =~ to_string(@odometer),
           "induced-failure log carries the odometer marker — an error path emitted an odometer_m value"

    refute log =~ @note,
           "induced-failure log carries the note marker — an error path emitted an event's notes field"

    refute log =~ @nickname,
           "induced-failure log carries the nickname marker — an error path emitted a vehicle nickname"

    refute log =~ @tab_id,
           "induced-failure log carries the tab_id marker — an error path emitted the envelope's tab_id"

    refute log =~ @service_date,
           "induced-failure log carries a service_date marker — an event's performed_at leaked into logs (INV-4)"

    refute log =~ @payload_marker,
           "induced-failure log carries the payload-fragment marker — an error path dumped a hydrate/ack/conflict/catalog payload verbatim"
  end
end
