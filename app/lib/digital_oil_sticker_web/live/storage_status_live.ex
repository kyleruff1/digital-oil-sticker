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
    {:ok,
     socket
     |> assign(:page_title, "Storage")
     |> assign(:confirm_erase?, false)}
  end

  @impl true
  def handle_event("export", _params, socket) do
    {:noreply, push_event(socket, "local_store:export", %{})}
  end

  def handle_event("request_persist", _params, socket) do
    {:noreply, push_event(socket, "local_store:request_persist", %{})}
  end

  def handle_event("ask_erase", _params, socket) do
    {:noreply, assign(socket, :confirm_erase?, true)}
  end

  def handle_event("cancel_erase", _params, socket) do
    {:noreply, assign(socket, :confirm_erase?, false)}
  end

  # Deliberately NOT gated on mutations_enabled?: erase is most needed in the
  # states that gate excludes — :data_missing, and read_only under a
  # newer-schema payload, where erasing is the one act that ends the state.
  # The client does the work; no record content passes through here.
  def handle_event("confirm_erase", _params, socket) do
    {:noreply,
     socket
     |> assign(:confirm_erase?, false)
     |> push_event("local_store:erase", %{})}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} unsaved_writes={@unsaved_writes} read_only={@read_only} conflict_notice={@conflict_notice}>
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

        <section class="mt-8 rounded border p-4" data-test="import-panel">
          <h2 class="font-semibold">{Copy.import_heading()}</h2>
          <p class="mt-1 text-xs text-base-content/70">{Copy.import_body()}</p>

          <%!-- Everything inside is client-owned (phx-update="ignore"): the
               file is read, validated, and written to IndexedDB in the
               browser, and the records never touch the socket (INV-23/26).
               The strings are all server-rendered so the copy-lint sees
               them; the hook only toggles visibility and fills counts. --%>
          <div id="storage-import" phx-hook="StorageImport" phx-update="ignore" class="mt-3">
            <label for="storage-import-file" class="mb-1 block text-sm font-semibold">
              {Copy.import_choose_label()}
            </label>
            <input
              id="storage-import-file"
              type="file"
              accept="application/json,.json"
              class="w-full text-sm"
            />

            <div data-import-preview hidden class="mt-3 rounded border border-amber-400 p-3">
              <p class="text-sm">
                Vehicles: <strong data-import-slot="vehicles"></strong>
                · Oil changes: <strong data-import-slot="events"></strong>
                · Exported: <strong data-import-slot="exported"></strong>
              </p>
              <p class="mt-2 text-sm">{Copy.import_warning()}</p>
              <div class="mt-3 flex gap-2">
                <button type="button" data-import-cancel class="btn btn-ghost btn-sm">
                  Cancel
                </button>
                <button
                  type="button"
                  data-import-confirm
                  class="btn btn-error btn-sm"
                  data-test="import-confirm"
                >
                  {Copy.import_confirm_label()}
                </button>
              </div>
            </div>

            <p data-import-error hidden role="alert" class="mt-2 text-sm text-error">
              <span data-import-error-text>
                <span data-error-kind="invalid" hidden>{Copy.import_invalid()}</span>
                <span data-error-kind="damaged" hidden>{Copy.import_damaged()}</span>
                <span data-error-kind="newer" hidden>{Copy.import_newer()}</span>
                <span data-error-kind="storage" hidden>{Copy.import_storage_failed()}</span>
              </span>
            </p>
          </div>
        </section>

        <section class="mt-6 rounded border border-error/40 p-4" data-test="erase-panel">
          <h2 class="font-semibold">{Copy.erase_heading()}</h2>
          <p class="mt-1 text-xs text-base-content/70">{Copy.erase_body()}</p>
          <button
            phx-click="ask_erase"
            class="btn btn-outline btn-error btn-sm mt-3"
            data-test="ask-erase"
          >
            {Copy.erase_confirm_label()}
          </button>
        </section>

        <div
          :if={@confirm_erase?}
          class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
          role="dialog"
          aria-modal="true"
          aria-labelledby="erase-title"
          data-test="erase-modal"
        >
          <div class="w-full max-w-sm rounded-lg bg-base-100 p-6 shadow-xl">
            <h2 id="erase-title" class="text-lg font-bold">{Copy.erase_heading()}</h2>
            <p class="mt-2 text-sm leading-relaxed">{Copy.erase_body()}</p>
            <div class="mt-5 flex justify-end gap-2">
              <button type="button" phx-click="cancel_erase" class="btn btn-ghost">Cancel</button>
              <button
                type="button"
                phx-click="confirm_erase"
                class="btn btn-error"
                data-test="confirm-erase"
              >
                {Copy.erase_confirm_label()}
              </button>
            </div>
          </div>
        </div>

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
