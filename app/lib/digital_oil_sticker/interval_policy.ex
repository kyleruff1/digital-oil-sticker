defmodule DigitalOilSticker.IntervalPolicy do
  @moduledoc """
  Decides which oil-change interval the app shows, and says where it came from.

  Three things can supply an interval:

    * a manufacturer schedule sourced for this exact configuration (we hold
      none yet — the clause is here so adding one changes data, not logic),
    * an interval the user set themselves,
    * our own model (`DigitalOilSticker.Catalog.OilModel`).

  The rule is the same one the claims policy states: **the shortest one wins**,
  and the answer always names its basis. Mileage and time are resolved
  independently, because a user may set a mileage interval and leave time to
  us; when the two dimensions end up on different bases the result is
  `:mixed` and the caller must show both.

  Nothing here ever lengthens an interval. If our model would allow more miles
  than the user asked for, the user's number stands.
  """

  @type basis :: :manufacturer | :user | :our_model | :none

  @type t :: %{
          miles: pos_integer() | nil,
          months: pos_integer() | nil,
          miles_basis: basis(),
          months_basis: basis(),
          basis: basis() | :mixed
        }

  @doc """
  `sources` is a keyword list of `{basis, %{miles: _, months: _}}` candidates.
  Absent or nil-valued candidates are ignored, so a caller with no model
  interval simply omits it.
  """
  @spec resolve(keyword()) :: t()
  def resolve(sources) do
    {miles, miles_basis} = shortest(sources, :miles)
    {months, months_basis} = shortest(sources, :months)

    %{
      miles: miles,
      months: months,
      miles_basis: miles_basis,
      months_basis: months_basis,
      basis: combine(miles_basis, months_basis)
    }
  end

  @doc """
  Convenience for the common call: the user's stored maintenance plan plus an
  `OilModel.interval/3` result. Passing `:not_applicable` (a BEV, say) yields
  no interval at all rather than falling back to the user's number, because
  there is no engine oil service to be due.
  """
  @spec for_vehicle(map() | nil, {:ok, map()} | :not_applicable | {:error, term()} | nil) ::
          t() | :not_applicable
  def for_vehicle(_plan, :not_applicable), do: :not_applicable

  def for_vehicle(plan, model_result) do
    plan = plan || %{}

    user =
      case {plan["interval_miles"], plan["interval_months"]} do
        {nil, nil} -> []
        {miles, months} -> [user: %{miles: miles, months: months}]
      end

    model =
      case model_result do
        {:ok, %{miles_recommended: miles, months_cap: months}} ->
          [our_model: %{miles: miles, months: months}]

        _ ->
          []
      end

    resolve(user ++ model)
  end

  # Manufacturer data outranks nothing by itself — it wins only by being
  # shorter — but it is listed first so an exact tie credits the source we can
  # actually cite rather than our own estimate.
  @precedence [:manufacturer, :user, :our_model]

  defp shortest(sources, dimension) do
    sources
    |> Enum.flat_map(fn {basis, values} ->
      case Map.get(values, dimension) do
        value when is_integer(value) and value > 0 -> [{value, basis}]
        _ -> []
      end
    end)
    |> Enum.min_by(fn {value, basis} -> {value, precedence_index(basis)} end, fn ->
      {nil, :none}
    end)
  end

  defp precedence_index(basis) do
    case Enum.find_index(@precedence, &(&1 == basis)) do
      nil -> length(@precedence)
      i -> i
    end
  end

  defp combine(same, same), do: same
  defp combine(:none, other), do: other
  defp combine(other, :none), do: other
  defp combine(_a, _b), do: :mixed
end
