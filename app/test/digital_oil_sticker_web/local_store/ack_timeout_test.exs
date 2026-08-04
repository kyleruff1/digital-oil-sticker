defmodule DigitalOilStickerWeb.LocalStore.AckTimeoutTest do
  @moduledoc """
  AC-12 / INV-24: a staged write whose browser ack never arrives must degrade
  to an :unsaved state that the user sees — not a silent retry, not a rolled
  back garage, not a stuck spinner.

  This is the exact failure INV-24 was written to prevent: a mutation the user
  believes they saved which the browser did not store, with no signal to the
  user and no visible entry to re-do. The safe outcome is a rendered "Not
  saved to this browser" banner that persists until the tab is closed, and NO
  silent replay of `local_store:put` (a replay behind the user's back is how
  a "successful save" turns into a duplicate the next time the browser cooperates).

  Test.exs pins @ack_timeout_ms to 100ms so a `Process.sleep(200)` reliably
  crosses the expiry without being tuned tight to the timer.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @vehicle %{
    "vehicle_id" => "11111111-1111-4111-8111-111111111111",
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

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 1,
    "tab_id" => "tab-ack",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 1},
      "vehicles" => [@vehicle],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  # Reach into the LiveView process to inspect the ledger the module keeps.
  # Same pattern as idempotence_test — assigns_snapshot/1. The ack-timeout
  # rule is about the pending_writes/unsaved_writes ledger, so equality
  # assertions on that ledger are the direct check.
  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "a staged write with no ack ends up :unsaved, not silently retried",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle")

    render_hook(view, "local_store:hydrate", @envelope)

    # Stage a real mutation through the UI: entering an interval and hitting
    # save is the shortest path to `stage_mutation` from a phx-submit. The
    # ack never comes because the test never fires `local_store:ack`.
    render_change(view, "interval_change", %{
      "interval" => %{"months" => "6", "miles" => "5000"}
    })

    render_submit(view, "interval_save", %{})

    assert_push_event(view, "local_store:put", payload)
    mutation_id = payload["mutation_id"]
    assert is_binary(mutation_id)

    # Before the timeout, the ledger records it as still saving. This anchors
    # the test to the STATE MACHINE — if the initial status ever changed, this
    # assertion would flag it rather than the later :unsaved assertion silently
    # passing on a mislabeled entry.
    assert %{status: :saving} = assigns(view).pending_writes[mutation_id]

    # SNAPSHOT the optimistic garage BEFORE the timeout. The staged plan is
    # applied to `:garage` immediately by `stage_mutation`, so the vehicle now
    # carries the pending interval. After the timeout, the same value MUST
    # still be present — a `mark_unsaved` that silently rolled back the garage
    # would erase the value the user is looking at while the "not saved"
    # banner claims they can see it. That silent-rollback failure mode is
    # exactly what INV-24 forbids.
    optimistic_plan =
      assigns(view).garage.vehicles
      |> Enum.find(&(&1["vehicle_id"] == @vehicle["vehicle_id"]))
      |> Map.get("maintenance_plan")

    assert is_map(optimistic_plan),
           "the staged interval must be applied to the garage before ack (optimistic write)"

    # Cross the 100ms ack window (test.exs pins it) with a 2x margin. The
    # timer message hits the LiveView; the next synchronous call to `view`
    # flushes the mailbox, so `render(view)` below both waits for handling
    # AND returns the resulting HTML.
    Process.sleep(200)
    html = render(view)

    # (1) The ledger flipped to :unsaved. The mutation_id is not removed from
    # pending_writes — mark_unsaved updates its status in place so the record
    # keeps its optimistic garage state alongside the unsaved marker.
    assert %{status: :unsaved} = assigns(view).pending_writes[mutation_id]

    # (2) The unsaved_writes list picked up an entry keyed by this mutation.
    # A timeout carries no reason (mark_unsaved/2 arity), so reason is nil.
    assert Enum.any?(
             assigns(view).unsaved_writes,
             &(&1.mutation_id == mutation_id and &1.reason == nil)
           )

    # (3) NO silent retry. A second `local_store:put` after the timeout would
    # be exactly the "app quietly saves again behind the user's back" pattern
    # INV-24 forbids — the user chose to know when their write did not land,
    # and a background replay erases that signal.
    refute_push_event(view, "local_store:put", %{})

    # (4) The user sees the failure. "Not saved to this browser" has no
    # apostrophe, so a plain substring match is safe (no HEEx escape concern).
    assert html =~ Copy.unsaved_record()

    # (5) The optimistic value is STILL there. This is the pair to the pre-
    # timeout snapshot above — same vehicle, same plan, byte-equal. If
    # mark_unsaved (or any callee) reverted `:garage`, the value the user
    # entered would disappear from the row underneath the unsaved banner —
    # the exact "silent rollback" INV-24.5 was written to forbid.
    retained_plan =
      assigns(view).garage.vehicles
      |> Enum.find(&(&1["vehicle_id"] == @vehicle["vehicle_id"]))
      |> Map.get("maintenance_plan")

    assert retained_plan == optimistic_plan,
           "the optimistic garage value must persist across ack timeout — no silent rollback"

    # (6) The banner itself is non-dismissible. It carries no dismiss control
    # (no phx-click clearing the assign, no timer that hides it), because a
    # user who dismissed it and then forgot would be exactly the case
    # INV-24.5 was written to prevent.
    refute html =~ ~s(data-test="unsaved-writes-dismiss"),
           "the unsaved-writes banner must not carry a dismiss control"
  end
end
