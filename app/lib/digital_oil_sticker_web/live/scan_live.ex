defmodule DigitalOilStickerWeb.ScanLive do
  @moduledoc """
  The landing page for a scanned sticker code (`/s`).

  A stranger points a phone camera at a windshield sticker. The QR they scan
  is a URL — `https://digitaloilsticker.com/s#<code>` — whose fragment carries
  the sticker's date, odometer, and grade encoded by
  `DigitalOilSticker.StickerCode`. The fragment never reaches the server
  (INV-26); it is read by `assets/js/hooks/scan_landing.js` on mount and
  handed back over the socket as the `scan_code` event.

  The LiveView is deliberately isolated from `live_session :garage` — no
  IndexedDB hydration, no per-user assigns — because the scanner is not the
  owner and the page's contract is that no browser storage is loaded here.

  ## Four view modes

    * `:awaiting`     — mounted, waiting for the hook to report the fragment.
                        Renders a skeleton sticker so the first paint is
                        never empty.
    * `:no_code`      — the fragment was empty (visited `/s` bare). Explains
                        what the URL is for.
    * `:bad_code`     — the fragment was non-empty but did not decode. Names
                        the failure honestly without guessing at what went
                        wrong.
    * `:sticker`      — decoded. Renders the sticker with the historical
                        record in the stamped viewports; the top ("estimated
                        due") viewports stay blank because computing them
                        would require someone else's private interval.

  ## The `scan_code` event contract

  Client sends `%{"code" => <string>}`. The server never trusts the code —
  `StickerCode.decode/1` is a bijection over a strict byte layout and returns
  a tagged tuple for any input that does not match. Length is bounded before
  decode as a courtesy; the decoder itself refuses anything longer than the
  format ever produces.
  """
  use DigitalOilStickerWeb, :live_view

  import DigitalOilStickerWeb.Components.Sticker

  alias DigitalOilSticker.{StickerCode, Units}
  alias DigitalOilSticker.Catalog.Queries.Identity
  alias DigitalOilStickerWeb.Copy

  # The code is 40 base32 characters plus, at most, a length byte and 255 bytes
  # of tail (custom grade text) — encoded, that is ~450 characters. Anything
  # much beyond that is not a StickerCode; refuse before we bother the decoder.
  @max_code_length 500

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Digital Oil Sticker")
     |> assign(:view, %{mode: :awaiting})}
  end

  @impl true
  def handle_event("scan_code", %{"code" => ""}, socket) do
    {:noreply, assign(socket, :view, %{mode: :no_code})}
  end

  def handle_event("scan_code", %{"code" => code}, socket) when is_binary(code) do
    view =
      cond do
        byte_size(code) > @max_code_length -> %{mode: :bad_code}
        true -> decode_view(code)
      end

    {:noreply, assign(socket, :view, view)}
  end

  # A non-string `code` cannot come from the well-formed hook; treat as bad.
  def handle_event("scan_code", _params, socket) do
    {:noreply, assign(socket, :view, %{mode: :bad_code})}
  end

  defp decode_view(code) do
    case StickerCode.decode(code) do
      {:ok, sticker} ->
        %{
          mode: :sticker,
          vehicle: format_vehicle(Identity.get_configuration_labels(sticker.configuration_key)),
          changed: format_date(sticker.changed_on),
          mileage: format_mileage(sticker.odometer_m),
          grade: sticker.grade
        }

      {:error, _reason} ->
        %{mode: :bad_code}
    end
  end

  # A configuration_key from an older catalog (or a truncated one that decoded
  # to a valid UUID by luck) may not resolve to a current catalog row. Return
  # nil in that case rather than crashing; the template gates the vehicle line
  # on presence.
  defp format_vehicle(nil), do: nil

  defp format_vehicle(%{year: y, make: mk, model: mo, trim: t}) do
    [y, mk, mo, t] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join(" ")
  end

  defp format_date(nil), do: nil
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%b %d, %Y")

  # Miles is the display unit here for one reason only: the sticker code carries
  # metres, and the scanner may not have the owner's unit preference (that is a
  # `prefs` field in the owner's IndexedDB, which we don't load on this page).
  # Miles is the default the app ships with; a later cut can offer a toggle.
  defp format_mileage(nil), do: nil

  defp format_mileage(metres) when is_integer(metres) and metres >= 0 do
    miles = metres |> Units.from_metres(:mi) |> round()
    "#{format_int(miles)} mi"
  end

  defp format_int(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="scan-landing"
      phx-hook="ScanLanding"
      class="mx-auto max-w-3xl px-4 py-6"
      data-test="scan-landing"
    >
      <.awaiting :if={@view.mode == :awaiting} />
      <.no_code :if={@view.mode == :no_code} />
      <.bad_code :if={@view.mode == :bad_code} />
      <.sticker_view :if={@view.mode == :sticker} view={@view} />
    </main>
    """
  end

  # -- View-mode partials -----------------------------------------------------

  defp awaiting(assigns) do
    ~H"""
    <div data-test="scan-awaiting">
      <span class="sr-only">{Copy.scan_awaiting()}</span>
      <.sticker skeleton />
    </div>
    """
  end

  defp no_code(assigns) do
    ~H"""
    <div class="py-10 text-center" data-test="scan-no-code">
      <h1 class="text-2xl font-bold">{Copy.scan_no_code_heading()}</h1>
      <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
        {Copy.scan_no_code_body()}
      </p>
      <.link navigate={~p"/"} class="btn btn-primary mt-6">
        {Copy.scan_return_to_app()}
      </.link>
    </div>
    """
  end

  defp bad_code(assigns) do
    ~H"""
    <div class="py-10 text-center" data-test="scan-bad-code">
      <h1 class="text-2xl font-bold">{Copy.scan_bad_code_heading()}</h1>
      <p class="mx-auto mt-4 max-w-prose text-sm leading-relaxed text-base-content/80">
        {Copy.scan_bad_code_body()}
      </p>
      <.link navigate={~p"/"} class="btn btn-primary mt-6">
        {Copy.scan_return_to_app()}
      </.link>
    </div>
    """
  end

  attr :view, :map, required: true

  defp sticker_view(assigns) do
    ~H"""
    <div data-test="scan-sticker">
      <%!-- The vehicle name resolved from the code's configuration_key. Rendered
           above the sticker when the catalog still has that row; hidden when it
           doesn't, rather than showing "Unknown vehicle" (which would misread
           as a bug when the actual state is that the code came from an older
           catalog with retired IDs). --%>
      <p
        :if={@view.vehicle}
        class="mx-auto mb-4 max-w-prose text-center text-lg font-semibold"
        data-test="scan-vehicle"
      >
        {@view.vehicle}
      </p>

      <%!-- Top viewports (`date_value`/`mileage_value`) are DELIBERATELY blank
           — omitted rather than passed as nil to keep the attribute-type
           check quiet. They are "estimated due" fields on the owner's front
           page; the scanner has no interval to compute a due from (INV-25).
           The historical record lives in the stamped viewports below. --%>
      <.sticker changed_value={@view.changed} grade_value={@view.grade} />

      <dl
        :if={@view.mileage}
        class="mx-auto mt-4 max-w-prose text-center text-sm text-base-content/70"
        data-test="scan-mileage-recap"
      >
        <dt class="inline font-semibold">Mileage at last change:</dt>
        <dd class="inline">{@view.mileage}</dd>
      </dl>

      <p class="mx-auto mt-4 max-w-prose text-center text-sm leading-relaxed text-base-content/80">
        {Copy.scan_sticker_caption()}
      </p>

      <p class="mt-8 text-center">
        <.link navigate={~p"/"} class="btn btn-primary">
          {Copy.scan_return_to_app()}
        </.link>
      </p>
    </div>
    """
  end
end
