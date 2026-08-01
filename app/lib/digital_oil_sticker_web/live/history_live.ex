defmodule DigitalOilStickerWeb.HistoryLive do
  @moduledoc """
  Service history, newest-first by (performed_at desc, event_id desc).
  Each row shows its provenance badge; deletion requires confirmation and
  offers an in-session undo (10 s) before the tombstone commits. Deleting an
  event removes only its linked reading, never an independent same-date one.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  alias DigitalOilStickerWeb.Components.Badges
  alias DigitalOilStickerWeb.Copy
  alias DigitalOilStickerWeb.LocalStore.Session

  @undo_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "History")
     |> assign(:confirm_delete, nil)
     |> assign(:undo, nil)}
  end

  @impl true
  def handle_event("ask_delete", %{"event-id" => id}, socket) do
    {:noreply, assign(socket, :confirm_delete, id)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("confirm_delete", %{"event-id" => id}, socket) do
    if Session.mutations_enabled?(socket) do
      Process.send_after(self(), {:commit_delete, id}, @undo_ms)
      {:noreply, socket |> assign(:confirm_delete, nil) |> assign(:undo, id)}
    else
      {:noreply, put_flash(socket, :error, Copy.session_only_banner())}
    end
  end

  def handle_event("undo_delete", _params, socket) do
    {:noreply, assign(socket, :undo, nil)}
  end

  @impl true
  def handle_info({:commit_delete, id}, socket) do
    if socket.assigns.undo == id do
      event = Enum.find(socket.assigns.garage.events, &(&1["event_id"] == id))

      deletes =
        [%{"store" => "events", "key" => id}] ++
          linked_reading_deletes(socket.assigns.garage, event)

      {socket, _} = Session.stage_mutation(socket, [], deletes)
      {:noreply, assign(socket, :undo, nil)}
    else
      {:noreply, socket}
    end
  end

  # Only the reading sourced from THIS event — never an independent entry.
  defp linked_reading_deletes(_garage, nil), do: []

  defp linked_reading_deletes(garage, event) do
    garage.readings
    |> Enum.filter(&(&1["source"] == "service_event" and &1["source_ref"] == event["event_id"]))
    |> Enum.map(&%{"store" => "readings", "key" => &1["reading_id"]})
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :events, sorted_events(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl">
        <h1 class="text-2xl font-bold">History</h1>

        <div :if={@local_state == :hydrating} class="mt-6 animate-pulse rounded border p-6" aria-hidden="true">
          <span class="sr-only">{Copy.sr_checking()}</span>
        </div>

        <p :if={@local_state == :loaded and @events == []} class="mt-6 text-sm text-zinc-600">
          Nothing recorded yet — the next useful step is to
          <.link navigate={~p"/service/new"} class="underline">record the first oil change</.link>.
        </p>

        <ol :if={@events != []} class="mt-6 space-y-3">
          <li :for={event <- @events} class="rounded border p-4" data-test="history-row">
            <div :if={@undo == event["event_id"]} class="flex items-center justify-between">
              <p class="text-sm">Deleting…</p>
              <button phx-click="undo_delete" class="btn btn-sm">Undo</button>
            </div>
            <div :if={@undo != event["event_id"]}>
              <div class="flex items-baseline justify-between gap-2">
                <span class="font-semibold">{event["performed_at"]}</span>
                <span class="text-sm text-zinc-600">
                  {event["odometer_input_value"]} {event["input_unit"]}
                </span>
              </div>
              <p class="mt-1 flex flex-wrap items-center gap-2 text-sm">
                <span :if={event["oil_brand"] || event["oil_family"]}>
                  {[event["oil_brand"], event["oil_family"]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")}
                </span>
                <span :if={event["oil_viscosity"]}>· {event["oil_viscosity"]}</span>
                <Badges.provenance_badge mode={if event["provenance_mode"] == "catalog", do: :catalog, else: :manual} />
              </p>
              <p :if={event["notes"] not in [nil, ""]} class="mt-1 text-sm text-zinc-600">{event["notes"]}</p>
              <div class="mt-2">
                <button
                  :if={@confirm_delete != event["event_id"]}
                  phx-click="ask_delete"
                  phx-value-event-id={event["event_id"]}
                  class="btn btn-ghost btn-sm"
                >
                  Delete
                </button>
                <span :if={@confirm_delete == event["event_id"]} class="flex items-center gap-2">
                  <span class="text-sm">Delete this record from this browser?</span>
                  <button phx-click="confirm_delete" phx-value-event-id={event["event_id"]} class="btn btn-sm">
                    Delete
                  </button>
                  <button phx-click="cancel_delete" class="btn btn-ghost btn-sm">Keep</button>
                </span>
              </div>
            </div>
          </li>
        </ol>
      </div>
    </Layouts.app>
    """
  end

  defp sorted_events(assigns) do
    assigns.garage.events
    |> Enum.sort_by(&{&1["performed_at"] || "", &1["event_id"]}, :desc)
  end
end
