defmodule DigitalOilStickerWeb.OilRecommendationTest do
  @moduledoc """
  What the app SUGGESTS versus what the user chose, and how honestly the
  sticker names the calculation.

  Two closely-related properties:

    * At intake, choosing a base stock pre-selects the top suggested grade for
      the vehicle's engine class — the closest per-vehicle recommendation the
      current data supports. An explicit user choice always wins.
    * The sticker qualifier shows the ACTUAL numbers (\"10,000 miles or 12
      months, whichever comes first\") rather than the shape of the calculation
      (\"our estimate\") — otherwise a full-synthetic rule with a 12-month cap
      reads as \"just added a year\" and nothing on screen says the calendar
      cap governed because the mileage cap is far away.
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ecto.Query

  alias DigitalOilSticker.Catalog.OilModel

  # A configuration_key whose engine class has both a suggested grade AND
  # a "leftover" grade the user could pick instead — so the "explicit choice
  # wins" test has a real target to pick.
  defp any_classified_config do
    DigitalOilSticker.CatalogRepo.one(
      from(c in "vehicle_configurations",
        select: %{
          key: c.configuration_key,
          year: c.model_year,
          make_id: c.make_id,
          model_id: c.model_id,
          class: c.engine_class_code
        },
        where: not is_nil(c.engine_class_code),
        limit: 1
      )
    )
  end

  # A grade the shipped model knows about but the given class does NOT
  # suggest. Nil if every grade happens to be suggested for this class.
  defp non_suggested_grade(class_code) do
    {_suggested, others} = OilModel.grade_choices(class_code)

    case others do
      [%{code: code} | _] -> code
      _ -> nil
    end
  end

  defp hydrate_empty(view) do
    render_hook(view, "local_store:hydrate", %{
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
    })
  end

  defp drive_cascade_to_confirm(view, row) do
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
  end

  describe "auto-selecting the grade at intake" do
    test "picking a base stock pre-selects the top suggested grade, and the save carries it", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      hydrate_empty(view)
      row = any_classified_config()
      drive_cascade_to_confirm(view, row)

      [%{code: expected_grade} | _] = OilModel.grades_for_class(row.class)

      render_change(view, "oil_change", %{
        "oil" => %{"base_stock" => "full_synthetic", "grade" => ""}
      })

      # Confirming without touching the grade must save that same value — the
      # save path and the render path both go through the picker's assigns, so
      # a divergence here means the pre-fill was cosmetic.
      render_click(view, "confirm", %{})
      assert_push_event(view, "local_store:put", payload)

      vehicle =
        payload["upserts"] |> Enum.find(&(&1["store"] == "vehicles")) |> Map.fetch!("record")

      assert vehicle["maintenance_plan"]["planned_grade"] == expected_grade,
             "auto-selected grade did not travel with the saved vehicle"
    end

    test "an explicit choice from the suggested list survives a form re-emit", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      hydrate_empty(view)
      row = any_classified_config()
      drive_cascade_to_confirm(view, row)

      [%{code: first}, %{code: second} | _] =
        case OilModel.grades_for_class(row.class) do
          [_, _ | _] = list ->
            list

          # Class has only one suggested grade — fall back to the "other" list
          # to find a second real target the user could pick.
          [first] ->
            [first | OilModel.grade_choices(row.class) |> elem(1)]
        end

      render_change(view, "oil_change", %{
        "oil" => %{"base_stock" => "full_synthetic", "grade" => ""}
      })

      # User overrides the auto-selected top with the second entry, then the
      # form re-emits (same values, another change event). The user's pick
      # must survive; auto-selection is one-shot, not a re-assertion.
      render_change(view, "oil_change", %{
        "oil" => %{"base_stock" => "full_synthetic", "grade" => second}
      })

      render_click(view, "confirm", %{})
      assert_push_event(view, "local_store:put", payload)

      vehicle =
        payload["upserts"] |> Enum.find(&(&1["store"] == "vehicles")) |> Map.fetch!("record")

      assert vehicle["maintenance_plan"]["planned_grade"] == second
      refute vehicle["maintenance_plan"]["planned_grade"] == first
    end

    test "\"I don't know yet\" saves without a grade and does not fabricate one", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle/select")
      hydrate_empty(view)
      row = any_classified_config()
      drive_cascade_to_confirm(view, row)

      render_change(view, "oil_change", %{
        "oil" => %{"base_stock" => "__unknown__"}
      })

      render_click(view, "confirm", %{})
      assert_push_event(view, "local_store:put", payload)

      vehicle =
        payload["upserts"] |> Enum.find(&(&1["store"] == "vehicles")) |> Map.fetch!("record")

      assert vehicle["maintenance_plan"]["planned_oil"] == "unknown"
      refute Map.has_key?(vehicle["maintenance_plan"], "planned_base_stock")
      refute Map.has_key?(vehicle["maintenance_plan"], "planned_grade")

      # A discarded finding this asserts against too: auto_grade_for/1 should
      # not care what the leftover grade was — unknown-oil means unknown.
      _ = non_suggested_grade(row.class)
    end
  end

  describe "the sticker qualifier" do
    defp vehicle(plan \\ %{"planned_oil" => "selected", "planned_base_stock" => "full_synthetic"}) do
      %{
        "vehicle_id" => "11111111-1111-4111-8111-111111111111",
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

    defp event(overrides \\ %{}) do
      Map.merge(
        %{
          "event_id" => "22222222-2222-4222-8222-222222222222",
          "vehicle_id" => "11111111-1111-4111-8111-111111111111",
          "performed_at" => "2026-06-15",
          "odometer_m" => 80_467_200,
          "input_unit" => "mi",
          "oil_base_stock" => "full_synthetic",
          "provenance_mode" => "manual"
        },
        overrides
      )
    end

    defp hydrate_with(view, vehicle, event) do
      render_hook(view, "local_store:hydrate", %{
        "envelope" => "dos_local",
        "schema_version" => 1,
        "seq" => 1,
        "tab_id" => "t",
        "generated_at" => "2026-08-01T00:00:00Z",
        "data" => %{
          "meta" => nil,
          "vehicles" => [vehicle],
          "events" => [event],
          "readings" => [],
          "usage" => [],
          "reminders" => [],
          "prefs" => nil
        },
        "storage" => %{"mode" => "idb", "boot_hint" => "never"}
      })
    end

    test "names both ceilings, in miles-then-months order, joined by \"whichever comes first\"",
         %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = hydrate_with(view, vehicle(), event())

      # The exact numbers come from the shipped rule for gas_direct_injection ×
      # full_synthetic × normal service.
      {:ok, rule} = OilModel.interval("gas_direct_injection", "full_synthetic", "normal")

      assert html =~
               "#{format_int(rule.miles_recommended)} miles or #{rule.months_cap} months, whichever comes first"
    end

    test "a user interval override reads with its own numbers and is credited to the user", %{
      conn: conn
    } do
      {:ok, view, _} = live(conn, ~p"/")

      html =
        hydrate_with(
          view,
          vehicle(%{"interval_miles" => 4000, "interval_months" => 6}),
          event()
        )

      assert html =~ "4,000 miles or 6 months, whichever comes first"
      assert html =~ "Your interval"
    end

    defp format_int(n) when n >= 1000 do
      n
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()
    end

    defp format_int(n), do: Integer.to_string(n)
  end
end
