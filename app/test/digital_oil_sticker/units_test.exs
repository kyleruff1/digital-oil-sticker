defmodule DigitalOilSticker.UnitsTest do
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Units

  describe "to_metres/2 exact conversions" do
    test "1 mi = 1609.344 m rounds to 1609" do
      assert Units.to_metres(1, :mi) == {:ok, 1609}
    end

    test "10_000 mi = 16_093_440 m exactly" do
      assert Units.to_metres(10_000, :mi) == {:ok, 16_093_440}
    end

    test "rounding is half-up to the nearest metre" do
      # 2 mi = 3218.688 -> 3219; 3 mi = 4828.032 -> 4828
      assert Units.to_metres(2, :mi) == {:ok, 3219}
      assert Units.to_metres(3, :mi) == {:ok, 4828}
      # 0.5 mi = 804.672 -> 805
      assert Units.to_metres("0.5", :mi) == {:ok, 805}
      # 2.5 km = 2500 exactly
      assert Units.to_metres("2.5", :km) == {:ok, 2500}
    end

    test "km is a factor of 1000" do
      assert Units.to_metres(1, :km) == {:ok, 1000}
      assert Units.to_metres(12_345, :km) == {:ok, 12_345_000}
    end

    test "zero is fine in both units" do
      assert Units.to_metres(0, :mi) == {:ok, 0}
      assert Units.to_metres(0, :km) == {:ok, 0}
    end
  end

  describe "to_metres/2 binary parsing" do
    test "strips commas" do
      assert Units.to_metres("1,000", :mi) == {:ok, 1_609_344}
    end

    test "strips spaces" do
      assert Units.to_metres(" 12 500 ", :km) == {:ok, 12_500_000}
    end

    test "strips commas and spaces together with decimals" do
      assert Units.to_metres("1, 000.5", :km) == {:ok, 1_000_500}
    end
  end

  describe "to_metres/2 rejection" do
    test "negative values are :negative" do
      assert Units.to_metres(-1, :mi) == {:error, :negative}
      assert Units.to_metres(-0.5, :km) == {:error, :negative}
      assert Units.to_metres("-42", :mi) == {:error, :negative}
    end

    test "implausible values are :implausible" do
      # ceiling: 1_600_000 km = 1.6e9 m exactly passes
      assert Units.to_metres(1_600_000, :km) == {:ok, 1_600_000_000}
      assert Units.to_metres(1_600_001, :km) == {:error, :implausible}
      # 1_000_000 mi = 1_609_344_000 m > 1.6e9
      assert Units.to_metres(1_000_000, :mi) == {:error, :implausible}
    end

    test "non-numeric values are :not_a_number" do
      assert Units.to_metres("about 12", :mi) == {:error, :not_a_number}
      assert Units.to_metres("", :km) == {:error, :not_a_number}
      assert Units.to_metres("12.3.4", :km) == {:error, :not_a_number}
      assert Units.to_metres(nil, :mi) == {:error, :not_a_number}
      assert Units.to_metres(:twelve, :mi) == {:error, :not_a_number}
    end
  end

  describe "from_metres/2" do
    test "converts to one decimal place" do
      assert Units.from_metres(1609, :mi) == 1.0
      assert Units.from_metres(16_093_440, :mi) == 10_000.0
      assert Units.from_metres(2500, :km) == 2.5
      assert Units.from_metres(0, :mi) == 0.0
    end
  end

  describe "round-trip property (deterministic sample)" do
    # Deterministic sample across the plausible mile range; StreamData is
    # not a dependency, so a fixed-step comprehension stands in for it. The
    # implausibility ceiling (1.6e9 m) caps stored mileage at 994,193 mi,
    # so the sample tops out there rather than at 999,999.
    @max_plausible_miles 994_193
    @sample Enum.to_list(0..@max_plausible_miles//997) ++ [1, @max_plausible_miles]

    test "the sample ceiling really is the plausibility boundary" do
      assert {:ok, _} = Units.to_metres(@max_plausible_miles, :mi)
      assert Units.to_metres(@max_plausible_miles + 1, :mi) == {:error, :implausible}
    end

    test "to_metres -> from_metres round-trips within 0.05 mi" do
      for miles <- @sample do
        assert {:ok, metres} = Units.to_metres(miles, :mi)
        displayed = Units.from_metres(metres, :mi)

        assert abs(displayed - miles) <= 0.05,
               "#{miles} mi -> #{metres} m -> #{displayed} mi drifted"
      end
    end

    test "repeated unit toggling does not drift" do
      for miles <- @sample do
        assert {:ok, m0} = Units.to_metres(miles, :mi)

        d1 = Units.from_metres(m0, :mi)
        assert {:ok, m1} = Units.to_metres(d1, :mi)

        d2 = Units.from_metres(m1, :mi)
        assert {:ok, m2} = Units.to_metres(d2, :mi)

        d3 = Units.from_metres(m2, :mi)

        assert d2 == d1, "display drifted for #{miles}: #{d1} -> #{d2}"
        assert d3 == d2, "display drifted for #{miles}: #{d2} -> #{d3}"
        assert m2 == m1, "stored metres drifted for #{miles}: #{m1} -> #{m2}"
      end
    end

    test "toggling through km and back does not drift stored metres" do
      for miles <- @sample do
        assert {:ok, m0} = Units.to_metres(miles, :mi)

        # display in km, re-enter as km, display in mi, re-enter as mi
        km = Units.from_metres(m0, :km)
        assert {:ok, m1} = Units.to_metres(km, :km)
        mi = Units.from_metres(m1, :mi)
        assert {:ok, m2} = Units.to_metres(mi, :mi)

        # a 0.1 km display step is 100 m; one round of re-entry stays within
        # half that step, and the second round is a fixed point
        assert abs(m1 - m0) <= 50
        km2 = Units.from_metres(m2, :km)
        assert {:ok, m3} = Units.to_metres(km2, :km)
        mi2 = Units.from_metres(m3, :mi)
        assert {:ok, m4} = Units.to_metres(mi2, :mi)
        assert abs(m4 - m2) <= 1, "metres drifted for #{miles}: #{m2} -> #{m4}"
      end
    end
  end
end
