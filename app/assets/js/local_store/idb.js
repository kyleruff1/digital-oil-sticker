// The only module in the app permitted to touch IndexedDB (DOS-M09-001).
// Every exported function resolves to a tagged result — {ok: true, ...} or
// {ok: false, error: {kind}} — and never throws across the module boundary.
// Errors are reported as kinds only; no record content is ever logged.

import {DB_NAME, IDB_VERSION, SCHEMA_VERSION, STORES, STORE_NAMES, META_KEY} from "./schema.js"

const PROBE_KEY = "__probe"

/** Map a DOM exception to a typed error kind. Kinds not derivable from an
 * exception (blocked, conflict, probe_failed) are assigned by the flow that
 * detects them, not here. */
export function classifyError(err) {
  switch (err && err.name) {
    case "QuotaExceededError":
      return "quota_exceeded"
    case "VersionError":
      return "version_error"
    case "SecurityError":
    case "InvalidStateError":
    case "UnknownError":
      return "unavailable"
    case "NotFoundError":
    case "ConstraintError":
      return "upgrade_failed"
    default:
      return "unknown"
  }
}

function fail(kind, extra) {
  return {ok: false, error: {kind, ...extra}}
}

function failFrom(err) {
  return fail(classifyError(err))
}

// Ordered structural upgrades. Forward-only and additive: createObjectStore /
// createIndex only — no upgrade step ever deletes a store that could hold data.
function runUpgrade(db, upgradeTx) {
  for (const [name, def] of Object.entries(STORES)) {
    let store
    if (db.objectStoreNames.contains(name)) {
      store = upgradeTx.objectStore(name)
    } else {
      store = def.keyPath
        ? db.createObjectStore(name, {keyPath: def.keyPath})
        : db.createObjectStore(name)
    }
    for (const idx of def.indexes) {
      if (!store.indexNames.contains(idx.name)) {
        store.createIndex(idx.name, idx.keyPath)
      }
    }
  }
}

export function openDatabase() {
  return new Promise(resolve => {
    let factory
    try {
      factory = globalThis.indexedDB
    } catch {
      factory = undefined
    }
    if (!factory) return resolve(fail("unavailable"))

    let request
    try {
      request = factory.open(DB_NAME, IDB_VERSION)
    } catch (err) {
      return resolve(failFrom(err))
    }

    request.onblocked = () => resolve(fail("blocked"))
    request.onupgradeneeded = () => {
      try {
        runUpgrade(request.result, request.transaction)
      } catch {
        try {
          request.transaction.abort()
        } catch {
          // already aborted
        }
        resolve(fail("upgrade_failed"))
      }
    }
    request.onerror = () => resolve(failFrom(request.error))
    request.onsuccess = () => resolve({ok: true, db: request.result})
  })
}

/** Prove the database is actually writable (private-browsing and blocked-storage
 * modes can open a database that then rejects writes): put/get/delete a probe
 * record in `meta` under a reserved key that readAll can never surface. */
export function probeRoundTrip(db) {
  return new Promise(resolve => {
    let tx
    try {
      tx = db.transaction(META_KEY, "readwrite")
    } catch {
      return resolve(fail("probe_failed"))
    }
    tx.onabort = () => resolve(fail("probe_failed"))
    tx.onerror = () => resolve(fail("probe_failed"))
    tx.oncomplete = () => resolve({ok: true})

    const store = tx.objectStore(META_KEY)
    const putReq = store.put({probe: true}, PROBE_KEY)
    putReq.onsuccess = () => {
      const getReq = store.get(PROBE_KEY)
      getReq.onsuccess = () => store.delete(PROBE_KEY)
    }
  })
}

/** Read every store in ONE readonly transaction. Singleton stores (meta, prefs)
 * yield the object or null; record stores yield arrays. */
export function readAll(db) {
  return new Promise(resolve => {
    let tx
    try {
      tx = db.transaction(STORE_NAMES, "readonly")
    } catch (err) {
      return resolve(failFrom(err))
    }
    tx.onabort = () => resolve(failFrom(tx.error))
    tx.onerror = () => resolve(failFrom(tx.error))

    const data = {}
    for (const name of STORE_NAMES) {
      const def = STORES[name]
      const store = tx.objectStore(name)
      if (def.keyPath === null) {
        // Read by exact singleton key — never getAll — so a leaked probe record
        // under any other key can never reach an envelope.
        const req = store.get(def.singletonKey)
        req.onsuccess = () => {
          data[name] = req.result === undefined ? null : req.result
        }
      } else {
        const req = store.getAll()
        req.onsuccess = () => {
          data[name] = req.result || []
        }
      }
    }

    tx.oncomplete = () => resolve({ok: true, data})
  })
}

/** Apply a server-issued write instruction in ONE readwrite transaction across
 * the affected stores plus meta, guarded by a compare-and-set on meta.seq so a
 * stale tab can never silently overwrite newer records (INV-24.7).
 *
 * `nowIso` is supplied by the caller: this module never reads the clock, so its
 * behavior is a pure function of its inputs and is testable without fakes. */
export function applyPut(db, payload, nowIso) {
  const upserts = payload.upserts || []
  const deletes = payload.deletes || []
  const seq = payload.seq

  return new Promise(resolve => {
    const names = new Set([META_KEY])
    for (const u of upserts) names.add(u.store)
    for (const d of deletes) names.add(d.store)

    let tx
    try {
      tx = db.transaction([...names], "readwrite")
    } catch (err) {
      return resolve(failFrom(err))
    }

    // Set before an intentional abort so onabort reports the true cause
    // (conflict) instead of a generic transaction error.
    let result = null
    tx.onabort = () => resolve(result || failFrom(tx.error))
    tx.onerror = () => {
      // Request-level errors (e.g. QuotaExceededError) abort the transaction;
      // onabort resolves with the classified kind.
    }
    tx.oncomplete = () => resolve(result || {ok: true})

    const metaStore = tx.objectStore(META_KEY)
    const getReq = metaStore.get(META_KEY)
    getReq.onsuccess = () => {
      const stored = getReq.result || null
      const foundSeq = stored && typeof stored.seq === "number" ? stored.seq : 0
      if (foundSeq !== seq - 1) {
        result = fail("conflict", {expected_seq: seq - 1, found_seq: foundSeq})
        try {
          tx.abort()
        } catch {
          // already aborted
        }
        return
      }
      try {
        for (const {store, record} of upserts) {
          const def = STORES[store]
          const os = tx.objectStore(store)
          if (def && def.keyPath === null) {
            os.put(record, def.singletonKey)
          } else {
            os.put(record)
          }
        }
        for (const {store, key} of deletes) {
          tx.objectStore(store).delete(key)
        }
        const nextMeta = {
          ...(stored || {created_at: nowIso}),
          seq,
          schema_version: (stored && stored.schema_version) || SCHEMA_VERSION,
          last_write_at: nowIso,
        }
        metaStore.put(nextMeta, META_KEY)
      } catch (err) {
        result = failFrom(err)
        try {
          tx.abort()
        } catch {
          // already aborted
        }
      }
    }
  })
}

/** Ask the browser for persistent (eviction-exempt) storage. */
export async function requestPersistence() {
  try {
    if (!navigator.storage || typeof navigator.storage.persist !== "function") {
      return "unavailable"
    }
    return (await navigator.storage.persist()) ? "granted" : "denied"
  } catch {
    return "unavailable"
  }
}

/** Report the browser's own usage/quota estimate, or null — never a fabricated
 * figure (INV-15 spirit: no invented facts, storage included). */
export async function estimateQuota() {
  try {
    if (!navigator.storage || typeof navigator.storage.estimate !== "function") {
      return null
    }
    const est = await navigator.storage.estimate()
    if (!est || typeof est.usage !== "number" || typeof est.quota !== "number") {
      return null
    }
    return {usage: est.usage, quota: est.quota}
  } catch {
    return null
  }
}

/** Clear every store in one readwrite transaction (user-initiated erase). */
/** Replace the ENTIRE store with an imported envelope's data, in one
 * readwrite transaction: every store cleared, then the file's records written.
 *
 * Deliberately not CAS-guarded like applyPut: an import is the user explicitly
 * choosing the file over whatever is here, stated in those words before this
 * runs. A merge would need per-record conflict answers nobody can give for a
 * store they can no longer see (the import exists for the evicted-store case).
 *
 * The meta singleton comes from the file when it has one, so the seq lineage
 * and "data has existed here" signal survive the trip; a file without meta
 * gets a minimal one, because meta's presence is what distinguishes an
 * intentionally emptied store from an evicted one. */
export function replaceAll(db, data, {schemaVersion, seq, nowIso}) {
  return new Promise(resolve => {
    let tx
    try {
      tx = db.transaction(STORE_NAMES, "readwrite")
    } catch (err) {
      return resolve(failFrom(err))
    }
    tx.onabort = () => resolve(failFrom(tx.error))
    tx.onerror = () => {}
    tx.oncomplete = () => resolve({ok: true})

    try {
      for (const name of STORE_NAMES) {
        const def = STORES[name]
        const os = tx.objectStore(name)
        os.clear()

        if (def.keyPath === null) {
          // last_write_at is a META field; stamping it on prefs would smuggle
          // an alien key into that record's __unknown__ carry-through.
          const value =
            name === META_KEY
              ? {
                  ...(data[name] || {schema_version: schemaVersion, seq: seq || 0, created_at: nowIso}),
                  last_write_at: nowIso,
                }
              : data[name]
          if (value) os.put(value, def.singletonKey)
        } else {
          for (const record of data[name] || []) {
            os.put(record)
          }
        }
      }
    } catch (err) {
      resolve(failFrom(err))
      try {
        tx.abort()
      } catch {
        // already aborted
      }
    }
  })
}

export function eraseAll(db) {
  return new Promise(resolve => {
    let tx
    try {
      tx = db.transaction(STORE_NAMES, "readwrite")
    } catch (err) {
      return resolve(failFrom(err))
    }
    tx.onabort = () => resolve(failFrom(tx.error))
    tx.onerror = () => {}
    tx.oncomplete = () => resolve({ok: true})
    for (const name of STORE_NAMES) {
      tx.objectStore(name).clear()
    }
  })
}
