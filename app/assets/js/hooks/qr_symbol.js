// Draws the QR symbol for the sticker.
//
// The code itself is computed server-side by DigitalOilSticker.StickerCode and
// arrives in `data-payload` — there is exactly one canonical encoder and this
// is not it. What happens here is only rendering.
//
// The element is `phx-update="ignore"` so LiveView leaves the injected SVG
// alone, but attribute changes still reach it and still fire `updated()`. That
// is what redraws the symbol when a new oil change is logged.

import {toSvg} from "../sticker_qr.js"

export const QrSymbol = {
  mounted() {
    this.draw()
  },

  updated() {
    this.draw()
  },

  draw() {
    const payload = this.el.dataset.payload

    if (!payload) return this.giveUp()

    // Already drawn for this payload. Without this guard, any unrelated
    // attribute change would re-run the encoder — cheap, but it also discards
    // and rebuilds the SVG under a scanner that may be mid-read.
    if (this.el.dataset.drawnFor === payload) return

    // MEDIUM rather than QUARTILE: measured on real hardware, both decode down
    // to the same ~1.6 device pixels per module, so the extra recovery capacity
    // buys nothing here and costs four modules of density. Print, where the
    // symbol can actually get damaged, is a different decision and is made
    // where the print artwork is generated.
    const result = toSvg(payload, {ecc: "medium"})

    if (!result.ok) return this.giveUp()

    this.el.innerHTML = result.svg
    this.el.dataset.drawnFor = payload
    this.el.removeAttribute("data-qr-failed")
  },

  // A symbol that cannot be drawn leaves nothing behind. The printed code below
  // it is the record; a broken or stale image next to it would be worse than an
  // empty box, because it looks scannable.
  giveUp() {
    this.el.innerHTML = ""
    delete this.el.dataset.drawnFor
    this.el.setAttribute("data-qr-failed", "true")
  },
}
