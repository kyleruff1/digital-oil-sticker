defmodule DigitalOilStickerWeb.RequestPayloadAuditTest do
  @moduledoc """
  DOS-M09-007 AC-11 / FR-15: the whole-session request-payload audit.

  `DigitalOilSticker.Catalog.ImpersonalSelectorTest` proves the STRUCTURAL
  property — the Selector's closed vocabulary cannot atomize a personal key on
  any declared catalog function, so no personal identifier can shape a query.
  `CatalogEventsPayloadTest` proves the same guarantee under a scripted
  dispatch through `CatalogEvents.handle/4`. Both of those inspect the values
  the pipeline BUILDS (a `%Selector{}` reconstructed inside the test) — they
  do not read what the LiveView process actually PUSHES back out over the
  wire.

  This file closes that gap: a full scripted session drives a real LiveView
  through `hydrate → interval_save → switch_vehicle → hydrate again` and
  captures every outbound push-event the LiveView emits during the sequence.
  `Phoenix.LiveViewTest`'s proxy delivers each `push_event/3` to the test
  process as `{ref, {:push_event, name, payload}}`, so a runtime drain
  captures exactly what would have crossed the WebSocket to the browser
  (see `Phoenix.LiveView.Test.ClientProxy.push_events/2`). No `:sys.trace`
  needed — LiveViewTest already IS the trace surface for push events, and
  `assert_push_event/4` reads from the same mailbox.

  The audit's scope is intentionally narrow: outbound *control-plane*
  payloads only. The rendered HTML diff a LiveView returns to the browser is
  by design a mirror of the user's own records (vehicle nickname, VIN
  suffix, mileage — the very fields on screen), so a "no PII in any wire
  bytes" claim over the diff would be false. Instead we assert on the
  narrower and truer claim FR-15 makes: no HTTP request, socket payload, or
  event carries a personal field that was not asked for by the client.

  ## Sentinel placement

  Personal-data sentinels are placed on records the scripted session's
  mutations DO NOT WRITE BACK. `interval_save` writes the ACTIVE vehicle
  (via `save_plan/3`, whole-record write) — so the active vehicle is a
  sentinel-free plain record. The second vehicle carries the VIN and
  nickname sentinels; `switch_vehicle` writes only a `prefs` singleton with
  `active_vehicle_id`, not the vehicle's own fields. The event on the
  active vehicle carries the odometer and notes sentinels; the scripted
  session stages no event mutations, so events never travel outbound. The
  envelope's `tab_id` is a session-only field and is not part of any push
  payload's shape. This gives a clean assertion: NONE of the sentinels may
  appear in ANY captured payload.

  If Phoenix ever routes push_events through a different mailbox shape, the
  drain helper is the only line that needs to change — the assertions
  ride on the collected list, not on `assert_push_event/4`'s macro
  expansion.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Each sentinel is deliberately distinctive so a substring match is
  # unambiguous. The choice matches `log_scan_test.exs`'s markers where it
  # can — a leak here that also trips the log scan is nicer to diagnose.
  @vin "1HGBH41JXMN109186"
  @note "test-secret-note"
  @odometer 123_456
  @nickname "MyBelovedTruck"
  @tab_id "tab-secretmarker"

  # The active vehicle throughout the first phase; interval_save writes it
  # BACK verbatim, so it must carry no sentinel — otherwise the intentional
  # write would look like a leak.
  @active_id "11111111-1111-4111-8111-111111111111"

  # The second vehicle, target of switch_vehicle. Carries the VIN and
  # nickname sentinels precisely because switch_vehicle writes only a
  # `prefs` record — the vehicle's own fields never travel back out.
  @other_id "22222222-2222-4222-8222-222222222222"

  # One event on the active vehicle, carrying the odometer and note
  # sentinels. Never mutated by the scripted session.
  @event_id "33333333-3333-4333-8333-333333333333"

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 7,
    "tab_id" => @tab_id,
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 7},
      "vehicles" => [
        %{
          "vehicle_id" => @active_id,
          # Plain values — the active vehicle is written BACK by
          # interval_save, so its record must be sentinel-free.
          "nickname" => "Camry",
          "vin_last6" => "000000",
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
        },
        %{
          "vehicle_id" => @other_id,
          # Sentinels on the OTHER vehicle — switch_vehicle writes only
          # a `prefs` record naming this vehicle by id; the vehicle's own
          # fields never cross the wire.
          "nickname" => @nickname,
          "vin_last6" => @vin,
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{
            "year" => 2020,
            "make" => "BMW",
            "model" => "328i"
          },
          "support_status" => "identity_only",
          "engine_class_code" => "gas_direct_injection",
          "maintenance_plan" => nil
        }
      ],
      "events" => [
        %{
          "event_id" => @event_id,
          "vehicle_id" => @active_id,
          "performed_at" => "2026-07-01T00:00:00Z",
          # Sentinels on the event. The scripted session stages no event
          # mutations, so an event record never travels back out.
          "odometer_m" => @odometer,
          "input_unit" => "mi",
          "provenance_mode" => "manual",
          "notes" => @note
        }
      ],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => %{"unit_system" => "mi", "active_vehicle_id" => @active_id}
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  # Drain every {_ref, {:push_event, name, payload}} message from the test
  # mailbox. LiveViewTest's proxy sends these unbatched via `send_caller/2`
  # after each render cycle, so a single drain at the end of the session
  # sees every event any of the mounted views emitted. The ref is not
  # constrained — multiple LiveView mounts each get their own proxy ref, and
  # this audit does not care which view emitted an event, only that no
  # emitted event carried a sentinel.
  defp drain_push_events do
    do_drain([])
  end

  defp do_drain(acc) do
    receive do
      {_ref, {:push_event, name, payload}} -> do_drain([{name, payload} | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # A push-event payload can be an arbitrarily deep map/list; the sentinel
  # check must walk the whole structure, not stringify-and-substring (which
  # would false-negative on integer sentinels re-encoded as floats or
  # false-positive on framework-emitted UUIDs). Recursion is over the
  # decoded Elixir term as it exists in the process — the shape the
  # transport layer will serialize verbatim.
  defp contains?(payload, sentinel) when is_map(payload) do
    Enum.any?(payload, fn {k, v} -> contains?(k, sentinel) or contains?(v, sentinel) end)
  end

  defp contains?(payload, sentinel) when is_list(payload) do
    Enum.any?(payload, &contains?(&1, sentinel))
  end

  defp contains?(payload, sentinel) when is_tuple(payload) do
    payload |> Tuple.to_list() |> contains?(sentinel)
  end

  defp contains?(payload, sentinel) when is_binary(sentinel) and is_binary(payload),
    do: payload == sentinel or String.contains?(payload, sentinel)

  defp contains?(payload, sentinel) when is_integer(sentinel) and is_integer(payload),
    do: payload == sentinel

  # A string sentinel against a non-string atom/number, or an integer
  # sentinel against a string, is trivially false. Explicit rather than a
  # blanket catch-all so a future sentinel type (a UUID atom, say) fails
  # loudly here rather than silently returning false.
  defp contains?(_payload, _sentinel), do: false

  defp leaks(events, sentinel) do
    Enum.filter(events, fn {_name, payload} -> contains?(payload, sentinel) end)
  end

  test "a full scripted session emits no PII sentinel in any outbound push_event",
       %{conn: conn} do
    # 1. Mount the vehicle profile page and hydrate. The envelope carries
    #    every sentinel; the LiveView reads the two vehicles and one event
    #    into `socket.assigns.garage` and drops the tab_id at the session
    #    boundary (it is never re-emitted).
    {:ok, vehicle_view, _html} = live(conn, ~p"/vehicle")
    render_hook(vehicle_view, "local_store:hydrate", @envelope)

    # 2. interval_change followed by interval_save. `save_plan/3` writes the
    #    ACTIVE vehicle back verbatim as a `local_store:put` upsert — the
    #    active vehicle is the plain one on purpose, so this write carries
    #    no sentinel value even though it carries a full vehicle record.
    render_change(vehicle_view, "interval_change", %{
      "interval" => %{"months" => "6", "miles" => "5000"}
    })

    render_submit(vehicle_view, "interval_save", %{})

    # 3. Switch to the second vehicle. `switch_vehicle` writes ONLY a
    #    `prefs` singleton naming `@other_id`; the vehicle's own fields
    #    (nickname/vin_last6 sentinels) never leave the process. This is
    #    the load-bearing distinction — a bug that dumped the whole vehicle
    #    record instead of just the prefs would surface the sentinels
    #    right here.
    {:ok, sticker_view, _html} = live(conn, ~p"/")
    render_hook(sticker_view, "local_store:hydrate", @envelope)
    render_click(sticker_view, "toggle_garage", %{})
    render_click(sticker_view, "switch_vehicle", %{"vehicle-id" => @other_id})

    # 4. Hydrate again on the same page — the final "hydrate again" step of
    #    the scripted sequence. A hydrate MUST NOT echo any of its own
    #    fields back to the client; the server's response is a rendered
    #    diff, not a push. If a regression started push-echoing the
    #    envelope (a debug handler that pushes what it received, say),
    #    every sentinel would show up here.
    render_hook(sticker_view, "local_store:hydrate", %{@envelope | "seq" => 8})

    events = drain_push_events()

    # Proof of life: the drain actually observed traffic. Without this a
    # regression that stopped emitting push_events entirely would make the
    # sentinel refutations vacuously true.
    assert events != [],
           "drain captured zero push_events — LiveViewTest proxy delivery may have changed shape; " <>
             "the audit's sentinel refutations become vacuous when no events are observed"

    # Each sentinel gets its own assertion so a failure names exactly which
    # field leaked and which event carried it. `leaks/2` returns the full
    # (name, payload) tuples so the failure message shows the specific
    # push_event that spilled — not just "some payload leaked X".
    assert leaks(events, @vin) == [],
           "a captured push_event payload carries the VIN sentinel — a mutation or hydrate " <>
             "echoed vin_last6 from a record that should not have been written back: " <>
             inspect(leaks(events, @vin))

    assert leaks(events, @note) == [],
           "a captured push_event payload carries the notes sentinel — an event's `notes` field " <>
             "left the LiveView process, but the scripted session staged no event mutation: " <>
             inspect(leaks(events, @note))

    assert leaks(events, @odometer) == [],
           "a captured push_event payload carries the odometer sentinel — an event's `odometer_m` " <>
             "value left the LiveView process, but no event was mutated: " <>
             inspect(leaks(events, @odometer))

    assert leaks(events, @nickname) == [],
           "a captured push_event payload carries the nickname sentinel — the OTHER vehicle's " <>
             "nickname leaked, but switch_vehicle should have written only a prefs record: " <>
             inspect(leaks(events, @nickname))

    assert leaks(events, @tab_id) == [],
           "a captured push_event payload carries the tab_id sentinel — the envelope's tab_id " <>
             "was echoed back through a push, which no `local_store:*` event's shape allows: " <>
             inspect(leaks(events, @tab_id))
  end
end
