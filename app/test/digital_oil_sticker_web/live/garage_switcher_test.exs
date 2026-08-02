defmodule DigitalOilStickerWeb.GarageSwitcherTest do
  @moduledoc """
  The vehicle bar: which vehicle the sticker is about, switching between
  vehicles, and removing one.

  The removal path carries the risk here. The records live only in this
  browser, so a delete is genuinely unrecoverable — it must never happen from
  one click, and it must take the vehicle's dependent records with it, because
  an orphaned oil change is quarantined by the next hydration and surfaces
  forever as \"could not read some records\".
  """
  use DigitalOilStickerWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias DigitalOilStickerWeb.Copy

  @car_one "11111111-1111-4111-8111-111111111111"
  @car_two "33333333-3333-4333-8333-333333333333"

  defp vehicle(id, make, model) do
    %{
      "vehicle_id" => id,
      "archived" => false,
      "model_year" => 2020,
      "configuration_key" => "000384cf-aee6-5ba8-968a-1fe30158f387",
      "display_snapshot" => %{
        "year" => 2020,
        "make" => make,
        "model" => model,
        "build" => "2020 — #{Copy.not_specified()}"
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
      # Omitting this is not a shortcut: hydration validation quarantines the
      # record, and the test would then exercise an empty-events garage.
      "provenance_mode" => "manual"
    }
  end

  defp hydrate(view, data) do
    render_hook(view, "local_store:hydrate", %{
      "envelope" => "dos_local",
      "schema_version" => 1,
      "seq" => Map.get(data, "seq", 1),
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
          Map.delete(data, "seq")
        ),
      "storage" => %{"mode" => "idb", "boot_hint" => "never"}
    })
  end

  defp two_car_garage(view) do
    hydrate(view, %{
      "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
      "events" => [
        event("22222222-2222-4222-8222-222222222222", @car_one),
        event("44444444-4444-4444-8444-444444444444", @car_two)
      ]
    })
  end

  describe "the bar" do
    test "describes the vehicle without labelling its parts", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = two_car_garage(view)

      assert html =~ "data-test=\"vehicle-bar\""
      assert html =~ "2020 Toyota Camry"
      # A description, not a form.
      refute html =~ "Year:"
      refute html =~ "Make:"
    end

    test "a placeholder build is dropped from the description", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = two_car_garage(view)

      refute html =~ "Camry · 2020 — #{Copy.not_specified()}"
    end

    test "the folder starts collapsed and opens to the rest of the garage", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      html = two_car_garage(view)

      refute html =~ "data-test=\"garage-panel\""

      html = render_click(view, "toggle_garage", %{})

      assert html =~ "data-test=\"garage-panel\""
      assert html =~ Copy.other_vehicles()
      assert html =~ Copy.add_vehicle()
      assert html =~ "2020 BMW 328i"
    end
  end

  describe "switching" do
    test "stages the choice in prefs and the sticker follows immediately", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      two_car_garage(view)
      render_click(view, "toggle_garage", %{})

      html = render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

      # The write the browser will persist.
      assert_push_event(view, "local_store:put", payload)
      assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]
      assert prefs["active_vehicle_id"] == @car_two

      # And the optimistic render: the bar is about the BMW without waiting
      # for an ack or a rehydration.
      assert html =~ "2020 BMW 328i"
      # Panel closes after a choice.
      refute html =~ "data-test=\"garage-panel\""
    end

    test "every garage page honours the switch, not just the sticker", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/vehicle")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"active_vehicle_id" => @car_two}
      })

      assert render(view) =~ "BMW"
    end
  end

  describe "removing a vehicle" do
    test "one click never deletes — it opens the confirmation", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      two_car_garage(view)
      render_click(view, "toggle_garage", %{})

      html = render_click(view, "ask_delete_vehicle", %{"vehicle-id" => @car_two})

      assert html =~ "data-test=\"delete-vehicle-modal\""
      assert html =~ Copy.delete_vehicle_heading()
      # Named and counted: the user is told exactly what is about to go.
      assert html =~ "2020 BMW 328i"
      assert html =~ "1 recorded"
      # Nothing staged yet.
      refute_push_event(view, "local_store:put", %{})
    end

    test "cancelling closes the modal and stages nothing", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      two_car_garage(view)
      render_click(view, "ask_delete_vehicle", %{"vehicle-id" => @car_two})

      html = render_click(view, "cancel_delete_vehicle", %{})

      refute html =~ "data-test=\"delete-vehicle-modal\""
      refute_push_event(view, "local_store:put", %{})
    end

    test "confirming deletes the vehicle WITH its dependent records", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")
      two_car_garage(view)
      render_click(view, "ask_delete_vehicle", %{"vehicle-id" => @car_two})

      html = render_click(view, "confirm_delete_vehicle", %{})

      assert_push_event(view, "local_store:put", payload)
      deletes = payload["deletes"]

      assert %{"store" => "vehicles", "key" => @car_two} in to_wire(deletes)

      assert %{"store" => "events", "key" => "44444444-4444-4444-8444-444444444444"} in to_wire(
               deletes
             )

      # The OTHER vehicle's records are untouched.
      refute Enum.any?(
               to_wire(deletes),
               &(&1["key"] == "22222222-2222-4222-8222-222222222222")
             )

      # And the optimistic render: the BMW is gone from the garage panel now,
      # not after the next hydration.
      refute html =~ "data-test=\"delete-vehicle-modal\""
      render_click(view, "toggle_garage", %{})
      refute render(view) =~ "2020 BMW 328i"
    end

    test "deleting the explicitly chosen vehicle clears the stored choice", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"active_vehicle_id" => @car_two}
      })

      render_click(view, "ask_delete_vehicle", %{"vehicle-id" => @car_two})
      html = render_click(view, "confirm_delete_vehicle", %{})

      assert_push_event(view, "local_store:put", payload)

      assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]
      refute Map.has_key?(prefs, "active_vehicle_id")

      # The sticker falls back to the remaining vehicle rather than to nothing.
      assert html =~ "2020 Toyota Camry"
    end
  end

  describe "after the last vehicle is deleted" do
    test "the next mount reads as an empty garage, not as lost records", %{conn: conn} do
      # Deleting everything leaves the meta singleton behind — that is what an
      # INTENTIONAL emptying looks like, versus eviction which takes meta too.
      # Before this distinction, the next mount resolved :data_missing: a
      # screen accusing the browser of losing records the user chose to
      # remove, in a state that refuses every write — no way to start again.
      {:ok, view, _} = live(conn, ~p"/")

      html =
        hydrate(view, %{
          "meta" => %{"schema_version" => 1, "seq" => 7},
          "vehicles" => [],
          "events" => []
        })

      assert html =~ "Set up your first vehicle"
      refute html =~ "stored records are gone"
    end

    test "a truly wiped store still reads as lost records", %{conn: conn} do
      # No meta at all + a boot hint that says data existed: that is eviction,
      # and it must keep saying so.
      {:ok, view, _} = live(conn, ~p"/")

      html =
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
          "storage" => %{"mode" => "idb", "boot_hint" => "has_data"}
        })

      assert html =~ "stored records are gone"
    end
  end

  describe "what the qualifier attributes" do
    test "a user interval that beats the unknown-oil floor is credited to the user", %{conn: conn} do
      # Intake answered "I don't know yet", then the user set their own,
      # SHORTER interval. Shortest-wins means the user's number is what the
      # sticker shows — and the label must say so. The floor sentence here
      # would attribute their number to our model and promise that recording
      # the oil extends it, false on both counts.
      {:ok, view, _} = live(conn, ~p"/")

      floor_beating_vehicle =
        vehicle(@car_one, "Toyota", "Camry")
        |> Map.put("engine_class_code", "gas_direct_injection")
        |> Map.put("maintenance_plan", %{
          "planned_oil" => "unknown",
          "interval_miles" => 1000,
          "interval_months" => 2
        })

      html =
        hydrate(view, %{
          "vehicles" => [floor_beating_vehicle],
          "events" => [
            event("22222222-2222-4222-8222-222222222222", @car_one)
            |> Map.put("oil_base_stock", nil)
          ]
        })

      assert html =~ "Your interval"
      refute html =~ "shortest interval we model"
    end
  end

  describe "what a staged write persists" do
    test "a record hydrated with unknown fields writes them back FLAT", %{conn: conn} do
      # A newer release wrote prefs with a field this one does not know. It
      # hydrates nested under __unknown__; persisting it that way would
      # shadow the field forever. The write-back must restore the flat wire
      # shape.
      {:ok, view, _} = live(conn, ~p"/")

      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"unit_system" => "mi", "future_field" => "kept"}
      })

      render_click(view, "toggle_garage", %{})
      render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

      assert_push_event(view, "local_store:put", payload)
      assert [%{"store" => "prefs", "record" => prefs}] = payload["upserts"]

      assert prefs["future_field"] == "kept"
      refute Map.has_key?(prefs, "__unknown__")
      assert prefs["active_vehicle_id"] == @car_two
    end
  end

  describe "when prefs cannot be read" do
    test "switching refuses instead of destroying the quarantined record", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      # unit_system "nmi" fails validation, so the singleton quarantines and
      # garage.prefs hydrates nil. A switch would then write a fresh record
      # over content the contract promises stays exportable.
      hydrate(view, %{
        "vehicles" => [vehicle(@car_one, "Toyota", "Camry"), vehicle(@car_two, "BMW", "328i")],
        "prefs" => %{"unit_system" => "nmi", "time_zone" => "America/Denver"}
      })

      render_click(view, "toggle_garage", %{})
      html = render_click(view, "switch_vehicle", %{"vehicle-id" => @car_two})

      refute_push_event(view, "local_store:put", %{})
      assert html =~ "Could not read this browser&#39;s stored settings"
    end
  end

  # The put payload's deletes may arrive as wire pairs; normalize for `in`.
  defp to_wire(deletes) do
    Enum.map(deletes, fn
      %{"store" => _, "key" => _} = d -> d
      [store, key] -> %{"store" => store, "key" => key}
    end)
  end
end
