defmodule DigitalOilSticker.DueTest do
  @moduledoc """
  The due calculation, and above all which OIL it reasons from.

  The chain is a claim about how much we know: what the last change RECORDS
  beats what intake says the vehicle USES, which beats "not known yet", which
  is never a guessed stock — it is the model's floor for the engine. An
  inversion anywhere in that chain shows the user a number derived from
  weaker knowledge than they gave us.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog.OilModel
  alias DigitalOilSticker.Due

  # A class the shipped model actually has rules for.
  @class "gas_direct_injection"

  defp vehicle(plan) do
    %{
      "vehicle_id" => "11111111-1111-4111-8111-111111111111",
      "engine_class_code" => @class,
      "maintenance_plan" => plan
    }
  end

  defp event(overrides \\ %{}) do
    Map.merge(
      %{
        "event_id" => "22222222-2222-4222-8222-222222222222",
        "vehicle_id" => "11111111-1111-4111-8111-111111111111",
        "performed_at" => "2026-06-15",
        "odometer_m" => 100_584_000,
        "input_unit" => "mi",
        "oil_base_stock" => "full_synthetic"
      },
      overrides
    )
  end

  describe "which oil the model reasons from" do
    test "what the change records beats what intake planned" do
      # Intake said conventional; the change says full synthetic went in.
      # The recorded fact wins.
      due =
        Due.compute(
          vehicle(%{"planned_oil" => "selected", "planned_base_stock" => "conventional"}),
          event(%{"oil_base_stock" => "full_synthetic"})
        )

      {:ok, expected} = OilModel.interval(@class, "full_synthetic", "normal")

      assert due.oil_basis == :event
      assert due.resolved.miles == expected.miles_recommended
    end

    test "a change with no oil recorded falls back to the intake answer" do
      due =
        Due.compute(
          vehicle(%{"planned_oil" => "selected", "planned_base_stock" => "conventional"}),
          event(%{"oil_base_stock" => nil})
        )

      {:ok, expected} = OilModel.interval(@class, "conventional", "normal")

      assert due.oil_basis == :planned
      assert due.resolved.miles == expected.miles_recommended
    end

    test "\"I don't know yet\" resolves to the model's floor, never a guessed stock" do
      due =
        Due.compute(
          vehicle(%{"planned_oil" => "unknown"}),
          event(%{"oil_base_stock" => nil})
        )

      assert due.oil_basis == :unknown_oil

      # The floor property is the whole claim: no stock we model may promise
      # fewer miles than the unknown-oil answer.
      for stock <- OilModel.base_stocks() do
        {:ok, rule} = OilModel.interval(@class, stock.code, "normal")

        assert due.resolved.miles <= rule.miles_recommended,
               "the unknown-oil interval exceeds #{stock.code}, so it is not a floor"
      end
    end

    test "no oil knowledge at all resolves to no model interval" do
      due = Due.compute(vehicle(nil), event(%{"oil_base_stock" => nil}))

      assert due.oil_basis == :none
      assert due.resolved.basis == :none
      assert due.date_text == nil
    end

    test "an event stock the model does not know falls through, not latches" do
      # A legacy or imported record with "synthetic" — a string our tables do
      # not carry. Store validation does not constrain the field, so the
      # record hydrates cleanly. "We cannot read that record" must not erase
      # what intake DID tell us: the chain falls through to the planned oil.
      due =
        Due.compute(
          vehicle(%{"planned_oil" => "selected", "planned_base_stock" => "conventional"}),
          event(%{"oil_base_stock" => "synthetic"})
        )

      {:ok, expected} = OilModel.interval(@class, "conventional", "normal")

      assert due.oil_basis == :planned
      assert due.resolved.miles == expected.miles_recommended
    end

    test "an unreadable event stock still reaches the unknown-oil floor" do
      due =
        Due.compute(
          vehicle(%{"planned_oil" => "unknown"}),
          event(%{"oil_base_stock" => "synthetic"})
        )

      assert due.oil_basis == :unknown_oil
      assert is_integer(due.resolved.miles)
    end
  end

  describe "the anchor" do
    test "due mileage is the odometer AT the change plus the interval" do
      due =
        Due.compute(
          vehicle(nil) |> Map.put("maintenance_plan", %{"interval_miles" => 5000}),
          event()
        )

      # 100_584_000 m = 62,500 mi exactly; + 5,000 = 67,500.
      assert due.due_odometer_m == 100_584_000 + round(5000 * 1609.344)
      assert due.mileage_text == "67,500 mi"
    end

    test "no change recorded means no due values, not values measured from nothing" do
      due = Due.compute(vehicle(%{"interval_miles" => 5000, "interval_months" => 6}), nil)

      assert due.due_on == nil
      assert due.due_odometer_m == nil
      assert due.date_text == nil
    end

    test "the user's shorter interval still wins over the planned oil's model interval" do
      # Shortest-wins is IntervalPolicy's contract; this asserts the planned
      # fallback did not bypass it.
      due =
        Due.compute(
          vehicle(%{
            "planned_oil" => "selected",
            "planned_base_stock" => "full_synthetic",
            "interval_miles" => 1000
          }),
          event(%{"oil_base_stock" => nil})
        )

      assert due.resolved.miles == 1000
      assert due.resolved.miles_basis == :user
    end
  end
end
