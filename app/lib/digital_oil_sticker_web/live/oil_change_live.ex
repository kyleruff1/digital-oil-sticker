defmodule DigitalOilStickerWeb.OilChangeLive do
  @moduledoc """
  Record an oil change: three-dropdown date, odometer + unit, the type of oil
  (base stock + viscosity grade from our own model), filter, notes. One
  idempotent staged mutation per submission; duplicates warn with an explicit
  proceed choice; the record renders as SAVING until the browser
  acknowledges the write.

  Brand is not asked for. Different brands sell the same chemistry, so the
  answer added redundancy without adding a fact worth storing — what changes
  the interval is the base stock and the grade.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  import DigitalOilStickerWeb.Components.{DateSelect, OdometerInput, OilTypeSelect}
  alias DigitalOilSticker.Catalog.OilModel
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
     |> assign(:base_stock, nil)
     |> assign(:grade, nil)
     |> assign(:show_all_grades?, false)
     |> assign(:manual_grade?, false)
     |> assign(:manual_grade, nil)
     |> assign(:filter_text, nil)
     |> assign(:notes, "")
     |> assign(:date_errors, [])
     |> assign(:date_announce, nil)
     |> assign(:odo_errors, [])
     |> assign(:duplicate_pending, nil)
     |> assign(:submitted_token, nil)
     |> assign(:base_stocks, OilModel.base_stocks())}
  end

  @impl true
  def handle_event("form_change", params, socket) do
    date = params["service_date"] || %{}
    odo = params["odometer"] || %{}
    oil = params["oil"] || %{}

    {month, day, year} =
      {parse_int(date["month"]), parse_int(date["day"]), parse_int(date["year"])}

    {day, announce} =
      case validate_day_clear(month, day, year) do
        {:cleared, msg} -> {nil, msg}
        :ok -> {day, nil}
      end

    {grade, show_all?, manual_grade?} = grade_choice(oil["grade"], socket.assigns)

    socket =
      socket
      |> assign(month: month, day: day, year: year, date_announce: announce, date_errors: [])
      |> assign(
        odo_value: presence(odo["value"]),
        odo_unit: odo["unit"] || socket.assigns.odo_unit,
        odo_errors: []
      )
      |> assign(base_stock: presence(oil["base_stock"]))
      |> assign(grade: grade, show_all_grades?: show_all?, manual_grade?: manual_grade?)
      |> assign(manual_grade: presence(oil["manual_grade"]))
      |> assign(filter_text: presence(params["filter"]))
      |> assign(notes: String.slice(params["notes"] || "", 0, @notes_limit))

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

    with {:vehicle, vehicle} when is_map(vehicle) <- {:vehicle, vehicle},
         {:date, {:ok, date}} <-
           {:date,
            validate(
              socket.assigns.month,
              socket.assigns.day,
              socket.assigns.year,
              model_year,
              today
            )},
         {:odo, {:ok, metres}} <-
           {:odo,
            Units.to_metres(socket.assigns.odo_value || "", unit_atom(socket.assigns.odo_unit))} do
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

    # Provenance is about the GRADE: one we list is "catalog", one the user
    # typed is "manual". Base stock is always a choice from our fixed list.
    #
    # The effective_* helpers, not the raw assigns: the form pre-fills from the
    # intake step's standing answer, and what is SAVED must be what the form
    # SHOWS. Reading the raw assign here would save nil for a user who accepted
    # the pre-filled oil without touching it — a record disagreeing with the
    # screen it was saved from.
    {grade, provenance} =
      if a.manual_grade?,
        do: {a.manual_grade, "manual"},
        else: {effective_listed_grade(a), "catalog"}

    %{
      "event_id" => Ecto.UUID.generate(),
      "vehicle_id" => vehicle["vehicle_id"],
      "performed_at" => Date.to_iso8601(date),
      "odometer_m" => metres,
      "odometer_input_value" => a.odo_value,
      "input_unit" => a.odo_unit,
      "oil_base_stock" => effective_base_stock(a),
      "oil_viscosity" => grade,
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
        [
          %{"store" => "events", "record" => event},
          %{"store" => "readings", "record" => reading}
        ],
        [],
        navigate_to: ~p"/"
      )

    socket
    |> assign(:submitted_token, socket.assigns.form_token)
    |> put_flash(:info, Copy.saving())
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

  defp active_vehicle(garage), do: Session.active_vehicle(garage)

  # -- pre-fill from the intake step -------------------------------------------
  #
  # The intake step records what oil the vehicle USES; until the user touches
  # the oil controls on this form, that standing answer is the form's answer.
  # Both render and save go through these helpers so the record can never
  # disagree with the screen.

  defp planned(assigns) do
    case active_vehicle(assigns.garage) do
      %{"maintenance_plan" => plan} when is_map(plan) -> plan
      _ -> %{}
    end
  end

  defp effective_base_stock(assigns),
    do: assigns.base_stock || planned(assigns)["planned_base_stock"]

  # Only a grade we actually list pre-selects. A manual grade from intake would
  # need this form silently switched into manual mode to show it — implicit
  # state a user did not ask for — so it simply starts unselected instead.
  defp effective_listed_grade(assigns) do
    assigns.grade ||
      case planned(assigns)["planned_grade"] do
        grade when is_binary(grade) ->
          if Enum.any?(OilModel.grades(), &(&1.code == grade)), do: grade

        _ ->
          nil
      end
  end

  # Grades filtered to the vehicle's engine class, with the rest one control
  # away. An unclassified vehicle gets no suggestions rather than another
  # class's list, so the grouping never implies a fact we do not have.
  #
  # Derived at render, not at mount: the garage arrives from the browser after
  # the LiveView has already mounted, so anything computed from it at mount is
  # computed from an empty garage.
  defp grade_assigns(assigns) do
    class_code =
      case active_vehicle(assigns.garage) do
        %{"engine_class_code" => code} -> code
        _ -> nil
      end

    {suggested, others} = OilModel.grade_choices(class_code)

    assigns
    |> assign(:engine_class_name, class_display_name(class_code))
    |> assign(:suggested_grades, suggested)
    |> assign(:other_grades, others)
  end

  defp class_display_name(nil), do: nil

  defp class_display_name(code) do
    case OilModel.engine_class(code) do
      %{display_name: name} -> name
      _ -> nil
    end
  end

  # "__all__" and "__manual__" are UI affordances, not grades: they switch the
  # control and never become a stored value.
  defp grade_choice("__all__", assigns), do: {assigns.grade, true, false}
  defp grade_choice("__manual__", assigns), do: {assigns.grade, assigns.show_all_grades?, true}

  defp grade_choice(value, assigns),
    do: {presence(value), assigns.show_all_grades?, assigns.manual_grade?}

  defp validate_day_clear(month, day, year) do
    if is_integer(month) and is_integer(day) and is_integer(year) and
         day > :calendar.last_day_of_the_month(year, month) do
      {:cleared,
       Copy.day_cleared(month_name(month), year, :calendar.last_day_of_the_month(year, month))}
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
    assigns = assigns |> assign(:notes_limit, @notes_limit) |> grade_assigns()

    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only}>
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

          <.oil_type_select
            base_stocks={@base_stocks}
            base_stock={effective_base_stock(assigns)}
            suggested_grades={@suggested_grades}
            other_grades={@other_grades}
            grade={effective_listed_grade(assigns)}
            show_all_grades?={@show_all_grades?}
            manual_grade?={@manual_grade?}
            manual_grade={@manual_grade}
            engine_class_name={@engine_class_name}
          />

          <div class="grid grid-cols-2 gap-2">
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
            <textarea
              id="oil-notes"
              name="notes"
              rows="3"
              maxlength={to_string(@notes_limit)}
              class="w-full rounded border px-3 py-2"
            >{@notes}</textarea>
            <p class="mt-1 text-xs text-base-content/70">
              {String.length(@notes)}/{@notes_limit} characters
            </p>
          </div>

          <div
            :if={@duplicate_pending}
            class="rounded border border-amber-400 p-3"
            role="alertdialog"
            aria-label="Possible duplicate"
          >
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
