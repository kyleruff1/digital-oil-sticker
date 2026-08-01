defmodule DigitalOilStickerWeb.OilChangeLive do
  @moduledoc """
  Record an oil change: three-dropdown date, odometer + unit, oil brand →
  family (catalog browsing path when available, always with the user-entered
  fallback), viscosity (GRADE), filter, notes. One idempotent staged
  mutation per submission; duplicates warn with an explicit proceed choice;
  the record renders as SAVING until the browser acknowledges the write.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  import DigitalOilStickerWeb.Components.{DateSelect, OdometerInput, ProductSelect}
  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.Selector
  alias DigitalOilSticker.{Clock, Units}
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @notes_limit 2_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Log an oil change")
     |> assign(:form_token, Ecto.UUID.generate())
     |> assign(:month, nil)
     |> assign(:day, nil)
     |> assign(:year, nil)
     |> assign(:odo_value, nil)
     |> assign(:odo_unit, "mi")
     |> assign(:oil_brand_id, nil)
     |> assign(:oil_family_id, nil)
     |> assign(:manual?, false)
     |> assign(:manual_brand, nil)
     |> assign(:manual_family, nil)
     |> assign(:viscosity, nil)
     |> assign(:filter_text, nil)
     |> assign(:notes, "")
     |> assign(:date_errors, [])
     |> assign(:date_announce, nil)
     |> assign(:odo_errors, [])
     |> assign(:duplicate_pending, nil)
     |> assign(:submitted_token, nil)
     |> load_oil_brands()
     |> assign(:oil_families, [])}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    date = params["service_date"] || %{}
    odo = params["odometer"] || %{}
    oil = params["oil"] || %{}

    {month, day, year} = {parse_int(date["month"]), parse_int(date["day"]), parse_int(date["year"])}

    {day, announce} =
      case validate_day_clear(month, day, year) do
        {:cleared, msg} -> {nil, msg}
        :ok -> {day, nil}
      end

    manual? = oil["brand_id"] == "__manual__" or socket.assigns.oil_brands == []
    brand_id = if manual?, do: nil, else: presence(oil["brand_id"])

    socket =
      socket
      |> assign(month: month, day: day, year: year, date_announce: announce, date_errors: [])
      |> assign(odo_value: presence(odo["value"]), odo_unit: odo["unit"] || socket.assigns.odo_unit, odo_errors: [])
      |> assign(manual?: manual?, manual_brand: presence(oil["manual_brand"]), manual_family: presence(oil["manual_family"]))
      |> assign(viscosity: presence(params["viscosity"]), filter_text: presence(params["filter"]))
      |> assign(notes: String.slice(params["notes"] || "", 0, @notes_limit))
      |> maybe_load_families(brand_id)
      |> assign(oil_family_id: if(manual?, do: nil, else: presence(oil["family_id"])))

    {:noreply, socket}
  end

  def handle_event("submit", params, socket) do
    cond do
      not Session.mutations_enabled?(socket) ->
        {:noreply, put_flash(socket, :error, Copy.session_only_banner())}

      socket.assigns.submitted_token == socket.assigns.form_token ->
        # Idempotency: double-tap of an already-staged form is a no-op.
        {:noreply, socket}

      true ->
        do_submit(socket, params)
    end
  end

  def handle_event("duplicate_proceed", _params, socket) do
    case socket.assigns.duplicate_pending do
      nil -> {:noreply, socket}
      event -> {:noreply, stage_event(assign(socket, :duplicate_pending, nil), event)}
    end
  end

  def handle_event("duplicate_cancel", _params, socket) do
    {:noreply, assign(socket, :duplicate_pending, nil)}
  end

  defp do_submit(socket, _params) do
    vehicle = active_vehicle(socket.assigns.garage)
    today = Clock.today()
    model_year = vehicle && vehicle["model_year"]

    with {:vehicle, %{} = vehicle} <- {:vehicle, vehicle},
         {:date, {:ok, date}} <-
           {:date, validate(socket.assigns.month, socket.assigns.day, socket.assigns.year, model_year, today)},
         {:odo, {:ok, metres}} <-
           {:odo, Units.to_metres(socket.assigns.odo_value || "", unit_atom(socket.assigns.odo_unit))} do
      event = build_event(socket, vehicle, date, metres)

      case find_duplicate(socket.assigns.garage, event) do
        nil -> {:noreply, stage_event(socket, event)}
        _dup -> {:noreply, assign(socket, :duplicate_pending, event)}
      end
    else
      {:vehicle, _} ->
        {:noreply, put_flash(socket, :error, "Set up a vehicle first.")}

      {:date, {:incomplete, msg}} ->
        {:noreply, assign(socket, :date_errors, [msg])}

      {:date, {:cleared_day, msg}} ->
        {:noreply, assign(socket, day: nil, date_announce: msg)}

      {:date, {:error, msgs}} ->
        {:noreply, assign(socket, :date_errors, msgs)}

      {:odo, {:error, _}} ->
        {:noreply, assign(socket, :odo_errors, ["Enter a valid, non-negative odometer reading."])}
    end
  end

  defp build_event(socket, vehicle, date, metres) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    a = socket.assigns

    {brand_name, family_name, provenance} =
      if a.manual? or a.oil_brand_id == nil do
        {a.manual_brand, a.manual_family, "manual"}
      else
        brand = Enum.find(a.oil_brands, &(&1.id == a.oil_brand_id))
        family = Enum.find(a.oil_families, &(&1.id == a.oil_family_id))
        {brand && brand.display_name, family && family.product_family, "catalog"}
      end

    %{
      "event_id" => Ecto.UUID.generate(),
      "vehicle_id" => vehicle["vehicle_id"],
      "performed_at" => Date.to_iso8601(date),
      "odometer_m" => metres,
      "odometer_input_value" => a.odo_value,
      "input_unit" => a.odo_unit,
      "oil_brand" => brand_name,
      "oil_family" => family_name,
      "oil_viscosity" => a.viscosity,
      "filter_text" => a.filter_text,
      "notes" => a.notes,
      "provenance_mode" => provenance,
      "created_at" => now,
      "updated_at" => now
    }
  end

  defp stage_event(socket, event) do
    reading = %{
      "reading_id" => Ecto.UUID.generate(),
      "vehicle_id" => event["vehicle_id"],
      "observed_at" => event["performed_at"],
      "odometer_m" => event["odometer_m"],
      "input_unit" => event["input_unit"],
      "source" => "service_event",
      "source_ref" => event["event_id"],
      "valid" => true
    }

    {socket, _mutation_id} =
      Session.stage_mutation(
        socket,
        [%{"store" => "events", "record" => event}, %{"store" => "readings", "record" => reading}],
        []
      )

    socket
    |> assign(:submitted_token, socket.assigns.form_token)
    |> put_flash(:info, Copy.saving())
    |> push_navigate(to: ~p"/")
  end

  defp find_duplicate(garage, event) do
    with {:ok, date} <- Date.from_iso8601(event["performed_at"]) do
      Enum.find(garage.events, fn e ->
        e["vehicle_id"] == event["vehicle_id"] and
          match?({:ok, _}, Date.from_iso8601(e["performed_at"] || "")) and
          abs(Date.diff(date, Date.from_iso8601!(e["performed_at"]))) <= 1 and
          is_integer(e["odometer_m"]) and
          abs(e["odometer_m"] - event["odometer_m"]) <= round(50 * 1609.344)
      end)
    else
      _ -> nil
    end
  end

  defp active_vehicle(garage), do: garage.vehicles |> Enum.reject(&(&1["archived"] == true)) |> List.first()

  defp load_oil_brands(socket) do
    case Selector.validate(:list_oil_brands, %{"page_size" => 200}) do
      {:ok, sel} ->
        case Catalog.list_oil_brands(sel) do
          {:ok, %{status: :identity_only, data: brands}} -> assign(socket, :oil_brands, brands)
          _ -> assign(socket, :oil_brands, [])
        end

      _ ->
        assign(socket, :oil_brands, [])
    end
  end

  defp maybe_load_families(socket, nil), do: assign(socket, oil_brand_id: nil, oil_families: [])

  defp maybe_load_families(%{assigns: %{oil_brand_id: same}} = socket, same), do: socket

  defp maybe_load_families(socket, brand_id) do
    families =
      with {:ok, sel} <- Selector.validate(:list_oil_families, %{"oil_brand_id" => brand_id, "page_size" => 200}),
           {:ok, %{data: rows}} <- Catalog.list_oil_families(sel) do
        rows
      else
        _ -> []
      end

    assign(socket, oil_brand_id: brand_id, oil_families: families, oil_family_id: nil)
  end

  defp validate_day_clear(month, day, year) do
    if is_integer(month) and is_integer(day) and is_integer(year) and
         day > :calendar.last_day_of_the_month(year, month) do
      {:cleared, Copy.day_cleared(month_name(month), year, :calendar.last_day_of_the_month(year, month))}
    else
      :ok
    end
  end

  defp unit_atom("km"), do: :km
  defp unit_atom(_), do: :mi

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {i, ""} -> i
      _ -> nil
    end
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(s), do: s

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :notes_limit, @notes_limit)
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl">
        <h1 class="text-2xl font-bold">Log an oil change</h1>

        <form phx-change="form_change" phx-submit="submit" class="mt-6 space-y-5">
          <input type="hidden" name="form_token" value={@form_token} />

          <.date_select
            id="oil-date"
            legend="Oil changed date"
            month={@month}
            day={@day}
            year={@year}
            min_year={min_year(assigns)}
            max_year={Clock.today().year}
            errors={@date_errors}
            announce={@date_announce}
          />

          <.odometer_input id="oil-odometer" value={@odo_value} unit={@odo_unit} errors={@odo_errors} />

          <.product_select
            brands={@oil_brands}
            families={@oil_families}
            brand_id={@oil_brand_id}
            family_id={@oil_family_id}
            manual?={@manual?}
            manual_brand={@manual_brand}
            manual_family={@manual_family}
          />

          <div class="grid grid-cols-2 gap-2">
            <div>
              <label for="oil-viscosity" class="mb-1 block text-sm font-semibold">Grade (viscosity)</label>
              <input
                type="text"
                id="oil-viscosity"
                name="viscosity"
                value={@viscosity}
                placeholder="e.g. 5W-30"
                maxlength="20"
                class="w-full min-h-11 rounded border px-3 py-2"
              />
            </div>
            <div>
              <label for="oil-filter" class="mb-1 block text-sm font-semibold">Filter (optional)</label>
              <input
                type="text"
                id="oil-filter"
                name="filter"
                value={@filter_text}
                maxlength="80"
                class="w-full min-h-11 rounded border px-3 py-2"
              />
            </div>
          </div>

          <div>
            <label for="oil-notes" class="mb-1 block text-sm font-semibold">Notes (optional)</label>
            <textarea id="oil-notes" name="notes" rows="3" maxlength={to_string(@notes_limit)} class="w-full rounded border px-3 py-2">{@notes}</textarea>
            <p class="mt-1 text-xs text-zinc-500">{String.length(@notes)}/{@notes_limit} characters</p>
          </div>

          <div :if={@duplicate_pending} class="rounded border border-amber-400 p-3" role="alertdialog" aria-label="Possible duplicate">
            <p class="text-sm">
              {Copy.duplicate_warning(
                @duplicate_pending["performed_at"],
                @duplicate_pending["odometer_input_value"],
                @duplicate_pending["input_unit"]
              )}
            </p>
            <div class="mt-2 flex gap-2">
              <button type="button" phx-click="duplicate_proceed" class="btn btn-sm">Record it anyway</button>
              <button type="button" phx-click="duplicate_cancel" class="btn btn-ghost btn-sm">Cancel</button>
            </div>
          </div>

          <button type="submit" class="btn btn-primary w-full" phx-disable-with={Copy.saving()}>
            Save to this browser
          </button>
        </form>
      </div>
    </Layouts.app>
    """
  end

  defp min_year(assigns) do
    case active_vehicle(assigns.garage) do
      %{"model_year" => y} when is_integer(y) -> y
      _ -> Clock.today().year - 30
    end
  end

end
