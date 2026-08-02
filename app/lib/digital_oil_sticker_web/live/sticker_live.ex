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
  alias DigitalOilStickerWeb.LocalStore.Session

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Digital Oil Sticker")
     |> assign(:garage_open?, false)
     |> assign(:confirm_delete_vehicle, nil)}
  end

  @impl true
  def handle_event("toggle_garage", _params, socket) do
    {:noreply, update(socket, :garage_open?, &(not &1))}
  end

  def handle_event("switch_vehicle", %{"vehicle-id" => id}, socket) do
    cond do
      not Session.mutations_enabled?(socket) ->
        {:noreply, put_flash(socket, :error, Copy.session_only_banner())}

      # A quarantined prefs singleton means the stored record holds content
      # this release cannot read. Writing over it would destroy that content
      # — settings a newer release wrote, kept exportable by the validation
      # contract — so the switch is refused rather than made destructive.
      Session.prefs_quarantined?(socket) ->
        {:noreply, put_flash(socket, :error, Copy.prefs_unreadable())}

      true ->
        prefs =
          (socket.assigns.garage.prefs || %{})
          |> Map.put("active_vehicle_id", id)

        {socket, _mutation_id} =
          Session.stage_mutation(socket, [%{"store" => "prefs", "record" => prefs}], [])

        {:noreply, assign(socket, :garage_open?, false)}
    end
  end

  def handle_event("ask_delete_vehicle", %{"vehicle-id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete_vehicle, id)}
  end

  def handle_event("cancel_delete_vehicle", _params, socket) do
    {:noreply, assign(socket, :confirm_delete_vehicle, nil)}
  end

  def handle_event("confirm_delete_vehicle", _params, socket) do
    id = socket.assigns.confirm_delete_vehicle
    garage = socket.assigns.garage

    with true <- is_binary(id),
         true <- Session.mutations_enabled?(socket) do
      # The vehicle's dependent records go WITH it, in the same mutation.
      # Leaving them behind would strand orphans that the next hydration
      # quarantines — the deleted vehicle's oil changes surfacing forever as
      # "could not read some records".
      deletes =
        [%{"store" => "vehicles", "key" => id}] ++
          dependent_deletes(garage.events, "event_id", "events", id) ++
          dependent_deletes(garage.readings, "reading_id", "readings", id) ++
          dependent_deletes(garage.usage, "usage_id", "usage", id) ++
          dependent_deletes(garage.reminders, "reminder_id", "reminders", id)

      # If the deleted vehicle was the explicitly chosen one, the stored choice
      # is cleared in the same write rather than left dangling — unless prefs
      # sits in quarantine, where writing would destroy unreadable content. A
      # dangling id is harmless by design (active_vehicle falls back), so
      # skipping the cleanup costs nothing.
      upserts =
        case garage.prefs do
          %{"active_vehicle_id" => ^id} = prefs ->
            if Session.prefs_quarantined?(socket),
              do: [],
              else: [%{"store" => "prefs", "record" => Map.delete(prefs, "active_vehicle_id")}]

          _ ->
            []
        end

      {socket, _mutation_id} = Session.stage_mutation(socket, upserts, deletes)

      {:noreply, assign(socket, :confirm_delete_vehicle, nil)}
    else
      _ ->
        {:noreply,
         socket
         |> assign(:confirm_delete_vehicle, nil)
         |> put_flash(:error, Copy.session_only_banner())}
    end
  end

  defp dependent_deletes(records, id_key, store, vehicle_id) do
    records
    |> Enum.filter(&(&1["vehicle_id"] == vehicle_id))
    |> Enum.map(&%{"store" => store, "key" => &1[id_key]})
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :view, derive_view(assigns))

    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only}>
      <div class="mx-auto max-w-2xl">
        <%!-- Which vehicle this sticker is about, as a description rather than
             a labelled form: "2015 BMW 328i", not "Year: 2015 Make: BMW". The
             folder opens the rest of the garage. --%>
        <div :if={@view.vehicle} class="mb-3" data-test="vehicle-bar">
          <button
            type="button"
            phx-click="toggle_garage"
            aria-expanded={to_string(@garage_open?)}
            aria-controls="garage-panel"
            class="btn btn-ghost btn-sm gap-2 px-2 text-base font-semibold normal-case"
          >
            <.icon
              name={if @garage_open?, do: "hero-folder-open", else: "hero-folder"}
              class="size-5"
            />
            {vehicle_desc(@view.vehicle)}
          </button>

          <div
            :if={@garage_open?}
            id="garage-panel"
            class="mt-2 rounded border p-3"
            data-test="garage-panel"
          >
            <p class="text-xs font-semibold uppercase tracking-wide text-base-content/70">
              {Copy.other_vehicles()}
            </p>
            <ul class="mt-2 space-y-1">
              <li
                :for={vehicle <- @view.garage_vehicles}
                class="flex items-center justify-between gap-2"
              >
                <button
                  :if={vehicle["vehicle_id"] != @view.vehicle["vehicle_id"]}
                  type="button"
                  phx-click="switch_vehicle"
                  phx-value-vehicle-id={vehicle["vehicle_id"]}
                  class="btn btn-ghost btn-sm grow justify-start normal-case"
                  data-test="switch-vehicle"
                >
                  {vehicle_desc(vehicle)}
                </button>
                <span
                  :if={vehicle["vehicle_id"] == @view.vehicle["vehicle_id"]}
                  class="grow px-3 py-1 text-sm font-semibold"
                >
                  {vehicle_desc(vehicle)}
                  <span class="ml-1 text-xs font-normal text-base-content/70">(showing)</span>
                </span>
                <button
                  type="button"
                  phx-click="ask_delete_vehicle"
                  phx-value-vehicle-id={vehicle["vehicle_id"]}
                  class="btn btn-ghost btn-sm"
                  aria-label={"Remove #{vehicle_desc(vehicle)}"}
                  data-test="ask-delete-vehicle"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </li>
            </ul>
            <.link navigate={~p"/vehicle/select"} class="btn btn-ghost btn-sm mt-2 gap-1 normal-case">
              <.icon name="hero-plus" class="size-4" /> {Copy.add_vehicle()}
            </.link>
          </div>
        </div>

        <div
          :if={@confirm_delete_vehicle}
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="delete-vehicle-title"
          data-test="delete-vehicle-modal"
        >
          <div class="w-full max-w-sm rounded-lg bg-base-100 p-6 shadow-xl">
            <h2 id="delete-vehicle-title" class="text-lg font-bold">
              {Copy.delete_vehicle_heading()}
            </h2>
            <p class="mt-2 text-sm leading-relaxed">
              {Copy.delete_vehicle_body(
                vehicle_desc(find_vehicle(@garage, @confirm_delete_vehicle)),
                deletable_event_count(@garage, @confirm_delete_vehicle)
              )}
            </p>
            <div class="mt-5 flex justify-end gap-2">
              <button type="button" phx-click="cancel_delete_vehicle" class="btn btn-ghost">
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_delete_vehicle"
                class="btn btn-error"
                data-test="confirm-delete-vehicle"
              >
                Remove from this browser
              </button>
            </div>
          </div>
        </div>

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
    qr: nil,
    vehicle: nil,
    garage_vehicles: []
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
    vehicle = Session.active_vehicle(garage)

    if vehicle == nil do
      %{@blank | mode: :empty}
    else
      last = Session.last_oil_change(garage, vehicle["vehicle_id"])
      due = Due.compute(vehicle, last)

      %{
        @blank
        | mode: :sticker,
          date: due.date_text,
          mileage: due.mileage_text,
          grade: grade_of(last),
          changed: due.changed_on && Calendar.strftime(due.changed_on, "%b %d, %Y"),
          qualifier: qualifier_for(last, due),
          qr: qr_for(vehicle, last),
          vehicle: vehicle,
          garage_vehicles: Enum.reject(garage.vehicles, &(&1["archived"] == true))
      }
    end
  end

  # "2015 BMW 328i · LE", not a labelled form. The nickname wins when the user
  # gave one; a placeholder build ("2015 — Not specified") adds nothing to the
  # description and is dropped from it.
  defp vehicle_desc(nil), do: ""

  defp vehicle_desc(vehicle) do
    case vehicle["nickname"] do
      name when is_binary(name) and name != "" ->
        name

      _ ->
        snap = vehicle["display_snapshot"] || %{}
        build = snap["build"]

        head =
          [snap["year"], snap["make"], snap["model"]]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(" ")

        if is_binary(build) and build != "" and not String.contains?(build, Copy.not_specified()) do
          "#{head} · #{build}"
        else
          head
        end
    end
  end

  defp find_vehicle(garage, id),
    do: Enum.find(garage.vehicles, &(&1["vehicle_id"] == id))

  defp deletable_event_count(garage, id),
    do: Enum.count(garage.events, &(&1["vehicle_id"] == id))

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

  # The numbers come from DigitalOilSticker.Due; saying WHOSE interval produced
  # them is a sourcing claim (INV-20/21) and stays here, with the copy catalog.
  defp qualifier_for(nil, _due), do: "No oil change recorded yet."
  defp qualifier_for(_event, %{resolved: :not_applicable}), do: Copy.not_applicable_ev()

  # The oil type was answered "I don't know yet" at intake AND the floor is
  # what actually supplied the numbers. Both conditions, not just the first:
  # when the user's own shorter interval wins in IntervalPolicy, this sentence
  # would attribute their number to our model and promise that recording the
  # oil extends it — false on both counts, since shortest-wins keeps their
  # interval in force whatever oil is recorded (INV-20/21).
  defp qualifier_for(_event, %{oil_basis: :unknown_oil, resolved: %{basis: :our_model}}),
    do: "#{Copy.estimated_due_date()} — #{Copy.unknown_oil_qualifier()}"

  # The plan holds an APP-CHOSEN oil (never user-touched at intake). Attribute
  # honestly: the number is our estimate, ASSUMING that oil, not "based on
  # your answer." Same math the picker's recommendation showed; the label
  # keeps the assumption visible on every subsequent render.
  #
  # Two clauses: :our_model is the common case (pure model interval), and
  # the fallthrough catches :mixed — where the user set one dimension and the
  # model supplied the other from the assumed oil. Missing the :mixed head
  # dropped the "assuming" caveat entirely for any vehicle where the user had
  # set months but left miles blank.
  defp qualifier_for(
         _event,
         %{oil_basis: :planned_default, resolved: %{basis: :our_model, miles: mi, months: mo}}
       ),
       do: "#{Copy.estimated_due_date()} — #{ceiling_line(mi, mo)}. #{Copy.assumed_oil_note()}"

  defp qualifier_for(_event, %{oil_basis: :planned_default, resolved: resolved}),
    do: "#{qualifier(resolved)} #{Copy.assumed_oil_note()}"

  defp qualifier_for(_event, %{resolved: resolved}), do: qualifier(resolved)

  # The sticker never shows a number without saying whose interval it is.
  #
  # And it now shows the two ceilings explicitly. Otherwise a 10,000 mi / 12 mo
  # rule for a truck engine reads as "just added a year" on the DATE row, when
  # the truth is that the calendar cap governed because the mileage cap is far
  # away — two ceilings joined by OR, not a mechanical add.
  defp qualifier(%{basis: :none}),
    do: "Record what type of oil went in, or set #{Copy.your_interval()}, to see a due estimate."

  defp qualifier(%{basis: :user, miles: mi, months: mo}),
    do:
      "#{Copy.estimated_due_date()} — #{ceiling_line(mi, mo)}. Based on #{Copy.your_interval()}, not manufacturer guidance."

  defp qualifier(%{basis: :our_model, miles: mi, months: mo}),
    do:
      "#{Copy.estimated_due_date()} — #{ceiling_line(mi, mo)}. #{Copy.our_model_label()}, not manufacturer guidance."

  defp qualifier(%{basis: :manufacturer, miles: mi, months: mo}),
    do:
      "#{Copy.estimated_due_date()} — #{ceiling_line(mi, mo)}. From your vehicle maker's own schedule."

  defp qualifier(%{miles: mi, months: mo, miles_basis: miles_basis, months_basis: months_basis}),
    do:
      "#{Copy.estimated_due_date()} — #{ceiling_line(mi, mo)}. Mileage from #{basis_name(miles_basis)}, date from #{basis_name(months_basis)}."

  # Whichever ceiling is present, named in miles-then-months order joined by
  # "or". Both nil is unreachable — resolve/1 would return basis :none, which
  # the clause above catches — but the fallthrough is harmless.
  defp ceiling_line(mi, mo) when is_integer(mi) and is_integer(mo),
    do: "#{format_int(mi)} miles or #{mo} months, whichever comes first"

  defp ceiling_line(mi, nil) when is_integer(mi), do: "#{format_int(mi)} miles"
  defp ceiling_line(nil, mo) when is_integer(mo), do: "#{mo} months"
  defp ceiling_line(_, _), do: "no ceiling"

  defp format_int(n) when n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_int(n), do: Integer.to_string(n)

  defp basis_name(:user), do: Copy.your_interval()
  defp basis_name(:our_model), do: Copy.our_model_label()
  defp basis_name(:manufacturer), do: "your vehicle maker"
  defp basis_name(:none), do: "no source"

  defp grade_of(nil), do: nil
  defp grade_of(event), do: event["oil_viscosity"]
end
