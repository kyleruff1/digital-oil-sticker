// Storage-behavior cases: the ones that actually break users.

import { PASS, FAIL, UNPROVEN } from '../report.mjs'
import * as harness from '../harness/storage.mjs'
import * as app from '../harness/app.mjs'

// Copy that must never appear before hydration resolves (INV-24.3). A cheerful
// empty-garage claim in even one frame is a lie about the user's data.
const EMPTY_GARAGE_CLAIMS = [/Set up your first vehicle/i, /No vehicle is set up/i]

const STORAGE_UNAVAILABLE = /storage could not be used/i
const DATA_MISSING = /stored records are gone/i

export const cases = [
  {
    id: 'availability.ladder',
    // Installs a context-level init script, which Playwright cannot remove.
    // On a CDP-attached browser (real Android Chrome) that would leak into every
    // later case, so the device runner restarts the browser around it.
    needsFreshContext: true,
    requirement: 'FR-6',
    async run({ page, context, baseUrl }) {
      // Blocked IndexedDB must yield session-only + a banner, and must NOT
      // fall back to localStorage for records or to the server.
      await harness.blockIndexedDb(context)
      await app.gotoConnected(page, baseUrl)
      await page.waitForTimeout(2500)

      const text = await page.innerText('body')
      if (!STORAGE_UNAVAILABLE.test(text)) {
        return { status: FAIL, detail: `blocked IndexedDB did not surface the storage-unavailable state; saw: ${text.slice(0, 200)}` }
      }

      const ls = await harness.localStorageDump(page)
      const recordish = Object.entries(ls).filter(([k]) => k !== 'dos_boot_state' && !k.startsWith('phx:'))
      if (recordish.length) {
        return { status: FAIL, detail: `records fell back to localStorage: keys ${recordish.map(([k]) => k).join(', ')}` }
      }

      return { status: PASS, evidence: { localStorageKeys: Object.keys(ls) } }
    },
  },

  {
    id: 'hydration.no-empty-claim-before-resolution',
    requirement: 'FR-7',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)

      const { frames, resolved } = await app.captureFramesUntil(
        page,
        baseUrl,
        text => EMPTY_GARAGE_CLAIMS.some(re => re.test(text)) || /DATE/.test(text)
      )

      if (!resolved) {
        return { status: FAIL, detail: 'hydration neither resolved nor surfaced a failure state within the budget' }
      }

      // Every frame BEFORE the last must be free of the claim: the resolved
      // frame is allowed to say the garage is empty, because by then it knows.
      const premature = frames.slice(0, -1).findIndex(f => EMPTY_GARAGE_CLAIMS.some(re => re.test(f)))
      if (premature !== -1) {
        return { status: FAIL, detail: `frame ${premature} of ${frames.length} claimed an empty garage before hydration resolved` }
      }

      return { status: PASS, evidence: { frames: frames.length } }
    },
  },

  {
    id: 'hydration.idempotent',
    requirement: 'FR-8',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      const before = await app.readStore(page)
      await page.reload({ waitUntil: 'load' })
      await page.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected())
      await page.waitForTimeout(2000)
      const after = await app.readStore(page)

      if (JSON.stringify(before) !== JSON.stringify(after)) {
        return { status: FAIL, detail: 'hydrating the same payload twice changed the store — hydration is writing back' }
      }
      return { status: PASS }
    },
  },

  {
    id: 'hydration.reconnect-no-skeleton-teardown',
    requirement: 'FR-8',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await app.logOilChange(page, baseUrl)
      await page.waitForTimeout(1500)

      const beforeText = await page.innerText('body')

      // Drop the socket the way a deploy or a network blip does.
      await page.evaluate(() => window.liveSocket && window.liveSocket.disconnect())
      await page.waitForTimeout(500)
      await page.evaluate(() => window.liveSocket && window.liveSocket.connect())
      await page.waitForTimeout(3000)

      const afterText = await page.innerText('body')

      if (EMPTY_GARAGE_CLAIMS.some(re => re.test(afterText)) && !EMPTY_GARAGE_CLAIMS.some(re => re.test(beforeText))) {
        return { status: FAIL, detail: 'reconnect tore the view down to an empty-garage state' }
      }
      // The sticker's own values must come back.
      const hadDate = /DATE/.test(beforeText)
      if (hadDate && !/DATE/.test(afterText)) {
        return { status: FAIL, detail: 'reconnect did not restore the hydrated view' }
      }
      return { status: PASS }
    },
  },

  {
    id: 'eviction.data-missing-distinct-from-first-visit',
    requirement: 'FR-10',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      await harness.evictStoreKeepingHint(page)
      await app.gotoConnected(page, baseUrl)
      await page.waitForTimeout(2500)
      const evicted = await page.innerText('body')

      if (!DATA_MISSING.test(evicted)) {
        return { status: FAIL, detail: `evicted store did not render the data-missing state; saw: ${evicted.slice(0, 200)}` }
      }

      // And a genuine first visit must read differently.
      await harness.clearAll(page)
      await app.gotoConnected(page, baseUrl)
      await page.waitForTimeout(2500)
      const fresh = await page.innerText('body')

      if (DATA_MISSING.test(fresh)) {
        return { status: FAIL, detail: 'a genuine first visit rendered the data-missing state' }
      }
      return { status: PASS }
    },
  },

  {
    id: 'quota.exhaustion-is-honest',
    // Installs a context-level init script, which Playwright cannot remove.
    // On a CDP-attached browser (real Android Chrome) that would leak into every
    // later case, so the device runner restarts the browser around it.
    needsFreshContext: true,
    requirement: 'FR-11',
    async run({ page, context, baseUrl }) {
      // Set a vehicle up on healthy storage first, so there is prior state
      // whose survival can be checked, then make the store start refusing.
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      const before = await app.readStore(page)

      // Targeted at the record stores, not at a write count. A count assumed
      // every engine performs the same number of writes before the first real
      // record lands; it does not, and the same number that reproduced a
      // refusal on Chromium let the write straight through on WebKit.
      await harness.failWritesToRecordStores(context, 'QuotaExceededError')
      await app.gotoConnected(page, `${baseUrl}/service/new`)

      try {
        await app.logOilChange(page, baseUrl, { odometer: '55000' })
      } catch {
        // Staying on the form is a legitimate response to a failed write.
      }
      // Poll rather than sample once. The notice arrives after an IndexedDB
      // round trip plus a server ack, and how long that takes differs per
      // engine — sampling at a fixed delay failed on CI's WebKit while passing
      // locally, which is a property of the harness, not of the application.
      let honest = false
      let text = ''
      const deadline = Date.now() + 25_000

      while (Date.now() < deadline) {
        text = await page.innerText('body').catch(() => '')
        honest = /Not saved to this browser|storage is full|could not be used/i.test(text)
        if (honest) break
        await page.waitForTimeout(500)
      }

      if (!honest) {
        return {
          status: FAIL,
          detail: `a write that failed with QuotaExceededError produced no honest notice; saw: ${text.slice(0, 220)}`,
        }
      }

      // Prior state must survive: a failed write may not take existing records
      // with it.
      const after = await app.readStore(page)
      const lost = (before.vehicles || []).length > (after.vehicles || []).length
      if (lost) {
        return { status: FAIL, detail: 'a failed write destroyed previously stored records' }
      }

      return { status: PASS, evidence: { vehiclesBefore: (before.vehicles || []).length, vehiclesAfter: (after.vehicles || []).length } }
    },
  },

  {
    id: 'multitab.propagation-and-compare-and-set',
    requirement: 'FR-13',
    async run({ context, baseUrl }) {
      const a = await context.newPage()
      const b = await context.newPage()

      await app.gotoConnected(a, baseUrl)
      await harness.clearAll(a)
      await app.setUpVehicle(a, baseUrl)

      await app.gotoConnected(b, baseUrl)
      await b.waitForTimeout(2500)
      const bText = await b.innerText('body')

      if (EMPTY_GARAGE_CLAIMS.some(re => re.test(bText))) {
        await a.close(); await b.close()
        return { status: FAIL, detail: 'a second tab did not see the first tab’s committed vehicle' }
      }

      // Now commit in A again and confirm B converges rather than clobbering.
      await app.logOilChange(a, baseUrl)
      await a.waitForTimeout(1500)
      await b.waitForTimeout(2500)

      const storeA = await app.readStore(a)
      const storeB = await app.readStore(b)
      await a.close(); await b.close()

      if (JSON.stringify(storeA.events) !== JSON.stringify(storeB.events)) {
        return { status: FAIL, detail: 'tabs diverged on the events store after a commit' }
      }
      return { status: PASS, evidence: { events: (storeA.events || []).length } }
    },
  },

  {
    id: 'multitab.safe-without-broadcastchannel',
    // Installs a context-level init script, which Playwright cannot remove.
    // On a CDP-attached browser (real Android Chrome) that would leak into every
    // later case, so the device runner restarts the browser around it.
    needsFreshContext: true,
    requirement: 'FR-13',
    async run({ context, baseUrl }) {
      await harness.removeBroadcastChannel(context)
      const a = await context.newPage()
      const b = await context.newPage()

      await app.gotoConnected(a, baseUrl)
      await harness.clearAll(a)
      await app.setUpVehicle(a, baseUrl)
      await a.waitForTimeout(1000)

      // Without BroadcastChannel, B learns on its next hydration, not sooner.
      await app.gotoConnected(b, baseUrl)
      await b.waitForTimeout(2500)
      const storeB = await app.readStore(b)
      const vehicles = (storeB.vehicles || []).length

      await a.close(); await b.close()

      if (vehicles !== 1) {
        return { status: FAIL, detail: `without BroadcastChannel the store held ${vehicles} vehicles; a lost update or a duplicate` }
      }
      return { status: PASS }
    },
  },

  {
    id: 'export.round-trip',
    requirement: 'FR-14',
    async run() {
      // Honest reporting beats a green check: the application has an export
      // path and no import path (DOS-M05-007), so this cannot be exercised.
      return {
        status: UNPROVEN,
        detail:
          'the app ships export but no import, so export -> clear -> import cannot be run. ' +
          'Import is DOS-M05-007 scope; until it exists this assertion is unrunnable, not passing.',
      }
    },
  },

  {
    id: 'import.catalog-references-re-resolved',
    requirement: 'FR-15',
    async run() {
      return {
        status: UNPROVEN,
        detail: 'depends on the import path, which does not exist yet (DOS-M05-007)',
      }
    },
  },

  {
    id: 'migration.forward-from-recorded-fixtures',
    requirement: 'FR-9',
    async run() {
      return {
        status: UNPROVEN,
        detail:
          'schema_version 1 is the only version ever shipped, so no prior-version fixture exists to migrate from. ' +
          'This becomes runnable at the first schema bump and is unproven — not passing — until then.',
      }
    },
  },
]
