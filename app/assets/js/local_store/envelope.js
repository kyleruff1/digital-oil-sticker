// The single payload envelope shape shared by hydrate, write-back, and export
// (DOS-M09-002 FR-2). `storage` is a transient sibling describing this session's
// storage condition; it and `tab_id` are ephemeral and must never reach a file
// the user keeps (export.js strips both).

export function buildEnvelope({schemaVersion, seq, tabId, nowIso, data, storage}) {
  return {
    envelope: "dos_local",
    schema_version: schemaVersion,
    seq,
    tab_id: tabId,
    generated_at: nowIso,
    data,
    storage,
  }
}

/** The empty data payload: singletons null, record stores empty. */
export function emptyData() {
  return {
    meta: null,
    vehicles: [],
    events: [],
    readings: [],
    usage: [],
    reminders: [],
    prefs: null,
  }
}
