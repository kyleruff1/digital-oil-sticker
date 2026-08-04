defmodule DigitalOilStickerWeb.LocalStore.InteractionBeforeHydrateTest do
  @moduledoc """
  AC-19: a mutating click that arrives BEFORE `local_store:hydrate` must be
  refused at the handle_event level — not just at `Session.mutations_enabled?/1`
  where the API-level gate check lives.

  The gate itself has API-level coverage (see `newer_schema_readonly_test.exs`
  and `quarantine_test.exs`), but a green API test cannot prove the handler
  actually consulted the gate. `StickerLive.switch_vehicle` is the mutating
  handler that checks `mutations_enabled?/1` FIRST, before any other guard, so
  driving it while the socket is still `:hydrating` is what proves the click
  path itself refuses to stage a write pre-hydration. A regression where the
  handler forgot to call the gate would slip past every hydrated-state test
  but fail here: `stage_mutation` would run, `garage.prefs` would flip to the
  new active_vehicle_id, `seq` would advance, and a `local_store:put` would
  fly to the client whose IndexedDB (per this state) may not even be open
  yet — the pre-hydration write the state machine exists to prevent.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  # `live/2` hands back a proxy; assigns live inside the LiveView process.
  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "switch_vehicle fired before hydrate: state unmoved, no put pushed, garage untouched",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    initial = assigns(view)
    # Sanity: the on_mount hook parked us in :hydrating with the empty garage
    # baseline — this is the pre-condition the gate is defending.
    assert initial.local_state == :hydrating
    assert initial.seq == 0
    assert initial.garage.prefs == nil

    # No hydrate envelope is delivered — the socket stays in :hydrating.
    # `render_click/3` bypasses the DOM (the vehicle switcher isn't even
    # rendered in the :skeleton view), which is the whole point: this
    # simulates the racy click a tab could deliver via an already-open
    # LiveView connection before its hydrate round-trip completes.
    render_click(view, "switch_vehicle", %{
      "vehicle-id" => "11111111-1111-4111-8111-111111111111"
    })

    after_click = assigns(view)

    # (a) The state machine did not move. A click must not be misread as an
    # implicit hydrate signal, and no code path may quietly transition out of
    # :hydrating just because a user did something.
    assert after_click.local_state == :hydrating

    # (b) No `local_store:put` was pushed. This is the write the pre-hydration
    # gate exists to suppress — an emitted put here would tell the browser to
    # persist a mutation whose base state (`seq`) was never established, the
    # exact CAS-race precondition the protocol forbids.
    refute_push_event(view, "local_store:put", %{})

    # (c) No optimistic side effect on garage assigns. `stage_mutation`
    # would have set `garage.prefs = %{"active_vehicle_id" => id}` and bumped
    # `seq` to 1; both assigns must be byte-identical to the pre-click
    # snapshot, since the handler bailed on the gate before the write staged.
    assert after_click.garage == initial.garage
    assert after_click.seq == initial.seq
    assert after_click.pending_writes == %{}
  end
end
