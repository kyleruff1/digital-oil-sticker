defmodule DigitalOilStickerWeb.StorageRecoveryTest do
  @moduledoc """
  The recovery half of the storage page: importing an export file and erasing
  everything.

  The states that need these controls MOST are the states that gate everything
  else off — :data_missing (evicted store, an export file in hand) and
  read_only (a newer release's data). A recovery control gated behind
  mutations_enabled? would be a fire escape locked from the inside, so the
  assertions here are as much about AVAILABILITY in bad states as about the
  controls themselves.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

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

  describe "the import panel" do
    test "renders with its strings server-side, where the copy-lint can see them", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      html = hydrate(view, %{})

      assert html =~ "data-test=\"import-panel\""
      assert html =~ Copy.import_heading()
      assert html =~ "is not uploaded anywhere"
      # Every failure message is pre-rendered; the hook only toggles which is
      # visible, so no client code composes user-facing text.
      assert html =~ Copy.import_invalid()
      assert html =~ "integrity hash"
      assert html =~ "newer version of the app"
    end

    test "is present in the evicted-store state it exists for", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      html =
        hydrate(view, %{"storage" => %{"mode" => "idb", "boot_hint" => "has_data"}})

      # Substring without the apostrophe: HEEx escapes it to an entity.
      assert html =~ "stored records are gone"
      assert html =~ "data-test=\"import-panel\""
      assert html =~ "data-test=\"erase-panel\""

      # AC-2 negative half: the :data_missing render must not carry the
      # :empty first-visit HEADING — a returning user whose browser
      # cleared its site data must not be greeted as a first-time
      # visitor. The state line above the disclosure is what distinguishes
      # states, and Copy.empty_heading() ("Set up your first vehicle")
      # never appears on the storage panel in any state.
      #
      # The INV-25 disclosure prose (Copy.empty_body/0, which contains
      # "no account and no copy on our server") DOES render here — it
      # renders in every state on /settings/storage on purpose, because
      # the states most tempted to hide it are the states where the user
      # most needs it. See storage_status_panel_test.exs (AC-13) for the
      # positive assertion that INV-25 holds in :data_missing.
      refute html =~ Copy.empty_heading()

      # Sharper refutation on the same axis: the state_line shown above
      # the disclosure must reflect :data_missing, not :empty. The :empty
      # state_line is a first-visit reassurance ("Nothing is stored in
      # this browser yet."); rendering it in :data_missing would tell a
      # returning user with an export in hand that they never had data,
      # inverting the meaning of the panel. Refuting the exact substring
      # (rather than only the :empty HEADING) catches an unconditional
      # "getting started" hint being sprinkled into every state.
      refute html =~ "Nothing is stored in this browser yet."
    end
  end

  describe "the erase control" do
    test "one click never erases — it opens the confirmation", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate(view, %{})

      refute render(view) =~ "data-test=\"erase-modal\""

      html = render_click(view, "ask_erase", %{})

      assert html =~ "data-test=\"erase-modal\""
      assert html =~ "no other copy anywhere"
      refute_push_event(view, "local_store:erase", %{})
    end

    test "cancelling closes the modal and pushes nothing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate(view, %{})
      render_click(view, "ask_erase", %{})

      html = render_click(view, "cancel_erase", %{})

      refute html =~ "data-test=\"erase-modal\""
      refute_push_event(view, "local_store:erase", %{})
    end

    test "confirming pushes the erase event to the client", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")
      hydrate(view, %{})
      render_click(view, "ask_erase", %{})

      html = render_click(view, "confirm_erase", %{})

      assert_push_event(view, "local_store:erase", %{})
      refute html =~ "data-test=\"erase-modal\""
    end

    test "works in the read-only newer-schema state, where it is the only exit", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/settings/storage")

      hydrate(view, %{
        "schema_version" => 99,
        "seq" => 5,
        "data" => %{"meta" => %{"schema_version" => 99, "seq" => 5}},
        "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
      })

      # The session is read_only: ordinary mutations are refused. Erase is
      # deliberately not one of them — erasing is how this state ends.
      render_click(view, "ask_erase", %{})
      render_click(view, "confirm_erase", %{})

      assert_push_event(view, "local_store:erase", %{})
    end
  end
end
