defmodule DigitalOilStickerWeb.CatalogEvents do
  @moduledoc """
  The web edge for catalog queries: maps the fixed `catalog:*` LiveView event
  names to validated selectors via the compiled allowlist, spends the
  socket's tier-1 rate-limit bucket, and dispatches to the facade. Lives
  OUTSIDE the Catalog namespace so FR-18 (no Phoenix references under
  Catalog) holds.
  """
  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{RateLimit, Selector, Vocabulary}

  @event_functions %{
    "catalog:select_year" => :list_makes,
    "catalog:select_make" => :list_models,
    "catalog:select_model" => :list_configurations,
    "catalog:select_configuration" => :get_configuration,
    "catalog:resolve_requirements" => :get_lubricant_requirements,
    "catalog:resolve_products" => :search_oils,
    "catalog:resolve_filters" => :list_compatible_filters,
    "catalog:list_oil_grades" => :list_oil_grades,
    "catalog:select_base_stock" => :get_oil_interval,
    "catalog:select_service_condition" => :get_oil_interval
  }

  @doc """
  Validate an event payload against the event's key allowlist and the closed
  vocabulary, then run the mapped facade function. `bucket` is the socket's
  own token bucket; the caller stores the returned bucket back in assigns.
  """
  @spec handle(binary(), map(), RateLimit.t(), integer()) ::
          {:ok, term(), RateLimit.t()} | {:error, atom(), RateLimit.t()}
  def handle(event, params, %RateLimit{} = bucket, now_ms \\ System.monotonic_time(:millisecond)) do
    with {:allow, allowed_keys} <- fetch_allowlist(event),
         :ok <- reject_extra_keys(params, allowed_keys),
         {:ok, bucket2} <- RateLimit.take(bucket, 1, now_ms),
         function <- Map.fetch!(@event_functions, event),
         {:ok, selector} <- Selector.validate(function, params) do
      case apply(Catalog, function, [selector]) do
        {:ok, result} -> {:ok, result, bucket2}
        {:error, kind} -> {:error, kind, bucket2}
      end
    else
      {:error, :rate_limited} -> {:error, :rate_limited, bucket}
      _ -> {:error, :invalid_selector, bucket}
    end
  end

  defp fetch_allowlist(event) do
    case Map.fetch(Vocabulary.event_allowlist(), event) do
      {:ok, keys} -> {:allow, keys}
      :error -> :unknown_event
    end
  end

  defp reject_extra_keys(params, allowed) do
    if Enum.all?(Map.keys(params), &(&1 in allowed)), do: :ok, else: :error
  end

  def event_functions, do: @event_functions
end
