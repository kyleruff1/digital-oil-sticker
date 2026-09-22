defmodule DigitalOilStickerWeb.InducedCrashLogTest do
  @moduledoc """
  DOS-M09-007 AC-13: systematic per-handler induced-crash log check.

  AC-10 / `LocalStore.LogScanTest` already drives the three LocalStore
  protocol events (hydrate / ack / conflict) through a real session and
  refutes personal markers in the captured log — but only for those three.
  Every OTHER `phx-event` and `phx-change` handler across the LiveView
  surface has to clear the same bar: when the handler crashes on a
  malformed payload, no personal value carried on the socket may reach
  the log.

  The mechanism the crash could leak through is the GenServer terminate
  report: a `Phoenix.LiveView.Channel` crashing under `proc_lib` may emit
  the last message and the process state, and the process state is the
  socket, which is the assigns, which is the whole garage. Phoenix strips
  this by contract; this file is the runtime companion that proves it
  did. `ProductionPostureTest` catches a log call written into `lib/`
  under a payload-shaped name; nothing but running the interaction and
  reading the captured log will notice a framework-emitted terminate
  report that carries the state along.

  For each LiveView, one strict-pattern-match handler is driven with a
  malformed payload to induce a `FunctionClauseError`. Every handler on
  that LiveView runs in the same channel process, so the property proved
  on one is the property proved on all — the manifest below enumerates
  the full set so a new handler that lands without shared coverage is
  visible as an unlisted line, and a future LiveView that adds one and
  forgets a strict-pattern representative for its induced crash fails
  `every_liveview_covered/0`.

  `capture_log` with its default `level: nil` temporarily enables every
  Logger level for the duration of the function, so the crash report
  emitted at `:error` and any debug lines the framework logs while
  tearing the channel down are all captured. Since the LiveView channel
  is a linked process, the test process traps exits so the crash of the
  view does not take the test with it.

  Also asserts `debug_errors: false` in the production endpoint config
  (against the evaluated `config/prod.exs`, not a regex over the file):
  a raised exception must not surface assigns to a 500 page.
  `ProductionPostureTest` covers the same key in its FR-12 block; the
  overlap is deliberate — AC-13's contract is that the induced-crash
  path is safe in the shipped release, and the shipped release's
  `debug_errors` setting is half of that contract.
  """
  use DigitalOilStickerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  import ExUnit.CaptureLog

  @app_root Path.expand("../..", __DIR__)

  # Sentinels planted in a full hydrate envelope. Each is distinctive so a
  # base64/UUID collision with a framework-emitted mutation id or key base
  # fragment cannot mask a real leak, and a common word ("Toyota") cannot
  # collide with copy. Mirrors LocalStore.LogScanTest's sentinel style.
  @vin "1HGBH41JXMN109186"
  @odometer 987_654
  @note "induced-crash-secret-note"
  @nickname "MyCrashTestTruck"
  @tab_id "tab-crash-secretmarker"
  @service_date "2026-06-15"
  @payload_marker "sentinel-crash-fragment-a19k4"

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
          "maintenance_plan" => %{"interval_months" => 6, "interval_miles" => 5000}
        }
      ],
      "events" => [
        %{
          "event_id" => "22222222-2222-4222-8222-222222222222",
          "vehicle_id" => @vehicle_id,
          "performed_at" => "#{@service_date}T00:00:00Z",
          "odometer_m" => @odometer,
          "input_unit" => "mi",
          "provenance_mode" => "manual",
          "notes" => @note,
          # Unknown-key carry-through preserves this under `__unknown__`, so
          # a handler or terminate report that dumps the record surfaces the
          # marker verbatim.
          "custom_payload_marker" => @payload_marker
        }
      ],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => %{"active_vehicle_id" => @vehicle_id}
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  # Every `handle_event/3` clause across the six live_session LiveViews.
  # `pattern:` names the required-key shape the clause matches on —
  # `nil` means the clause accepts any params map (no way to fail its
  # match with a payload alone; covered indirectly by the strict-pattern
  # crash on the same channel process, which shares its terminate path).
  # `crash_target?:` marks the one clause per LiveView this test induces
  # a crash on; `every_liveview_covered/0` asserts every LiveView has at
  # least one crash target listed here.
  @handlers [
    # StickerLive — `/`
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "toggle_garage",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "switch_vehicle",
      pattern: {:strict, %{"vehicle-id" => :required}},
      crash_target?: true
    },
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "set_skin",
      pattern: {:strict, %{"skin" => :required}},
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "ask_delete_vehicle",
      pattern: {:strict, %{"vehicle-id" => :required}},
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "cancel_delete_vehicle",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.StickerLive,
      route: "/",
      event: "confirm_delete_vehicle",
      pattern: nil,
      crash_target?: false
    },

    # VehicleProfileLive — `/vehicle`
    %{
      lv: DigitalOilStickerWeb.VehicleProfileLive,
      route: "/vehicle",
      event: "interval_change",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.VehicleProfileLive,
      route: "/vehicle",
      event: "toggle_override",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.VehicleProfileLive,
      route: "/vehicle",
      event: "set_condition",
      # Guarded pattern: condition in ["normal", "severe"]. A bogus
      # condition value fails the guard, which is a FunctionClauseError
      # on the clause head — the same class of crash as a missing key.
      pattern: {:guarded, %{"condition" => ~w(normal severe)}},
      crash_target?: true
    },
    %{
      lv: DigitalOilStickerWeb.VehicleProfileLive,
      route: "/vehicle",
      event: "reminder_lead_change",
      pattern: {:strict, %{"lead_days" => :required}},
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.VehicleProfileLive,
      route: "/vehicle",
      event: "interval_save",
      pattern: nil,
      crash_target?: false
    },

    # VehiclePickerLive — `/vehicle/select`
    %{
      lv: DigitalOilStickerWeb.VehiclePickerLive,
      route: "/vehicle/select",
      event: "cascade_change",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.VehiclePickerLive,
      route: "/vehicle/select",
      event: "oil_change",
      pattern: {:strict, %{"oil" => :required}},
      crash_target?: true
    },
    %{
      lv: DigitalOilStickerWeb.VehiclePickerLive,
      route: "/vehicle/select",
      event: "confirm",
      pattern: nil,
      crash_target?: false
    },

    # OilChangeLive — `/service/new`
    %{
      lv: DigitalOilStickerWeb.OilChangeLive,
      route: "/service/new",
      event: "form_change",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.OilChangeLive,
      route: "/service/new",
      event: "submit",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.OilChangeLive,
      route: "/service/new",
      event: "duplicate_proceed",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.OilChangeLive,
      route: "/service/new",
      event: "switch_vehicle",
      pattern: {:strict, %{"vehicle-id" => :required}},
      crash_target?: true
    },
    %{
      lv: DigitalOilStickerWeb.OilChangeLive,
      route: "/service/new",
      event: "duplicate_cancel",
      pattern: nil,
      crash_target?: false
    },

    # HistoryLive — `/history`
    %{
      lv: DigitalOilStickerWeb.HistoryLive,
      route: "/history",
      event: "ask_delete",
      pattern: {:strict, %{"event-id" => :required}},
      crash_target?: true
    },
    %{
      lv: DigitalOilStickerWeb.HistoryLive,
      route: "/history",
      event: "cancel_delete",
      pattern: nil,
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.HistoryLive,
      route: "/history",
      event: "confirm_delete",
      pattern: {:strict, %{"event-id" => :required}},
      crash_target?: false
    },
    %{
      lv: DigitalOilStickerWeb.HistoryLive,
      route: "/history",
      event: "undo_delete",
      pattern: nil,
      crash_target?: false
    },

    # StorageStatusLive — `/settings/storage`.
    # Every handler accepts _params, so there is no in-process induced
    # crash target here — the LocalStore protocol handlers (hydrate /
    # ack / conflict) attached by LocalStoreHook run in the same channel
    # process and are covered by LocalStore.LogScanTest, which drives
    # this same LiveView through export/erase/hydrate under CaptureLog.
    # The line below is not a crash target — it is inventory, so the
    # `every_liveview_covered/0` check knows this LV is intentionally
    # covered by a sibling test rather than in this file.
    %{
      lv: DigitalOilStickerWeb.StorageStatusLive,
      route: "/settings/storage",
      event: "export",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },
    %{
      lv: DigitalOilStickerWeb.StorageStatusLive,
      route: "/settings/storage",
      event: "request_persist",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },
    %{
      lv: DigitalOilStickerWeb.StorageStatusLive,
      route: "/settings/storage",
      event: "ask_erase",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },
    %{
      lv: DigitalOilStickerWeb.StorageStatusLive,
      route: "/settings/storage",
      event: "cancel_erase",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },
    %{
      lv: DigitalOilStickerWeb.StorageStatusLive,
      route: "/settings/storage",
      event: "confirm_erase",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },

    # AttributionLive — `/attribution`.
    # Declares zero handle_event/3 clauses of its own; the only events it
    # sees are the LocalStore protocol handlers attached by LocalStoreHook,
    # which share the same channel process and terminate path proven safe
    # by LocalStore.LogScanTest. Inventory row so manifest_coverage sees
    # this LV as intentionally sibling-covered rather than missing.
    %{
      lv: DigitalOilStickerWeb.AttributionLive,
      route: "/attribution",
      event: "__no_own_handlers__",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.LocalStore.LogScanTest
    },

    # ScanLive — `/s`.
    # Runs in its own live_session (`:scan`), not `:garage`, so the
    # LocalStoreHook does not attach and no hydrated PII ever lands in its
    # assigns — the invariant this whole file is written to catch a leak of.
    # The `scan_code` event carries only a StickerCode string, which is
    # public by construction (see StickerCode's moduledoc: "the code is not
    # a secret"). Inventory row so manifest_coverage sees this LV as
    # intentionally sibling-covered; ScanLiveTest itself exercises the bad-
    # payload and oversized-payload paths that would otherwise crash it.
    %{
      lv: DigitalOilStickerWeb.ScanLive,
      route: "/s",
      event: "scan_code",
      pattern: nil,
      crash_target?: false,
      covered_by: DigitalOilStickerWeb.ScanLiveTest
    }
  ]

  # Malformed payload per handler: `%{}` misses a `{:strict, %{key => ...}}`
  # pattern, and a bogus value misses a `{:guarded, %{key => allowed}}`
  # clause. The payloads themselves carry NO markers — the only PII source
  # in the run is the hydrated assigns, so a leak here proves the crash
  # path serialised the socket state, not the message.
  defp induce_crash_payload({:strict, _}), do: %{}

  defp induce_crash_payload({:guarded, allowed_map}) do
    Map.new(allowed_map, fn {key, _allowed} -> {key, "not-a-real-value"} end)
  end

  # Route the crash through render_hook (works for both phx-click and
  # phx-change events — the wire protocol is the same "event" message).
  # A crashing handle_event in a linked channel process raises `:exit`
  # in the caller of GenServer.call; the test process is trapping exits
  # (see setup) so the exit surfaces as a caught reason rather than
  # propagating and taking the test with it.
  defp induce_crash(view, event, pattern) do
    payload = induce_crash_payload(pattern)

    try do
      render_hook(view, event, payload)
      :did_not_crash
    rescue
      _ -> :rescued
    catch
      :exit, reason -> {:exit, reason}
    end
  end

  setup do
    # Trap exits so a linked view crashing inside capture_log does not
    # kill the test process before it can read the captured log back.
    # Restored on test end automatically.
    Process.flag(:trap_exit, true)
    :ok
  end

  describe "every mutating handler's induced crash keeps hydrated PII out of the log" do
    for %{lv: lv, route: route, event: event, pattern: pattern, crash_target?: true} <-
          @handlers do
      test "#{inspect(lv)} `#{event}` on #{route}", %{conn: conn} do
        pattern = unquote(Macro.escape(pattern))
        route = unquote(route)
        event = unquote(event)

        log =
          capture_log(fn ->
            {:ok, view, _html} = live(conn, route)
            # Plant every marker in the socket's assigns. If the crash
            # report dumps the state, all markers travel with it.
            render_hook(view, "local_store:hydrate", @envelope)

            _ = induce_crash(view, event, pattern)

            # Give the trapped :EXIT and any post-terminate log lines
            # from :logger a moment to land before capture_log stops.
            # ClientProxy shutdown emits its report inline; this only
            # covers a slow scheduler on CI.
            Process.sleep(20)
          end)

        # None of the markers may appear anywhere in the captured log —
        # not once, not obfuscated, not in a terminate report. One
        # refute per marker so a failure message names the field.
        refute log =~ @vin,
               "#{event} crash log carries the VIN marker — the terminate report leaked " <>
                 "vin_last6 from socket.assigns.garage"

        refute log =~ to_string(@odometer),
               "#{event} crash log carries the odometer marker — an odometer_m value from " <>
                 "socket.assigns.garage.events reached the log"

        refute log =~ @note,
               "#{event} crash log carries the note marker — an event's notes field leaked " <>
                 "via the terminate report"

        refute log =~ @nickname,
               "#{event} crash log carries the nickname marker — a vehicle nickname from " <>
                 "socket.assigns.garage.vehicles leaked"

        refute log =~ @tab_id,
               "#{event} crash log carries the tab_id marker — the hydrated envelope's tab_id " <>
                 "leaked through the crash report"

        refute log =~ @service_date,
               "#{event} crash log carries a service_date marker — an event's performed_at " <>
                 "reached the log (INV-4)"

        refute log =~ @payload_marker,
               "#{event} crash log carries the payload-fragment marker — a handler or the " <>
                 "terminate report dumped a record verbatim"
      end
    end
  end

  describe "manifest coverage" do
    test "every LiveView in the :garage live_session has a covered handler" do
      # The router's live_session :garage is the surface AC-13 owns.
      # Every LiveView reachable from it must have EITHER a
      # `crash_target?: true` entry (induced-crash-covered here) OR a
      # `covered_by:` entry pointing to the sibling test that owns it —
      # otherwise the manifest is out of date and a new LiveView shipped
      # without induced-crash coverage.
      liveviews_in_router =
        DigitalOilStickerWeb.Router.__routes__()
        |> Enum.filter(&(&1.plug == Phoenix.LiveView.Plug))
        |> Enum.map(fn route ->
          # Router records LiveView identity under
          # `route.metadata[:phoenix_live_view]` as `{Module, action,
          # extra, live_session}`. `route.plug_opts` is just the action
          # atom (e.g. `:index`), not the module.
          route.metadata[:phoenix_live_view] |> elem(0)
        end)
        |> Enum.uniq()

      manifest_lvs = @handlers |> Enum.map(& &1.lv) |> Enum.uniq()

      missing = liveviews_in_router -- manifest_lvs

      assert missing == [],
             "these LiveViews are routed but absent from the induced-crash manifest: " <>
               inspect(missing)

      for lv <- liveviews_in_router do
        entries = Enum.filter(@handlers, &(&1.lv == lv))
        has_crash_target? = Enum.any?(entries, & &1.crash_target?)
        has_sibling_cover? = Enum.any?(entries, &Map.has_key?(&1, :covered_by))

        assert has_crash_target? or has_sibling_cover?,
               "#{inspect(lv)} has no crash_target and no covered_by entry — it lacks " <>
                 "induced-crash coverage for AC-13"
      end
    end

    test "every crash_target names a pattern that can actually miss" do
      # A crash target with `pattern: nil` cannot be induced to crash
      # by a payload alone, so it would silently no-op the assertions
      # above. Guard against that.
      for %{crash_target?: true, event: event, pattern: pattern} <- @handlers do
        assert pattern != nil,
               "handler #{inspect(event)} is marked crash_target? but has pattern: nil — " <>
                 "there is no malformed payload that can miss its clause"
      end
    end
  end

  describe "production endpoint config" do
    test "debug_errors is set to false explicitly in config/prod.exs" do
      # Reads the evaluated production config, not the source text: what
      # matters is the value the release actually starts with. A raised
      # exception under `debug_errors: true` would render the Phoenix
      # debug page including request params and socket assigns straight
      # to the client — the same PII this file's crash-log tests keep
      # out of the log would land on a 500 page instead.
      #
      # `Config.Reader.read!` walks the imports the same way the release
      # does, so `debug_errors: false` inherited via `config/config.exs`
      # rather than set in prod.exs would also pass here — the assertion
      # is on the effective value, not on where it lives. The overlap
      # with ProductionPostureTest's key-presence check (which asserts
      # `Keyword.has_key?(:debug_errors)` against the same read) is
      # deliberate: that test guards against inheriting the default,
      # this one guards against the value being wrong.
      prod =
        Config.Reader.read!(Path.join(@app_root, "config/prod.exs"), env: :prod)

      endpoint = prod[:digital_oil_sticker][DigitalOilStickerWeb.Endpoint]

      assert endpoint[:debug_errors] == false,
             "config/prod.exs does not set debug_errors: false — a raised exception in " <>
               "production would render the Phoenix debug page with request params and " <>
               "socket assigns visible to the client"
    end

    test "the production logger formatter runs through SocketRedactor" do
      # The runtime crash tests above run under the test env's Logger
      # formatter. The test env inherits its `:default_formatter` from
      # `config/config.exs` (test.exs sets no override), so what the
      # tests exercise IS what production runs. This assertion pins
      # that contract in one line: whichever env this test file runs
      # in, the formatter must be `SocketRedactor.format/4`. A
      # future edit that flips it back to a raw format string in
      # config.exs — or adds a raw override to prod.exs, or removes
      # the redactor — makes the induced-crash log tests silently
      # ineffective (they'd still exercise the crash path, but the
      # formatter would emit the leak), and this test is the guard
      # against that silent failure.
      merged_prod =
        Config.Reader.read!(Path.join(@app_root, "config/config.exs"), env: :prod)

      assert merged_prod[:logger][:default_formatter][:format] ==
               {DigitalOilStickerWeb.Logger.SocketRedactor, :format},
             "config/config.exs no longer routes the default Logger formatter through " <>
               "SocketRedactor — a LiveView crash would once again dump socket.assigns.garage " <>
               "into the standard GenServer crash report"
    end
  end
end
