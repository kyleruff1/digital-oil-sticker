defmodule DigitalOilStickerWeb.StorageStateBannerTest do
  @moduledoc """
  The :data_missing and deadline-flavored :storage_unavailable states disable
  every write, but before these banners existed they had no surface outside
  the sticker page and /settings/storage — on /vehicle/select the lockout was
  invisible until a save failed with a flash that read as a form error. These
  tests pin the banners to the states, and pin that the two never stack on
  top of the session-only banner.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @empty_data %{
    "meta" => nil,
    "vehicles" => [],
    "events" => [],
    "readings" => [],
    "usage" => [],
    "reminders" => [],
    "prefs" => nil
  }

  defp hydrate(view, storage) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 0,
      "tab_id" => "test-tab",
      "generated_at" => "2026-09-22T00:00:00Z",
      "data" => @empty_data,
      "storage" => storage
    })
  end

  describe ":data_missing (empty stores, boot hint says data existed)" do
    test "banner renders on /vehicle/select", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      html = hydrate(view, %{"mode" => "idb", "boot_hint" => "has_data"})

      assert has_element?(view, "[data-test=data-missing-banner]")
      assert html =~ "stored records are gone"
      refute has_element?(view, "[data-test=storage-unavailable-banner]")
    end

    test "banner renders on /history", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/history")
      hydrate(view, %{"mode" => "idb", "boot_hint" => "has_data"})

      assert has_element?(view, "[data-test=data-missing-banner]")
    end

    test "no banner on a genuine first visit", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      hydrate(view, %{"mode" => "idb", "boot_hint" => "never"})

      refute has_element?(view, "[data-test=data-missing-banner]")
      refute has_element?(view, "[data-test=storage-unavailable-banner]")
    end
  end

  describe ":storage_unavailable without a session_only envelope" do
    test "an undecodable hydrate surfaces the storage-unavailable banner", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      html = render_hook(view, "local_store:hydrate", %{"not" => "an envelope"})

      assert has_element?(view, "[data-test=storage-unavailable-banner]")
      assert html =~ "storage could not be used"
      refute has_element?(view, "[data-test=data-missing-banner]")
    end

    test "a session_only envelope keeps ITS banner and never shows two", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")

      hydrate(view, %{
        "mode" => "session_only",
        "reason" => "open_timeout",
        "boot_hint" => "never"
      })

      assert has_element?(view, "[data-test=session-only-banner]")
      refute has_element?(view, "[data-test=storage-unavailable-banner]")
      refute has_element?(view, "[data-test=data-missing-banner]")
    end
  end

  describe "pages with their own full-page view stay banner-free" do
    test "the sticker page renders its :data_missing view, not the banner", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, %{"mode" => "idb", "boot_hint" => "has_data"})

      assert html =~ "stored records are gone"
      refute has_element?(view, "[data-test=data-missing-banner]")
    end
  end
end
