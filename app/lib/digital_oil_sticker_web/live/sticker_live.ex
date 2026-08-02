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
  alias DigitalOilSticker.{Due, StickerCode}
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
          class="mt-3 text-center text-sm text-base-content/70"
        >
          {@view.qualifier}
        </p>

        <.qr_symbol :if={@view.qr} code={@view.qr.code} payload={@view.qr.payload} />

        <div :if={@view.mode == :empty} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.empty_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
            {Copy.empty_body()}
          </p>
          <.link navigate={~p"/vehicle/select"} class="btn btn-primary mt-6">Set up a vehicle</.link>
        </div>

        <div :if={@view.mode == :data_missing} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.data_missing_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
            {Copy.data_missing_body()}
          </p>
          <.link navigate={~p"/settings/storage"} class="btn btn-primary mt-6">Import a file</.link>
        </div>

        <div :if={@view.mode == :hydration_refused} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.hydration_refused_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
            {Copy.hydration_refused_body(@cap_error)}
          </p>
          <.link navigate={~p"/settings/storage"} class="btn btn-primary mt-6">Export a file</.link>
        </div>

        <div :if={@view.mode == :storage_unavailable} class="py-10 text-center">
          <h1 class="text-2xl font-bold">{Copy.storage_unavailable_heading()}</h1>
          <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
            {Copy.storage_unavailable_body()}
          </p>
          <.link navigate={~p"/vehicle/select"} class="btn mt-6">Look up a vehicle</.link>
        </div>

        <div :if={@view.mode == :sticker} class="mt-8 flex justify-center gap-3">
          <.link navigate={~p"/service/new"} class="btn btn-primary">Log an oil change</.link>
          <.link navigate={~p"/history"} class="btn btn-ghost">History</.link>
        </div>

        <p :if={@view.mode == :sticker} class="mt-6 text-center text-xs text-base-content/80">
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
      due = Due.compute(vehicle, last)

      %{
        @blank
        | mode: :sticker,
          date: due.date_text,
          mileage: due.mileage_text,
          grade: grade_of(last),
          changed: due.changed_on && Calendar.strftime(due.changed_on, "%b %d, %Y"),
          qualifier: qualifier_for(last, due),
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
      changed_on: Due.performed_date(last),
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

  # The numbers come from DigitalOilSticker.Due; saying WHOSE interval produced
  # them is a sourcing claim (INV-20/21) and stays here, with the copy catalog.
  defp qualifier_for(nil, _due), do: "No oil change recorded yet."
  defp qualifier_for(_event, %{resolved: :not_applicable}), do: Copy.not_applicable_ev()
  defp qualifier_for(_event, %{resolved: resolved}), do: qualifier(resolved)

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
end
