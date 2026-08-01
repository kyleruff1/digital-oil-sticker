defmodule DigitalOilStickerWeb.Components.DateSelect do
  @moduledoc """
  The oil-changed date as THREE dropdowns (owner-locked): month / day / year
  in a fieldset with visible labels. Day options are computed server-side
  (correct Gregorian leap handling via :calendar); an invalid day after a
  month/year change is CLEARED and announced, never silently coerced.
  Future dates are rejected; pre-model-year dates warn and block save.
  """
  use Phoenix.Component
  alias DigitalOilStickerWeb.Copy

  @months ~w(January February March April May June July August September October November December)

  attr :id, :string, required: true
  attr :legend, :string, default: "Date of oil change"
  attr :month, :integer, default: nil
  attr :day, :integer, default: nil
  attr :year, :integer, default: nil
  attr :min_year, :integer, required: true
  attr :max_year, :integer, required: true
  attr :errors, :list, default: []
  attr :announce, :string, default: nil, doc: "e.g. the day-cleared announcement"

  def date_select(assigns) do
    assigns = assign(assigns, :day_options, day_options(assigns.month, assigns.year))

    ~H"""
    <fieldset id={@id} phx-hook="DateSelect" class="rounded border p-3">
      <legend class="px-1 text-sm font-semibold">{@legend}</legend>
      <div class="grid grid-cols-3 gap-2">
        <div>
          <label for={"#{@id}-month"} class="mb-1 block text-xs font-medium">Month</label>
          <select id={"#{@id}-month"} name="service_date[month]" class="w-full min-h-11 rounded border px-2 py-2" aria-describedby={"#{@id}-error"}>
            <option value="">Month</option>
            {Phoenix.HTML.Form.options_for_select(Enum.with_index(@months, 1) |> Enum.map(fn {m, i} -> {m, i} end), @month)}
          </select>
        </div>
        <div>
          <label for={"#{@id}-day"} class="mb-1 block text-xs font-medium">Day</label>
          <select id={"#{@id}-day"} name="service_date[day]" class="w-full min-h-11 rounded border px-2 py-2" aria-describedby={"#{@id}-error"}>
            <option value="">Day</option>
            {Phoenix.HTML.Form.options_for_select(1..@day_options, @day)}
          </select>
        </div>
        <div>
          <label for={"#{@id}-year"} class="mb-1 block text-xs font-medium">Year</label>
          <select id={"#{@id}-year"} name="service_date[year]" class="w-full min-h-11 rounded border px-2 py-2" aria-describedby={"#{@id}-error"}>
            <option value="">Year</option>
            {Phoenix.HTML.Form.options_for_select(Enum.to_list(@max_year..@min_year//-1), @year)}
          </select>
        </div>
      </div>
      <p :if={@errors != []} id={"#{@id}-error"} role="alert" class="mt-2 text-sm text-red-700">
        {Enum.join(@errors, " ")}
      </p>
      <p :if={@announce} role="status" aria-live="polite" class="mt-1 text-xs text-zinc-600">{@announce}</p>
    </fieldset>
    """
  end

  @doc "Day count: exact when month+year known; safe superset otherwise."
  def day_options(nil, _year), do: 31
  def day_options(month, nil) when month in [1, 3, 5, 7, 8, 10, 12], do: 31
  def day_options(2, nil), do: 29
  def day_options(month, nil) when month in [4, 6, 9, 11], do: 30
  def day_options(month, year), do: :calendar.last_day_of_the_month(year, month)

  @doc """
  Validate a {month, day, year} selection against today and the vehicle's
  model year. Returns {:ok, %Date{}} | {:incomplete, msg} | {:error, msgs} |
  {:cleared_day, announcement} when the chosen day no longer exists.
  """
  def validate(month, day, year, model_year, today) do
    cond do
      is_nil(month) or is_nil(day) or is_nil(year) ->
        {:incomplete, Copy.date_incomplete()}

      day > :calendar.last_day_of_the_month(year, month) ->
        {:cleared_day, Copy.day_cleared(Enum.at(@months, month - 1), year, :calendar.last_day_of_the_month(year, month))}

      true ->
        date = Date.new!(year, month, day)

        cond do
          Date.after?(date, today) -> {:error, [Copy.date_future()]}
          is_integer(model_year) and year < model_year -> {:error, [Copy.date_before_model_year()]}
          true -> {:ok, date}
        end
    end
  end

  def month_name(n) when n in 1..12, do: Enum.at(@months, n - 1)
end
