defmodule DigitalOilSticker.Catalog do
  @moduledoc """
  The catalog facade (DOS-M09-004) — the ONLY public query surface. Every
  function takes a validated `%Selector{}` and returns `{:ok, %Result{}}` or
  a typed error (`:invalid_selector | :rate_limited | :catalog_unavailable |
  :stale_cursor`). No module in this namespace references Phoenix, Plug, or
  client-storage code (FR-18, asserted by boundary test).

  Pipeline per call: (rate limiting is tier-1, applied by the caller against
  its own socket bucket) → cache → query → status derivation → result.
  """
  alias DigitalOilSticker.Catalog.{
    Cache,
    Metadata,
    OilModel,
    Result,
    Selector,
    SourceGate,
    Status,
    Telemetry
  }

  alias DigitalOilSticker.Catalog.Queries.{Identity, Products, Provenance, Service}

  @type error ::
          {:error, :invalid_selector | :rate_limited | :catalog_unavailable | :stale_cursor}

  def metadata do
    guarded(:metadata, fn -> {:ok, Metadata.get()} end)
  end

  @spec list_years(Selector.t()) :: {:ok, Result.t()} | error
  def list_years(%Selector{function: :list_years}) do
    call(:list_years, %Selector{function: :list_years}, fn sel ->
      years = Identity.years()

      {:ok,
       Result.new(:identity_only, years,
         total_known?: true,
         total: length(years),
         provenance: [],
         qualifiers: qualifiers_for_identity(sel)
       )}
    end)
  end

  def list_years(_), do: {:error, :invalid_selector}

  @spec list_makes(Selector.t()) :: {:ok, Result.t()} | error
  def list_makes(%Selector{function: :list_makes} = sel) do
    call(:list_makes, sel, fn s ->
      with {:ok, rows, cursor} <- Identity.makes_page(s) do
        total = Identity.count_distinct_makes(s.year)
        {:ok, Result.new(:identity_only, rows, cursor: cursor, total_known?: true, total: total)}
      end
    end)
  end

  def list_makes(_), do: {:error, :invalid_selector}

  @spec list_models(Selector.t()) :: {:ok, Result.t()} | error
  def list_models(%Selector{function: :list_models} = sel) do
    call(:list_models, sel, fn s ->
      # AC-4: a fabricated `make_id` that never appeared in the prior level's
      # response is rejected with `:unsupported`, not answered with an empty
      # page. The check runs before the models query so no join work happens
      # for a bad parent id.
      if Identity.make_exists?(s.year, s.make_id) do
        with {:ok, rows, cursor} <- Identity.models_page(s) do
          total = Identity.count_distinct_models(s.year, s.make_id)

          {:ok,
           Result.new(:identity_only, rows, cursor: cursor, total_known?: true, total: total)}
        end
      else
        {:ok,
         Result.new(:unsupported, [],
           total_known?: true,
           total: 0,
           qualifiers: [%{code: :parent_not_in_cascade}]
         )}
      end
    end)
  end

  def list_models(_), do: {:error, :invalid_selector}

  @spec list_configurations(Selector.t()) :: {:ok, Result.t()} | error
  def list_configurations(%Selector{function: :list_configurations} = sel) do
    call(:list_configurations, sel, fn s ->
      # AC-4: both parents (make_id under year, then model_id under
      # (year, make_id)) must be real cascade-drawn values. Either miss short-
      # circuits to `:unsupported` with the same qualifier the models level
      # emits, so callers can distinguish "bad parent" from "real parent,
      # empty child set".
      cond do
        not Identity.make_exists?(s.year, s.make_id) ->
          {:ok, Result.new(:unsupported, [], qualifiers: [%{code: :parent_not_in_cascade}])}

        not Identity.model_exists?(s.year, s.make_id, s.model_id) ->
          {:ok, Result.new(:unsupported, [], qualifiers: [%{code: :parent_not_in_cascade}])}

        true ->
          with {:ok, rows, cursor} <- Identity.configurations_page(s) do
            {:ok, Result.new(:identity_only, rows, cursor: cursor, total_known?: false)}
          end
      end
    end)
  end

  def list_configurations(_), do: {:error, :invalid_selector}

  @spec get_configuration(Selector.t()) :: {:ok, Result.t()} | error
  def get_configuration(%Selector{function: :get_configuration} = sel) do
    call(:get_configuration, sel, fn s ->
      config = Identity.get_configuration(s.configuration_key)
      {status, qualifiers} = Status.derive(config, %{schedules: [], requirements: [], claims: []})

      case config do
        nil ->
          {:ok, Result.new(status, nil, qualifiers: qualifiers)}

        _ ->
          {:ok,
           Result.new(config_status(config), config,
             qualifiers: qualifiers,
             provenance: Provenance.sources([config.source_id])
           )}
      end
    end)
  end

  def get_configuration(_), do: {:error, :invalid_selector}

  @spec get_schedules(Selector.t()) :: {:ok, Result.t()} | error
  def get_schedules(%Selector{function: :get_schedules} = sel) do
    call(:get_schedules, sel, fn s ->
      config = Identity.get_configuration(s.configuration_key)
      schedules = if config, do: Service.schedules(s), else: []

      {status, qualifiers} =
        Status.derive(config, %{schedules: schedules, requirements: [], claims: []})

      {:ok,
       Result.new(status, schedules,
         qualifiers: qualifiers,
         provenance: Provenance.sources(Enum.map(schedules, & &1.source_id))
       )}
    end)
  end

  def get_schedules(_), do: {:error, :invalid_selector}

  @spec get_lubricant_requirements(Selector.t()) :: {:ok, Result.t()} | error
  def get_lubricant_requirements(%Selector{function: :get_lubricant_requirements} = sel) do
    call(:get_lubricant_requirements, sel, fn s ->
      config = Identity.get_configuration(s.configuration_key)

      cond do
        is_nil(config) ->
          {:ok,
           Result.new(:unsupported, [], qualifiers: [%{code: :configuration_not_in_data_version}])}

        not SourceGate.cleared?(:oil_requirements) ->
          {:ok,
           Result.new(:identity_only, [],
             qualifiers: [
               %{code: :source_not_cleared_for_web_serving, fact_domain: :oil_requirements}
             ]
           )}

        true ->
          requirements = Service.requirements(s)

          {status, qualifiers} =
            Status.derive(config, %{schedules: [], requirements: requirements, claims: []})

          status = if status == :schedule_supported, do: :identity_only, else: status

          {:ok,
           Result.new(status, requirements,
             qualifiers: qualifiers,
             provenance: Provenance.sources(Enum.map(requirements, & &1.source_id))
           )}
      end
    end)
  end

  def get_lubricant_requirements(_), do: {:error, :invalid_selector}

  @doc """
  RECOMMENDATION path (INV-16-guarded): requires a resolved requirement id.
  With zero oil_requirements rows this is always identity_only/empty — a
  product name in a list never implies compatibility.
  """
  @spec search_oils(Selector.t()) :: {:ok, Result.t()} | error
  def search_oils(%Selector{function: :search_oils} = sel) do
    call(:search_oils, sel, fn s ->
      cond do
        not SourceGate.cleared?(:oil_products) ->
          {:ok,
           Result.new(:identity_only, [],
             qualifiers: [
               %{code: :source_not_cleared_for_web_serving, fact_domain: :oil_products}
             ]
           )}

        Products.requirement_exists?(s.requirement_id) ->
          # Requirement resolution + claim intersection lands with M03 data; the
          # branch is unreachable in build 1 and returns honestly empty.
          {:ok,
           Result.new(:identity_only, [], qualifiers: [%{code: :no_licensed_requirement_match}])}

        true ->
          {:ok,
           Result.new(:unsupported, [], qualifiers: [%{code: :requirement_not_in_data_version}])}
      end
    end)
  end

  def search_oils(_), do: {:error, :invalid_selector}

  @doc """
  Our own oil model's grades, split into the ones typical for this engine
  class and the rest. Not a manufacturer specification and not a product
  list — see `DigitalOilSticker.Catalog.OilModel`.
  """
  @spec list_oil_grades(Selector.t()) :: {:ok, Result.t()} | error
  def list_oil_grades(%Selector{function: :list_oil_grades} = sel) do
    call(:list_oil_grades, sel, fn s ->
      {suggested, others} = OilModel.grade_choices(s.engine_class_code)

      {:ok,
       Result.new(:our_model, %{suggested: suggested, others: others},
         total_known?: true,
         total: length(suggested) + length(others),
         qualifiers: [our_model_qualifier()]
       )}
    end)
  end

  def list_oil_grades(_), do: {:error, :invalid_selector}

  @spec list_oil_base_stocks(Selector.t()) :: {:ok, Result.t()} | error
  def list_oil_base_stocks(%Selector{function: :list_oil_base_stocks} = sel) do
    call(:list_oil_base_stocks, sel, fn _s ->
      stocks = OilModel.base_stocks()

      {:ok,
       Result.new(:our_model, stocks,
         total_known?: true,
         total: length(stocks),
         qualifiers: [our_model_qualifier()]
       )}
    end)
  end

  def list_oil_base_stocks(_), do: {:error, :invalid_selector}

  @doc """
  The interval OUR model gives for (engine class, base stock, service
  condition). Never a manufacturer schedule: when one exists for the vehicle
  it outranks this, and whichever is shorter wins.

  A combination we hold no rule for resolves to the lowest published interval
  for that base stock (`basis: :fallback_lowest_published`) rather than an
  extrapolation.
  """
  @spec get_oil_interval(Selector.t()) :: {:ok, Result.t()} | error
  def get_oil_interval(%Selector{function: :get_oil_interval} = sel) do
    call(:get_oil_interval, sel, fn s ->
      condition = s.service_condition || "normal"

      case OilModel.interval(s.engine_class_code, s.base_stock_code, condition) do
        {:ok, interval} ->
          qualifiers =
            [our_model_qualifier()] ++
              if interval.basis == :fallback_lowest_published,
                do: [%{code: :lowest_published_interval_used}],
                else: []

          {:ok, Result.new(:our_model, interval, qualifiers: qualifiers)}

        :not_applicable ->
          {:ok, Result.new(:not_applicable, nil, qualifiers: [%{code: :no_engine_oil_service}])}

        {:error, :unknown_base_stock} ->
          {:ok, Result.new(:unsupported, nil, qualifiers: [%{code: :base_stock_not_in_model}])}
      end
    end)
  end

  def get_oil_interval(_), do: {:error, :invalid_selector}

  @spec list_compatible_filters(Selector.t()) :: {:ok, Result.t()} | error
  def list_compatible_filters(%Selector{function: :list_compatible_filters} = sel) do
    call(:list_compatible_filters, sel, fn s ->
      config = Identity.get_configuration(s.configuration_key)

      cond do
        is_nil(config) ->
          {:ok,
           Result.new(:unsupported, [], qualifiers: [%{code: :configuration_not_in_data_version}])}

        not SourceGate.cleared?(:filters) ->
          {:ok, Result.new(:identity_only, [], qualifiers: [%{code: :no_licensed_filter_source}])}

        true ->
          rows = Products.fitments_for_configuration(s.configuration_key)
          status = if rows == [], do: :identity_only, else: :full_product_supported
          {:ok, Result.new(status, rows)}
      end
    end)
  end

  def list_compatible_filters(_), do: {:error, :invalid_selector}

  @spec get_provenance(Selector.t()) :: {:ok, Result.t()} | error
  def get_provenance(%Selector{function: :get_provenance} = sel) do
    call(:get_provenance, sel, fn _s ->
      {:ok, Result.new(:identity_only, Provenance.all_sources())}
    end)
  end

  def get_provenance(_), do: {:error, :invalid_selector}

  # -- internals --------------------------------------------------------------

  defp call(function, %Selector{} = sel, fun) do
    Telemetry.span(function, fn ->
      Cache.fetch(function, sel, fn -> guarded(function, fn -> fun.(sel) end) end)
    end)
  end

  defp guarded(_function, fun) do
    fun.()
  rescue
    e in [DBConnection.ConnectionError, Exqlite.Error] ->
      :telemetry.execute([:dos, :catalog, :unavailable], %{count: 1}, %{kind: e.__struct__})
      {:error, :catalog_unavailable}
  end

  # Test-only seam. Exposes the private `guarded/2` rescue so failure-mode
  # tests can exercise it with a raising fn instead of starving the real
  # connection pool — the latter races with any async: true test that reads
  # CatalogRepo in the same suite run and produced a real flake. Same
  # coverage (a genuine raise crossing the rescue), zero concurrent-test
  # side effects. Do not call from production code.
  @doc false
  def __test_guarded__(fun) when is_function(fun, 0), do: guarded(:__test__, fun)

  defp config_status(%{support_status: "not_applicable"}), do: :not_applicable
  defp config_status(%{support_status: "unsupported"}), do: :unsupported
  defp config_status(%{support_status: "schedule_supported"}), do: :schedule_supported
  defp config_status(%{support_status: "full_product_supported"}), do: :full_product_supported
  defp config_status(_), do: :identity_only

  defp qualifiers_for_identity(_sel), do: []

  # Every oil-model result carries this so no caller can render an interval
  # without the sentence that says whose model it is.
  defp our_model_qualifier do
    %{
      code: :our_own_model,
      model_version: OilModel.model_version(),
      basis: OilModel.basis_statement()
    }
  end
end
