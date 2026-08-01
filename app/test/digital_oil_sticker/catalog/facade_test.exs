defmodule DigitalOilSticker.Catalog.FacadeTest do
  @moduledoc "Cascade walk against the fixture + failure-mode exclusivity + events edge."
  use ExUnit.Case, async: true

  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{OilModel, RateLimit, Selector}
  alias DigitalOilStickerWeb.CatalogEvents

  test "the full cascade resolves real fixture data: years → makes → models → configurations" do
    {:ok, years_sel} = Selector.validate(:list_years, %{})
    {:ok, years} = Catalog.list_years(years_sel)
    assert 2024 in years.data

    {:ok, makes_sel} = Selector.validate(:list_makes, %{"year" => 2024})
    {:ok, makes} = Catalog.list_makes(makes_sel)
    toyota = Enum.find(makes.data, &(&1.normalized_name == "toyota"))
    assert toyota, "fixture must contain Toyota for 2024"

    {:ok, models_sel} = Selector.validate(:list_models, %{"year" => 2024, "make_id" => toyota.id})
    {:ok, models} = Catalog.list_models(models_sel)
    assert models.total > 0
    assert models.total_known?

    model = hd(models.data)

    {:ok, configs_sel} =
      Selector.validate(:list_configurations, %{
        "year" => 2024,
        "make_id" => toyota.id,
        "model_id" => model.id
      })

    {:ok, configs} = Catalog.list_configurations(configs_sel)
    assert configs.data != []
    assert hd(configs.data).completeness_code == "identity_only"
  end

  test "oil grades are suggested per engine class and always labeled as our own model" do
    {:ok, sel} =
      Selector.validate(:list_oil_grades, %{"engine_class_code" => "gas_direct_injection"})

    {:ok, result} = Catalog.list_oil_grades(sel)

    assert result.status == :our_model
    assert Enum.any?(result.data.suggested, &(&1.code == "0W-20"))
    # Suggestions and the rest partition the model — nothing is dropped.
    assert result.total == length(OilModel.grades())
    assert Enum.any?(result.qualifiers, &(&1.code == :our_own_model))
  end

  test "an unknown engine class suggests nothing rather than another class's grades" do
    {:ok, sel} = Selector.validate(:list_oil_grades, %{})
    {:ok, result} = Catalog.list_oil_grades(sel)

    assert result.data.suggested == []
    assert length(result.data.others) == length(OilModel.grades())
  end

  test "an engine class outside the model is rejected, not passed through" do
    assert {:error, :invalid_selector} =
             Selector.validate(:list_oil_grades, %{"engine_class_code" => "gas_turbocharged"})
  end

  test "the interval for a direct-injection engine is shorter than the base stock's published high" do
    {:ok, sel} =
      Selector.validate(:get_oil_interval, %{
        "engine_class_code" => "gas_direct_injection",
        "base_stock_code" => "full_synthetic"
      })

    {:ok, result} = Catalog.get_oil_interval(sel)
    stock = OilModel.base_stock("full_synthetic")

    assert result.status == :our_model
    assert result.data.miles_recommended < stock.published_miles_high
    assert result.data.miles_recommended >= result.data.miles_low
    assert Enum.any?(result.qualifiers, &(&1.code == :our_own_model))
  end

  test "severe service never lengthens an interval" do
    for stock <- OilModel.base_stocks(),
        class <- OilModel.engine_classes(),
        class.engine_oil == "applicable" do
      {:ok, normal} = OilModel.interval(class.code, stock.code, "normal")
      {:ok, severe} = OilModel.interval(class.code, stock.code, "severe")

      assert severe.miles_recommended <= normal.miles_recommended
      assert severe.months_cap <= normal.months_cap
    end
  end

  test "no modelled interval ever exceeds its base stock's published range" do
    for stock <- OilModel.base_stocks(),
        class <- OilModel.engine_classes(),
        class.engine_oil == "applicable" do
      {:ok, rule} = OilModel.interval(class.code, stock.code, "normal")
      assert rule.miles_recommended <= stock.published_miles_high
    end
  end

  test "a vehicle with no engine oil service gets no interval at all" do
    {:ok, sel} =
      Selector.validate(:get_oil_interval, %{
        "engine_class_code" => "bev",
        "base_stock_code" => "full_synthetic"
      })

    assert {:ok, %{status: :not_applicable, data: nil}} = Catalog.get_oil_interval(sel)
  end

  test "search_oils (recommendation path) never lists products without a resolved requirement" do
    fake = String.duplicate("0", 8) <> "-0000-5000-8000-" <> String.duplicate("0", 12)
    {:ok, sel} = Selector.validate(:search_oils, %{"requirement_id" => fake})
    {:ok, result} = Catalog.search_oils(sel)
    assert result.status == :unsupported
    assert result.data == []
  end

  test "failure modes are mutually exclusive: an absent fact is a status, never an error" do
    fake = String.duplicate("0", 8) <> "-0000-5000-8000-" <> String.duplicate("0", 12)
    {:ok, sel} = Selector.validate(:list_compatible_filters, %{"configuration_key" => fake})
    assert {:ok, %{status: :unsupported, data: []}} = Catalog.list_compatible_filters(sel)
  end

  describe "the CatalogEvents web edge" do
    test "a payload with an extra key is rejected and no query runs" do
      ref = attach_query_counter()
      bucket = RateLimit.new()

      assert {:error, :invalid_selector, _} =
               CatalogEvents.handle(
                 "catalog:select_year",
                 %{"year" => 2024, "vin" => "X"},
                 bucket,
                 0
               )

      assert query_count(ref) == 0
    end

    test "a valid event round-trips and spends one token" do
      bucket = RateLimit.new(30, 5, 0)

      assert {:ok, result, bucket2} =
               CatalogEvents.handle("catalog:select_year", %{"year" => 2024}, bucket, 0)

      assert result.status == :identity_only
      assert bucket2.tokens < bucket.tokens
    end

    test "a drained bucket rate-limits without executing" do
      empty = %RateLimit{RateLimit.new(1, 1, 0) | tokens: 0.0}

      assert {:error, :rate_limited, ^empty} =
               CatalogEvents.handle("catalog:select_year", %{"year" => 2024}, empty, 0)
    end

    test "an unknown event name is invalid" do
      bucket = RateLimit.new()
      assert {:error, :invalid_selector, _} = CatalogEvents.handle("catalog:evil", %{}, bucket, 0)
    end
  end

  test "the pure token bucket refills over time and caps at capacity" do
    bucket = RateLimit.new(10, 5, 0)
    {:ok, drained} = drain(bucket, 10, 0)
    assert {:error, :rate_limited} = RateLimit.take(drained, 1, 0)
    assert {:ok, _} = RateLimit.take(drained, 1, 1_000)
    {:ok, refilled} = RateLimit.take(drained, 1, 60_000)
    assert refilled.tokens <= 10.0
  end

  defp drain(bucket, 0, _now), do: {:ok, bucket}

  defp drain(bucket, n, now) do
    {:ok, b} = RateLimit.take(bucket, 1, now)
    drain(b, n - 1, now)
  end

  # Telemetry handlers are global, so count only the spans this test's own
  # process emitted — otherwise a concurrent async module's queries land here.
  defp attach_query_counter do
    ref = :counters.new(1, [])
    test_pid = self()

    :telemetry.attach(
      "test-query-counter-#{inspect(self())}",
      [:dos, :catalog, :query, :stop],
      fn _, _, _, pid -> if self() == pid, do: :counters.add(ref, 1, 1) end,
      test_pid
    )

    on_exit(fn -> :telemetry.detach("test-query-counter-#{inspect(self())}") end)
    ref
  end

  defp query_count(ref), do: :counters.get(ref, 1)
end
