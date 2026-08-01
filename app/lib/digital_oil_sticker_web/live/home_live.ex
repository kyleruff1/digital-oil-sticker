defmodule DigitalOilStickerWeb.HomeLive do
  @moduledoc """
  Skeleton landing page. Its job is to prove the hosted path end to end:
  the page renders server-side, the LiveView WebSocket connects, and an
  interaction round-trips. It holds no personal data — under INV-23 the
  user's garage lives only in browser storage, hydrated per INV-24.
  """
  use DigitalOilStickerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Digital Oil Sticker")
     |> assign(:pings, 0)
     |> assign(:connected?, connected?(socket))}
  end

  @impl true
  def handle_event("ping", _params, socket) do
    {:noreply, update(socket, :pings, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto max-w-2xl px-6 py-16">
      <img src={~p"/images/dos-logo.svg"} alt="Digital Oil Sticker" class="w-full max-w-md" />

      <p class="mt-8 text-lg leading-relaxed">
        An accurate, explainable replacement for the windshield oil-change sticker.
        Record a service, add odometer readings, and see when the next one is actually due.
      </p>

      <dl class="mt-10 grid grid-cols-2 gap-4 text-sm">
        <div class="rounded-lg border p-4">
          <dt class="font-semibold">LiveView socket</dt>
          <dd data-test="socket-state">
            {if @connected?, do: "connected", else: "connecting…"}
          </dd>
        </div>
        <div class="rounded-lg border p-4">
          <dt class="font-semibold">Round trips</dt>
          <dd data-test="ping-count">{@pings}</dd>
        </div>
      </dl>

      <button
        phx-click="ping"
        class="mt-6 rounded-lg border px-4 py-2 font-semibold hover:bg-zinc-100"
      >
        Send a round trip
      </button>

      <p class="mt-10 text-sm text-zinc-500">
        Skeleton deployment. No vehicle data is served yet, and nothing you enter is
        stored on the server — this app keeps your records in your own browser.
      </p>
    </main>
    """
  end
end
