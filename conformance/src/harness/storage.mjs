// Simulation harnesses (FR-6, FR-10, FR-11, FR-13).
//
// Each function states exactly what real-world condition it approximates AND
// what it does not, because a simulation that is mistaken for the real thing is
// worse than no simulation: it converts "we did not test this" into a green
// check. Anything a harness cannot faithfully reproduce is named here and
// reported `unproven` by the case that needs it.

/**
 * Blocked IndexedDB — approximates: a browser or profile setting that refuses
 * IndexedDB entirely, and Firefox private windows historically.
 * Does NOT approximate: a store that opens and then rejects writes partway
 * through a session, or an OS-level disk failure.
 *
 * Installed before any app script runs so the failure is present at the first
 * open, which is when the app decides its storage mode.
 */
export async function blockIndexedDb(context) {
  await context.addInitScript(() => {
    Object.defineProperty(window, 'indexedDB', {
      configurable: true,
      get() {
        throw new DOMException('IndexedDB is blocked in this profile', 'SecurityError')
      },
    })
  })
}

/**
 * Private / incognito window — approximates: a browsing context whose
 * persistent storage is walled off from the profile, which is what every
 * mainstream engine does for private browsing. Firefox private historically
 * refused IndexedDB entirely; Chromium incognito and WebKit private wall IDB
 * per-window and drop it when the window closes. In every case the app must
 * recognise the context as session-only and warn BEFORE the user starts typing
 * something they think is being kept (AC-10).
 *
 * Simulated by blocking IndexedDB at the window level — the same signal the
 * app already reacts to for `storage_mode: :session_only`. This keeps the
 * approximation uniform across engines; Playwright does not expose a real
 * private/incognito mode per newContext, and switching it at browser launch
 * would force per-case relaunching, which the runner is not shaped for.
 *
 * Does NOT approximate: real quota walls, localStorage lifetime differences,
 * or tab-close eviction — those need a device under a real private window and
 * are scheduled in the manual matrix.
 */
export async function enterPrivateMode(context) {
  await context.addInitScript(() => {
    Object.defineProperty(window, 'indexedDB', {
      configurable: true,
      get() {
        throw new DOMException('IndexedDB is unavailable in this private window', 'SecurityError')
      },
    })
  })
}

/**
 * Storage that refuses writes to the RECORD stores while still accepting the
 * app's start-up probe — approximates: a profile that fills up mid-session,
 * which is when a quota error actually reaches a user.
 *
 * Targeting by store rather than by a write COUNT is the whole point. Counting
 * assumed every engine performs the same number of writes before the first
 * real record lands, and it does not: the same magic number that reproduced a
 * refusal on Chromium let the write straight through on WebKit, so the case
 * reported a missing notice when there had been nothing to report. That is a
 * harness reading as a product defect, which is worse than no harness.
 *
 * The app's probe writes to `meta` (see probeRoundTrip in idb.js), so leaving
 * `meta` alone means storage detection succeeds and the failure lands exactly
 * where it should — on the user's record.
 *
 * Does NOT approximate: real quota accounting, partial writes, or the browser
 * rolling back a transaction that already reported success. The genuinely
 * measured quota path needs a device under real storage pressure and is
 * scheduled in the manual matrix.
 */
export async function failWritesToRecordStores(context, errorName) {
  await context.addInitScript(
    ({ name, targets }) => {
      const realOpen = indexedDB.open.bind(indexedDB)
      indexedDB.open = (...args) => {
        const request = realOpen(...args)
        request.addEventListener('success', () => {
          const db = request.result
          const realTransaction = db.transaction.bind(db)
          db.transaction = (stores, mode, ...rest) => {
            const tx = realTransaction(stores, mode, ...rest)
            if (mode !== 'readwrite') return tx

            for (const storeName of [].concat(stores)) {
              if (!targets.includes(storeName)) continue

              let store
              try {
                store = tx.objectStore(storeName)
              } catch {
                continue
              }
              for (const op of ['put', 'add']) {
                const real = store[op].bind(store)
                store[op] = (...opArgs) => {
                  const req = real(...opArgs)
                  // Arrives asynchronously, the way a real rejection does.
                  setTimeout(() => {
                    const err = new DOMException('simulated quota exhaustion', name)
                    Object.defineProperty(req, 'error', { configurable: true, get: () => err })
                    req.dispatchEvent(new Event('error'))
                    try {
                      tx.abort()
                    } catch {}
                  }, 0)
                  return req
                }
              }
            }
            return tx
          }
        })
        return request
      }
    },
    { name: errorName, targets: ['events', 'readings', 'vehicles'] }
  )
}

/**
 * An evicted or cleared store with the boot hint left behind — approximates:
 * the browser reclaiming origin storage, or the user clearing site data while
 * localStorage survives. This is the `:data_missing` trigger.
 *
 * Does NOT approximate: real eviction pressure or its timing. Whether a browser
 * evicts at all, and after how long, is unmeasured — see
 * `conformance/observations/eviction.md`.
 */
export async function evictStoreKeepingHint(page) {
  // The app's hook holds an open connection, and an open connection BLOCKS
  // deleteDatabase. Chromium happened to tear ours down in time; WebKit
  // reported `blocked` and the database survived, so the case "failed" against
  // a store that was never actually evicted. Navigating away first destroys the
  // hook and closes the connection, which is also what a real eviction implies:
  // the page is not open.
  const origin = new URL(page.url()).origin
  await page.goto('about:blank')
  await page.goto(`${origin}/robots.txt`, { waitUntil: 'load' })

  const deleted = await deleteDatabases(page)
  if (!deleted) throw new Error('IndexedDB deletion was blocked; the eviction harness did not evict anything')

  await page.evaluate(() => localStorage.setItem('dos_boot_state', 'has_data'))
}

// Resolves false rather than hanging when a delete is blocked, so a harness
// that did not do its job says so instead of producing a misleading result.
async function deleteDatabases(page) {
  return page.evaluate(async () => {
    const names = (await indexedDB.databases?.())?.map(d => d.name) ?? ['dos_local']

    const results = await Promise.all(
      names.map(
        name =>
          new Promise(resolve => {
            const req = indexedDB.deleteDatabase(name)
            req.onsuccess = () => resolve(true)
            req.onerror = () => resolve(false)
            req.onblocked = () => resolve(false)
            setTimeout(() => resolve(false), 3000)
          })
      )
    )
    return results.every(Boolean)
  })
}

/**
 * Seed the `meta` singleton with a caller-chosen `schema_version` — approximates:
 * a browser that last opened the app under a release newer than the one now
 * running, so its stored `meta.schema_version` exceeds the server's. The app's
 * own protocol cannot produce this state legally (its writes always stamp the
 * current SCHEMA_VERSION), so a direct IndexedDB seed is the only faithful
 * driver of the FR-9 newer-than-server branch. DOS-M09-008's data-and-persistence
 * contract permits direct seeding for exactly this "state the adapter cannot
 * legally produce" case.
 *
 * Opens `dos_local` at IDB_VERSION 1, creating the full store layout in the
 * upgrade path so callers can seed either before the app has ever booted or
 * after (the app's own open at the same version is a no-op when the stores
 * already exist). Closes its own connection before returning, so a subsequent
 * app open is not blocked by a lingering handle.
 *
 * Does NOT approximate: the process of arriving at a newer version in the
 * first place (a real migration or upgrade), or any record content beyond
 * the meta singleton — this seeds the version marker only.
 */
export async function seedNewerSchemaMeta(page, { schemaVersion, seq = 1 } = {}) {
  await page.evaluate(async ({ schemaVersion, seq }) => {
    const openDb = () =>
      new Promise((resolve, reject) => {
        const req = indexedDB.open('dos_local', 1)
        req.onupgradeneeded = () => {
          const db = req.result
          if (!db.objectStoreNames.contains('meta')) db.createObjectStore('meta')
          for (const [name, keyPath] of [
            ['vehicles', 'vehicle_id'],
            ['events', 'event_id'],
            ['readings', 'reading_id'],
            ['usage', 'usage_id'],
            ['reminders', 'reminder_id'],
          ]) {
            if (!db.objectStoreNames.contains(name)) {
              db.createObjectStore(name, { keyPath })
            }
          }
          if (!db.objectStoreNames.contains('prefs')) db.createObjectStore('prefs')
        }
        req.onblocked = () => reject(new Error('open blocked'))
        req.onsuccess = () => resolve(req.result)
        req.onerror = () => reject(req.error || new Error('open failed'))
      })

    const db = await openDb()
    try {
      await new Promise((resolve, reject) => {
        const tx = db.transaction('meta', 'readwrite')
        tx.oncomplete = () => resolve()
        tx.onerror = () => reject(tx.error)
        tx.onabort = () => reject(tx.error)
        const now = new Date().toISOString()
        tx.objectStore('meta').put(
          { schema_version: schemaVersion, seq, created_at: now, last_write_at: now },
          'meta'
        )
      })
    } finally {
      db.close()
    }
  }, { schemaVersion, seq })
}

/**
 * BroadcastChannel absent — approximates: engines or contexts that do not
 * expose it. The compare-and-set on `meta.seq` must still prevent lost updates
 * without it (FR-13); only the promptness of cross-tab notification degrades.
 */
export async function removeBroadcastChannel(context) {
  await context.addInitScript(() => {
    delete window.BroadcastChannel
  })
}

/** Wipe everything, including the boot hint: a genuine first visit. */
export async function clearAll(page) {
  const origin = new URL(page.url()).origin
  await page.goto('about:blank')
  await page.goto(`${origin}/robots.txt`, { waitUntil: 'load' })

  await deleteDatabases(page)
  await page.evaluate(() => {
    localStorage.clear()
    sessionStorage.clear()
  })
}

/** Everything localStorage holds, so the suite can assert the app writes only
 * the non-personal boot hint there (and Phoenix's own theme key). */
export async function localStorageDump(page) {
  return page.evaluate(() => Object.fromEntries(Object.entries(localStorage)))
}
