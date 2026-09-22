defmodule DigitalOilStickerWeb.LocalStore.TwoTabConflictTest do
  @moduledoc """
  AC-15: the server-side stale-seq conflict path.

  When another tab (the "second tab") wins the CAS race and writes a newer
  `seq`, this tab's next put lands as a conflict. The server-owned handler
  in `Session.handle_conflict/2` is the invariant this test protects:

    1. re-enter the `:hydrating` skeleton (mutations paused, spinner shown)
    2. raise the `:conflict_notice` flag (the "we caught it" signal)
    3. push `local_store:rehydrate` so the client re-reads from IndexedDB
    4. re-arm the hydration deadline so a dropped rehydrate degrades to
       `:storage_unavailable` instead of leaving the tab a frozen skeleton
    5. accept a fresh hydrate at the newer `seq` and land back in `:loaded`

  `error_mapping_test.exs` covers step (3)'s push and the deadline re-arm in
  isolation. This file exercises the full round-trip — conflict in, rehydrate
  out, fresh envelope back, `:loaded` restored — which is the actual sequence
  the two-tab race triggers in production.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @valid_envelope %{
    "envelope" => "dos_local",
    "schema_version" => 1,
    "seq" => 1,
    "tab_id" => "tab-b",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 1, "seq" => 1},
      "vehicles" => [
        %{
          "vehicle_id" => "22222222-2222-4222-8222-222222222222",
          "nickname" => "Wagon",
          "archived" => false
        }
      ],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp assigns(view) do
    :sys.get_state(view.pid).socket.assigns
  end

  test "conflict routes back to :hydrating, sets the notice flag, and pushes rehydrate",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Tab B lands the initial hydrate at seq=1 and settles into :loaded.
    render_hook(view, "local_store:hydrate", @valid_envelope)
    before = assigns(view)
    assert before.local_state == :loaded
    assert before.seq == 1
    # No conflict has been seen yet — the flag is either missing or false.
    refute Map.get(before, :conflict_notice) == true

    # Tab A wrote at seq=2 first; Tab B's next put loses the CAS race and the
    # client reports the conflict. This is the event handle_conflict/2 owns.
    render_hook(view, "local_store:conflict", %{
      "seq" => 2,
      "reason" => "stale_seq_cas_failed"
    })

    after_conflict = assigns(view)

    assert after_conflict.local_state == :hydrating,
           "handle_conflict must re-enter :hydrating so mutations pause"

    assert after_conflict.conflict_notice == true,
           "handle_conflict must raise :conflict_notice so the reload notice is shown"

    # The deadline must be RE-ARMED — otherwise a dropped rehydrate would
    # leave this tab a permanent skeleton. Contract: a fresh ref is assigned.
    assert is_reference(after_conflict.hydration_deadline_ref)

    # And the client must be asked to re-read local storage.
    assert_push_event(view, "local_store:rehydrate", %{})

    # The user must see WHY the tab just changed. `Copy.sr_checking()` is
    # also on-screen because we're back in :hydrating, but it does not
    # explain the reload — a tab that skipped the notice would still show
    # it, so asserting only sr_checking would miss a missing-banner
    # regression. `Copy.conflict_notice()` is the actual "we caught it"
    # signal and is only rendered when @conflict_notice is truthy.
    # HEEx escapes the apostrophe in "browser's" to &#39;, so match on an
    # apostrophe-free substring (same pattern as error_mapping_test.exs).
    html = render(view)

    assert html =~ "Reloaded from this",
           "the conflict-notice banner must render so the user is told a sibling tab wrote newer data"

    assert html =~ ~s(data-test="conflict-notice"),
           "the notice must carry its data-test id so downstream tests can anchor on it"
  end

  test "a fresh hydrate at the newer seq restores :loaded after conflict",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @valid_envelope)
    render_hook(view, "local_store:conflict", %{"seq" => 2})

    # Sanity: the conflict put us back into :hydrating.
    assert assigns(view).local_state == :hydrating

    # The client obeys the rehydrate push and sends the newer envelope.
    render_hook(view, "local_store:hydrate", %{@valid_envelope | "seq" => 2})

    settled = assigns(view)

    assert settled.local_state == :loaded,
           "a successful rehydrate at the newer seq must clear :hydrating and land in :loaded"

    assert settled.seq == 2

    # The deadline was cancelled on the successful hydrate.
    assert settled.hydration_deadline_ref == nil

    # And the skeleton "checking" notice is gone — the tab is live again.
    refute render(view) =~ Copy.sr_checking()
  end
end
