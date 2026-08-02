defmodule DigitalOilStickerWeb.VehicleProfileLive do
  @moduledoc """
  The active vehicle's profile: display snapshot, support status, how we
  classify the engine, the interval our own model gives it, and the controls
  that change that answer — severe service, and a manual override.

  Everything on this page that produces a number says where the number came
  from. Our model is labeled as ours; a user override is labeled as theirs.
  Neither is presented as manufacturer guidance (INV-20/21).
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  alias DigitalOilSticker.Catalog.OilModel
  alias DigitalOilSticker.{CalendarExport, Due}
  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @lead_choices Enum.map(CalendarExport.lead_time_options(), &elem(&1, 1))

  # The base stock the estimate on this page is quoted against when the user
  # has not logged a change yet. Full synthetic is the most common purchase
  # and the longest interval, so quoting it here and letting the real logged
  # value shorten it later never surprises someone with a shorter number.
  @default_base_stock "full_synthetic"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Your vehicle")
     |> assign(:interval_months, nil)
     |> assign(:interval_miles, nil)
     |> assign(:interval_errors, [])
     |> assign(:override?, false)
     |> assign(:base_stocks, OilModel.base_stocks())}
  end

  @impl true
  def handle_event("interval_change", params, socket) do
    {:noreply,
     socket
     |> assign(:interval_months, parse_int(params["interval"]["months"]))
     |> assign(:interval_miles, parse_int(params["interval"]["miles"]))
     |> assign(:interval_errors, [])}
  end

  def handle_event("toggle_override", _params, socket) do
    {:noreply, assign(socket, :override?, not socket.assigns.override?)}
  end

  # Severe service is a property of how the vehicle is driven, so it is stored
  # on the vehicle rather than asked again at every oil change.
  def handle_event("set_condition", %{"condition" => condition}, socket)
      when condition in ["normal", "severe"] do
    case active_vehicle(socket.assigns.garage) do
      nil ->
        {:noreply, put_flash(socket, :error, "Set up a vehicle first.")}

      vehicle ->
        plan = Map.put(vehicle["maintenance_plan"] || %{}, "service_condition", condition)
        {:noreply, save_plan(socket, vehicle, plan, navigate: false)}
    end
  end

  def handle_event("reminder_lead_change", %{"lead_days" => raw}, socket) do
    vehicle = active_vehicle(socket.assigns.garage)
    days = parse_int(raw)

    cond do
      vehicle == nil ->
        {:noreply, socket}

      not Session.mutations_enabled?(socket) ->
        {:noreply, put_flash(socket, :error, Copy.session_only_banner())}

      days not in @lead_choices ->
        # Not one of the offered lead times — a tampered select, not a choice.
        {:noreply, socket}

      true ->
        now = DateTime.utc_now() |> DateTime.to_iso8601()

        record =
          (find_reminder(socket.assigns.garage, vehicle["vehicle_id"]) ||
             %{
               "reminder_id" => Ecto.UUID.generate(),
               "vehicle_id" => vehicle["vehicle_id"],
               "kind" => "oil_change",
               "created_at" => now
             })
          |> Map.merge(%{
            "lead_value" => days,
            "lead_unit" => "days",
            "enabled" => true,
            "updated_at" => now
          })

        {socket, _mutation_id} =
          Session.stage_mutation(socket, [%{"store" => "reminders", "record" => record}], [])

        {:noreply, socket}
    end
  end

  def handle_event("interval_save", _params, socket) do
    vehicle = active_vehicle(socket.assigns.garage)
    months = socket.assigns.interval_months
    miles = socket.assigns.interval_miles

    cond do
      vehicle == nil ->
        {:noreply, put_flash(socket, :error, "Set up a vehicle first.")}

      not Session.mutations_enabled?(socket) ->
        {:noreply, put_flash(socket, :error, Copy.session_only_banner())}

      is_nil(months) and is_nil(miles) ->
        {:noreply,
         assign(socket, :interval_errors, [
           "#{Copy.your_interval()} needs months, miles, or both."
         ])}

      (is_integer(months) and months <= 0) or (is_integer(miles) and miles <= 0) ->
        {:noreply, assign(socket, :interval_errors, ["Intervals must be positive."])}

      true ->
        plan =
          (vehicle["maintenance_plan"] || %{})
          |> Map.merge(%{
            "basis" => "user_entered",
            "interval_months" => months,
            "interval_miles" => miles,
            "set_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

        {:noreply, save_plan(socket, vehicle, plan, navigate: true)}
    end
  end

  defp save_plan(socket, vehicle, plan, opts) do
    updated =
      vehicle
      |> Map.put("maintenance_plan", plan)
      |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

    stage_opts = if opts[:navigate], do: [navigate_to: ~p"/"], else: []

    {socket, _id} =
      Session.stage_mutation(
        socket,
        [%{"store" => "vehicles", "record" => updated}],
        [],
        stage_opts
      )

    put_flash(socket, :info, Copy.saving())
  end

  @impl true
  def render(assigns) do
    vehicle = active_vehicle(assigns.garage)

    assigns =
      assigns
      |> assign(:vehicle, vehicle)
      |> assign(:engine_class, vehicle && OilModel.engine_class(vehicle["engine_class_code"]))
      |> assign(:condition, condition_of(vehicle))
      |> assign(:estimate, estimate_for(vehicle, assigns.garage))
      |> assign(:severe_questions, severe_questions())
      |> assign(:reminder, reminder_view(assigns.garage, vehicle))
      # Ready but INERT: `manufacturer_viscosity` is a nullable inner key on
      # `maintenance_plan` that DOS-M03-007 (ADR-0007 lane b) will populate
      # once ingest lands. Until then this is always nil and the whole
      # section below is suppressed — no placeholder, no "unknown". The
      # display works the moment data lands with no further code changes.
      |> assign(:manufacturer_viscosity, manufacturer_viscosity(vehicle))

    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only}>
      <div class="mx-auto max-w-xl">
        <h1 class="text-2xl font-bold">Your vehicle</h1>

        <div
          :if={@local_state == :hydrating}
          class="mt-6 animate-pulse rounded border p-6"
          aria-hidden="true"
        >
          <span class="sr-only">{Copy.sr_checking()}</span>
        </div>

        <div :if={@local_state != :hydrating and is_nil(@vehicle)} class="mt-6">
          <p class="text-sm text-base-content/80">No vehicle is set up in this browser yet.</p>
          <.link navigate={~p"/vehicle/select"} class="btn btn-primary mt-4">Choose a vehicle</.link>
        </div>

        <div :if={@vehicle} class="mt-6 space-y-6">
          <section class="rounded border p-4">
            <h2 class="font-semibold">{snapshot_line(@vehicle)}</h2>
            <p class="mt-2 flex flex-wrap gap-2">
              <Badges.support_badge status={support_atom(@vehicle["support_status"])} />
              <Badges.precision_badge :if={
                @vehicle["display_snapshot"]["build"] =~ Copy.not_specified()
              } />
            </p>
            <p :if={@engine_class} class="mt-2 text-xs text-base-content/70">
              {Copy.engine_class_line(@engine_class.display_name)} — {@engine_class.reasoning}
            </p>
            <p class="mt-2 text-xs text-base-content/70">
              Schedule: {Copy.source_unavailable()} — no licensed manufacturer schedule exists for
              this selection yet.
            </p>
          </section>

          <section :if={@estimate == :not_applicable} class="rounded border p-4">
            <h2 class="font-semibold">{Copy.not_applicable_ev()}</h2>
            <p class="mt-1 text-sm text-base-content/80">
              {@engine_class && @engine_class.reasoning}
            </p>
          </section>

          <section :if={is_map(@estimate)} class="rounded border p-4">
            <h2 class="font-semibold">{Copy.our_model_label()}</h2>
            <p class="mt-1 text-lg">
              {Copy.interval_summary(@estimate.miles_recommended, @estimate.months_cap)}
            </p>
            <p class="mt-1 text-xs text-base-content/70">{@estimate.reasoning}</p>
            <%!-- Same "assuming" clause the sticker renders for the same
                 defaulted-plan state, one navigation away. Without it, THIS
                 page — the one a user visits precisely to inspect and change
                 what the app is assuming — reads as a confirmed choice. --%>
            <p
              :if={@estimate[:oil_basis] == :planned_default}
              class="mt-2 text-xs text-amber-700"
            >
              {Copy.assumed_oil_note()}
            </p>
            <p :if={@estimate.basis == :fallback_lowest_published} class="mt-2 text-xs text-amber-700">
              {Copy.lowest_published_used()}
            </p>
            <p class="mt-3 text-xs leading-relaxed text-base-content/70">{Copy.our_model_basis()}</p>

            <details class="mt-3">
              <summary class="cursor-pointer text-sm font-medium">
                Every interval we model for this engine
              </summary>
              <table class="mt-2 w-full text-left text-xs">
                <thead>
                  <tr>
                    <th scope="col" class="py-1 pr-2">Type of oil</th>
                    <th scope="col" class="py-1 pr-2">Normal</th>
                    <th scope="col" class="py-1">Severe</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- interval_rows(@vehicle)} class="border-t">
                    <th scope="row" class="py-1 pr-2 font-normal">{row.base_stock}</th>
                    <td class="py-1 pr-2">{row.normal}</td>
                    <td class="py-1">{row.severe}</td>
                  </tr>
                </tbody>
              </table>
            </details>
          </section>

          <%!-- Ready but INERT: renders only when DOS-M03-007 populates
               `maintenance_plan.manufacturer_viscosity` with an OEM-sourced
               value backed by per-row provenance in our internal source
               register (ADR-0007 lane b, RECOMMENDATION_CLAIMS_POLICY.md
               §"Factory recommendation label"). The badge deliberately
               carries NO source information — publisher, URL, revision
               date — the promise is that we hold OEM-backed provenance,
               not that we expose whose data it came from. --%>
          <section
            :if={is_binary(@manufacturer_viscosity) and @manufacturer_viscosity != ""}
            class="rounded border p-4"
          >
            <h2 class="font-semibold">{Copy.manufacturer_viscosity_heading()}</h2>
            <p class="mt-2 flex flex-wrap items-center gap-2">
              <span class="text-lg">{@manufacturer_viscosity}</span>
              <Badges.factory_recommendation_badge />
            </p>
          </section>

          <section :if={is_map(@estimate)} class="rounded border p-4">
            <h2 class="font-semibold">{Copy.severe_service_prompt()}</h2>
            <ul class="mt-2 list-disc pl-5 text-sm text-base-content/80">
              <li :for={question <- @severe_questions}>{question}</li>
            </ul>
            <p class="mt-2 text-xs text-base-content/70">{Copy.severe_service_effect()}</p>
            <div class="mt-3 flex gap-2">
              <button
                type="button"
                phx-click="set_condition"
                phx-value-condition="severe"
                aria-pressed={to_string(@condition == "severe")}
                class={["btn btn-sm", @condition == "severe" && "btn-primary"]}
              >
                Yes, severe service
              </button>
              <button
                type="button"
                phx-click="set_condition"
                phx-value-condition="normal"
                aria-pressed={to_string(@condition == "normal")}
                class={["btn btn-sm", @condition == "normal" && "btn-primary"]}
              >
                No, normal service
              </button>
            </div>
          </section>

          <section class="rounded border p-4">
            <h2 class="font-semibold">{Copy.your_interval()}</h2>

            <div :if={not @override? and not has_own_interval?(@vehicle)}>
              <p class="mt-1 text-xs text-base-content/70">
                You have not set your own interval. We are using {Copy.our_model_label()} above.
              </p>
              <button type="button" phx-click="toggle_override" class="btn btn-sm mt-3">
                {Copy.override_interval_label()}
              </button>
            </div>

            <form
              :if={@override? or has_own_interval?(@vehicle)}
              id="interval-form"
              phx-change="interval_change"
              phx-submit="interval_save"
              class="mt-3"
            >
              <p class="mb-2 text-xs text-base-content/70">
                {Copy.interval_overridden()} Whichever is shorter — yours or {Copy.our_model_label()} —
                is what the sticker shows.
              </p>
              <div class="grid grid-cols-2 gap-2">
                <div>
                  <label for="interval-months" class="mb-1 block text-xs font-medium">Months</label>
                  <input
                    type="text"
                    inputmode="numeric"
                    id="interval-months"
                    name="interval[months]"
                    value={
                      @interval_months || current_interval(@vehicle, "interval_months") ||
                        suggested(@estimate, :months_cap)
                    }
                    class="w-full min-h-11 rounded border px-3 py-2"
                  />
                </div>
                <div>
                  <label for="interval-miles" class="mb-1 block text-xs font-medium">Miles</label>
                  <input
                    type="text"
                    inputmode="numeric"
                    id="interval-miles"
                    name="interval[miles]"
                    value={
                      @interval_miles || current_interval(@vehicle, "interval_miles") ||
                        suggested(@estimate, :miles_recommended)
                    }
                    class="w-full min-h-11 rounded border px-3 py-2"
                  />
                </div>
              </div>
              <p :if={@interval_errors != []} role="alert" class="mt-2 text-sm text-error">
                {Enum.join(@interval_errors, " ")}
              </p>
              <button type="submit" class="btn btn-primary mt-3" phx-disable-with={Copy.saving()}>
                Save {Copy.your_interval()}
              </button>
            </form>
          </section>

          <section
            :if={@reminder && @reminder.applicable?}
            class="mt-6 rounded border p-4"
            data-test="reminder-panel"
          >
            <h2 class="font-semibold">{Copy.reminder_heading()}</h2>
            <p class="mt-1 text-xs text-base-content/70">{Copy.reminder_body()}</p>

            <form phx-change="reminder_lead_change" class="mt-3">
              <label for="reminder-lead" class="mb-1 block text-sm font-semibold">
                {Copy.reminder_lead_label()}
              </label>
              <select
                id="reminder-lead"
                name="lead_days"
                class="w-full min-h-11 rounded border px-2 py-2 sm:max-w-xs"
              >
                {Phoenix.HTML.Form.options_for_select(
                  CalendarExport.lead_time_options(),
                  @reminder.lead_days
                )}
              </select>
            </form>

            <%!-- The file is built server-side but DOWNLOADED from markup the
                 browser already has — a download route would put the due date
                 and mileage in a URL, and URLs end up in access logs. --%>
            <button
              :if={@reminder.ics}
              type="button"
              id="calendar-download"
              phx-hook="CalendarDownload"
              data-ics={@reminder.ics}
              data-filename={CalendarExport.filename()}
              class="btn btn-primary mt-3"
              data-test="calendar-download"
            >
              {Copy.reminder_download()}
            </button>
            <p :if={is_nil(@reminder.ics)} class="mt-3 text-sm text-base-content/70">
              {Copy.reminder_needs_change()}
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp active_vehicle(garage), do: Session.active_vehicle(garage)

  defp find_reminder(garage, vehicle_id) do
    Enum.find(
      garage.reminders,
      &(&1["vehicle_id"] == vehicle_id and &1["kind"] == "oil_change")
    )
  end

  # Everything the reminder panel shows, from the garage. The calendar file is
  # built only when a due date exists — the reminder is measured from a logged
  # change, and an event with no date would be a promise about nothing.
  defp reminder_view(_garage, nil), do: nil

  defp reminder_view(garage, vehicle) do
    id = vehicle["vehicle_id"]
    record = find_reminder(garage, id)
    lead_days = sanitize_lead(record && record["lead_value"])
    last = Session.last_oil_change(garage, id)
    due = Due.compute(vehicle, last)

    ics =
      with %Date{} = due_on <- due.due_on,
           {:ok, ics} <-
             CalendarExport.build(%{
               vehicle_id: id,
               due_on: due_on,
               vehicle_label: snapshot_line(vehicle),
               due_mileage: due.mileage_text,
               changed_on: due.changed_on,
               lead_days: lead_days,
               sequence_at: sequence_instant(record, last)
             }) do
        ics
      else
        _ -> nil
      end

    %{lead_days: lead_days, ics: ics, applicable?: due.resolved != :not_applicable}
  end

  # A stored lead outside the offered set (an older release's option, a
  # tampered record) falls back to the default instead of failing the build —
  # a failed build rendered "Log an oil change first" over a garage that
  # plainly has one, which is worse than a default lead.
  defp sanitize_lead(value) when is_integer(value),
    do: if(value in @lead_choices, do: value, else: 7)

  defp sanitize_lead(value) when is_binary(value), do: sanitize_lead(parse_int(value) || -1)
  defp sanitize_lead(_), do: 7

  # The instant of the LAST user action that changed what the calendar event
  # says — the lead choice or the logged change, whichever is newer. It drives
  # SEQUENCE, which must advance on every re-download a client is meant to
  # treat as a replacement.
  defp sequence_instant(record, last_event) do
    [record && record["updated_at"], last_event && last_event["created_at"]]
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(fn iso ->
      case DateTime.from_iso8601(iso) do
        {:ok, dt, _offset} -> [dt]
        _ -> []
      end
    end)
    |> case do
      [] -> nil
      instants -> Enum.max(instants, DateTime)
    end
  end

  defp condition_of(nil), do: "normal"

  defp condition_of(vehicle) do
    case get_in(vehicle, ["maintenance_plan", "service_condition"]) do
      "severe" -> "severe"
      _ -> "normal"
    end
  end

  defp estimate_for(nil, _garage), do: nil

  # The SAME knowledge chain the sticker uses (Due.oil_rule: recorded change,
  # then intake's answer, then the unknown floor) — two derivations here meant
  # this page's "Our estimate" could quote full synthetic while the sticker
  # one navigation away, and the reminder file built on THIS page, were both
  # computed from the conventional oil the last change recorded. The
  # historical full-synthetic default remains only for the state where the
  # chain knows nothing at all.
  defp estimate_for(vehicle, garage) do
    last = Session.last_oil_change(garage, vehicle["vehicle_id"])

    # The oil_basis is carried alongside the interval so the render pass can
    # attribute honestly — a :planned_default interval must say "assuming" the
    # same way the sticker does, or this page contradicts a sticker one
    # navigation away. The whole point of extracting Due was one calculation,
    # one label; dropping the label here re-created the divergence.
    case Due.oil_rule(vehicle, last) do
      {{:ok, interval}, basis} ->
        Map.put(interval, :oil_basis, basis)

      {:not_applicable, _basis} ->
        :not_applicable

      {nil, :none} ->
        case OilModel.interval(
               vehicle["engine_class_code"],
               @default_base_stock,
               condition_of(vehicle)
             ) do
          {:ok, interval} -> Map.put(interval, :oil_basis, :none)
          :not_applicable -> :not_applicable
          {:error, _} -> nil
        end
    end
  end

  defp interval_rows(vehicle) do
    for stock <- OilModel.base_stocks() do
      %{
        base_stock: stock.display_name,
        normal: cell(OilModel.interval(vehicle["engine_class_code"], stock.code, "normal")),
        severe: cell(OilModel.interval(vehicle["engine_class_code"], stock.code, "severe"))
      }
    end
  end

  defp cell({:ok, %{miles_recommended: miles, months_cap: months}}),
    do: "#{miles} mi / #{months} mo"

  defp cell(_), do: Copy.not_specified()

  defp severe_questions do
    case OilModel.service_condition("severe") do
      %{questions: questions} -> questions
      _ -> []
    end
  end

  defp suggested(estimate, key) when is_map(estimate), do: Map.get(estimate, key)
  defp suggested(_estimate, _key), do: nil

  defp snapshot_line(%{
         "display_snapshot" => %{"year" => y, "make" => ma, "model" => mo, "build" => b}
       }) do
    [y, ma, mo, b] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
  end

  defp snapshot_line(_), do: Copy.not_specified()

  defp support_atom("not_applicable"), do: :not_applicable
  defp support_atom("unsupported"), do: :unsupported
  defp support_atom("schedule_supported"), do: :schedule_supported
  defp support_atom("full_product_supported"), do: :full_product_supported
  defp support_atom(_), do: :identity_only

  defp current_interval(%{"maintenance_plan" => %{} = plan}, key), do: plan[key]
  defp current_interval(_, _), do: nil

  # Returns the OEM-sourced viscosity string when the vehicle carries one
  # and nil otherwise. Callers gate the badge on nil/"" — the field will be
  # nil until DOS-M03-007 ingest populates it.
  defp manufacturer_viscosity(nil), do: nil

  defp manufacturer_viscosity(vehicle),
    do: get_in(vehicle, ["maintenance_plan", "manufacturer_viscosity"])

  defp has_own_interval?(vehicle) do
    not is_nil(current_interval(vehicle, "interval_miles")) or
      not is_nil(current_interval(vehicle, "interval_months"))
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.replace(s, ~r/[,\s]/, "")) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
