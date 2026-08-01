defmodule DigitalOilSticker.Catalog.Status do
  @moduledoc """
  INV-11 status derivation as a pure function with a FIXED branch order:
  source gate → reference resolution → applicability → presence. NULL
  electrification is NOT a BEV (unknown stays unknown); a missing reference
  is `unsupported`, never a nearest match; empty schedule/requirement tables
  are `identity_only` with no interval anywhere in the term.
  """
  alias DigitalOilSticker.Catalog.SourceGate

  @type outcome :: %{schedules: list(), requirements: list(), claims: list()}

  @spec derive(map() | nil, outcome()) :: {atom(), [map()]}
  def derive(configuration, outcome \\ %{schedules: [], requirements: [], claims: []})

  def derive(nil, _outcome) do
    {:unsupported, [%{code: :configuration_not_in_data_version}]}
  end

  def derive(config, outcome) do
    cond do
      not SourceGate.cleared?(:maintenance_schedules) ->
        {:unsupported, [%{code: :source_not_cleared_for_web_serving, fact_domain: :maintenance_schedules}]}

      bev?(config) ->
        {:not_applicable, [%{code: :no_engine_oil_plan, basis: :electrification_bev}]}

      outcome.schedules == [] ->
        {:identity_only, [%{code: :no_licensed_schedule}]}

      outcome.requirements == [] ->
        {:schedule_supported, []}

      outcome.claims != [] ->
        {:full_product_supported, []}

      true ->
        {:schedule_supported, []}
    end
  end

  @doc "BEV iff a stored catalog column says so. NULL means unknown, never BEV."
  def bev?(%{electrification_level: "BEV"}), do: true
  def bev?(%{electrification_level: level}) when is_binary(level), do: String.upcase(level) == "BEV"
  def bev?(%{fuel_primary: "Electricity", fuel_secondary: nil}), do: true
  def bev?(_), do: false
end
