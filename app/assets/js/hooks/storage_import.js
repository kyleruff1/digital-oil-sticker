// Import an export file into this browser's store. ENTIRELY client-side: the
// file is read here, validated here, and written to IndexedDB here. It never
// travels to the server — the records are personal data (INV-23/26), and the
// whole point of "stored in this browser" is that no server ever holds them.
//
// The element this hook mounts on is phx-update="ignore": LiveView renders the
// frame and every string (they live in the copy catalog, where the copy-lint
// can see them), and this hook only toggles visibility and fills in counts.
//
// The flow is choose → preview → confirm, and the confirm replaces the store
// WHOLESALE. A merge would need per-record conflict answers the user cannot
// give about a store they can no longer see — the import exists for exactly
// the evicted-store case.

import * as idb from "../local_store/idb.js"
import {SCHEMA_VERSION} from "../local_store/schema.js"
import {markHasData} from "../local_store/boot_hint.js"

const RECORD_STORES = ["vehicles", "events", "readings", "usage", "reminders"]

export const StorageImport = {
  mounted() {
    this.file = null
    this.parsed = null

    this.input = this.el.querySelector("input[type=file]")
    this.preview = this.el.querySelector("[data-import-preview]")
    this.error = this.el.querySelector("[data-import-error]")
    this.errorText = this.el.querySelector("[data-import-error-text]")

    this.input.addEventListener("change", () => this.inspect())
    this.el.querySelector("[data-import-confirm]").addEventListener("click", () => this.commit())
    this.el.querySelector("[data-import-cancel]").addEventListener("click", () => this.reset())
  },

  reset() {
    this.parsed = null
    this.input.value = ""
    this.preview.hidden = true
    this.error.hidden = true
  },

  showError(kind) {
    // The messages are server-rendered spans keyed by kind; this only picks
    // which one is visible. No free text is composed here.
    this.preview.hidden = true
    this.error.hidden = false
    for (const line of this.errorText.querySelectorAll("[data-error-kind]")) {
      line.hidden = line.dataset.errorKind !== kind
    }
  },

  async inspect() {
    const file = this.input.files && this.input.files[0]
    if (!file) return this.reset()

    let parsed
    try {
      parsed = JSON.parse(await file.text())
    } catch {
      return this.showError("invalid")
    }

    if (!parsed || parsed.envelope !== "dos_local" || typeof parsed.data !== "object") {
      return this.showError("invalid")
    }

    if (!Number.isInteger(parsed.schema_version)) return this.showError("invalid")

    // A file from a NEWER release is refused, not guessed at — the same rule
    // the hydration path applies to a newer stored schema.
    if (parsed.schema_version > SCHEMA_VERSION) return this.showError("newer")

    for (const store of RECORD_STORES) {
      if (!Array.isArray(parsed.data[store] || [])) return this.showError("invalid")
    }

    // Integrity: the export wrote a SHA-256 over the payload with exported_at
    // and the hash itself excluded. Spread order preserves the original key
    // order, so the reconstruction stringifies byte-identically.
    const verdict = await this.verifyHash(parsed)
    if (verdict === "mismatch") return this.showError("damaged")

    this.parsed = parsed
    this.error.hidden = true
    this.fillPreview(parsed)
    this.preview.hidden = false
  },

  async verifyHash(parsed) {
    if (typeof parsed.sha256 !== "string") return "absent"

    try {
      const {sha256: _sha, exported_at: _at, ...payload} = parsed
      const bytes = new TextEncoder().encode(JSON.stringify(payload))
      const digest = await crypto.subtle.digest("SHA-256", bytes)
      const hex = [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("")
      return hex === parsed.sha256 ? "ok" : "mismatch"
    } catch {
      // No SubtleCrypto (insecure context): integrity simply goes unchecked
      // rather than blocking the recovery path it exists to protect.
      return "unverifiable"
    }
  },

  fillPreview(parsed) {
    const counts = {
      vehicles: (parsed.data.vehicles || []).length,
      events: (parsed.data.events || []).length,
      exported: typeof parsed.exported_at === "string" ? parsed.exported_at.slice(0, 10) : "—",
    }
    for (const slot of this.el.querySelectorAll("[data-import-slot]")) {
      slot.textContent = counts[slot.dataset.importSlot]
    }
  },

  async commit() {
    if (!this.parsed) return

    const opened = await idb.openDatabase()
    if (!opened.ok) return this.showError("storage")

    const result = await idb.replaceAll(opened.db, this.parsed.data, {
      schemaVersion: this.parsed.schema_version,
      seq: this.parsed.seq,
      nowIso: new Date().toISOString(),
    })
    opened.db.close?.()

    if (!result.ok) return this.showError("storage")

    markHasData()

    // A full reload rather than a protocol dance: every LiveView on this page
    // re-mounts and re-hydrates from the replaced store, and other tabs
    // recover through the seq-conflict → rehydrate path on their next write.
    window.location.reload()
  },
}
