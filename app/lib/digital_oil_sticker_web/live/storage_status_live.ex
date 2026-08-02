defmodule DigitalOilStickerWeb.StorageStatusLive do
  @moduledoc """
  The honest storage page: where records live ("stored in this browser"),
  persistence grant state, quota estimate (or the honest absence of one),
  quarantine counts, and export. INV-25: no backup/sync/restore framing.
  """
  use DigitalOilStickerWeb, :live_view

  alias DigitalOilStickerWeb.Layouts

  alias DigitalOilStickerWeb.Copy

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Storage")}
  end

  @impl true
  def handle_event("export", _params, socket) do
    {:noreply, push_event(socket, "local_store:export", %{})}
  end

  def handle_event("request_persist", _params, socket) do
    {:noreply, push_event(socket, "local_store:request_persist", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only}>
      <div class="mx-auto max-w-xl">
        <h1 class="text-2xl font-bold">Storage</h1>

        <p class="mt-4 text-sm leading-relaxed text-base-content/80">{Copy.empty_body()}</p>

        <dl class="mt-6 space-y-3 text-sm">
          <div class="rounded border p-3">
            <dt class="font-semibold">State</dt>
            <dd data-test="storage-state">{state_line(@local_state, @storage_mode)}</dd>
          </div>
          <div class="rounded border p-3">
            <dt class="font-semibold">Keeping storage under pressure</dt>
            <dd>
              {persist_line(@persist_granted)}
              <%!-- Inside the <dd>, not beside it: a <div> within a <dl> may
                   contain only dt/dd groups. --%>
              <button
                :if={is_nil(@persist_granted) and @storage_mode == :durable_capable}
                phx-click="request_persist"
                class="btn btn-sm mt-2"
              >
                Ask this browser to keep storage
              </button>
            </dd>
          </div>
          <div class="rounded border p-3">
            <dt class="font-semibold">Space</dt>
            <dd>{quota_line(@quota)}</dd>
          </div>
          <div :if={@quarantine != []} class="rounded border border-amber-400 p-3">
            <dt class="font-semibold">{Copy.quarantine_notice()}</dt>
            <dd>{Copy.quarantine_body(length(@quarantine), record_total(assigns))}</dd>
          </div>
        </dl>

        <button phx-click="export" class="btn btn-primary mt-6">Export a file</button>

        <p class="mt-8 text-xs text-base-content/80">{Copy.no_affiliation()}</p>
      </div>
    </Layouts.app>
    """
  end

  defp state_line(:loaded, :durable_capable), do: "Records are stored in this browser."
  defp state_line(:empty, _), do: "Nothing is stored in this browser yet."
  defp state_line(:data_missing, _), do: Copy.data_missing_heading()
  defp state_line(:hydration_refused, _), do: Copy.hydration_refused_heading()
  defp state_line(:storage_unavailable, _), do: Copy.storage_unavailable_heading()
  defp state_line(:hydrating, _), do: Copy.sr_checking()
  defp state_line(_, :session_only), do: Copy.session_only_banner()
  defp state_line(_, _), do: "Checking…"

  defp persist_line(true),
    do: "This browser agreed to keep the app's storage when space runs low."

  defp persist_line(false),
    do: "This browser did not agree to keep the app's storage when space runs low."

  defp persist_line(nil),
    do: "This browser does not report whether it will keep the app's storage."

  defp quota_line(nil), do: "This browser does not report a storage estimate."

  defp quota_line(%{usage: usage, quota: quota}) when quota > 0 do
    pct = Float.round(usage / quota * 100, 1)
    "#{mb(usage)} of #{mb(quota)} used (#{pct}%)."
  end

  defp quota_line(_), do: "This browser does not report a storage estimate."

  defp mb(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp record_total(assigns) do
    g = assigns.garage
    length(g.vehicles) + length(g.events) + length(g.readings) + length(assigns.quarantine)
  end
end
