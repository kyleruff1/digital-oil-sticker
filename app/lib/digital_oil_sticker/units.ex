defmodule DigitalOilSticker.Units do
  @moduledoc """
  Distance unit conversion at the boundary (DATA_DICTIONARY unit rules,
  DOS-M09-001 FR-4).

  Mileage is persisted in one integer base unit — metres — with conversion
  only at the boundary, so switching between miles and kilometres never
  loses precision. 1 mi = 1,609.344 m exactly; 1 km = 1,000 m. Conversions
  to metres round half-up to the nearest metre.

  Values above 1,600,000 km (1.6e9 m) are rejected as implausible.
  """

  @metres_per_mile 1609.344
  # 1 mi = 1_609_344 / 1_000 m exactly (integer arithmetic path)
  @mile_numerator 1_609_344
  @mile_denominator 1_000
  @metres_per_km 1000

  # 1_600_000 km
  @implausible_ceiling_m 1_600_000_000

  @type unit :: :mi | :km

  @doc "The implausibility ceiling in metres (1,600,000 km)."
  @spec implausible_ceiling_m() :: pos_integer()
  def implausible_ceiling_m, do: @implausible_ceiling_m

  @doc """
  Converts a distance in the given unit to whole metres.

  Accepts an integer, a float, or a binary (commas and spaces are stripped
  from binaries before parsing). Rounds half-up to the nearest metre.

  Returns `{:ok, metres}` or `{:error, :not_a_number | :negative |
  :implausible}`.
  """
  @spec to_metres(integer() | float() | binary(), unit()) ::
          {:ok, non_neg_integer()} | {:error, :not_a_number | :negative | :implausible}
  def to_metres(value, unit) when unit in [:mi, :km] do
    with {:ok, number} <- parse_number(value),
         :ok <- check_non_negative(number) do
      number
      |> convert(unit)
      |> check_plausible()
    end
  end

  @doc """
  Converts whole metres to the given unit as a float rounded to one decimal
  place.
  """
  @spec from_metres(non_neg_integer(), unit()) :: float()
  def from_metres(metres, :mi) when is_integer(metres) and metres >= 0 do
    Float.round(metres / @metres_per_mile, 1)
  end

  def from_metres(metres, :km) when is_integer(metres) and metres >= 0 do
    Float.round(metres / @metres_per_km, 1)
  end

  ## Conversion

  # Integer inputs convert through exact integer arithmetic; float inputs
  # round half-up via Kernel.round/1 (half away from zero, which is half-up
  # for the non-negative values that reach here).
  defp convert(value, :mi) when is_integer(value) do
    div(value * @mile_numerator + div(@mile_denominator, 2), @mile_denominator)
  end

  defp convert(value, :mi) when is_float(value), do: round(value * @metres_per_mile)

  defp convert(value, :km) when is_integer(value), do: value * @metres_per_km

  defp convert(value, :km) when is_float(value), do: round(value * @metres_per_km)

  defp check_plausible(metres) when metres > @implausible_ceiling_m, do: {:error, :implausible}
  defp check_plausible(metres), do: {:ok, metres}

  defp check_non_negative(number) when number < 0, do: {:error, :negative}
  defp check_non_negative(_number), do: :ok

  ## Parsing

  defp parse_number(value) when is_integer(value), do: {:ok, value}

  defp parse_number(value) when is_float(value) do
    # Reject NaN/infinity-ish inputs defensively; Elixir floats are finite,
    # so a plain float passes through.
    {:ok, value}
  end

  defp parse_number(value) when is_binary(value) do
    stripped = String.replace(value, [",", " "], "")

    case Integer.parse(stripped) do
      {int, ""} ->
        {:ok, int}

      _ ->
        case Float.parse(stripped) do
          {float, ""} -> {:ok, float}
          _ -> {:error, :not_a_number}
        end
    end
  end

  defp parse_number(_value), do: {:error, :not_a_number}
end
