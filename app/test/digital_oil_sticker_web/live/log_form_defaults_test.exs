defmodule DigitalOilStickerWeb.LogFormDefaultsTest do
  @moduledoc """
  The log form's on-load defaults: today's date, the active vehicle context,
  and vehicle switching when there's more than one car.

  These land the "less friction to log" property alongside the existing
  honesty properties for oil pre-fill and defaulted plans.
  """
  # Not async: this suite manipulates the global Clock env, which would race
  # with any other test using the default Clock.
  use DigitalOilStickerWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias DigitalOilSticker.Clock

  defmodule FixedClock do
    @behaviour DigitalOilSticker.Clock
    @impl true
    def today, do: ~D[2026-08-02]
    @impl true
    def now, do: ~U[2026-08-02 00:00:00Z]
  end

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => 1,
      "tab_id" => "t",
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

  # Real UUIDs, not "v1"/"v2" — the hydration validator quarantines a vehicle
  # whose `vehicle_id` is not a valid UUID, at which point garage.vehicles is
  # empty and the tabs/name markup does not render, so the failure looks like
  # the render logic is broken when actually it's the fixture.
  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "22222222-2222-4222-8222-222222222222"

  defp vehicle(
         id,
         make,
         model,
         plan \\ %{
           "planned_oil" => "selected",
           "planned_base_stock" => "full_synthetic",
           "planned_grade" => "5W-30"
         }
       ) do
    %{
      "vehicle_id" => id,
      "archived" => false,
      "model_year" => 2020,
      "display_snapshot" => %{"year" => 2020, "make" => make, "model" => model, "build" => "LE"},
      "engine_class_code" => "gas_direct_injection",
      "maintenance_plan" => plan
    }
  end

  describe "today's date is pre-filled" do
    test "the three date dropdowns render with today selected on mount", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")
      hydrate(view, %{})

      today = Clock.today()
      html = render(view)

      # Phoenix renders selected boolean attribute as `selected=""`.
      assert html =~ ~s(<option selected="" value="#{today.month}">)
      assert html =~ ~s(<option selected="" value="#{today.day}">)
      assert html =~ ~s(<option selected="" value="#{today.year}">)
    end

    test "the pre-fill is deterministic against a fixed clock (boundary coverage)", %{conn: conn} do
      # Ties the acknowledged UTC-vs-local seam down against silent regression.
      # If someone later changes Clock.today's shape or the mount's pre-fill
      # logic, this test breaks loudly instead of a user in Pacific quietly
      # recording tomorrow's date on a change they made tonight.
      #
      # A proper client-local fix (phx-hook reporting navigator TZ) is the
      # real remedy — this test locks the CURRENT behavior, not the desired
      # behavior, and its failure message should nudge whoever changes it to
      # revisit that decision.
      previous = Application.get_env(:digital_oil_sticker, :clock)
      Application.put_env(:digital_oil_sticker, :clock, __MODULE__.FixedClock)

      try do
        {:ok, view, _} = live(conn, ~p"/service/new")
        hydrate(view, %{})
        html = render(view)

        # FixedClock returns 2026-08-02 — a UTC day that would be Aug 1 for
        # any user in a timezone east of… wait, WEST of UTC in the evening.
        # The test asserts the raw mount behavior; a client-local-date fix
        # would break this test on purpose.
        assert html =~ ~s(<option selected="" value="8">)
        assert html =~ ~s(<option selected="" value="2">)
        assert html =~ ~s(<option selected="" value="2026">)
      after
        if previous do
          Application.put_env(:digital_oil_sticker, :clock, previous)
        else
          Application.delete_env(:digital_oil_sticker, :clock)
        end
      end
    end

    test "a user can still clear the pre-filled date by picking the blank option", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")
      hydrate(view, %{})

      # Change day to blank — form_change absorbs the parsed nil, and
      # subsequent renders show Day not selected. The pre-fill is a starting
      # value, not a re-assertion.
      html =
        render_change(view, "form_change", %{
          "service_date" => %{"month" => "", "day" => "", "year" => ""},
          "odometer" => %{"value" => "", "unit" => "mi"},
          "oil" => %{"base_stock" => "", "grade" => ""},
          "notes" => ""
        })

      today = Clock.today()

      # The specific day-of-today should NOT be selected after clearing —
      # otherwise clearing would be impossible on any form change.
      refute html =~ ~s(<option selected="" value="#{today.day}">)
    end
  end

  describe "vehicle context on the log form" do
    test "with one vehicle, the vehicle description is shown as a header", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        hydrate(view, %{
          "vehicles" => [vehicle(@car_one, "Toyota", "Camry")]
        })

      assert html =~ "data-test=\"log-form-vehicle-name\""
      assert html =~ "Logging a change for"
      assert html =~ "2020 Toyota Camry"
      # Not a tab bar — one vehicle is not a choice.
      refute html =~ "data-test=\"log-form-vehicle-tabs\""

      # But the "add a vehicle" affordance is available on both the one-
      # and two-plus-vehicle case, so a user in the log form can start a
      # second vehicle without navigating out to the sticker first.
      assert html =~ "data-test=\"log-form-add-vehicle\""
    end

    test "with two vehicles, tabs render with the active one selected", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        hydrate(view, %{
          "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
          "prefs" => %{"active_vehicle_id" => @car_two}
        })

      assert html =~ "data-test=\"log-form-vehicle-tabs\""
      # Both vehicles appear as tabs
      assert html =~ "2020 Toyota Camry"
      assert html =~ "2020 BMW 328i"
      # Active one is selected — a screen reader hears the selected state via
      # aria-selected on the button that carries the active vehicle.
      assert html =~
               ~s(aria-selected="true" phx-click="switch_vehicle" phx-value-vehicle-id="#{@car_two}")

      assert html =~
               ~s(aria-selected="false" phx-click="switch_vehicle" phx-value-vehicle-id="#{@car_one}")
    end

    test "clicking a non-active tab switches the vehicle for this session", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"active_vehicle_id" => @car_one}
      })

      render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

      assert_push_event(view, "local_store:put", payload)
      assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]
      assert prefs["active_vehicle_id"] == @car_two

      # And the render reflects it optimistically, without waiting for a
      # rehydration.
      html = render(view)

      assert html =~
               ~s(aria-selected="true" phx-click="switch_vehicle" phx-value-vehicle-id="#{@car_two}")
    end

    test "clicking the already-active tab does not reset the form", %{conn: conn} do
      # The button fires on every click regardless of aria-selected, so a
      # user who confirmed their vehicle by clicking its already-highlighted
      # tab must not lose the values they just typed.
      {:ok, view, _} = live(conn, ~p"/service/new")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"active_vehicle_id" => @car_one}
      })

      render_change(view, "form_change", %{
        "service_date" => %{"month" => "8", "day" => "2", "year" => "2026"},
        "odometer" => %{"value" => "50000", "unit" => "mi"},
        "oil" => %{"base_stock" => "conventional", "grade" => ""},
        "notes" => ""
      })

      # Click the SAME tab (car_one, which is active).
      render_click(view, "switch_vehicle", %{"vehicle-id" => @car_one})

      # Nothing was pushed (no prefs write), and the form values survived.
      refute_push_event(view, "local_store:put", %{})

      html = render(view)
      assert html =~ ~s(value="50000")
      assert html =~ ~s(value="conventional" checked)
    end

    test "switching resets the form so typed values do not leak to the new vehicle", %{
      conn: conn
    } do
      # This was reproduced on tablet before the fix: a user types 50,000 in
      # the odometer for the Camry, clicks the Navigator tab, and the
      # 50,000 stays — a submit at that point records the Camry's typed
      # values against the Navigator's vehicle_id. The switch handler now
      # resets the vehicle-specific form state; the date stays because it's
      # a real-world calendar day, not a per-vehicle fact.
      {:ok, view, _} = live(conn, ~p"/service/new")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"active_vehicle_id" => @car_one}
      })

      render_change(view, "form_change", %{
        "service_date" => %{"month" => "8", "day" => "2", "year" => "2026"},
        "odometer" => %{"value" => "50000", "unit" => "mi"},
        "oil" => %{"base_stock" => "conventional", "grade" => ""},
        "notes" => "some notes"
      })

      render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

      html = render(view)

      # Vehicle-specific state cleared: no selected radio, no odometer value,
      # no notes, no filter.
      refute html =~ ~s(value="conventional" checked)
      refute html =~ ~s(value="50000")
      refute html =~ ">some notes<"

      # Save with no oil now produces a nil-oil event (the plan is
      # "selected" full_synthetic — that WOULD pre-fill because the switch
      # target's plan is selected). This asserts the negative more
      # importantly: nothing from the old vehicle survives.
      refute html =~ ~s(value="50,000")
    end
  end

  describe "no per-radio range previews on the log form" do
    test "the base-stock radios show only names, not \"X–Y miles typical\" hints", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/service/new")

      html =
        hydrate(view, %{
          "vehicles" => [vehicle(@car_one, "Toyota", "Camry")]
        })

      # The hint was on the intake side before it was removed; it's the same
      # component here. The log form now suppresses it too — the range
      # calculation is what appears AFTER submitting, on the sticker page.
      refute html =~ "miles typical"
    end
  end
end
