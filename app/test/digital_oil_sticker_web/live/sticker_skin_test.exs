defmodule DigitalOilStickerWeb.StickerSkinTest do
  @moduledoc """
  The sticker skin system: six named looks driven by CSS custom properties
  under a `data-skin` attribute, chosen from a picker on `/` and persisted in
  the browser's prefs singleton.

  The invariants under test:

    * the pref writes through the same staged-mutation path as every other
      prefs write — unknown fields stay flat, quarantine refuses, read-only
      refuses;
    * an unknown skin value falls back to the default at render time and is
      never "repaired" by a write-back;
    * `data-skin` tracks the optimistically-applied garage instantly (the
      repaint IS the feedback);
    * the picker exists only where the sticker does, and each button carries
      its accessible state.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.{Copy, Skins}

  @car_one "11111111-1111-4111-8111-111111111111"

  defp vehicle(id) do
    %{
      "vehicle_id" => id,
      "archived" => false,
      "model_year" => 2020,
      "configuration_key" => "000384cf-aee6-5ba8-968a-1fe30158f387",
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "2020"
      },
      "maintenance_plan" => %{"interval_months" => 6, "interval_miles" => 5000}
    }
  end

  defp event(id, vehicle_id) do
    %{
      "event_id" => id,
      "vehicle_id" => vehicle_id,
      "performed_at" => "2026-06-15",
      "odometer_m" => 80_467_200,
      "input_unit" => "mi",
      "oil_viscosity" => "5W-30",
      "oil_base_stock" => "full_synthetic",
      "provenance_mode" => "manual"
    }
  end

  defp hydrate(view, data, opts \\ []) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => Keyword.get(opts, :schema_version, 1),
      "seq" => 1,
      "tab_id" => "test-tab",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" =>
        Map.merge(
          %{
            "meta" => nil,
            "vehicles" => [],
            "events" => [],
            "readings" => [],
            "usage" => [],
            "reminders" => [],
            "prefs" => nil
          },
          data
        ),
      "storage" => %{"mode" => "idb", "boot_hint" => "never"}
    })
  end

  defp one_car(extra \\ %{}) do
    Map.merge(
      %{
        "vehicles" => [vehicle(@car_one)],
        "events" => [event("22222222-2222-4222-8222-222222222222", @car_one)]
      },
      extra
    )
  end

  describe "the pref write" do
    test "picking a skin stages a prefs upsert with unknown fields kept flat", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      hydrate(view, one_car(%{"prefs" => %{"unit_system" => "mi", "future_field" => "kept"}}))

      render_click(view, "set_skin", %{"skin" => "midnight-shift"})

      assert_push_event(view, "local_store:put", payload)
      assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]

      assert prefs["sticker_skin"] == "midnight-shift"
      assert prefs["future_field"] == "kept"
      refute Map.has_key?(prefs, "__unknown__")
    end

    test "a quarantined prefs singleton refuses the write", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # unit_system "nmi" fails validation → the singleton quarantines and a
      # write would destroy content the contract keeps exportable.
      hydrate(view, one_car(%{"prefs" => %{"unit_system" => "nmi"}}))

      html = render_click(view, "set_skin", %{"skin" => "track-day"})

      refute_push_event(view, "local_store:put", %{})
      assert html =~ "Could not read this browser&#39;s stored settings"
    end

    test "an unknown slug is ignored without a write", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      hydrate(view, one_car())

      html = render_click(view, "set_skin", %{"skin" => "hotdog"})

      refute_push_event(view, "local_store:put", %{})
      assert html =~ ~s|data-skin="service-bay"|
    end

    test "read-only mode refuses the write", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # A newer schema version hydrates read_only: mutations are off across
      # the board, and the skin write is no exception.
      hydrate(view, one_car(), schema_version: 2)

      render_click(view, "set_skin", %{"skin" => "blueprint"})

      refute_push_event(view, "local_store:put", %{})
    end
  end

  describe "data-skin rendering" do
    test "defaults to service-bay after a plain hydrate", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, one_car())

      assert html =~ ~s|data-skin="service-bay"|
    end

    test "renders the stored skin from prefs", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, one_car(%{"prefs" => %{"sticker_skin" => "track-day"}}))

      assert html =~ ~s|data-skin="track-day"|
      # The theme-color mirror the SkinChrome hook reads.
      assert html =~ ~s|data-theme-color="#C8102E"|
    end

    test "an unknown stored skin falls back to the default without a write", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, one_car(%{"prefs" => %{"sticker_skin" => "zebra"}}))

      assert html =~ ~s|data-skin="service-bay"|
      refute_push_event(view, "local_store:put", %{})
    end

    test "the click's own render already carries the new attribute", %{conn: conn} do
      # Optimistic, pre-ack: the repaint is the feedback.
      {:ok, view, _} = live(conn, ~p"/")
      hydrate(view, one_car())

      html = render_click(view, "set_skin", %{"skin" => "brushed-steel"})

      assert html =~ ~s|data-skin="brushed-steel"|
    end

    test "another garage page inherits the stored skin", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/history")
      html = hydrate(view, one_car(%{"prefs" => %{"sticker_skin" => "blueprint"}}))

      assert html =~ ~s|data-skin="blueprint"|
    end
  end

  describe "the picker" do
    test "renders six pressed-state buttons with visible names in :sticker mode", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate(view, one_car(%{"prefs" => %{"sticker_skin" => "vintage-pump"}}))

      assert html =~ ~s|data-test="skin-picker"|

      for slug <- Skins.slugs() do
        assert html =~ ~s|data-test="skin-#{slug}"|
        assert html =~ Copy.skin_name(slug)
      end

      # Exactly one button is pressed — the active skin.
      pressed_count = html |> String.split(~s|aria-pressed="true"|) |> length() |> Kernel.-(1)
      assert pressed_count == 1

      # The 44px floor rides on every button.
      assert html =~ "min-h-11"
    end

    test "is absent pre-hydration and in :empty mode", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      # Pre-hydration: skeleton, no controls.
      refute html =~ ~s|data-test="skin-picker"|

      # :empty — no sticker to preview; the page's job is vehicle setup.
      html = hydrate(view, %{})
      refute html =~ ~s|data-test="skin-picker"|
      refute render(view) =~ ~s|data-test="skin-picker"|
    end
  end
end
