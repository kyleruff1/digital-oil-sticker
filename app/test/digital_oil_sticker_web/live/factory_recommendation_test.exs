defmodule DigitalOilStickerWeb.FactoryRecommendationTest do
  @moduledoc """
  The "Factory recommendation" badge on the vehicle profile page. The label
  and the display are ready but INERT today: they render only when
  `maintenance_plan.manufacturer_viscosity` is populated by DOS-M03-007
  (ADR-0007 lane b) with a value backed by per-row provenance in our
  internal source register.

  This test locks in the three non-negotiables from
  RECOMMENDATION_CLAIMS_POLICY.md §"Factory recommendation label":

    * without a manufacturer viscosity on the plan, the badge is silent —
      no placeholder, no "unknown", no heading;
    * with one, the value AND the badge render together;
    * the SOURCE never appears on-screen — no publisher name, no URL, no
      revision date — even if the vehicle record carries those fields
      alongside the viscosity. The badge is the promise that we hold OEM
      provenance; the identifying attribution stays in our source register.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @vehicle_id "11111111-1111-4111-8111-111111111111"

  defp vehicle(plan) do
    %{
      "vehicle_id" => @vehicle_id,
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{
        "year" => 2020,
        "make" => "Toyota",
        "model" => "Camry",
        "build" => "LE"
      },
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => plan
    }
  end

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
      "tab_id" => "test-tab",
      "generated_at" => "2026-08-02T00:00:00Z",
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

  test "without a manufacturer_viscosity, the badge does not render", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")

    html =
      hydrate(view, %{
        "vehicles" => [
          vehicle(%{
            "planned_oil" => "selected",
            "planned_base_stock" => "full_synthetic",
            "planned_grade" => "5W-30"
          })
        ],
        "prefs" => %{"active_vehicle_id" => @vehicle_id}
      })

    refute html =~ Copy.factory_recommendation_label()
    refute html =~ Copy.manufacturer_viscosity_heading()
    refute html =~ "data-factory-recommendation"
  end

  test "with a manufacturer_viscosity, the value AND the badge render", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")

    html =
      hydrate(view, %{
        "vehicles" => [
          vehicle(%{
            "planned_oil" => "selected",
            "planned_base_stock" => "full_synthetic",
            "planned_grade" => "5W-30",
            "manufacturer_viscosity" => "0W-20"
          })
        ],
        "prefs" => %{"active_vehicle_id" => @vehicle_id}
      })

    assert html =~ Copy.factory_recommendation_label()
    assert html =~ Copy.manufacturer_viscosity_heading()
    assert html =~ "data-factory-recommendation=\"true\""
    assert html =~ "0W-20"
  end

  test "the source never leaks into the rendered HTML — publisher/URL/id/date all stay off-screen",
       %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/vehicle")

    # A vehicle carrying source-identifying data alongside the value the
    # badge certifies. The badge's whole contract is that we hold OEM
    # provenance without exposing whose data it is; the source must never
    # ride out to the client, so we plant the actual ADR-0007 §"What every
    # lane must preserve" row-level provenance fields — the ones the
    # `maintenance_schedules` / `oil_requirements` DDL mandates
    # (`source_locator`, `source_page`, `source_effective_date`,
    # `source_id`, `verification_state`) — alongside a candidate
    # publisher name, and assert none of them appear on-screen. Planting
    # these under the plan simulates the failure mode the ingest must
    # avoid: bundling per-row source metadata into the client vehicle
    # payload.
    html =
      hydrate(view, %{
        "vehicles" => [
          vehicle(%{
            "manufacturer_viscosity" => "0W-20",
            "manufacturer_viscosity_publisher" => "MOTOR Information Systems",
            "manufacturer_viscosity_source_locator" =>
              "https://internal.example.invalid/motor/oem-schedules/88712",
            "manufacturer_viscosity_source_page" => "OilSpecs, section 2.4",
            "manufacturer_viscosity_source_effective_date" => "2026-05-01",
            "manufacturer_viscosity_source_id" => "src_motor_2026_q3_row_88712",
            "manufacturer_viscosity_verification_state" => "verified_second_review"
          })
        ],
        "prefs" => %{"active_vehicle_id" => @vehicle_id}
      })

    # The label AND the value MUST render...
    assert html =~ Copy.factory_recommendation_label()
    assert html =~ "0W-20"

    # ...and no source-identifying token may appear anywhere in the HTML.
    # These are the fields ADR-0007 §"What every lane must preserve"
    # names as the row-level provenance every published schedule/
    # requirement row carries — plus a candidate publisher name.
    refute html =~ "MOTOR"
    refute html =~ "motor"
    refute html =~ "src_motor_2026_q3_row_88712"
    refute html =~ "internal.example.invalid"
    refute html =~ "2026-05-01"
    refute html =~ "OilSpecs"
    refute html =~ "verified_second_review"
    refute html =~ "source_locator"
    refute html =~ "source_page"
    refute html =~ "source_id"
    refute html =~ "verification_state"
    refute html =~ "publisher"
  end
end
