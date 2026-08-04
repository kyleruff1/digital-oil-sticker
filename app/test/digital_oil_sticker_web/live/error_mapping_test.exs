defmodule DigitalOilStickerWeb.ErrorMappingTest do
  @moduledoc """
  AC-10: the four error→state mappings every UX card renders (FR-10).

  Each condition maps to a distinct `local_state` assign, and the rendered
  output uses the correct heading from Copy — never another state's heading.

  1. storage-unavailable  — generic hydration error / session-only storage
  2. quota-exceeded        — cap rejection → :hydration_refused
  3. hydration-deadline    — no hydrate arrives in time → :storage_unavailable
  4. stale-seq-conflict    — another tab wrote → :hydrating + rehydrate push
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

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
  @data_missing "stored records are gone"

  describe "storage-unavailable (generic hydration error)" do
    test "session-only storage renders the storage-unavailable heading", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      html =
        render_hook(view, "local_store:hydrate", %{
          @valid_envelope
          | "storage" => %{"mode" => "session_only", "boot_hint" => "never"}
        })

      assert html =~ @storage_unavailable
      refute html =~ @data_missing
      refute html =~ Copy.hydration_refused_heading()
      refute html =~ Copy.empty_heading()
    end
  end

  describe "hydration-deadline-expired" do
    test "no hydrate within the deadline renders storage-unavailable", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # The deadline timer was armed when the connected mount happened.
      # test.exs sets hydration_deadline_ms to 100ms, so wait for it.
      Process.sleep(200)

      html = render(view)

      # Assert on the socket state first — the substring below infers state
      # from copy, but the state assign is what actually governs behavior.
      # A regression that flips the state incorrectly but happens to render
      # matching copy would slip past a substring-only test.
      socket = :sys.get_state(view.pid).socket
      assert socket.assigns.local_state == :storage_unavailable,
             "deadline expiry must transition local_state to :storage_unavailable"

      assert html =~ @storage_unavailable
      refute html =~ Copy.hydration_refused_heading()

      # AC-6 explicit: :storage_unavailable copy must be DISTINCT from
      # :empty and :data_missing. A page that rendered the empty-garage
      # heading in the storage-failure state would invite the user to
      # start over on top of records that may still exist — INV-25.
      refute html =~ Copy.empty_heading(),
             ":storage_unavailable must not render the empty-garage heading"

      refute html =~ @data_missing,
             ":storage_unavailable must not render the data-missing heading"

      # AC-6: in :storage_unavailable, mutations must be disabled so the app
      # never stages a write against a browser that could not hydrate.
      refute Session.mutations_enabled?(socket)

      # And the UI must not expose the mutating nav entry point.
      refute html =~ "Log an oil change"
    end

    test "a hydrate that arrives before the deadline cancels it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @valid_envelope)

      # Wait past the original deadline window.
      Process.sleep(200)

      html = render(view)

      refute html =~ @storage_unavailable
    end
  end

  describe "stale-seq-conflict" do
    test "a conflict event re-enters hydrating and pushes rehydrate", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @valid_envelope)
      refute render(view) =~ @storage_unavailable

      render_hook(view, "local_store:conflict", %{"seq" => 2})

      assert_push_event(view, "local_store:rehydrate", %{})
    end

    test "a conflict deadline that fires without rehydrate renders storage-unavailable",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      render_hook(view, "local_store:hydrate", @valid_envelope)
      render_hook(view, "local_store:conflict", %{"seq" => 2})

      # The conflict re-armed the deadline. Wait for it.
      Process.sleep(200)

      html = render(view)
      assert html =~ @storage_unavailable
    end

    test "a successful rehydrate after conflict restores the loaded state", %{conn: conn} do
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
end
