defmodule DigitalOilStickerWeb.LocalStore.IdempotenceTest do
  @moduledoc """
  AC-5 / ADR-0004 §"Enforcement" bullet 4: hydrating the same payload twice
  produces identical assigns and emits no write-back.

  Idempotence is the safety property that lets a reconnect re-hydrate without
  a compare-and-set race: the browser is free to send the same envelope again
  after a socket drop, and the server must land in the same state — same
  garage, same seq, same storage mode — without shipping a `local_store:put`
  the client will see as an unexpected write.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 4,
    "tab_id" => "tab-abc",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 4},
      "vehicles" => [
        %{
          "vehicle_id" => "11111111-1111-4111-8111-111111111111",
          "nickname" => "Truck",
          "archived" => false
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

  defp assigns_snapshot(view) do
    :sys.get_state(view.pid).socket.assigns
    |> Map.take([:local_state, :seq, :garage, :storage_mode, :read_only, :quarantine])
  end

  test "the same envelope hydrated twice lands in identical assigns", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @envelope)
    first = assigns_snapshot(view)

    render_hook(view, "local_store:hydrate", @envelope)
    second = assigns_snapshot(view)

    assert first == second
    assert first.local_state == :loaded
    assert first.seq == 4
  end

  test "a re-hydrate emits no server → client write-back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @envelope)
    render_hook(view, "local_store:hydrate", @envelope)

    # A stray `local_store:put` on a passive re-hydrate would look like a
    # spontaneous mutation to the client — the exact class of write the
    # idempotence rule forbids.
    refute_push_event(view, "local_store:put", %{})
  end
end
