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
  alias DigitalOilSticker.Catalog
  alias DigitalOilSticker.Catalog.Selector
  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @impl true
  def mount(_params, _session, socket) do
    years =
      case Selector.validate(:list_years, %{}) |> then(fn {:ok, s} -> Catalog.list_years(s) end) do
        {:ok, result} -> result.data
        _ -> []
      end

    {:ok,
     socket
     |> assign(:page_title, "Choose a vehicle")
     |> assign(:years, years)
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
        year != socket.assigns.year -> socket |> reset_cascade(:year) |> assign(:year, year) |> load_makes()
        make_id != socket.assigns.make_id -> socket |> reset_cascade(:make) |> assign(:make_id, make_id) |> load_models()
        model_id != socket.assigns.model_id -> socket |> reset_cascade(:model) |> assign(:model_id, model_id) |> load_configs()
        true -> assign(socket, :configuration_key, config_key)
      end

    {:noreply, socket}
  end

  def handle_event("confirm", _params, socket) do
    with key when is_binary(key) <- socket.assigns.configuration_key,
         {:ok, sel} <- Selector.validate(:get_configuration, %{"configuration_key" => key}),
         {:ok, result} when not is_nil(result.data) <- Catalog.get_configuration(sel),
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
        "archived" => false,
        "maintenance_plan" => nil,
        "created_at" => now,
        "updated_at" => now
      }

      {socket, _mutation_id} = Session.stage_mutation(socket, [%{"store" => "vehicles", "record" => vehicle}], [])
      {:noreply, push_navigate(socket, to: ~p"/vehicle")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a vehicle first, and make sure storage is available.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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

        <p id="cascade-count" role="status" aria-live="polite" aria-atomic="true" class="mt-2 text-sm text-zinc-500">
          {@count_announcement}
        </p>

        <section :if={@configuration_key} class="mt-6 rounded border p-4" data-test="confirm-panel">
          <h2 class="font-semibold">Review before saving</h2>
          <p class="mt-2 text-sm">{selected_summary(assigns)}</p>
          <p class="mt-2 flex flex-wrap gap-2 text-sm">
            <Badges.support_badge status={selected_status(assigns)} />
            <Badges.precision_badge :if={selected_config(assigns) && is_nil(selected_config(assigns).trim)} />
          </p>
          <p class="mt-2 text-xs text-zinc-500">
            Recommendations depend on exact configuration. {Copy.source_unavailable()} means no
            licensed schedule exists for this selection yet — you can still record oil changes
            and set {Copy.your_interval()}.
          </p>
          <button phx-click="confirm" class="btn btn-primary mt-4" data-test="confirm-vehicle">
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
  end

  defp reset_cascade(socket, :make) do
    socket
    |> assign(make_id: nil, model_id: nil, configuration_key: nil)
    |> assign(models: [], configs: [], models_empty: false, configs_empty: false)
  end

  defp reset_cascade(socket, :model) do
    socket |> assign(model_id: nil, configuration_key: nil) |> assign(configs: [], configs_empty: false)
  end

  defp load_makes(%{assigns: %{year: nil}} = socket), do: socket

  defp load_makes(socket) do
    run(socket, :list_makes, %{"year" => socket.assigns.year, "page_size" => 200}, fn socket, result ->
      socket
      |> assign(:makes, result.data)
      |> assign(:makes_empty, result.data == [])
      |> assign(:count_announcement, announce(result, "makes"))
    end)
  end

  defp load_models(%{assigns: %{make_id: nil}} = socket), do: socket

  defp load_models(socket) do
    params = %{"year" => socket.assigns.year, "make_id" => socket.assigns.make_id, "page_size" => 200}

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

  defp announce(%{total_known?: true, total: n}, noun), do: "#{n} #{noun}"
  defp announce(%{data: data}, noun), do: "#{length(data)} #{noun} shown — #{Copy.count_unknown()}"

  defp config_label(config) do
    [config.trim, config.series, config.engine_descriptor, config.transmission, config.drive_type]
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> "#{config.model_year} — #{Copy.not_specified()}"
      parts -> Enum.join(parts, " · ")
    end
  end

  defp selected_config(assigns),
    do: Enum.find(assigns.configs, &(&1.configuration_key == assigns.configuration_key))

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

    [assigns.year, make && make.display_name, model && model.display_name, config && config_label(config)]
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
