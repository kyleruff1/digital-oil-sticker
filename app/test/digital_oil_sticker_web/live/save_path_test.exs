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
          select: %{key: c.configuration_key, year: c.model_year, make_id: c.make_id, model_id: c.model_id},
          limit: 1
        )
      )

    # Drive the cascade so the LiveView holds the selection it commits.
    render_change(view, "cascade_change", %{"year" => to_string(row.year)})
    render_change(view, "cascade_change", %{"year" => to_string(row.year), "make_id" => row.make_id})

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
      "display_snapshot" => %{"year" => 2020, "make" => "Toyota", "model" => "Camry", "build" => "LE"},
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
end
