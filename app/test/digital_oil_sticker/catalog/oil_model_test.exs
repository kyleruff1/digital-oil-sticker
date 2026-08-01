defmodule DigitalOilSticker.Catalog.OilModelTest do
  @moduledoc """
  Our own oil model, checked against the two properties it has to hold: it
  never extrapolates upward, and it never presents itself as manufacturer
  guidance.
  """
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog.OilModel

  describe "the safety rule" do
    test "an unmodelled combination falls back to the lowest published interval" do
      # A base stock we model, against a class code we hold no rule for.
      {:ok, rule} = OilModel.interval("no_such_class", "full_synthetic", "normal")
      stock = OilModel.base_stock("full_synthetic")

      assert rule.basis == :fallback_lowest_published
      assert rule.miles_recommended == rule.miles_low
      assert rule.miles_low <= stock.published_miles_low
    end

    test "the fallback still honours a severe-service answer" do
      {:ok, normal} = OilModel.interval("no_such_class", "conventional", "normal")
      {:ok, severe} = OilModel.interval("no_such_class", "conventional", "severe")

      assert severe.miles_low < normal.miles_low
      assert severe.months_cap < normal.months_cap
    end

    test "a base stock outside the model is an error, never a guessed interval" do
      assert {:error, :unknown_base_stock} = OilModel.interval("gas_mid", "castor_oil", "normal")
    end

    test "every modelled interval stays inside its base stock's published range" do
      for stock <- OilModel.base_stocks(),
          class <- OilModel.engine_classes(),
          class.engine_oil == "applicable",
          condition <- OilModel.service_conditions() do
        {:ok, rule} = OilModel.interval(class.code, stock.code, condition.code)

        assert rule.miles_recommended <= stock.published_miles_high,
               "#{class.code}/#{stock.code}/#{condition.code} exceeds the published high"

        assert rule.miles_low >= 500
        assert rule.months_cap >= 3
      end
    end

    test "direct injection is modelled as shorter than an equivalent port-injected engine" do
      {:ok, di} = OilModel.interval("gas_direct_injection", "full_synthetic", "normal")
      {:ok, port} = OilModel.interval("gas_mid", "full_synthetic", "normal")

      assert di.miles_recommended < port.miles_recommended
    end
  end

  describe "engine classes" do
    test "classes with no engine oil service report that rather than an interval" do
      for class <- OilModel.engine_classes(), class.engine_oil == "not_applicable" do
        assert OilModel.interval(class.code, "full_synthetic", "normal") == :not_applicable
        assert OilModel.grades_for_class(class.code) == []
      end
    end

    test "every suggested grade is a grade we actually model" do
      codes = MapSet.new(OilModel.grades(), & &1.code)

      for class <- OilModel.engine_classes(), grade <- OilModel.grades_for_class(class.code) do
        assert MapSet.member?(codes, grade.code)
      end
    end

    test "suggested and other grades partition the model with no overlap" do
      {suggested, others} = OilModel.grade_choices("gas_small")
      suggested_codes = MapSet.new(suggested, & &1.code)
      other_codes = MapSet.new(others, & &1.code)

      assert MapSet.disjoint?(suggested_codes, other_codes)

      assert MapSet.union(suggested_codes, other_codes) ==
               MapSet.new(OilModel.grades(), & &1.code)
    end

    test "an unknown class borrows no other class's grades" do
      assert OilModel.grades_for_class("no_such_class") == []
      assert OilModel.grades_for_class(nil) == []
    end

    test "diesel records the service category it needs, since it is not interchangeable" do
      assert %{requires_service_category: category} = OilModel.engine_class("diesel_light")
      assert is_binary(category)
    end
  end

  describe "honesty about whose model this is" do
    test "the basis statement says it is ours and that a maker's schedule outranks it" do
      basis = OilModel.basis_statement()

      assert basis =~ "OUR model" or basis =~ "our own"
      assert basis =~ "manufacturer"
    end

    test "the safety rule is recorded in the artifact, not just in code" do
      assert OilModel.safety_rule() =~ "LOWEST"
      assert is_binary(OilModel.model_version())
    end

    test "every rule carries the reasoning that produced it" do
      for stock <- OilModel.base_stocks(),
          class <- OilModel.engine_classes(),
          class.engine_oil == "applicable" do
        {:ok, rule} = OilModel.interval(class.code, stock.code, "normal")
        assert String.length(rule.reasoning) > 20
      end
    end
  end
end
