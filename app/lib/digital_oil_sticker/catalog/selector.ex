defmodule DigitalOilSticker.Catalog.Selector do
  @moduledoc """
  A validated catalog selector. Structurally cannot hold free text: its field
  list is exactly the closed vocabulary. Validation REJECTS unknown keys and
  wrong types — it never strips, never coerces, never substitutes defaults
  (beyond the declared page_size default), and never echoes offending input.
  """
  alias DigitalOilSticker.Catalog.{Vocabulary, Metadata}

  @enforce_keys [:function]
  defstruct [
    :function,
    :year,
    :make_id,
    :model_id,
    :configuration_key,
    :requirement_id,
    :oil_brand_id,
    :oil_product_id,
    :filter_product_id,
    :condition,
    :entity_type,
    :entity_key,
    :cursor,
    page_size: 50
  ]

  @type t :: %__MODULE__{}

  @id_re ~r/^[a-z0-9-]{1,64}$/

  @spec validate(atom(), map()) :: {:ok, t()} | {:error, :invalid_selector}
  def validate(function, params) when is_map(params) do
    with %{required: required, optional: optional} <- Map.get(Vocabulary.function_specs(), function),
         {:ok, atomized} <- atomize_keys(params),
         :ok <- reject_unknown(atomized, required ++ optional),
         :ok <- require_all(atomized, required),
         {:ok, fields} <- check_types(atomized) do
      {:ok, struct!(__MODULE__, Map.put(fields, :function, function))}
    else
      _ -> {:error, :invalid_selector}
    end
  end

  def validate(_function, _params), do: {:error, :invalid_selector}

  defp atomize_keys(params) do
    Enum.reduce_while(params, {:ok, %{}}, fn
      {k, v}, {:ok, acc} when is_binary(k) ->
        case Vocabulary.key_atom(k) do
          {:ok, atom} -> {:cont, {:ok, Map.put(acc, atom, v)}}
          :error -> {:halt, :error}
        end

      _, _ ->
        {:halt, :error}
    end)
  end

  defp reject_unknown(atomized, allowed) do
    if Map.keys(atomized) -- allowed == [], do: :ok, else: :error
  end

  defp require_all(atomized, required) do
    if required -- Map.keys(atomized) == [], do: :ok, else: :error
  end

  defp check_types(atomized) do
    Enum.reduce_while(atomized, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      case check_type(Map.fetch!(Vocabulary.field_specs(), k), v) do
        {:ok, cast} -> {:cont, {:ok, Map.put(acc, k, cast)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp check_type({:integer, :window_years}, v) when is_integer(v) do
    {first, last} = Metadata.window_years()
    if v >= first and v <= last, do: {:ok, v}, else: :error
  end

  defp check_type({:integer, %Range{} = range}, v) when is_integer(v) do
    if v in range, do: {:ok, v}, else: :error
  end

  defp check_type({:catalog_id, _entity}, v) when is_binary(v) do
    if Regex.match?(@id_re, v), do: {:ok, v}, else: :error
  end

  defp check_type({:enum, values}, v) when is_binary(v) do
    # Fixed small enums: match against precomputed strings, never String.to_atom.
    case Enum.find(values, fn a -> Atom.to_string(a) == v end) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end

  defp check_type({:cursor}, v) when is_binary(v) and byte_size(v) <= 512, do: {:ok, v}
  defp check_type(_spec, _v), do: :error
end
