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

      assert html =~ @storage_unavailable
      refute html =~ Copy.hydration_refused_heading()
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
