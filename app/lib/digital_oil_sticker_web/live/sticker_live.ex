defmodule DigitalOilStickerWeb.StickerLive do
  @moduledoc """
  The front page: permanently the last-configured vehicle's sticker.
  DATE = estimated due date, MILEAGE = due odometer, GRADE = the oil grade
  recorded at the last change.

  Due values come from `DigitalOilSticker.IntervalPolicy`: the user's own
  interval, our own oil model, or whichever of the two is shorter. Neither is
  a manufacturer claim, and the line under the sticker always says which one
  produced the numbers (INV-20/21).

  Pre-hydration renders the sticker frame with skeleton viewports and zero
  empty-garage words (INV-24.3). More detail lives behind the menu.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  import DigitalOilStickerWeb.Components.Sticker
  import DigitalOilStickerWeb.Components.StickerQr
  alias DigitalOilSticker.Catalog.OilModel
  alias DigitalOilSticker.{IntervalPolicy, StickerCode, Units}
  alias DigitalOilStickerWeb.{Copy, Hosts}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Digital Oil Sticker")}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :view, derive_view(assigns))

    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only}>
      <div class="mx-auto max-w-2xl">
        <.sticker
          :if={@view.mode in [:skeleton, :sticker]}
          skeleton={@view.mode == :skeleton}
          date_value={@view.date}
          mileage_value={@view.mileage}
          grade_value={@view.grade}
          changed_value={@view.changed}
        />

        <p
          :if={@view.mode == :sticker and @view.qualifier}
          class="mt-3 text-center text-sm text-zinc-500"
        >
          {@view.qualifier}
        </p>

        <.qr_symbol :if={@view.qr} code={@view.qr.code} payload={@view.qr.payload} />

        <div :if={@view.mode == :empty} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.empty_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">
            {Copy.empty_body()}
          </p>
          <.link navigate={~p"/vehicle/select"} class="btn btn-primary mt-6">Set up a vehicle</.link>
        </div>

        <div :if={@view.mode == :data_missing} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.data_missing_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">
            {Copy.data_missing_body()}
          </p>
          <.link navigate={~p"/settings/storage"} class="btn btn-primary mt-6">Import a file</.link>
        </div>

        <div :if={@view.mode == :hydration_refused} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.hydration_refused_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-zinc-600">
            {Copy.hydration_refused_body(@cap_error)}
          </p>
          <.link navigate={~p"/settings/storage"} class="btn btn-primary mt-6">Export a file</.link>
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

        <p :if={@view.mode == :sticker} class="mt-6 text-center text-xs text-zinc-600">
          {Copy.does_not_notify()}
        </p>
      </div>
    </Layouts.app>
    """
  end

  # Every mode carries the same keys, so a new field cannot be added to one
  # branch and forgotten in the other five — which is a crash in a template
  # that only the unlucky hydration state reaches.
  @blank %{
    mode: nil,
    date: nil,
    mileage: nil,
    grade: nil,
    changed: nil,
    qualifier: nil,
    qr: nil
  }

  # Pure view derivation from the hydration state + garage.
  defp derive_view(assigns) do
    case assigns.local_state do
      :hydrating -> %{@blank | mode: :skeleton}
      :empty -> %{@blank | mode: :empty}
      :data_missing -> %{@blank | mode: :data_missing}
      :hydration_refused -> %{@blank | mode: :hydration_refused}
      :storage_unavailable -> %{@blank | mode: :storage_unavailable}
      :loaded -> sticker_view(assigns.garage)
    end
  end

  defp sticker_view(garage) do
    vehicle = active_vehicle(garage)

    if vehicle == nil do
      %{@blank | mode: :empty}
    else
      last = last_event(garage, vehicle["vehicle_id"])
      plan = vehicle["maintenance_plan"] || %{}
      due = due_values(last, plan, vehicle)

      %{
        @blank
        | mode: :sticker,
          date: due.date,
          mileage: due.mileage,
          grade: grade_of(last),
          changed: changed_on(last),
          qualifier: due.qualifier,
          qr: qr_for(vehicle, last)
      }
    end
  end

  # The scannable form of what the sticker shows.
  #
  # Encoded here rather than in the browser because this is the canonical
  # implementation and there should be exactly one. The browser port exists for
  # the other direction: a scan arrives as `/s#CODE`, and a fragment is never
  # sent to the server, so only the client can read it back.
  #
  # `nil` when the values cannot be encoded — a vehicle with no catalog
  # configuration, most commonly. No symbol is better than one that resolves to
  # a vehicle the user did not pick.
  defp qr_for(vehicle, last) do
    sticker = %{
      configuration_key: vehicle["configuration_key"],
      changed_on: performed_date(last),
      odometer_m: last && last["odometer_m"],
      grade: last && last["oil_viscosity"],
      base_stock: last && last["oil_base_stock"]
    }

    case StickerCode.encode(sticker) do
      # The code goes in the FRAGMENT. A path would put the odometer, service
      # date, and grade it encodes into the request line and every access log
      # in between (INV-26); a fragment is never sent to the server at all.
      {:ok, code} -> %{code: code, payload: "https://#{Hosts.canonical()}/s##{code}"}
      {:error, _} -> nil
    end
  end

  defp performed_date(nil), do: nil

  defp performed_date(event) do
    case Date.from_iso8601(String.slice(event["performed_at"] || "", 0, 10)) do
      {:ok, date} -> date
      _ -> nil
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

  # DATE/MILEAGE come from the last change plus the resolved interval. With no
  # change recorded there is nothing to count from, so we say that rather than
  # showing a due date measured from nothing.
  defp due_values(nil, _plan, _vehicle),
    do: %{date: nil, mileage: nil, qualifier: "No oil change recorded yet."}

  defp due_values(event, plan, vehicle) do
    unit = event["input_unit"] || "mi"

    case IntervalPolicy.for_vehicle(plan, model_interval(vehicle, event)) do
      :not_applicable ->
        %{date: nil, mileage: nil, qualifier: Copy.not_applicable_ev()}

      resolved ->
        %{
          date: due_date(event, resolved.months),
          mileage: due_mileage(event, resolved.miles, unit),
          qualifier: qualifier(resolved)
        }
    end
  end

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

  defp due_date(event, months) do
    with m when is_integer(m) <- months,
         {:ok, performed} <- Date.from_iso8601(String.slice(event["performed_at"] || "", 0, 10)) do
      performed |> shift_months(m) |> Calendar.strftime("%b %d, %Y")
    else
      _ -> nil
    end
  end

  defp due_mileage(event, miles, unit) do
    with mi when is_integer(mi) <- miles,
         m when is_integer(m) <- event["odometer_m"] do
      due_m = m + round(mi * 1609.344)
      "#{format_int(round(Units.from_metres(due_m, unit_atom(unit))))} #{unit}"
    else
      _ -> nil
    end
  end

  # Matched rather than converted with String.to_existing_atom/1. The atom only
  # "already exists" once Units happens to have been loaded, so that call
  # crashed or not depending on module load order — the sticker rendering fine
  # in one process and raising in another with identical data.
  defp unit_atom("km"), do: :km
  defp unit_atom(_), do: :mi

  # The sticker never shows a number without saying whose interval it is.
  defp qualifier(%{basis: :none}),
    do: "Record what type of oil went in, or set #{Copy.your_interval()}, to see a due estimate."

  defp qualifier(%{basis: :user}),
    do:
      "#{Copy.estimated_due_date()} — based on #{Copy.your_interval()}, not manufacturer guidance."

  defp qualifier(%{basis: :our_model}),
    do: "#{Copy.estimated_due_date()} — #{Copy.our_model_label()}, not manufacturer guidance."

  defp qualifier(%{basis: :manufacturer}),
    do: "#{Copy.estimated_due_date()} — from your vehicle maker's own schedule."

  defp qualifier(%{miles_basis: miles_basis, months_basis: months_basis}),
    do:
      "#{Copy.estimated_due_date()} — mileage from #{basis_name(miles_basis)}, " <>
        "date from #{basis_name(months_basis)}. Whichever comes first."

  defp basis_name(:user), do: Copy.your_interval()
  defp basis_name(:our_model), do: Copy.our_model_label()
  defp basis_name(:manufacturer), do: "your vehicle maker"
  defp basis_name(:none), do: "no source"

  defp grade_of(nil), do: nil
  defp grade_of(event), do: event["oil_viscosity"]

  # The date the oil was actually changed. Unlike DATE and MILEAGE above it,
  # this is a record of something the user did, not an estimate we derived —
  # so it needs no qualifier and carries no basis.
  defp changed_on(nil), do: nil

  defp changed_on(event) do
    case Date.from_iso8601(String.slice(event["performed_at"] || "", 0, 10)) do
      {:ok, date} -> Calendar.strftime(date, "%b %d, %Y")
      _ -> nil
    end
  end

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
