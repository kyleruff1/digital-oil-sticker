defmodule DigitalOilStickerWeb.StickerLive do
  @moduledoc """
  The front page: permanently the last-configured vehicle's sticker.
  DATE = estimated due date, MILEAGE = due odometer, GRADE = the oil grade
  recorded at the last change. All due values derive ONLY from the user's
  own interval ("Your interval") applied to the last logged change — never a
  manufacturer claim (no licensed schedule data exists; INV-20/21).

  Pre-hydration renders the sticker frame with skeleton viewports and zero
  empty-garage words (INV-24.3). More detail lives behind the menu.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  import DigitalOilStickerWeb.Components.Sticker
  alias DigitalOilSticker.Units
  alias DigitalOilStickerWeb.Copy

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Digital Oil Sticker")}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :view, derive_view(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <.sticker
          :if={@view.mode in [:skeleton, :sticker]}
          skeleton={@view.mode == :skeleton}
          date_value={@view.date}
          mileage_value={@view.mileage}
          grade_value={@view.grade}
        />

        <p :if={@view.mode == :sticker and @view.qualifier} class="mt-3 text-center text-sm text-zinc-500">
          {@view.qualifier}
        </p>

        <div :if={@view.mode == :empty} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.empty_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">{Copy.empty_body()}</p>
          <.link navigate={~p"/vehicle/select"} class="btn btn-primary mt-6">Set up a vehicle</.link>
        </div>

        <div :if={@view.mode == :data_missing} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.data_missing_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">{Copy.data_missing_body()}</p>
          <.link navigate={~p"/settings/storage"} class="btn btn-primary mt-6">Import a file</.link>
        </div>

        <div :if={@view.mode == :storage_unavailable} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.storage_unavailable_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">
            {Copy.storage_unavailable_body()}
          </p>
          <.link navigate={~p"/vehicle/select"} class="btn mt-6">Look up a vehicle</.link>
        </div>

        <div :if={@view.mode == :sticker} class="mt-8 flex justify-center gap-3">
          <.link navigate={~p"/service/new"} class="btn btn-primary">Log an oil change</.link>
          <.link navigate={~p"/history"} class="btn btn-ghost">History</.link>
        </div>

        <p :if={@view.mode == :sticker} class="mt-6 text-center text-xs text-zinc-400">
          {Copy.does_not_notify()}
        </p>
      </div>
    </Layouts.app>
    """
  end

  # Pure view derivation from the hydration state + garage.
  defp derive_view(assigns) do
    case assigns.local_state do
      :hydrating ->
        %{mode: :skeleton, date: nil, mileage: nil, grade: nil, qualifier: nil}

      :empty ->
        %{mode: :empty, date: nil, mileage: nil, grade: nil, qualifier: nil}

      :data_missing ->
        %{mode: :data_missing, date: nil, mileage: nil, grade: nil, qualifier: nil}

      :storage_unavailable ->
        %{mode: :storage_unavailable, date: nil, mileage: nil, grade: nil, qualifier: nil}

      :loaded ->
        sticker_view(assigns.garage)
    end
  end

  defp sticker_view(garage) do
    vehicle = active_vehicle(garage)

    if vehicle == nil do
      %{mode: :empty, date: nil, mileage: nil, grade: nil, qualifier: nil}
    else
      last = last_event(garage, vehicle["vehicle_id"])
      plan = vehicle["maintenance_plan"] || %{}
      due = due_values(last, plan)

      %{
        mode: :sticker,
        date: due.date,
        mileage: due.mileage,
        grade: grade_of(last),
        qualifier: due.qualifier
      }
    end
  end

  defp active_vehicle(garage) do
    garage.vehicles
    |> Enum.reject(&(&1["archived"] == true))
    |> List.first()
  end

  defp last_event(garage, vehicle_id) do
    garage.events
    |> Enum.filter(&(&1["vehicle_id"] == vehicle_id))
    |> Enum.sort_by(&{&1["performed_at"], &1["event_id"]}, :desc)
    |> List.first()
  end

  # DATE/MILEAGE: last change + "Your interval" (user-entered only — the only
  # honest basis while no licensed schedule exists).
  defp due_values(nil, _plan), do: %{date: nil, mileage: nil, qualifier: "No oil change recorded yet."}

  defp due_values(event, plan) do
    months = plan["interval_months"]
    miles = plan["interval_miles"]
    unit = event["input_unit"] || "mi"

    date =
      with m when is_integer(m) <- months,
           {:ok, performed} <- Date.from_iso8601(String.slice(event["performed_at"] || "", 0, 10)) do
        performed |> shift_months(m) |> Calendar.strftime("%b %d, %Y")
      else
        _ -> nil
      end

    mileage =
      with mi when is_integer(mi) <- miles,
           m when is_integer(m) <- event["odometer_m"] do
        due_m = m + round(mi * 1609.344)
        "#{format_int(round(Units.from_metres(due_m, String.to_existing_atom(unit))))} #{unit}"
      else
        _ -> nil
      end

    qualifier =
      cond do
        date || mileage -> "#{Copy.estimated_due_date()} — based on #{Copy.your_interval()}, not manufacturer guidance."
        true -> "Set #{Copy.your_interval()} on the vehicle page to see a due estimate."
      end

    %{date: date, mileage: mileage, qualifier: qualifier}
  end

  defp grade_of(nil), do: nil
  defp grade_of(event), do: event["oil_viscosity"]

  defp shift_months(date, months) do
    total = date.year * 12 + (date.month - 1) + months
    year = div(total, 12)
    month = rem(total, 12) + 1
    day = min(date.day, :calendar.last_day_of_the_month(year, month))
    Date.new!(year, month, day)
  end

  defp format_int(n) when n >= 1000 do
    n |> Integer.to_string() |> String.reverse() |> String.replace(~r/(\d{3})(?=\d)/, "\\1,") |> String.reverse()
  end

  defp format_int(n), do: Integer.to_string(n)
end
