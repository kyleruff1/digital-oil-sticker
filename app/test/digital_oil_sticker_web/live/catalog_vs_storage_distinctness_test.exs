defmodule DigitalOilStickerWeb.CatalogVsStorageDistinctnessTest do
  @moduledoc """
  DOS-M09-003 AC-15 / FR-18 / INV-7: a catalog-outcome result and a
  storage-loss condition must render distinguishable screens; neither is
  described as the other. "No data for this vehicle" is never shown for a
  connection or storage failure, and a storage failure is never dressed up
  as "we couldn't find your configuration."

  M09-003 explicitly EXCLUDES the connectivity / catalog-DOWN state — that
  belongs to the connectivity work. What this file locks in is the copy
  boundary on the two states that DO live in the storage milestone: a
  hydrated vehicle whose exact configuration the catalog cannot match, and
  a session-only browser that cannot persist anything. The two share no
  headings, no bodies, and no fallback string.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @vehicle_id "11111111-1111-4111-8111-111111111111"

  # HEEx escapes ' to &#39; in the rendered HTML, so a raw Copy string that
  # contains an apostrophe never matches its own rendered form. Wrap Copy
  # values in this helper before searching the html so a Copy rename really
  # does trip the assertion — otherwise `refute` on an apostrophe-bearing
  # heading is a tautology and `assert` on one never matches.
  defp html_escape(str), do: Plug.HTML.html_escape(str)

  defp hydrate(view, overrides) do
    render_hook(
      view,
      "local_store:hydrate",
      Map.merge(
        %{
          "envelope" => "dos_local",
          "schema_version" => 1,
          "seq" => 1,
          "tab_id" => "t",
          "generated_at" => "2026-08-02T00:00:00Z",
          "data" => %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "never"}
        },
        overrides
      )
    )
  end

  test "an unmatched catalog configuration renders catalog copy, not storage-loss copy", %{
    conn: conn
  } do
    # The vehicle profile is where the app publishes its catalog-side answer
    # for the current selection. Hydrate a vehicle whose configuration_key
    # is not one the shipped catalog knows and whose display snapshot
    # carries "Not specified" for build — the exact shape a picker save
    # produces when the cascade never resolved to a full trim. The
    # precision badge fires, and the schedule line honestly says the
    # manufacturer source is not available. Storage is healthy IDB, so no
    # storage-loss frame is warranted.
    {:ok, view, _} = live(conn, ~p"/vehicle")

    vehicle = %{
      "vehicle_id" => @vehicle_id,
      "archived" => false,
      "model_year" => 2020,
      # Deliberately not a configuration_key any fixture catalog row uses.
      "configuration_key" => "does-not-exist-in-fixture-catalog",
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        # Matches Copy.not_specified() as a substring, which is the
        # condition the precision badge renders on.
        "build" => "2020 — Not specified"
      },
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => %{}
    }

    html =
      hydrate(view, %{
        "data" => %{
          "meta" => nil,
          "vehicles" => [vehicle],
          "events" => [],
          "readings" => [],
          "usage" => [],
          "reminders" => [],
          "prefs" => %{"active_vehicle_id" => @vehicle_id}
        }
      })

    # The catalog-outcome copy — precise about what the catalog CAN and
    # cannot tell us, without borrowing storage-loss language.
    assert html =~ Copy.precision_unverified()
    assert html =~ Copy.source_unavailable()

    # None of the storage-loss headings apply — the records are intact, so
    # the frame the user sees must not blame their browser. Apostrophe-free
    # substrings, because HEEx escapes ' to &#39; in the rendered HTML.
    refute html =~ "stored records are gone"
    refute html =~ "storage could not be used"
    refute html =~ "more than we will load at once"
  end

  test "session-only storage renders storage-loss copy, not catalog copy", %{conn: conn} do
    # The sticker page renders the storage-loss headings. session_only
    # mode resolves to :storage_unavailable in Session.resolve_state/2,
    # and its heading is one no catalog surface ever emits.
    {:ok, view, _} = live(conn, ~p"/")

    html =
      hydrate(view, %{"storage" => %{"mode" => "session_only", "reason" => "unavailable"}})

    # The storage-loss frame is visible. Apostrophe-free substring of
    # Copy.storage_unavailable_heading().
    assert html =~ "storage could not be used"

    # Copy-locked: pin the whole heading, not just a substring, so a Copy
    # rename that reused the catalog-side wording ("The vehicle storage
    # could not be read", say) would fail here — the substring check above
    # would still pass, but the exact Copy string would not appear. This
    # is the symmetric half of the catalog-error test below, and together
    # they catch a Copy rename in BOTH directions.
    assert html =~ html_escape(Copy.storage_unavailable_heading())

    # No catalog-outcome copy is co-opted for this state. A storage
    # failure is not "we could not verify your configuration"; it is not
    # "no catalog match"; it is not "the catalog could not be read".
    refute html =~ Copy.precision_unverified()
    refute html =~ Copy.no_catalog_match()
    refute html =~ Copy.catalog_unreadable()
  end

  test "a catalog-read failure renders catalog-unreadable copy, not storage-loss copy",
       %{conn: conn} do
    # VehiclePickerLive's run/4 folds every cascade-side error into the
    # @catalog_error assign, which is exactly the assign the mount reaches
    # for when Catalog.list_years returns nothing. A cascade_change with a
    # year outside the catalog's window fails Selector.validate with
    # {:error, :invalid_selector} and lands on the catch-all clause in
    # run/4 — flipping @catalog_error to :catalog_unavailable and rendering
    # the catalog-unreadable alert. Storage was never touched, so no
    # storage-loss frame is warranted.
    {:ok, view, _} = live(conn, ~p"/vehicle/select")

    html =
      render_hook(view, "cascade_change", %{
        "year" => "9999",
        "make_id" => "",
        "model_id" => "",
        "configuration_key" => ""
      })

    # The catalog-outcome frame is visible.
    assert html =~ Copy.catalog_unreadable()

    # None of the storage-loss headings apply — nothing in the browser is
    # gone, nothing was refused, storage itself is fine. A Copy rename that
    # made any storage-loss heading collide with this catalog-side one
    # would trip these refutes.
    refute html =~ html_escape(Copy.storage_unavailable_heading())
    refute html =~ html_escape(Copy.data_missing_heading())
    refute html =~ html_escape(Copy.hydration_refused_heading())
  end
end
