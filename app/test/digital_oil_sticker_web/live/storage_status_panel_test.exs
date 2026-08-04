defmodule DigitalOilStickerWeb.StorageStatusPanelTest do
  @moduledoc """
  INV-25 honesty surface guard for /settings/storage.

  This is the ONE page whose whole job is to tell the user the truth about
  where their records live: in this browser, on this device, no account,
  no server copy, and only an export file keeps or moves them. That truth
  is delivered by `Copy.empty_body()` and must render in every storage
  state the LiveView can be in — because the states most tempted to hide it
  (`:storage_unavailable`, `:hydration_refused`, `read_only`, `:data_missing`)
  are exactly the states where the user most needs it.

  This test does not care how the state line reads; other tests own that.
  It only asserts that in each of the seven states, the four INV-25 clauses
  are present:

    (a) "stored in this browser" / "on this device"
    (b) at least one loss condition (clearing site data / eviction /
        private browsing / uninstalling / switching devices)
    (c) BOTH "no account" AND "no copy on our server" (both halves are
        load-bearing; an OR check would let a regression that deletes
        one still pass)
    (d) export named as THE recovery — the "only way to keep" phrasing
        from Copy.empty_body's closing sentence, NOT just the word
        "export" (which would match the button label alone and hide a
        regression that strips the disclosure sentence)

  A second describe block guards the reachability half of the same
  invariant: the /settings/storage page must be linked from the main
  layout's <nav>, or the honesty surface is unreachable and the
  disclosure content above is dead code.

  A regression that wraps `Copy.empty_body()` in a `:if` on `@local_state`
  — or moves it under a state whose branch happens not to render it — is
  exactly the drift this test exists to fail on.

  HEEx escapes apostrophes to `&#39;`; every substring below is chosen
  without one.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.LocalStore.Caps

  # ------------------------------------------------------------------ helpers

  defp hydrate(view, overrides) do
    render_hook(
      view,
      "local_store:hydrate",
      Map.merge(
        %{
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
          "storage" => %{"mode" => "idb", "boot_hint" => "never"}
        },
        overrides
      )
    )
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  # A minimal V1-valid vehicle so `Validation.validate/2` accepts it and
  # `resolve_state/2` resolves to `:loaded` instead of falling through the
  # empty branches.
  defp one_valid_vehicle do
    [%{"vehicle_id" => "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "archived" => false}]
  end

  # An over-cap payload triggers `{:error, {:cap_exceeded, :vehicles}}` in
  # `Session.handle_hydrate/2`, landing in `:hydration_refused`.
  defp too_many_vehicles do
    for i <- 1..(Caps.max_vehicles() + 1) do
      %{
        "vehicle_id" =>
          "1111111#{rem(i, 10)}-1111-4111-8111-#{String.pad_leading("#{i}", 12, "0")}",
        "archived" => false
      }
    end
  end

  # The four INV-25 clauses. Each is asserted independently so a failure
  # names which clause vanished (the test's whole reason for existing).
  #
  # `state` is only used to make the failure message point at the state
  # under test — the assertions themselves are identical for every state,
  # because that IS the invariant.
  defp assert_inv25_disclosure(html, state) do
    # (a) this-browser-on-this-device framing
    assert String.contains?(html, ["stored in this browser", "on this device"]),
           "state=#{state}: INV-25 clause (a) missing — no 'stored in this browser' / 'on this device' framing on /settings/storage"

    # (b) at least one loss condition — any of the five enumerated in
    # Copy.empty_body/0
    assert String.contains?(html, [
             "Clearing your site data",
             "browser storage eviction",
             "private browsing",
             "uninstalling",
             "switching devices"
           ]),
           "state=#{state}: INV-25 clause (b) missing — no loss condition (clearing / eviction / private browsing / uninstall / switching) on /settings/storage"

    # (c) no account AND no server copy — both halves are required. An
    # OR match would let a regression that deletes "no copy on our server"
    # from Copy.empty_body pass while leaving "no account" alive (and
    # vice-versa); INV-25 needs both facts stated on this page.
    assert String.contains?(html, "no account"),
           "state=#{state}: INV-25 clause (c) missing — no 'no account' disclosure on /settings/storage"

    assert String.contains?(html, "no copy on our server"),
           "state=#{state}: INV-25 clause (c) missing — no 'no copy on our server' disclosure on /settings/storage"

    # (d) export as the recovery mechanism. Anchored on the "only way"
    # phrasing from Copy.empty_body's closing sentence — "Exporting a file
    # is the only way to keep or move them." — because a bare
    # case-insensitive /export/ match would still pass on the "Export a
    # file" button label alone, allowing a regression that strips the
    # disclosure sentence to sneak through. The button is not the
    # invariant; the prose that names export as THE recovery is.
    assert String.contains?(html, "only way to keep"),
           "state=#{state}: INV-25 clause (d) missing — no 'only way to keep' framing (Copy.empty_body's export-as-only-recovery sentence) on /settings/storage"
  end

  # ------------------------------------------------------------------- tests

  describe "the INV-25 disclosure renders in every storage state" do
    test ":hydrating (before any hydrate arrives)", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings/storage")

      # Sanity: no hydrate has fired, so the state machine is still in the
      # initial :hydrating assign from Session.init/1.
      assert assigns(view).local_state == :hydrating

      assert_inv25_disclosure(html, :hydrating)
    end

    test ":loaded (populated envelope)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{
          "data" => %{
            "meta" => nil,
            "vehicles" => one_valid_vehicle(),
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          }
        })

      assert assigns(view).local_state == :loaded

      assert_inv25_disclosure(html, :loaded)
    end

    test ":empty (empty payload with meta.seq > 0 — an intentionally emptied garage)",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      # meta.seq > 0 is what tells resolve_state/2 this store was emptied
      # on purpose (deleting the last vehicle) rather than never populated.
      html =
        hydrate(view, %{
          "seq" => 3,
          "data" => %{
            "meta" => %{"schema_version" => 1, "seq" => 3},
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          }
        })

      assert assigns(view).local_state == :empty

      assert_inv25_disclosure(html, :empty)
    end

    test ":data_missing (empty payload + boot_hint has_data — evicted store)",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{"storage" => %{"mode" => "idb", "boot_hint" => "has_data"}})

      assert assigns(view).local_state == :data_missing

      assert_inv25_disclosure(html, :data_missing)
    end

    test ":storage_unavailable (session_only storage mode)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{"storage" => %{"mode" => "session_only", "boot_hint" => "never"}})

      # resolve_state/2 short-circuits session_only to :storage_unavailable,
      # and the storage_mode assign records the wire mode separately.
      a = assigns(view)
      assert a.local_state == :storage_unavailable
      assert a.storage_mode == :session_only

      assert_inv25_disclosure(html, :storage_unavailable)
    end

    test ":hydration_refused (over-cap payload)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{
          "seq" => 1,
          "data" => %{
            "meta" => nil,
            "vehicles" => too_many_vehicles(),
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert assigns(view).local_state == :hydration_refused

      assert_inv25_disclosure(html, :hydration_refused)
    end

    test "read_only (schema_version > server)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{
          "schema_version" => 99,
          "seq" => 5,
          "data" => %{"meta" => %{"schema_version" => 99, "seq" => 5}},
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      # The newer-schema branch sets read_only + :loaded and takes zero
      # writes off the payload — the panel must still tell the truth about
      # where records live, because the export button on this very page is
      # the user's only exit.
      a = assigns(view)
      assert a.read_only == true
      assert a.local_state == :loaded

      assert_inv25_disclosure(html, :read_only)
    end
  end

  describe "the /settings/storage honesty surface is reachable from the main nav" do
    test "Layouts.app renders a Storage link to /settings/storage inside a <nav>",
         %{conn: conn} do
      # A perfectly-worded disclosure on /settings/storage is worthless if
      # nothing links to it. This test guards the reachability half of
      # INV-25: deleting the Storage <.link> from Layouts.app's header
      # <nav> (layouts.ex ~line 144) must fail this test.
      #
      # Uses the disconnected HTTP render of any page that mounts the
      # main layout ("/" — StickerLive) rather than /settings/storage
      # itself, so a bug that leaves the link visible only on the storage
      # page cannot mask a missing nav entry elsewhere.
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(href="/settings/storage"),
             "Expected an href=\"/settings/storage\" link in the layout of /"

      # Require the link sits inside a <nav> element, not orphaned as an
      # inline link buried in body copy. The main-menu <nav> in
      # Layouts.app is what makes Storage a first-class navigation
      # destination.
      assert Regex.match?(
               ~r/<nav[^>]*>[\s\S]*?href="\/settings\/storage"[\s\S]*?<\/nav>/,
               html
             ),
             "Expected the /settings/storage link to live inside a <nav> element on /"
    end
  end
end
