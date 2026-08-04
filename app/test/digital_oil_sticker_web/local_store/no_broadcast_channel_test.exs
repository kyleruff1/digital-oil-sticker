defmodule DigitalOilStickerWeb.LocalStore.NoBroadcastChannelTest do
  @moduledoc """
  AC-16: BroadcastChannel absent — CAS still surfaces conflict on next mount.

  BroadcastChannel is a client-side concern (assets/js/local_store/broadcast.js):
  when a sibling tab commits a write, it publishes on the channel so peers can
  refresh their in-memory view before staging their next mutation. When
  BroadcastChannel is unavailable (Safari private, certain WebView contexts,
  or the API is simply missing), peers do not learn of sibling writes until
  their own next mutation attempt.

  The server does not touch BroadcastChannel. What it owns for AC-16 is the
  compare-and-set safety net: if a tab that missed the broadcast stages a
  write against a stale seq, the client-side CAS in idb.js fails, the client
  emits `local_store:conflict`, and the server rehydrates. That server-side
  fallback path must fire identically regardless of whether a broadcast ever
  happened — no prior broadcast is a precondition, not a blocker.

  This test asserts the server's `local_store:conflict` handling works when
  the conflict is delivered "cold" (no prior broadcast round-trip modeled).
  The same code path as G9 covers, framed as the BroadcastChannel-absent
  scenario. The client-side CAS behavior in the absence of BroadcastChannel
  is exercised by the JS conformance suite (assets/js/**/*.test.js) — not
  reachable from ExUnit.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @valid_envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 1,
    "tab_id" => "t",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => nil,
      "vehicles" => [
        %{"vehicle_id" => "00000001-0000-4000-8000-000000000001", "archived" => false}
      ],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  # HEEx escapes apostrophes to &#39;, so match substrings without them.
  @storage_unavailable "storage could not be used"

  test "conflict delivered without any prior broadcast pushes rehydrate", %{conn: conn} do
    # Simulates a tab that never received a BroadcastChannel notification
    # from a sibling write: it mounts, hydrates, then attempts a mutation
    # whose client-side CAS against IndexedDB fails. The client emits
    # `local_store:conflict`; the server must fall back to rehydrate.
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @valid_envelope)
    refute render(view) =~ @storage_unavailable

    # No BroadcastChannel event ever happened in this session — the conflict
    # arrives cold, straight from a failed client-side CAS.
    render_hook(view, "local_store:conflict", %{"seq" => 2})

    assert_push_event(view, "local_store:rehydrate", %{})
  end

  test "conflict without broadcast re-arms the hydration deadline", %{conn: conn} do
    # If the rehydrate never lands, the safety-net path still surfaces the
    # storage-unavailable card — proving the deadline was actually re-armed
    # by handle_conflict/2 and not silently swallowed.
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @valid_envelope)
    render_hook(view, "local_store:conflict", %{"seq" => 2})

    # test.exs sets hydration_deadline_ms to 100ms; wait 2x margin.
    Process.sleep(200)

    html = render(view)
    assert html =~ @storage_unavailable
    refute html =~ Copy.hydration_refused_heading()
  end

  test "conflict without broadcast is followed by a clean rehydrate", %{conn: conn} do
    # End-to-end: cold conflict → rehydrate at the new seq → loaded state
    # restored. Confirms the server's fallback is not merely a one-way trip
    # to :hydrating; the tab recovers just as it does when a broadcast
    # preceded the CAS failure.
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @valid_envelope)
    render_hook(view, "local_store:conflict", %{"seq" => 2})

    html =
      render_hook(view, "local_store:hydrate", %{
        @valid_envelope
        | "seq" => 2
      })

    refute html =~ @storage_unavailable
    refute html =~ Copy.hydration_refused_heading()
  end
end
