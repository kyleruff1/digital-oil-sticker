defmodule DigitalOilSticker.Catalog.OilModel do
  @moduledoc """
  OUR OWN oil model, read once at boot into `:persistent_term`.

  This is deliberately not the recommendation path guarded by INV-16. That
  guard exists because a manufacturer requirement we do not hold must never be
  fabricated from a product name. This module makes no manufacturer claim at
  all: it is an interval model we authored, from SAE J300 grade definitions,
  published base-stock interval ranges, and engine classes we derive ourselves
  from EPA/DOE configuration fields. Every surface that renders it must say so
  (`basis_statement/0`), and any sourced manufacturer schedule outranks it
  (shorter always wins — see `RECOMMENDATION_CLAIMS_POLICY`).

  The whole model is ~110 rows, so it is loaded eagerly rather than queried per
  render. Like `Metadata` it fails closed: a catalog without the oil model
  stops the boot rather than letting the app silently show no intervals.

  ## The safety rule

  `interval/3` never extrapolates upward. A combination with no explicit rule
  falls back to the applicable base stock's published LOW mileage, tagged
  `:fallback_lowest_published`, so an unmodelled case is always conservative.
  """
  use GenServer

  @key {__MODULE__, :model}

  @type interval :: %{
          miles_low: pos_integer(),
          miles_recommended: pos_integer(),
          months_cap: pos_integer(),
          basis: :rule | :fallback_lowest_published,
          reasoning: String.t()
        }

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :persistent_term.put(@key, load())
    {:ok, %{}}
  end

  # -- public reads -----------------------------------------------------------

  def model_version, do: meta()["model_version"]
  def basis_statement, do: meta()["basis_statement"]
  def safety_rule, do: meta()["safety_rule"]
  def authored_at, do: meta()["authored_at"]

  @doc "All SAE J300 grades we model, ordered by winter then operating number."
  def grades, do: get().grades

  @doc "Grades flagged common — the default list length for a picker."
  def common_grades, do: Enum.filter(grades(), & &1.common?)

  def grade(code), do: Enum.find(grades(), &(&1.code == code))

  def base_stocks, do: get().base_stocks
  def base_stock(code), do: Enum.find(base_stocks(), &(&1.code == code))

  def engine_classes, do: get().engine_classes
  def engine_class(code), do: Map.get(get().engine_class_index, code)

  def service_conditions, do: get().service_conditions
  def service_condition(code), do: Enum.find(service_conditions(), &(&1.code == code))

  @doc """
  The grades typical for an engine class, best-first. Empty for classes with
  no engine oil service, and empty for an unknown class — an unknown class
  must not silently borrow another class's list.
  """
  def grades_for_class(nil), do: []

  def grades_for_class(class_code) do
    get().class_grades
    |> Map.get(class_code, [])
    |> Enum.map(&grade/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Suggested grades for a class, then every other grade we model. The caller
  renders the first group as the filtered list and the second behind a "show
  all" control, so the user can always reach a grade we did not suggest
  without leaving the closed vocabulary.
  """
  def grade_choices(class_code) do
    suggested = grades_for_class(class_code)
    suggested_codes = MapSet.new(suggested, & &1.code)
    {suggested, Enum.reject(grades(), &MapSet.member?(suggested_codes, &1.code))}
  end

  @doc """
  Our modelled interval for (engine class, base stock, service condition).

  Returns `:not_applicable` for classes with no engine oil service, and
  `{:error, :unknown_base_stock}` when the base stock is not one we model.
  Any other unmodelled combination resolves to the base stock's published low
  mileage per the safety rule rather than failing — a conservative number is
  more useful here than none.
  """
  @spec interval(String.t() | nil, String.t(), String.t()) ::
          {:ok, interval()} | :not_applicable | {:error, :unknown_base_stock}
  def interval(class_code, base_stock_code, condition_code \\ "normal") do
    stock = base_stock(base_stock_code)

    cond do
      is_nil(stock) ->
        {:error, :unknown_base_stock}

      match?(%{engine_oil: "not_applicable"}, engine_class(class_code)) ->
        :not_applicable

      true ->
        case Map.get(get().rules, {class_code, base_stock_code, condition_code}) do
          nil -> {:ok, fallback(stock, condition_code)}
          rule -> {:ok, Map.put(rule, :basis, :rule)}
        end
    end
  end

  @doc """
  Convenience for a whole vehicle configuration row: reads its stored
  `engine_class_code` (we never re-derive the class at request time — the
  classification lives in the artifact so it is versioned with the data).
  """
  def interval_for_configuration(config, base_stock_code, condition_code \\ "normal")
  def interval_for_configuration(nil, _stock, _condition), do: {:error, :unknown_configuration}

  def interval_for_configuration(%{engine_class_code: code}, stock, condition),
    do: interval(code, stock, condition)

  @doc """
  Every interval we model for one engine class, as a table the settings screen
  can render so the user can see the model rather than just its output.
  """
  def interval_table(class_code) do
    for stock <- base_stocks(),
        condition <- service_conditions(),
        {:ok, rule} <- [interval(class_code, stock.code, condition.code)] do
      %{base_stock: stock, service_condition: condition, interval: rule}
    end
  end

  # -- internals --------------------------------------------------------------

  defp get, do: :persistent_term.get(@key)
  defp meta, do: get().metadata

  # Not a rule we authored: scale nothing, take the published floor. The
  # condition factor is still applied because a severe-service answer is user
  # input we should honour even where our rule table has a hole.
  defp fallback(stock, condition_code) do
    factor = if condition_code == "severe", do: 0.5, else: 1.0
    low = max(500, round(stock.published_miles_low * factor / 250) * 250)
    months = if condition_code == "severe", do: max(3, div(stock.published_months_cap, 2)), else: stock.published_months_cap

    %{
      miles_low: low,
      miles_recommended: low,
      months_cap: months,
      basis: :fallback_lowest_published,
      reasoning:
        "We have no specific rule for this combination, so we use the lowest published interval for " <>
          "#{stock.display_name} (#{stock.published_miles_low} miles) rather than estimating upward."
    }
  end

  defp load do
    metadata = query!("SELECT key, value FROM oil_model_metadata") |> Map.new(fn [k, v] -> {k, v} end)

    if metadata == %{}, do: raise("catalog has no oil model (oil_model_metadata is empty)")

    grades =
      "SELECT code, winter, operating, common, notes FROM oil_grades ORDER BY winter, operating"
      |> query!()
      |> Enum.map(fn [code, winter, operating, common, notes] ->
        %{code: code, winter: winter, operating: operating, common?: common == 1, notes: notes}
      end)

    base_stocks =
      ("SELECT code, display_name, published_miles_low, published_miles_high, published_months_cap, reasoning " <>
         "FROM oil_base_stocks ORDER BY published_miles_low, code")
      |> query!()
      |> Enum.map(fn [code, name, low, high, months, reasoning] ->
        %{
          code: code,
          display_name: name,
          published_miles_low: low,
          published_miles_high: high,
          published_months_cap: months,
          reasoning: reasoning
        }
      end)

    engine_classes =
      ("SELECT code, display_name, engine_oil, interval_factor, requires_service_category, reasoning " <>
         "FROM engine_classes ORDER BY display_name")
      |> query!()
      |> Enum.map(fn [code, name, oil, factor, category, reasoning] ->
        %{
          code: code,
          display_name: name,
          engine_oil: oil,
          interval_factor: factor,
          requires_service_category: category,
          reasoning: reasoning
        }
      end)

    class_grades =
      "SELECT engine_class_code, grade_code FROM engine_class_grades ORDER BY engine_class_code, rank"
      |> query!()
      |> Enum.reduce(%{}, fn [class, grade], acc ->
        Map.update(acc, class, [grade], &(&1 ++ [grade]))
      end)

    service_conditions =
      "SELECT code, display_name, factor, reasoning, questions FROM service_conditions ORDER BY factor DESC"
      |> query!()
      |> Enum.map(fn [code, name, factor, reasoning, questions] ->
        %{
          code: code,
          display_name: name,
          factor: factor,
          reasoning: reasoning,
          questions: decode_questions(questions)
        }
      end)

    rules =
      ("SELECT engine_class_code, base_stock_code, service_condition, miles_low, miles_recommended, " <>
         "months_cap, reasoning FROM interval_rules")
      |> query!()
      |> Map.new(fn [class, stock, condition, low, rec, months, reasoning] ->
        {{class, stock, condition},
         %{miles_low: low, miles_recommended: rec, months_cap: months, reasoning: reasoning}}
      end)

    %{
      metadata: metadata,
      grades: grades,
      base_stocks: base_stocks,
      engine_classes: engine_classes,
      engine_class_index: Map.new(engine_classes, &{&1.code, &1}),
      class_grades: class_grades,
      service_conditions: service_conditions,
      rules: rules
    }
  end

  defp query!(sql), do: Ecto.Adapters.SQL.query!(DigitalOilSticker.CatalogRepo, sql, []).rows

  defp decode_questions(nil), do: []
  defp decode_questions(json), do: Jason.decode!(json)
end
