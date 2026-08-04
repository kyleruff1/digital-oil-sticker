defmodule DigitalOilStickerWeb.VehiclePickerLive do
  @moduledoc """
  Offline-honest vehicle selection: Year → Make → Model → Build cascade over
  the impersonal catalog query layer. Search/filter state is disposable —
  a vehicle is written to browser storage only on explicit confirmation.
  Changing an upstream level clears everything downstream. Zero-result
  distinguishes "no catalog match" from "the catalog could not be read".
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  import DigitalOilStickerWeb.Components.CascadeSelect
  import DigitalOilStickerWeb.Components.OilTypeSelect
  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.{OilModel, Selector}
  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @impl true
  def mount(_params, _session, socket) do
    years =
      case Selector.validate(:list_years, %{})
           |> then(fn {:ok, s} -> Catalog.list_years(s) end) do
        {:ok, result} -> result.data
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Choose a vehicle")
     |> assign(:years, years)
     |> assign(:base_stocks, OilModel.base_stocks())
     |> assign(:catalog_error, if(years == [], do: :catalog_unavailable))
     |> reset_cascade(:year)}
  end

  @impl true
  def handle_event("cascade_change", params, socket) do
    year = parse_int(params["year"])
    make_id = presence(params["make_id"])
    model_id = presence(params["model_id"])
    config_key = presence(params["configuration_key"])

    socket =
      cond do
        year != socket.assigns.year ->
          socket |> reset_cascade(:year) |> assign(:year, year) |> load_makes()

        make_id != socket.assigns.make_id ->
          socket |> reset_cascade(:make) |> assign(:make_id, make_id) |> load_models()

        model_id != socket.assigns.model_id ->
          socket |> reset_cascade(:model) |> assign(:model_id, model_id) |> load_configs()

        config_key != socket.assigns.configuration_key ->
          # A different build can mean a different engine class, which means a
          # different grade suggestion and a different recommendation. Oil
          # answers do not survive a change of engine.
          socket
          |> reset_oil()
          |> assign(:configuration_key, config_key)
          |> apply_oil_defaults()

        true ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("oil_change", %{"oil" => oil}, socket) do
    {grade, show_all?, manual?} = grade_choice(oil["grade"], socket.assigns)
    unknown? = oil["base_stock"] == "__unknown__"
    new_base_stock = if unknown?, do: nil, else: presence(oil["base_stock"])

    # Auto-select the top suggested grade the moment a base stock is chosen,
    # if the user hasn't picked a grade themselves. This is the closest thing
    # to a per-vehicle recommendation our current data supports — the picker
    # walks the vehicle's engine class through OilModel.grades_for_class, and
    # takes the first entry. Not the same as a manufacturer spec (see
    # ADR-0007), and never overrides an explicit choice.
    grade =
      if is_nil(grade) and is_binary(new_base_stock) and not manual?,
        do: auto_grade_for(socket.assigns),
        else: grade

    # `oil_touched?` distinguishes an app-defaulted answer from a user-chosen
    # one. Any dispatched oil-form change flips it — the user opened the form
    # and made (or accepted) a choice. It never flips back to false. Downstream
    # this decides whether the saved plan reads `"selected"` or `"defaulted"`,
    # which in turn decides whether the log form pre-fills from the plan and
    # whether the sticker attributes the number to the user's answer or to
    # the app's assumption.
    {:noreply,
     socket
     |> assign(:oil_touched?, true)
     |> assign(:oil_unknown?, unknown?)
     |> assign(:base_stock, new_base_stock)
     |> assign(grade: grade, show_all_grades?: show_all?, manual_grade?: manual?)
     |> assign(:manual_grade, presence(oil["manual_grade"]))}
  end

  def handle_event("confirm", _params, socket) do
    with key when is_binary(key) <- socket.assigns.configuration_key,
         {:ok, sel} <- Selector.validate(:get_configuration, %{"configuration_key" => key}),
         {:ok, result} when not is_nil(result.data) <- Catalog.get_configuration(sel),
         :ok <- oil_answered(socket, result.status),
         true <- Session.mutations_enabled?(socket) do
      config = result.data
      vehicle_id = Ecto.UUID.generate()
      now = DateTime.utc_now() |> DateTime.to_iso8601()

      vehicle = %{
        "vehicle_id" => vehicle_id,
        "configuration_key" => config.configuration_key,
        "catalog_data_version" => result.data_version,
        "nickname" => nil,
        "model_year" => config.model_year,
        "display_snapshot" => display_snapshot(socket, config),
        "support_status" => to_string(result.status),
        # Snapshot our classification and the model version that produced it,
        # so a later revision of the model never silently changes an interval
        # the user has already been shown.
        "engine_class_code" => config.engine_class_code,
        "oil_model_version" => OilModel.model_version(),
        "archived" => false,
        "maintenance_plan" => planned_oil(socket, result.status),
        "created_at" => now,
        "updated_at" => now
      }

      # Navigation is handed to the ack: if this browser refuses the write we
      # stay here and say so, instead of landing on a clean page that implies
      # the vehicle was stored.
      #
      # An oil-serviced vehicle routes to logging its most recent change: the
      # recommendation shown above is an interval, and it only becomes a date
      # and a mileage on the sticker once there is a change to measure from.
      # Saving a vehicle also SELECTS it, in the same write. Without this, a
      # garage that already has a car keeps that one active, and the user
      # lands on the next page looking at a different vehicle than the one
      # they just added. Skipped when prefs is quarantined — overwriting an
      # unreadable singleton destroys its content, and the new vehicle still
      # saves; only the selection falls back.
      prefs_upsert =
        if Session.prefs_quarantined?(socket) do
          []
        else
          prefs =
            (socket.assigns.garage.prefs || %{})
            |> Map.put("active_vehicle_id", vehicle_id)

          [%{"store" => "prefs", "record" => prefs}]
        end

      {socket, _mutation_id} =
        Session.stage_mutation(
          socket,
          [%{"store" => "vehicles", "record" => vehicle} | prefs_upsert],
          [],
          navigate_to:
            if(result.status == :not_applicable, do: ~p"/vehicle", else: ~p"/service/new")
        )

      {:noreply, socket}
    else
      {:error, :oil_unanswered} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Choose what oil the vehicle uses first — it sets the interval."
         )}

      _ ->
        {:noreply,
         put_flash(socket, :error, "Choose a vehicle first, and make sure storage is available.")}
    end
  end

  defp apply_oil_defaults(socket) do
    if is_binary(socket.assigns.configuration_key) and
         selected_status(socket.assigns) != :not_applicable do
      socket
      |> assign(:base_stock, "full_synthetic")
      |> assign(:grade, auto_grade_for(socket.assigns))
    else
      socket
    end
  end

  defp oil_answered(_socket, :not_applicable), do: :ok

  defp oil_answered(socket, _status) do
    if socket.assigns.oil_unknown? or is_binary(socket.assigns.base_stock),
      do: :ok,
      else: {:error, :oil_unanswered}
  end

  defp planned_oil(_socket, :not_applicable), do: nil

  defp planned_oil(socket, _status) do
    cond do
      socket.assigns.oil_unknown? ->
        %{"planned_oil" => "unknown"}

      # `"defaulted"` records that the plan carries an APP-CHOSEN oil, not a
      # user-answered one — apply_oil_defaults filled it and the user never
      # touched the oil form. Downstream: the log form does not pre-fill from
      # a defaulted plan (or the pre-fill would masquerade as the user's
      # answer about what they poured in), and the sticker qualifier labels
      # the estimate as "assuming" rather than "based on". "selected" is
      # reserved for a plan the user consciously chose or confirmed.
      true ->
        %{
          "planned_oil" => if(socket.assigns.oil_touched?, do: "selected", else: "defaulted"),
          "planned_base_stock" => socket.assigns.base_stock,
          "planned_grade" => effective_grade(socket.assigns)
        }
    end
  end

  defp effective_grade(%{manual_grade?: true, manual_grade: manual}), do: manual
  defp effective_grade(%{grade: grade}), do: grade

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      unsaved_writes={@unsaved_writes}
      read_only={@read_only}
      conflict_notice={@conflict_notice}
      storage_mode={@storage_mode}
    >
      <div>
        <h1 class="text-2xl font-bold">Choose a vehicle</h1>

        <p :if={@catalog_error} class="mt-4 rounded border border-red-300 p-3 text-sm" role="alert">
          {Copy.catalog_unreadable()}
        </p>

        <form phx-change="cascade_change" class="mt-6 grid grid-cols-2 gap-4 md:grid-cols-4">
          <.cascade_select
            id="cascade-year"
            name="year"
            label="Year"
            options={Enum.map(@years, &{&1, &1})}
            value={@year}
            state={if @years == [], do: :loading, else: :populated}
          />
          <.cascade_select
            id="cascade-make"
            name="make_id"
            label="Make"
            options={Enum.map(@makes, &{&1.display_name, &1.id})}
            value={@make_id}
            state={level_state(@year, @makes, @makes_empty)}
            upstream_label="year"
          />
          <.cascade_select
            id="cascade-model"
            name="model_id"
            label="Model"
            options={Enum.map(@models, &{&1.display_name, &1.id})}
            value={@model_id}
            state={level_state(@make_id, @models, @models_empty)}
            upstream_label="make"
          />
          <.cascade_select
            id="cascade-config"
            name="configuration_key"
            label="Build"
            options={Enum.map(@configs, &{config_label(&1), &1.configuration_key})}
            value={@configuration_key}
            state={level_state(@model_id, @configs, @configs_empty)}
            upstream_label="model"
          />
        </form>

        <p
          id="cascade-count"
          role="status"
          aria-live="polite"
          aria-atomic="true"
          class="mt-2 text-sm text-base-content/70"
        >
          {@count_announcement}
        </p>

        <section :if={@configuration_key} class="mt-6 rounded border p-4" data-test="confirm-panel">
          <h2 class="font-semibold">Review before saving</h2>
          <p class="mt-2 text-sm">{selected_summary(assigns)}</p>
          <p class="mt-2 flex flex-wrap gap-2 text-sm">
            <Badges.support_badge status={selected_status(assigns)} />
            <Badges.precision_badge :if={
              selected_config(assigns) && is_nil(selected_config(assigns).trim)
            } />
          </p>
          <p class="mt-2 text-xs text-base-content/70">{confirm_note(assigns)}</p>

          <div :if={selected_status(assigns) != :not_applicable} class="mt-5" data-test="intake-oil">
            <h3 class="font-semibold">{Copy.intake_oil_heading()}</h3>
            <p class="mt-1 text-xs text-base-content/70">{Copy.intake_oil_why()}</p>

            <form id="intake-oil-form" phx-change="oil_change" class="mt-3">
              <.oil_type_select
                base_stocks={@base_stocks}
                base_stock={@base_stock}
                defaulted?={not @oil_touched? and is_binary(@base_stock)}
                suggested_grades={elem(picker_grades(assigns), 0)}
                other_grades={elem(picker_grades(assigns), 1)}
                grade={@grade}
                show_all_grades?={@show_all_grades?}
                manual_grade?={@manual_grade?}
                manual_grade={@manual_grade}
                engine_class_name={engine_class_name(assigns)}
                unknown_option?
                unknown?={@oil_unknown?}
              />
            </form>

            <%!-- Live region: the recommendation number changes as the user
                 arrows through the base-stock radios or picks a different
                 grade, and sighted users track it in their peripheral vision.
                 Without aria-live a screen-reader user hears nothing when
                 the number below their current focus recomputes — the whole
                 comparison signal per-option previews used to carry is lost.
                 role=status + polite is the pattern this file already uses
                 for the cascade count above. --%>
            <p
              :if={recommendation(assigns)}
              class="mt-3 rounded border border-emerald-700/40 p-3 text-sm"
              data-test="intake-recommendation"
              role="status"
              aria-live="polite"
              aria-atomic="true"
            >
              <span class="font-semibold">{recommendation(assigns)}</span>
              <br />
              <span class="text-xs text-base-content/70">
                <%= cond do %>
                  <% @oil_unknown? -> %>
                    {Copy.unknown_oil_qualifier()}
                  <% not @oil_touched? -> %>
                    {Copy.assumed_oil_note()}
                  <% true -> %>
                    {Copy.our_model_label()}, not manufacturer guidance. Severe-service driving
                    shortens it — you can answer that on the vehicle page.
                <% end %>
              </span>
            </p>
          </div>

          <button
            phx-click="confirm"
            class="btn btn-primary mt-4"
            data-test="confirm-vehicle"
            disabled={not confirmable?(assigns)}
          >
            Save this vehicle
          </button>
        </section>

        <p class="mt-8 text-sm">
          <span class="font-semibold">{Copy.vehicle_not_listed()}?</span>
          A custom-vehicle path ships next; nothing is transmitted about your vehicle either way.
        </p>
      </div>
    </Layouts.app>
    """
  end

  # -- cascade state -----------------------------------------------------------

  defp reset_cascade(socket, :year) do
    socket
    |> assign(year: nil, make_id: nil, model_id: nil, configuration_key: nil)
    |> assign(makes: [], models: [], configs: [])
    |> assign(makes_empty: false, models_empty: false, configs_empty: false)
    |> assign(count_announcement: "")
    |> reset_oil()
  end

  defp reset_cascade(socket, :make) do
    socket
    |> assign(make_id: nil, model_id: nil, configuration_key: nil)
    |> assign(models: [], configs: [], models_empty: false, configs_empty: false)
    |> reset_oil()
  end

  defp reset_cascade(socket, :model) do
    socket
    |> assign(model_id: nil, configuration_key: nil)
    |> assign(configs: [], configs_empty: false)
    |> reset_oil()
  end

  defp reset_oil(socket) do
    assign(socket,
      base_stock: nil,
      oil_unknown?: false,
      grade: nil,
      show_all_grades?: false,
      manual_grade?: false,
      manual_grade: nil,
      oil_touched?: false
    )
  end

  # "__all__" and "__manual__" are UI affordances, not grades: they switch the
  # select's mode while keeping whatever grade was already chosen.
  defp grade_choice("__all__", assigns), do: {assigns.grade, true, false}
  defp grade_choice("__manual__", assigns), do: {assigns.grade, assigns.show_all_grades?, true}

  defp grade_choice(value, assigns),
    do: {presence(value), assigns.show_all_grades?, assigns.manual_grade?}

  defp load_makes(%{assigns: %{year: nil}} = socket), do: socket

  defp load_makes(socket) do
    run(socket, :list_makes, %{"year" => socket.assigns.year, "page_size" => 200}, fn socket,
                                                                                      result ->
      socket
      |> assign(:makes, result.data)
      |> assign(:makes_empty, result.data == [])
      |> assign(:count_announcement, announce(result, "makes"))
    end)
  end

  defp load_models(%{assigns: %{make_id: nil}} = socket), do: socket

  defp load_models(socket) do
    params = %{
      "year" => socket.assigns.year,
      "make_id" => socket.assigns.make_id,
      "page_size" => 200
    }

    run(socket, :list_models, params, fn socket, result ->
      socket
      |> assign(:models, result.data)
      |> assign(:models_empty, result.data == [])
      |> assign(:count_announcement, announce(result, "models"))
    end)
  end

  defp load_configs(%{assigns: %{model_id: nil}} = socket), do: socket

  defp load_configs(socket) do
    params = %{
      "year" => socket.assigns.year,
      "make_id" => socket.assigns.make_id,
      "model_id" => socket.assigns.model_id,
      "page_size" => 200
    }

    run(socket, :list_configurations, params, fn socket, result ->
      socket
      |> assign(:configs, result.data)
      |> assign(:configs_empty, result.data == [])
      |> assign(:count_announcement, announce(result, "builds"))
    end)
  end

  defp run(socket, function, params, on_ok) do
    bucket = socket.assigns.catalog_budget
    now = System.monotonic_time(:millisecond)

    with {:ok, bucket2} <- DigitalOilSticker.Catalog.RateLimit.take(bucket, 1, now),
         {:ok, sel} <- Selector.validate(function, params),
         {:ok, result} <- apply(Catalog, function, [sel]) do
      socket |> assign(:catalog_budget, bucket2) |> assign(:catalog_error, nil) |> on_ok.(result)
    else
      {:error, :rate_limited} -> assign(socket, :count_announcement, Copy.rate_limited())
      {:error, :catalog_unavailable} -> assign(socket, :catalog_error, :catalog_unavailable)
      _ -> assign(socket, :catalog_error, :catalog_unavailable)
    end
  end

  defp level_state(upstream, options, empty?) do
    cond do
      is_nil(upstream) -> :disabled
      empty? and options == [] -> :narrowed_empty
      true -> :populated
    end
  end

  defp announce(%{total_known?: true, total: n}, noun), do: "#{n} #{plural(noun, n)}"

  defp announce(%{data: data}, noun),
    do: "#{length(data)} #{plural(noun, length(data))} shown — #{Copy.count_unknown()}"

  defp plural(noun, 1), do: String.trim_trailing(noun, "s")
  defp plural(noun, _), do: noun

  defp config_label(config) do
    [config.trim, config.series, config.engine_descriptor, config.transmission, config.drive_type]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "#{config.model_year} — #{Copy.not_specified()}"
      parts -> Enum.join(parts, " · ")
    end
  end

  # The note under the badge has to agree with the badge. A vehicle with no
  # engine oil service must not be told it can log oil changes.
  defp confirm_note(assigns) do
    if selected_status(assigns) == :not_applicable do
      "This vehicle has no engine oil service, so there is no oil change to record or estimate."
    else
      "No licensed manufacturer schedule exists for this selection yet — #{Copy.source_unavailable()}. " <>
        "You will get #{Copy.our_model_label()} for when the oil is due, and you can set " <>
        "#{Copy.your_interval()} instead at any time."
    end
  end

  defp selected_config(assigns),
    do: Enum.find(assigns.configs, &(&1.configuration_key == assigns.configuration_key))

  # -- the oil step -------------------------------------------------------------

  defp picker_grades(assigns) do
    case selected_config(assigns) do
      %{engine_class_code: code} -> OilModel.grade_choices(code)
      _ -> {[], []}
    end
  end

  # Top of the class's suggested list. Returns nil for an unclassified vehicle
  # rather than picking from another class — an unknown engine must not
  # silently borrow another engine's grade.
  defp auto_grade_for(assigns) do
    case selected_config(assigns) do
      %{engine_class_code: code} ->
        case OilModel.grades_for_class(code) do
          [%{code: grade} | _] -> grade
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp engine_class_name(assigns) do
    with %{engine_class_code: code} <- selected_config(assigns),
         %{display_name: name} <- OilModel.engine_class(code) do
      name
    else
      _ -> nil
    end
  end

  # The deterministic answer the step exists for: engine class × oil type →
  # interval, shown before anything is saved. Computed for normal service —
  # the severe-service questions live on the vehicle page and only shorten it.
  defp recommendation(assigns) do
    config = selected_config(assigns)

    interval =
      cond do
        config == nil ->
          nil

        assigns.oil_unknown? ->
          OilModel.unknown_oil_interval(config.engine_class_code)

        is_binary(assigns.base_stock) ->
          OilModel.interval(config.engine_class_code, assigns.base_stock)

        true ->
          nil
      end

    case interval do
      {:ok, %{miles_recommended: miles, months_cap: months}} ->
        Copy.recommendation_line(format_int(miles), months)

      _ ->
        nil
    end
  end

  defp confirmable?(assigns) do
    selected_status(assigns) == :not_applicable or
      assigns.oil_unknown? or
      is_binary(assigns.base_stock)
  end

  defp format_int(n) when n >= 1000 do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_int(n), do: Integer.to_string(n)

  defp selected_status(assigns) do
    case selected_config(assigns) do
      %{support_status: "not_applicable"} -> :not_applicable
      %{support_status: "unsupported"} -> :unsupported
      _ -> :identity_only
    end
  end

  defp selected_summary(assigns) do
    make = Enum.find(assigns.makes, &(&1.id == assigns.make_id))
    model = Enum.find(assigns.models, &(&1.id == assigns.model_id))
    config = selected_config(assigns)

    [
      assigns.year,
      make && make.display_name,
      model && model.display_name,
      config && config_label(config)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp display_snapshot(socket, config) do
    make = Enum.find(socket.assigns.makes, &(&1.id == socket.assigns.make_id))
    model = Enum.find(socket.assigns.models, &(&1.id == socket.assigns.model_id))

    %{
      "year" => config.model_year,
      "make" => make && make.display_name,
      "model" => model && model.display_name,
      "build" => config_label(config)
    }
  end

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
end
