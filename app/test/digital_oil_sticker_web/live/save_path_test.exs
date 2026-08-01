defmodule DigitalOilStickerWeb.SavePathTest do
  @moduledoc """
  Exercises the real staged-mutation path end to end in the LiveView. The
  production bug this guards: Session.stage_mutation/3 was handed
  wire-shaped maps while Envelope.build_put/4 expected {store, payload}
  tuples, so every save crashed the LiveView instead of writing.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  defp hydrate_empty(view) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 0,
      "tab_id" => "test-tab",
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
    })
  end

  test "confirming a vehicle pushes a well-formed local_store:put", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle/select")
    hydrate_empty(view)

    row =
      DigitalOilSticker.CatalogRepo.one(
        from(c in "vehicle_configurations",
          join: m in "makes",
          on: m.id == c.make_id,
          select: %{
            key: c.configuration_key,
            year: c.model_year,
            make_id: c.make_id,
            model_id: c.model_id
          },
          limit: 1
        )
      )

    # Drive the cascade so the LiveView holds the selection it commits.
    render_change(view, "cascade_change", %{"year" => to_string(row.year)})

    render_change(view, "cascade_change", %{
      "year" => to_string(row.year),
      "make_id" => row.make_id
    })

    render_change(view, "cascade_change", %{
      "year" => to_string(row.year),
      "make_id" => row.make_id,
      "model_id" => row.model_id
    })

    render_change(view, "cascade_change", %{
      "year" => to_string(row.year),
      "make_id" => row.make_id,
      "model_id" => row.model_id,
      "configuration_key" => row.key
    })

    # The click must not crash the view, and must push a put with the
    # vehicle record the browser will store.
    render_click(view, "confirm", %{})
    assert_push_event(view, "local_store:put", payload)

    assert payload["seq"] == 1
    assert is_binary(payload["mutation_id"])
    assert [%{"store" => "vehicles", "record" => vehicle}] = payload["upserts"]
    assert vehicle["configuration_key"] == row.key
    assert vehicle["archived"] == false
    assert is_binary(vehicle["vehicle_id"])
  end

  test "saving Your interval pushes a put carrying the user-entered plan", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/vehicle")

    vehicle = %{
      "vehicle_id" => "11111111-1111-4111-8111-111111111111",
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "support_status" => "identity_only",
      "maintenance_plan" => nil
    }

    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 2,
      "tab_id" => "t",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => [vehicle],
        "events" => [],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
    })

    render_change(view, "interval_change", %{"interval" => %{"months" => "6", "miles" => "5000"}})
    render_submit(view, "interval_save", %{})

    assert_push_event(view, "local_store:put", payload)
    assert payload["seq"] == 3
    assert [%{"store" => "vehicles", "record" => saved}] = payload["upserts"]
    assert saved["maintenance_plan"]["interval_months"] == 6
    assert saved["maintenance_plan"]["interval_miles"] == 5000
    assert saved["maintenance_plan"]["basis"] == "user_entered"
  end

  test "a staged write is visible immediately to a view that stays on the page", %{conn: conn} do
    # The bug this guards: stage_mutation/3 pushed the write to the browser but
    # left assigns.garage untouched, so anything that saved without navigating
    # away kept rendering the pre-save state. Toggling severe service is that
    # case — it must change the estimate on screen, not on the next reload.
    {:ok, view, _html} = live(conn, ~p"/vehicle")

    vehicle = %{
      "vehicle_id" => "11111111-1111-4111-8111-111111111111",
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "support_status" => "identity_only",
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => nil
    }

    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
      "tab_id" => "t",
      "generated_at" => "2026-08-01T00:00:00Z",
      "data" => %{
        "meta" => nil,
        "vehicles" => [vehicle],
        "events" => [],
        "readings" => [],
        "usage" => [],
        "reminders" => [],
        "prefs" => nil
      },
      "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
    })

    {:ok, normal} =
      DigitalOilSticker.Catalog.OilModel.interval(
        "gas_direct_injection",
        "full_synthetic",
        "normal"
      )

    {:ok, severe} =
      DigitalOilSticker.Catalog.OilModel.interval(
        "gas_direct_injection",
        "full_synthetic",
        "severe"
      )

    assert render(view) =~ "#{normal.months_cap} months"

    html = render_click(view, "set_condition", %{"condition" => "severe"})

    assert html =~ "#{severe.months_cap} months"
    refute severe.months_cap == normal.months_cap
  end

  test "a browser holding newer records is told why saving is off", %{conn: conn} do
    # The defect this guards, same shape as the refused-write one: read_only
    # was set, mutations were gated on it, and Copy.read_only_banner/0 was
    # rendered nowhere — so the user found the save buttons inert with no
    # explanation and no route to their data.
    for route <- ["/", "/vehicle", "/service/new", "/history", "/settings/storage"] do
      {:ok, view, _html} = live(conn, route)

      html =
        render_hook(view, "local_store:hydrate", %{
          "envelope" => "dos_local",
          # Newer than the server's logical schema version.
          "schema_version" => 99,
          "seq" => 5,
          "tab_id" => "t",
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
        })

      assert html =~ "data from a newer version", "#{route} did not explain why saving is off"
      assert html =~ "Export a file", "#{route} offered no way to get the data out"
    end
  end

  test "a write the browser refused is shown, persistently, on every route", %{conn: conn} do
    # The defect this guards, found by the conformance suite: the copy for a
    # refused write existed and was never rendered anywhere, so a failed write
    # was completely silent and the user believed their entry was stored.
    for route <- ["/", "/vehicle", "/service/new", "/history", "/settings/storage"] do
      {:ok, view, _html} = live(conn, route)
      hydrate_empty(view)

      refute render(view) =~ DigitalOilStickerWeb.Copy.unsaved_record()

      # Drive a real staged write, then have the browser refuse it.
      {:ok, picker, _} = live(conn, ~p"/vehicle/select")
      hydrate_empty(picker)

      html =
        render_hook(view, "local_store:ack", %{
          "mutation_id" => "11111111-1111-4111-8111-111111111111",
          "status" => "error",
          "reason" => "quota"
        })

      assert html =~ DigitalOilStickerWeb.Copy.unsaved_record(),
             "#{route} did not surface a refused write"

      # Substring without the apostrophe: HEEx escapes it to an entity.
      assert html =~ "storage is full, so the entry was not stored",
             "#{route} did not use the quota-specific message"

      # Persistent: a re-render does not clear it.
      assert render(view) =~ DigitalOilStickerWeb.Copy.unsaved_record()
    end
  end
end
