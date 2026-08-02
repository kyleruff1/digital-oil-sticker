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

  # The put payload's deletes may arrive as wire pairs; normalize for `in`.
  defp to_wire(deletes) do
    Enum.map(deletes, fn
      %{"store" => _, "key" => _} = d -> d
      [store, key] -> %{"store" => store, "key" => key}
    end)
  end
end
