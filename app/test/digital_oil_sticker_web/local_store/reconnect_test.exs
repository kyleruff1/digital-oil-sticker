defmodule DigitalOilStickerWeb.LocalStore.ReconnectTest do
  @moduledoc """
  AC-14: a socket reconnect re-runs hydration, and any mutation the previous
  socket had staged but not yet acked is re-driven by the client — the server
  side of that contract is that a fresh mount holds NOTHING from the old
  socket's session (empty `pending_writes`, `:hydrating` local_state, empty
  garage) until the client re-sends the hydrate envelope.

  Phoenix.LiveViewTest exposes no in-process disconnect helper in this
  Phoenix.LiveView version, so this test drives the "server treats reconnect
  as a fresh mount" half by mounting the LiveView twice on the same conn: the
  second `live/2` is a brand-new LiveView process, which is exactly what the
  real reconnect delivers. The client half — re-emitting the pending
  `local_store:put` from its own queue — is covered by the JS conformance
  suite; the server invariant this test protects is that the server never
  remembers the old socket's staged mutation across the disconnect.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.LocalStore.Session

  # `live/2` hands back a `Phoenix.LiveViewTest.View` proxy — Session functions
  # need the actual socket, which lives inside the LiveView process.
  defp socket(view), do: :sys.get_state(view.pid).socket

  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "33333333-3333-4333-8333-333333333333"

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 3,
    "tab_id" => "tab-reconnect",
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
      "prefs" => %{"unit_system" => "mi"}
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp assigns(view), do: socket(view).assigns

  test "a fresh mount after the first one drops holds nothing from the old socket", %{conn: conn} do
    # First mount: hydrate, then stage a mutation the client never gets to ack.
    {:ok, view_a, _html} = live(conn, ~p"/")
    render_hook(view_a, "local_store:hydrate", @envelope)

    a_after_hydrate = assigns(view_a)
    assert a_after_hydrate.local_state == :loaded
    assert a_after_hydrate.seq == 3

    # Stage a real mutation by driving the switcher — this is the same code
    # path a user click would run, so the server bookkeeping (pending_writes,
    # seq bump, optimistic garage) is exercised the same way.
    render_click(view_a, "toggle_garage", %{})
    render_click(view_a, "switch_vehicle", %{"vehicle-id" => @car_two})

    # Sanity: the server emitted the write the client would have persisted.
    assert_push_event(view_a, "local_store:put", payload)
    assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]
    assert prefs["active_vehicle_id"] == @car_two

    a_after_mutation = assigns(view_a)
    # The pending write is on the OLD socket's ledger, waiting for an ack
    # that will never arrive because the client is about to disconnect.
    assert map_size(a_after_mutation.pending_writes) == 1
    assert a_after_mutation.seq == 4

    # Simulate reconnect: a second live/2 on the same conn spawns a brand-new
    # LiveView process — the state carried across the reconnect is exactly
    # what the client re-sends, nothing more.
    {:ok, view_b, remounted_html} = live(conn, ~p"/")

    # AC-14 explicit: the remount HTML must still contain the app shell (nav,
    # main, LocalStore hook element). A remount that tore down to a bare
    # skeleton would drop the layout the phx-disconnected class styles over,
    # causing a visible page flash. This is the substring check that catches
    # a shell regression — the JS conformance suite owns the full DOM diff.
    assert remounted_html =~ ~s(id="local-store"),
           "the remount must still carry the LocalStore hook element so hydration re-runs"

    assert remounted_html =~ ~s(phx-hook="LocalStore"),
           "the remount's hook attribute must survive so the client re-attaches"

    b_initial = assigns(view_b)

    # The invariant AC-14 protects on the server: none of the old socket's
    # state — not the pending write, not the loaded garage, not the seq —
    # survives the reconnect.
    assert b_initial.local_state == :hydrating,
           "fresh mount must start in :hydrating so Session.init runs cleanly"

    assert b_initial.pending_writes == %{},
           "the old socket's un-acked mutation must not appear on the new socket"

    assert b_initial.seq == 0
    assert b_initial.garage.vehicles == []
    assert b_initial.garage.prefs == nil
    assert b_initial.read_only == false
    assert b_initial.storage_mode == :unknown

    # Mutations must be refused before hydration completes — this is the
    # backstop that keeps a re-driven client write from being staged against
    # an empty garage.
    refute Session.mutations_enabled?(socket(view_b))

    # Re-hydrating the same envelope restores :garage on the new socket. The
    # client is the source of truth for what to send; the server is required
    # only to accept it and land in the same loaded state as before.
    render_hook(view_b, "local_store:hydrate", @envelope)

    b_after_rehydrate = assigns(view_b)
    assert b_after_rehydrate.local_state == :loaded
    assert b_after_rehydrate.seq == 3
    assert length(b_after_rehydrate.garage.vehicles) == 2
    assert b_after_rehydrate.garage.prefs == %{"unit_system" => "mi"}

    # And the second socket is now writable — the client's pending queue can
    # re-drive its un-acked mutation into a fresh stage_mutation on this
    # socket, which will get a fresh mutation_id and a fresh ack deadline.
    assert Session.mutations_enabled?(socket(view_b))
  end
end
