defmodule DigitalOilStickerWeb.VehicleProfileLive do
  @moduledoc """
  The active vehicle's profile: display snapshot, support status, and
  "Your interval" (the only interval basis while no licensed schedule
  exists — clearly labeled, never presented as manufacturer guidance).
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Your vehicle")
     |> assign(:interval_months, nil)
     |> assign(:interval_miles, nil)
     |> assign(:interval_errors, [])}
  end

  @impl true
  def handle_event("interval_change", params, socket) do
    {:noreply,
     socket
     |> assign(:interval_months, parse_int(params["interval"]["months"]))
     |> assign(:interval_miles, parse_int(params["interval"]["miles"]))
     |> assign(:interval_errors, [])}
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
        {:noreply, assign(socket, :interval_errors, ["#{Copy.your_interval()} needs months, miles, or both."])}

      (is_integer(months) and months <= 0) or (is_integer(miles) and miles <= 0) ->
        {:noreply, assign(socket, :interval_errors, ["Intervals must be positive."])}

      true ->
        updated =
          vehicle
          |> Map.put("maintenance_plan", %{
            "basis" => "user_entered",
            "interval_months" => months,
            "interval_miles" => miles,
            "set_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })
          |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

        {socket, _id} = Session.stage_mutation(socket, [%{"store" => "vehicles", "record" => updated}], [])
        {:noreply, socket |> put_flash(:info, Copy.saving()) |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :vehicle, active_vehicle(assigns.garage))

    ~H"""
    <div class="mx-auto max-w-xl">
      <h1 class="text-2xl font-bold">Your vehicle</h1>

      <div :if={@local_state == :hydrating} class="mt-6 animate-pulse rounded border p-6" aria-hidden="true">
        <span class="sr-only">{Copy.sr_checking()}</span>
      </div>

      <div :if={@local_state != :hydrating and is_nil(@vehicle)} class="mt-6">
        <p class="text-sm text-zinc-600">No vehicle is set up in this browser yet.</p>
        <.link navigate={~p"/vehicle/select"} class="btn btn-primary mt-4">Choose a vehicle</.link>
      </div>

      <div :if={@vehicle} class="mt-6 space-y-6">
        <section class="rounded border p-4">
          <h2 class="font-semibold">
            {snapshot_line(@vehicle)}
          </h2>
          <p class="mt-2 flex flex-wrap gap-2">
            <Badges.support_badge status={support_atom(@vehicle["support_status"])} />
            <Badges.precision_badge :if={@vehicle["display_snapshot"]["build"] =~ Copy.not_specified()} />
          </p>
          <p class="mt-2 text-xs text-zinc-500">
            Schedule: {Copy.source_unavailable()} — no licensed manufacturer schedule exists for
            this selection yet. Your records and estimates use {Copy.your_interval()} below.
          </p>
        </section>

        <section class="rounded border p-4">
          <h2 class="font-semibold">{Copy.your_interval()}</h2>
          <p class="mt-1 text-xs text-zinc-500">
            User-entered — not manufacturer guidance. The sticker's estimated due date and
            mileage come from this interval applied to your last recorded change.
          </p>
          <form phx-change="interval_change" phx-submit="interval_save" class="mt-3">
            <div class="grid grid-cols-2 gap-2">
              <div>
                <label for="interval-months" class="mb-1 block text-xs font-medium">Months</label>
                <input
                  type="text"
                  inputmode="numeric"
                  id="interval-months"
                  name="interval[months]"
                  value={@interval_months || current_interval(@vehicle, "interval_months")}
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
                  value={@interval_miles || current_interval(@vehicle, "interval_miles")}
                  class="w-full min-h-11 rounded border px-3 py-2"
                />
              </div>
            </div>
            <p :if={@interval_errors != []} role="alert" class="mt-2 text-sm text-red-700">
              {Enum.join(@interval_errors, " ")}
            </p>
            <button type="submit" class="btn btn-primary mt-3" phx-disable-with={Copy.saving()}>
              Save {Copy.your_interval()}
            </button>
          </form>
        </section>
      </div>
    </div>
    """
  end

  defp active_vehicle(garage), do: garage.vehicles |> Enum.reject(&(&1["archived"] == true)) |> List.first()

  defp snapshot_line(%{"display_snapshot" => %{"year" => y, "make" => ma, "model" => mo, "build" => b}}) do
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

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(String.replace(s, ~r/[,\s]/, "")) do
      {i, ""} -> i
      _ -> nil
    end
  end
end
