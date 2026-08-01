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
 * Storage that accepts writes and then starts refusing them — approximates: a
 * profile that fills up mid-session, which is when a quota error actually
 * reaches a user. `afterWrites` lets the app's own start-up probe succeed, so
 * the app reaches its normal storage mode and the failure lands on a real
 * record write rather than on availability detection.
 *
 * Does NOT approximate: real quota accounting, partial writes, or the browser
 * rolling back a transaction that already reported success. The genuinely
 * measured quota path needs a device with real storage pressure and is
 * scheduled in the manual matrix.
 */
export async function failWritesAfter(context, errorName, afterWrites = 4) {
  await context.addInitScript(
    ({ name, after }) => {
      let writes = 0
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
              let store
              try {
                store = tx.objectStore(storeName)
              } catch {
                continue
              }
              for (const op of ['put', 'add']) {
                const real = store[op].bind(store)
                store[op] = (...opArgs) => {
                  writes += 1
                  const req = real(...opArgs)
                  if (writes > after) {
                    // Arrives asynchronously, the way a real rejection does.
                    setTimeout(() => {
                      const err = new DOMException('simulated quota exhaustion', name)
                      Object.defineProperty(req, 'error', { configurable: true, get: () => err })
                      req.dispatchEvent(new Event('error'))
                      try {
                        tx.abort()
                      } catch {}
                    }, 0)
                  }
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
    { name: errorName, after: afterWrites }
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
