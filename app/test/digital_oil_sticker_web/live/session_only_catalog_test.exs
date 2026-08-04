defmodule DigitalOilStickerWeb.SessionOnlyCatalogTest do
  @moduledoc """
  AC-7: catalog browsing must keep working when the browser refuses to store
  anything. The vehicle-picker cascade (Year → Make → Model → Build) is
  driven entirely by server-side queries against the impersonal catalog; it
  does not touch IndexedDB. Session-only storage should therefore have no
  effect on lookup — the user can still find their vehicle. What session-only
  does affect is confirmation (nothing gets written), but that is a separate
  path and a separate story from browsing.

  The page must also not slip into outage framing ("broken", "failure",
  "the app cannot") when storage is unavailable. The honest framing is that
  entries will not be stored — not that the app itself is down.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias DigitalOilStickerWeb.LocalStore.Session

  # Outage-flavored phrasing the picker must never render, even under
  # session-only storage. "Not stored" is honest; "broken" implies the app
  # itself failed. The lists in copy_lint_test.exs cover global prohibited
  # marketing/framing terms; these are outage-specific and local to this AC.
  @outage_phrases ["broken", "failure", "app cannot", "the app is down"]

  defp any_row do
    DigitalOilSticker.CatalogRepo.one(
      from(c in "vehicle_configurations",
        join: m in "makes",
        on: m.id == c.make_id,
        select: %{
          year: c.model_year,
          make_id: c.make_id,
          model_id: c.model_id,
          make_name: m.display_name
        },
        limit: 1
      )
    )
  end

  defp hydrate_session_only(view) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 0,
      "tab_id" => "t",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => [],
        "events" => [],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "session_only", "reason" => "unavailable"}
    })
  end

  defp refute_outage(html, where) do
    lower = String.downcase(html)

    for phrase <- @outage_phrases do
      refute lower =~ phrase,
             "#{where} rendered outage phrase #{inspect(phrase)} under session-only storage"
    end
  end

  test "the year list is present pre-hydrate — mount reads it from the catalog", %{conn: conn} do
    # The years dropdown is populated in mount/3 before any hydrate arrives,
    # so a session-only browser cannot degrade year lookup even in theory —
    # the catalog call runs before the storage state is known.
    {:ok, _view, html} = live(conn, ~p"/vehicle/select")
    row = any_row()

    assert html =~ to_string(row.year),
           "the year #{row.year} must appear as a cascade option from mount"

    refute_outage(html, "static mount")
  end

  test "session-only hydrate lets the cascade populate makes for a chosen year", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle/select")
    hydrate_session_only(view)

    row = any_row()

    # Selecting a year triggers list_makes; the result populates the make
    # dropdown. This is the surface the AC guards: catalog IO is untouched
    # by the storage mode, so the make labels for the chosen year must
    # actually render.
    html = render_change(view, "cascade_change", %{"year" => to_string(row.year)})

    assert html =~ row.make_name,
           "make #{row.make_name} for year #{row.year} did not appear after cascade_change"

    # And the session's local_state has landed on :storage_unavailable — the
    # state assign is what governs mutability elsewhere. The picker page
    # itself never claims the app is down.
    socket = :sys.get_state(view.pid).socket
    assert socket.assigns.local_state == :storage_unavailable
    refute Session.mutations_enabled?(socket)

    refute_outage(html, "picker after selecting a year")
  end

  test "selecting a make then loads models — the second cascade level also works", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle/select")
    hydrate_session_only(view)

    row = any_row()

    render_change(view, "cascade_change", %{"year" => to_string(row.year)})

    html =
      render_change(view, "cascade_change", %{
        "year" => to_string(row.year),
        "make_id" => row.make_id
      })

    # The count announcement is our proof the models query returned rows —
    # it says "N models" for a populated result and "N models shown — …"
    # when the total is unknown. Either wording confirms the catalog call
    # completed and the dropdown was populated.
    assert html =~ ~r/\d+ (?:model|models)( shown)?/,
           "models cascade did not announce a populated result"

    refute_outage(html, "picker after selecting a make")
  end

  test "history renders without error in session-only mode", %{conn: conn} do
    # A catalog-adjacent read-only surface: /history has no records to show
    # (session-only starts empty), but the page itself must render cleanly.
    # A crash or an outage-flavored banner here would suggest storage failure
    # is fatal to the whole app, which it is not.
    {:ok, view, _html} = live(conn, ~p"/history")
    html = hydrate_session_only(view)

    assert html =~ "History"
    refute_outage(html, "/history under session-only")
  end
end
