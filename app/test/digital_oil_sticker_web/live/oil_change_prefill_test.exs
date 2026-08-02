defmodule DigitalOilStickerWeb.OilChangePrefillTest do
  @moduledoc """
  The log form's pre-fill from the intake step, and — the part that bites —
  what happens after the user OVERRIDES it. The invariant: the record saved is
  the record the screen showed. A pre-fill that keeps re-asserting itself
  after being cleared saves a value the user explicitly removed.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

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

  defp plan_full_synthetic do
    %{
      "planned_oil" => "selected",
      "planned_base_stock" => "full_synthetic",
      "planned_grade" => "5W-30"
    }
  end

  test "before any input, the form shows the intake answer", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/service/new")
    html = hydrate(view, %{"vehicles" => [vehicle(plan_full_synthetic())]})

    assert html =~ ~s(value="full_synthetic" checked)
  end

  test "a cleared grade stays cleared through to the saved record", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/service/new")
    hydrate(view, %{"vehicles" => [vehicle(plan_full_synthetic())]})

    # The user fills the form and clears the pre-filled grade back to
    # "Choose…". The params carry what the rendered controls show: the
    # checked radio still submits, the cleared select submits "".
    render_change(view, "form_change", %{
      "service_date" => %{"month" => "6", "day" => "15", "year" => "2026"},
      "odometer" => %{"value" => "50000", "unit" => "mi"},
      "oil" => %{"base_stock" => "full_synthetic", "grade" => ""},
      "notes" => ""
    })

    render_submit(view, "submit", %{})

    assert_push_event(view, "local_store:put", payload)

    event =
      payload["upserts"]
      |> Enum.find(&(&1["store"] == "events"))
      |> Map.fetch!("record")

    # The screen showed no grade; the record carries no grade. Before the
    # touch gate, the pre-fill re-asserted itself here and saved "5W-30" the
    # user had just removed.
    assert event["oil_viscosity"] == nil
    assert event["oil_base_stock"] == "full_synthetic"
  end

  test "a planned grade outside the suggested list does not pre-select invisibly", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/service/new")

    # A grade our tables list but this engine class does not suggest: the
    # select's visible options will not contain it before "show all", so
    # pre-selecting it would show "Choose…" while saving the hidden value.
    plan = %{plan_full_synthetic() | "planned_grade" => "20W-50"}
    html = hydrate(view, %{"vehicles" => [vehicle(plan)]})

    refute html =~ ~s(<option selected value="20W-50">)
  end
end
