defmodule DigitalOilSticker.Due do
  @moduledoc """
  When the next oil change is due, from the last one plus the resolved interval.

  Extracted so there is exactly one answer. The sticker shows this date and the
  calendar reminder alarms on it; two implementations would eventually disagree,
  and the failure would be a reminder that arrives on a different day than the
  number the user is looking at — with nothing to indicate which is wrong.

  ## The basis is the odometer AT the change, not the current one

  Due mileage is `odometer when the oil went in + the interval`. Re-basing on a
  later reading would push the target away every time the car was driven: at
  62,500 with an 8,000 mile interval it reads 70,500, and it must still read
  70,500 at 68,000. A target computed from the current odometer is never
  reached.

  Carries no user-facing wording. Which interval produced these numbers is a
  claim about sourcing (INV-20/21) and belongs to the copy catalog in the web
  layer; this module reports the basis and lets that layer say it.
  """

  alias DigitalOilSticker.Catalog.OilModel
  alias DigitalOilSticker.{IntervalPolicy, Units}

  @metres_per_mile 1609.344

  @type t :: %{
          due_on: Date.t() | nil,
          due_odometer_m: non_neg_integer() | nil,
          unit: String.t(),
          date_text: String.t() | nil,
          mileage_text: String.t() | nil,
          resolved: map() | :not_applicable | nil,
          changed_on: Date.t() | nil
        }

  @empty %{
    due_on: nil,
    due_odometer_m: nil,
    unit: "mi",
    date_text: nil,
    mileage_text: nil,
    resolved: nil,
    changed_on: nil
  }

  @doc """
  Computes the due position for a vehicle from its most recent oil change.

  With no change recorded there is nothing to count from, so everything is
  `nil` — a due date measured from nothing would be a number the user could
  act on and we could not defend.
  """
  @spec compute(map() | nil, map() | nil) :: t()
  def compute(nil, _event), do: @empty
  def compute(_vehicle, nil), do: @empty

  def compute(vehicle, event) do
    unit = unit_of(event)
    changed_on = performed_date(event)

    case IntervalPolicy.for_vehicle(vehicle["maintenance_plan"] || %{}, model_interval(vehicle, event)) do
      :not_applicable ->
        %{@empty | unit: unit, resolved: :not_applicable, changed_on: changed_on}

      resolved ->
        due_on = due_date(changed_on, resolved.months)
        due_m = due_odometer(event, resolved.miles)

        %{
          due_on: due_on,
          due_odometer_m: due_m,
          unit: unit,
          date_text: due_on && Calendar.strftime(due_on, "%b %d, %Y"),
          mileage_text: due_m && format_mileage(due_m, unit),
          resolved: resolved,
          changed_on: changed_on
        }
    end
  end

  @doc "The date an oil change was performed, or nil if it cannot be read."
  @spec performed_date(map() | nil) :: Date.t() | nil
  def performed_date(nil), do: nil

  def performed_date(event) do
    case Date.from_iso8601(String.slice(event["performed_at"] || "", 0, 10)) do
      {:ok, date} -> date
      _ -> nil
    end
  end

  # -- internals ---------------------------------------------------------------

  # Our model needs to know what went in last time; without a base stock we
  # cannot pick a rule, and guessing one would be inventing the input.
  defp model_interval(vehicle, event) do
    case event["oil_base_stock"] do
      stock when is_binary(stock) ->
        OilModel.interval(vehicle["engine_class_code"], stock, service_condition(vehicle))

      _ ->
        nil
    end
  end

  defp service_condition(vehicle) do
    case get_in(vehicle, ["maintenance_plan", "service_condition"]) do
      "severe" -> "severe"
      _ -> "normal"
    end
  end

  defp due_date(nil, _months), do: nil
  defp due_date(_changed_on, months) when not is_integer(months), do: nil
  defp due_date(changed_on, months), do: shift_months(changed_on, months)

  defp due_odometer(event, miles) when is_integer(miles) do
    case event["odometer_m"] do
      m when is_integer(m) -> m + round(miles * @metres_per_mile)
      _ -> nil
    end
  end

  defp due_odometer(_event, _miles), do: nil

  defp format_mileage(metres, unit) do
    "#{format_int(round(Units.from_metres(metres, unit_atom(unit))))} #{unit}"
  end

  defp unit_of(event), do: if(event["input_unit"] == "km", do: "km", else: "mi")

  # Matched rather than converted with String.to_existing_atom/1: that atom only
  # "already exists" once Units happens to have been loaded, which made this
  # crash or not depending on module load order.
  defp unit_atom("km"), do: :km
  defp unit_atom(_), do: :mi

  defp shift_months(date, months) do
    total = date.year * 12 + (date.month - 1) + months
    year = div(total, 12)
    month = rem(total, 12) + 1
    day = min(date.day, :calendar.last_day_of_the_month(year, month))
    Date.new!(year, month, day)
  end

  defp format_int(n) when n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_int(n), do: Integer.to_string(n)
end
