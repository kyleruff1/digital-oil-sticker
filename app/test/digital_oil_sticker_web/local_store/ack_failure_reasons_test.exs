defmodule DigitalOilStickerWeb.LocalStore.AckFailureReasonsTest do
  @moduledoc """
  AC-13 / INV-24.5: when the browser refuses a commit with
  `%{"status" => "error", "reason" => "quota_exceeded"}`, `Session.handle_ack`
  must (a) record the mutation on `unsaved_writes` with the reason intact so
  the layout can pick the quota-specific message, (b) render that
  quota-specific copy (not the generic not-saved body), (c) keep offering
  export as the recovery path, and (d) drop no record from the garage — the
  optimistic value stays and is visibly marked unsaved, never silently rolled
  back.

  Complements the ack-timeout test (AC-12) and the save-path breadth test.
  The ack-timeout path exercises reason `nil` and the two-arity `mark_unsaved`;
  the breadth test sprays a synthetic `mutation_id` at every route to prove
  the copy is wired everywhere. Neither pins the reducer invariant this test
  protects: a REAL staged mutation, addressed by the mutation_id the server
  actually assigned, whose error branch must preserve prior state at the
  assigns level. A regression in `handle_ack` that clears `garage`, drops the
  reason, or invisibly reverts the optimistic upsert would slip past a
  pure-DOM check but fail here.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  # HEEx escapes apostrophes to &#39;. Copy.unsaved_record/0 has none so a
  # plain module call is safe; Copy.quota_full/0 and Copy.not_saved_body/0
  # both contain apostrophes, so those checks use apostrophe-free fragments.
  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "22222222-2222-4222-8222-222222222222"

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 3,
    "tab_id" => "tab-ack-quota",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 3},
      "vehicles" => [
        %{
          "vehicle_id" => @car_one,
          "nickname" => "Camry",
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{"year" => 2020, "make" => "Toyota", "model" => "Camry"}
        },
        %{
          "vehicle_id" => @car_two,
          "nickname" => "BMW",
          "archived" => false,
          "model_year" => 2020,
          "display_snapshot" => %{"year" => 2020, "make" => "BMW", "model" => "328i"}
        }
      ],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => %{"unit_system" => "mi", "active_vehicle_id" => @car_one}
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "quota_exceeded ack: quota copy renders, prior state kept, export offered",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @envelope)

    initial = assigns(view)
    assert initial.local_state == :loaded
    assert length(initial.garage.vehicles) == 2, "hydration should load both vehicles"

    # Stage a REAL prefs mutation via the switcher — same code path a user
    # click runs, so `stage_mutation` assigns a real mutation_id, optimistically
    # applies the prefs upsert to `garage`, and pushes the write. Capturing the
    # mutation_id from the emitted event is what lets the ack address the
    # server's own bookkeeping instead of testing a fake id in isolation.
    render_click(view, "toggle_garage", %{})
    render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

    assert_push_event(view, "local_store:put", payload)
    mutation_id = payload["mutation_id"]
    assert is_binary(mutation_id)

    optimistic = assigns(view)

    # The optimistic upsert landed in the garage before the browser answered.
    # AC-13's "no record silently dropped" starts from this snapshot: the
    # error branch must not roll any of it back.
    assert optimistic.garage.prefs["active_vehicle_id"] == @car_two
    assert length(optimistic.garage.vehicles) == 2

    # Browser reports the write was refused because storage is full. The
    # reason string travels through unchanged so `unsaved_body/1` in the
    # layout can select the quota-specific copy — the wire vocabulary the
    # layout matches includes "quota_exceeded" alongside "quota" and
    # "QuotaExceededError".
    html =
      render_hook(view, "local_store:ack", %{
        "mutation_id" => mutation_id,
        "status" => "error",
        "reason" => "quota_exceeded"
      })

    after_error = assigns(view)

    # (1) The unsaved-writes ledger recorded the mutation and its reason.
    # `unsaved_writes` is the field the layout reads for `unsaved_body/1`; a
    # regression that dropped the reason would flip the banner to the generic
    # not-saved copy without failing any pending_writes assertion.
    assert Enum.any?(after_error.unsaved_writes, fn u ->
             u.mutation_id == mutation_id and u.reason == "quota_exceeded"
           end),
           "handle_ack did not record mutation with reason \"quota_exceeded\" on :unsaved_writes"

    # (2) The pending write's status flipped to :unsaved rather than being
    # popped — mark_unsaved updates in place so the optimistic garage state
    # keeps a paper trail alongside the visible marker.
    assert %{status: :unsaved} = after_error.pending_writes[mutation_id]

    # (3) The quota-specific message renders, not the generic body. HEEx
    # escapes both copy strings' apostrophes to &#39;, so match on the
    # apostrophe-free fragments (same pattern as save_path_test).
    assert html =~ "storage is full, so the entry was not stored"
    refute html =~ "This entry is on screen but was not stored"

    # (4) The persistent, non-dismissible "Not saved to this browser" marker.
    assert html =~ Copy.unsaved_record()

    # (5) Export is offered — the only recovery route INV-24.5 mandates when a
    # write cannot land in this browser.
    assert html =~ "Export a file"

    # (6) No record silently dropped from the garage. Both hydrated vehicles
    # are still present with the same ids, and the optimistic prefs value the
    # user just chose is still there — an invisible rollback of either would
    # be exactly the failure INV-24.5 forbids.
    assert length(after_error.garage.vehicles) == 2

    assert Enum.map(after_error.garage.vehicles, & &1["vehicle_id"]) ==
             Enum.map(optimistic.garage.vehicles, & &1["vehicle_id"])

    assert after_error.garage.prefs["active_vehicle_id"] == @car_two
  end
end
