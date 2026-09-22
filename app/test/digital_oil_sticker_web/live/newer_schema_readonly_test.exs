defmodule DigitalOilStickerWeb.NewerSchemaReadonlyTest do
  @moduledoc """
  AC-11 / FR-11 no-downgrade guarantee: a payload whose `schema_version` is
  newer than the server understands must be rendered read-only, must show the
  read-only banner explaining why, must still offer an Export path, and must
  never trigger a server → client write-back.

  This is the safety property that keeps an older release from silently
  overwriting a newer format the browser already holds. A single stray
  `local_store:put` on a newer envelope would downgrade the data on disk.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  # `schema_version` is deliberately far past `Envelope.current_schema_version/0`
  # (currently 1), driving the `{:error, {:newer_than_server, _}}` branch in
  # `Session.handle_hydrate/2`.
  @newer_envelope %{
    "envelope" => "dos_local",
    "schema_version" => 99,
    "seq" => 5,
    "tab_id" => "tab-newer",
    "generated_at" => "2026-08-01T00:00:00Z",
    "data" => %{
      "meta" => %{"schema_version" => 99, "seq" => 5},
      "vehicles" => [],
      "events" => [],
      "readings" => [],
      "usage" => [],
      "reminders" => [],
      "prefs" => nil
    },
    "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
  }

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "a newer-schema payload renders the read-only banner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_hook(view, "local_store:hydrate", @newer_envelope)

    # The banner has no apostrophes, so match the full Copy string directly.
    assert html =~ Copy.read_only_banner()
    # Guard the distinctive phrase so a Copy rewrite that still explains the
    # newer-version situation keeps this test green.
    assert html =~ "data from a newer version"
  end

  test "a newer-schema payload lands in read_only: true, :loaded", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @newer_envelope)

    a = assigns(view)
    assert a.read_only == true
    assert a.local_state == :loaded
  end

  test "a newer-schema payload still offers an Export path", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    html = render_hook(view, "local_store:hydrate", @newer_envelope)

    # If we lock the UI without a way to get the data out, the user is stuck
    # with an unrecoverable browser — FR-11 requires the export escape hatch.
    assert html =~ "Export a file"
  end

  test "a newer-schema payload triggers no server → client write-back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @newer_envelope)

    # The core no-downgrade invariant: a `local_store:put` on a newer payload
    # would rewrite the browser's data in the older format on disk.
    refute_push_event(view, "local_store:put", %{})
  end

  test "mutations_enabled?/1 returns false while read_only is set", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    render_hook(view, "local_store:hydrate", @newer_envelope)

    socket = :sys.get_state(view.pid).socket
    refute Session.mutations_enabled?(socket)

    # And still no write was emitted while we checked the gate.
    refute_push_event(view, "local_store:put", %{})
  end

  test "an attempted mutation in read-only produces zero write events", %{conn: conn} do
    # The refute_push_event checks above prove the hydrate path emits nothing,
    # but a regression could add a write-back on a downstream event (form
    # submit, switcher click, erase) that only fires when the user tries to
    # act. Drive one such event and prove the guard holds there too.
    {:ok, view, _html} = live(conn, ~p"/settings/storage")

    render_hook(view, "local_store:hydrate", @newer_envelope)

    socket = :sys.get_state(view.pid).socket

    refute Session.mutations_enabled?(socket),
           "hydrated read-only state must still gate mutations"

    # Deliberately attempt the erase confirmation flow — the only mutating
    # control that stays available in read_only (per storage_recovery_test).
    # Erase is not a downgrade write — it pushes local_store:erase, not
    # local_store:put — so it is allowed. The invariant we assert here is
    # that the flow emits NO downgrade write (local_store:put) whatsoever,
    # not that erase itself is blocked.
    render_click(view, "ask_erase", %{})
    render_click(view, "confirm_erase", %{})

    refute_push_event(view, "local_store:put", %{})
  end

  test "newer-schema hydrate does not populate :garage — export flows directly from IndexedDB",
       %{conn: conn} do
    # AC-11 forbids downgrade AND dropped fields. Both are enforced by the
    # SAME rule: the newer_than_server branch takes ZERO writes and touches
    # ZERO of the newer payload's records. It sets read_only + :loaded and
    # leaves :garage empty on the server. That is the correct design: the
    # server cannot honestly render fields it does not understand, and
    # attempting to canonicalize them through Schema.V1 would strip
    # anything not in the current allowlist — the "dropped fields" case
    # AC-11 forbids on write-back.
    #
    # The user's data is safe because export runs client-side against
    # IndexedDB directly (assets/js/local_store/export.js), not against
    # server assigns. The read-only banner routes the user to
    # /settings/storage where that client-side export button fires.
    {:ok, view, _html} = live(conn, ~p"/")

    envelope_with_unknowns =
      Map.update!(@newer_envelope, "data", fn data ->
        %{
          data
          | "vehicles" => [
              %{
                "vehicle_id" => "77777777-7777-4777-8777-777777777777",
                "archived" => false,
                "future_field_v99" => "sentinel-newer-payload"
              }
            ]
        }
      end)

    render_hook(view, "local_store:hydrate", envelope_with_unknowns)

    a = assigns(view)

    # The invariant: :read_only is set and NO write-back is emitted.
    # Since :garage stays empty, no downgraded record can be serialized
    # into a local_store:put. That empty garage is what makes the
    # "no downgrade, no dropped fields" guarantee mechanical rather than
    # aspirational — there is nothing to downgrade because there is
    # nothing in :garage to write.
    assert a.read_only == true
    assert a.local_state == :loaded
    assert a.garage.vehicles == []
    assert a.garage.events == []

    refute_push_event(view, "local_store:put", %{})
  end
end
