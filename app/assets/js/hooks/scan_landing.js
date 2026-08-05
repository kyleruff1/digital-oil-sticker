// Reads the sticker code from the URL fragment and hands it to the LiveView.
//
// The fragment is where the code lives, on purpose (see StickerQr's moduledoc
// on the server): a fragment is never sent to the server, so the date, the
// odometer, and the grade the code carries never appear on any request line
// between here and the browser (INV-26). The hook is the piece of that
// contract on the browser side.
//
// The empty string on `location.hash.slice(1)` is a real value, not a bug:
// visiting `/s` bare (no `#…`) hands the LiveView an empty payload, which is
// what it uses to route to the "scan a sticker" fallback.

export const ScanLanding = {
  mounted() {
    const code = window.location.hash.startsWith("#")
      ? window.location.hash.slice(1)
      : ""

    this.pushEvent("scan_code", {code})
  },
}
