// Hands the generated calendar file to the browser as a download.
//
// The file is built server-side, in DigitalOilSticker.CalendarExport, and
// arrives in `data-ics`. The DOWNLOAD is done here rather than through a route
// because a route would need the due date, the mileage, and the vehicle label
// to reach it somehow — in a URL, a query string, or a session — and all three
// end up in access logs (INV-26). A Blob built from markup the browser already
// has makes no request at all.

export const CalendarDownload = {
  mounted() {
    this.onClick = event => this.download(event)
    this.el.addEventListener("click", this.onClick)
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick)
  },

  download(event) {
    event.preventDefault()

    const raw = this.el.dataset.ics
    if (!raw) return

    // Re-normalized to CRLF regardless of what the attribute round-trip did to
    // the line endings: RFC 5545 requires CRLF, and some calendar clients
    // reject a bare-LF file outright.
    const ics = raw.replace(/\r?\n/g, "\r\n")

    const url = URL.createObjectURL(new Blob([ics], {type: "text/calendar;charset=utf-8"}))
    const link = document.createElement("a")

    link.href = url
    link.download = this.el.dataset.filename || "reminder.ics"
    link.rel = "noopener"

    // Appended rather than clicked detached: Firefox ignores a click on an
    // anchor that is not in the document.
    document.body.appendChild(link)
    link.click()
    link.remove()

    // Not revoked synchronously — Safari cancels a download whose blob URL is
    // released in the same tick as the click.
    setTimeout(() => URL.revokeObjectURL(url), 30_000)
  },
}
