// User-initiated export (INV-4, INV-5): produced entirely client-side with no
// server round trip. The file carries only the user's own records plus a
// SHA-256 integrity hash computed over the payload with the hash field excluded.

async function sha256Hex(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, "0")).join("")
}

/** Serialize the envelope, hash it, and trigger a download named
 * dos-export-<date>.json. `tab_id` and `storage` are ephemeral session values
 * and are stripped so no exported file can carry them (DOS-M09-001 FR-17). */
export async function exportFile(envelopeData, nowIso) {
  try {
    const {tab_id: _tabId, storage: _storage, ...exportable} = envelopeData
    const payloadJson = JSON.stringify(exportable)
    const sha256 = await sha256Hex(payloadJson)
    const file = {...exportable, exported_at: nowIso, sha256}

    const blob = new Blob([JSON.stringify(file)], {type: "application/json"})
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement("a")
    anchor.href = url
    anchor.download = `dos-export-${nowIso.slice(0, 10)}.json`
    document.body.appendChild(anchor)
    anchor.click()
    anchor.remove()
    URL.revokeObjectURL(url)
    return {ok: true}
  } catch {
    // Error kind only — never the payload.
    return {ok: false, error: {kind: "unknown"}}
  }
}
