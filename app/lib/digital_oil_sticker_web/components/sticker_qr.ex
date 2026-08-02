defmodule DigitalOilStickerWeb.Components.StickerQr do
  @moduledoc """
  The scannable form of a sticker: a QR symbol with its code printed beneath.

  ## Why the payload is a URL, and why the code is in the fragment

  A phone camera pointed at a bare code shows the user forty characters of
  base32 and offers them nothing to do about it. A URL opens the sticker. So
  the payload is a URL.

  The code sits in the **fragment**, not the path, and that is not a stylistic
  choice — a fragment is never sent to the server, so the odometer, service
  date, and grade the code carries stay off the request line and out of every
  access log between here and the browser (INV-26). A path would put them in
  both. The cost is that `#` is outside QR's alphanumeric character set, which
  forces the whole payload into byte mode and grows the symbol from 29 to 37
  modules. That is the price of the privacy property, and it was measured
  rather than assumed: both sizes decode down to roughly 1.6 device pixels per
  module on real hardware, so the larger symbol costs nothing that matters.

  ## Why the code is printed too

  It is not there to be retyped. It is there because it is the durable half:
  a scuffed, folded, or thermally faded symbol stops scanning long before
  forty characters of text stop being readable, and a shop system that has
  already captured the code can display it back for a human to compare against
  the sticker in the windshield.

  Printed without separators, deliberately. Grouping the characters would read
  better and would also mean the printed text is not what the decoder accepts,
  which is a trap for exactly the fallback path the printing exists to serve.
  """
  use Phoenix.Component

  alias DigitalOilStickerWeb.Copy

  attr :code, :string,
    required: true,
    doc: "the canonical sticker code, from StickerCode.encode/1"

  attr :payload, :string,
    required: true,
    doc: "the full scan URL carrying the code in its fragment"

  attr :id, :string, default: "sticker-qr"

  def qr_symbol(assigns) do
    ~H"""
    <figure class="dos-qr" data-test="sticker-qr">
      <%!-- phx-update="ignore" so LiveView does not fight the hook over the
           injected SVG. Attribute changes still reach the element and still
           fire updated(), which is what redraws it after a new oil change. --%>
      <div
        id={@id}
        class="dos-qr-symbol"
        phx-hook="QrSymbol"
        phx-update="ignore"
        data-payload={@payload}
        role="img"
        aria-label={Copy.qr_alt()}
      >
      </div>

      <figcaption class="dos-qr-caption">
        <code class="dos-qr-key" data-test="sticker-qr-key">{@code}</code>
        <span class="dos-qr-note">{Copy.qr_note()}</span>
      </figcaption>
    </figure>
    """
  end
end
