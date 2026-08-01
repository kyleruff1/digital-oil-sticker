defmodule DigitalOilSticker.IntervalPolicyTest do
  @moduledoc "The shortest interval wins, and the answer always names its basis."
  use ExUnit.Case, async: true

  alias DigitalOilSticker.IntervalPolicy

  test "with nothing to go on there is no interval and no invented basis" do
    assert %{miles: nil, months: nil, basis: :none} = IntervalPolicy.resolve([])
  end

  test "the user's interval wins when it is shorter than ours" do
    resolved =
      IntervalPolicy.resolve(
        user: %{miles: 4_000, months: 6},
        our_model: %{miles: 10_000, months: 12}
      )

    assert resolved.miles == 4_000
    assert resolved.months == 6
    assert resolved.basis == :user
  end

  test "our model wins when the user asked for longer — nothing here lengthens an interval" do
    resolved =
      IntervalPolicy.resolve(
        user: %{miles: 15_000, months: 24},
        our_model: %{miles: 8_000, months: 12}
      )

    assert resolved.miles == 8_000
    assert resolved.basis == :our_model
  end

  test "a manufacturer schedule wins a tie, because it is the one we could cite" do
    resolved =
      IntervalPolicy.resolve(
        user: %{miles: 5_000, months: 6},
        manufacturer: %{miles: 5_000, months: 6},
        our_model: %{miles: 5_000, months: 6}
      )

    assert resolved.basis == :manufacturer
  end

  test "dimensions resolve independently and a split result is reported as mixed" do
    resolved =
      IntervalPolicy.resolve(
        user: %{miles: 3_000, months: nil},
        our_model: %{miles: 10_000, months: 12}
      )

    assert resolved.miles_basis == :user
    assert resolved.months_basis == :our_model
    assert resolved.basis == :mixed
  end

  test "a vehicle with no engine oil service gets no interval, not the user's number" do
    plan = %{"interval_miles" => 5_000, "interval_months" => 6}
    assert IntervalPolicy.for_vehicle(plan, :not_applicable) == :not_applicable
  end

  test "for_vehicle falls back to the user's plan when our model has no answer" do
    plan = %{"interval_miles" => 5_000, "interval_months" => 6}
    resolved = IntervalPolicy.for_vehicle(plan, nil)

    assert resolved.miles == 5_000
    assert resolved.basis == :user
  end

  test "for_vehicle uses our model when the user has set no plan" do
    resolved =
      IntervalPolicy.for_vehicle(
        nil,
        {:ok, %{miles_recommended: 8_000, months_cap: 12, miles_low: 6_000}}
      )

    assert resolved.miles == 8_000
    assert resolved.basis == :our_model
  end

  test "zero and negative intervals are ignored rather than treated as strictest" do
    resolved =
      IntervalPolicy.resolve(
        user: %{miles: 0, months: -1},
        our_model: %{miles: 8_000, months: 12}
      )

    assert resolved.miles == 8_000
    assert resolved.basis == :our_model
  end
end
