// Storage-behavior cases: the ones that actually break users.

import { PASS, FAIL, UNPROVEN } from '../report.mjs'
import * as harness from '../harness/storage.mjs'
import * as app from '../harness/app.mjs'

// Copy that must never appear before hydration resolves (INV-24.3). A cheerful
// empty-garage claim in even one frame is a lie about the user's data.
const EMPTY_GARAGE_CLAIMS = [/Set up your first vehicle/i, /No vehicle is set up/i]

const STORAGE_UNAVAILABLE = /storage could not be used/i
const DATA_MISSING = /stored records are gone/i

// AC-5 — the four hydration-state heading substrings, sourced verbatim from
// DigitalOilStickerWeb.Copy in `app/lib/digital_oil_sticker_web/copy.ex`:
//   :hydrating           -> Copy.sr_checking/0            (skeleton carrier)
//   :empty (& :loaded)   -> Copy.empty_heading/0          (first-visit heading)
//   :storage_unavailable -> Copy.storage_unavailable_heading/0
//   :data_missing        -> Copy.data_missing_heading/0
// Held as a map so the mutual-exclusion check reads the same for every state:
// in the state we drove, only that state's heading may match. A regression
// that reused another state's copy — the exact hazard INV-24.3 / INV-25 exist
// to prevent — fails the case on the engine it regressed on.
const HYDRATING_HEADING = /Checking this browser for your records/i
const EMPTY_HEADING = /Set up your first vehicle/i
const STATE_HEADINGS = {
  hydrating: HYDRATING_HEADING,
  empty: EMPTY_HEADING,
  storage_unavailable: STORAGE_UNAVAILABLE,
  data_missing: DATA_MISSING,
}

function otherHeadings(activeState) {
  return Object.entries(STATE_HEADINGS).filter(([k]) => k !== activeState)
}

/**
 * Capture full-page HTML frames from first paint until `predicate(html)` is
 * true, so a state whose only text is held in an sr-only announcement carrier
 * (Copy.sr_checking on the :hydrating skeleton) is still observable — engines
 * disagree on whether `innerText` walks into `.sr-only` elements, and HTML
 * always includes them. Shape mirrors app.captureFramesUntil (which polls
 * innerText); kept inline because only this case needs the HTML variant.
 */
async function captureHtmlFramesUntil(
  page,
  url,
  predicate,
  { budgetMs = 10_000, intervalMs = 40 } = {}
) {
  const frames = []
  const navigation = page.goto(url, { waitUntil: 'commit' })
  const deadline = Date.now() + budgetMs

  while (Date.now() < deadline) {
    const html = await page.content().catch(() => null)
    if (typeof html === 'string') {
      frames.push(html)
      if (predicate(html)) break
    }
    await page.waitForTimeout(intervalMs)
  }

  await navigation.catch(() => {})
  return { frames, resolved: frames.length > 0 && predicate(frames.at(-1)) }
}

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
    id: 'storage.private-mode-warns-before-entry',
    // Installs a context-level init script, which Playwright cannot remove.
    // On a CDP-attached browser (real Android Chrome) that would leak into every
    // later case, so the device runner restarts the browser around it.
    needsFreshContext: true,
    requirement: 'AC-10',
    async run({ page, context, baseUrl }) {
      // A private / incognito window walls persistent storage off from the
      // profile: Firefox private has historically refused IndexedDB entirely,
      // Chromium incognito and WebKit private wall it per-window and drop it on
      // close. The uniform contract is that any data-entry surface in such a
      // context MUST warn the user before they type — a working input rendered
      // before a "nothing is being stored" banner lets them commit records they
      // think are safe.
      await harness.enterPrivateMode(context)

      // Ordering claim (a): at the first frame the year select — the first
      // data-entry control the app exposes — becomes focusable, the session-only
      // banner must already be present in the visible viewport. `waitUntil:
      // 'commit'` lets us poll from the earliest paintable frame; sampling more
      // slowly would let a brief window of "input alive, banner not yet" go
      // unmeasured, which is the exact hazard AC-10 forbids.
      const nav = page.goto(`${baseUrl}/vehicle/select`, { waitUntil: 'commit' })
      let firstFocusable = null
      const deadline = Date.now() + 10_000

      while (Date.now() < deadline) {
        const state = await page.evaluate(() => {
          const select = document.querySelector('select[name=year]')
          if (!select) return null
          const rect = select.getBoundingClientRect()
          const focusable =
            !select.disabled &&
            rect.width > 0 && rect.height > 0 &&
            rect.top < window.innerHeight && rect.bottom > 0 &&
            rect.left < window.innerWidth && rect.right > 0
          if (!focusable) return { focusable: false }
          const banner = document.querySelector('[data-test="session-only-banner"]')
          if (!banner) return { focusable: true, bannerInViewport: false }
          const br = banner.getBoundingClientRect()
          const bannerInViewport =
            br.width > 0 && br.height > 0 &&
            br.top < window.innerHeight && br.bottom > 0 &&
            br.left < window.innerWidth && br.right > 0
          return { focusable: true, bannerInViewport }
        }).catch(() => null)

        if (state && state.focusable) {
          firstFocusable = state
          break
        }
        await page.waitForTimeout(30)
      }
      await nav.catch(() => {})

      if (!firstFocusable) {
        return { status: FAIL, detail: 'the year select never became focusable within the 10s budget on /vehicle/select in private mode' }
      }
      if (!firstFocusable.bannerInViewport) {
        return {
          status: FAIL,
          detail:
            'the year select became focusable before the session-only banner was in the visible viewport — a user could start typing in a private window without being told storage is off',
        }
      }

      // Non-persistence claim (b): a write attempted through the UI must not
      // survive a page reload. In session-only mode the confirm click may or may
      // not navigate off /vehicle/select (the server session holds transient
      // state for the socket's lifetime); either shape is legitimate, because
      // the real check is that a reload finds nothing saved.
      try {
        await app.setUpVehicle(page, baseUrl)
      } catch {
        // A refusal that never navigates is a valid response to blocked storage;
        // the reload assertion below is the actual persistence check.
      }

      // Full reload, not just a re-navigation — new browser context state, new
      // LiveView socket. If any vehicle write leaked past the private-mode wall
      // it will hydrate here and render its sticker.
      await page.reload({ waitUntil: 'load' }).catch(() => {})
      await page.waitForFunction(
        () => window.liveSocket && window.liveSocket.isConnected(),
        null,
        { timeout: 20_000 }
      ).catch(() => {})
      await page.waitForTimeout(2000)

      const bodyAfter = await page.innerText('body').catch(() => '')

      // 'DATE' appears on the rendered sticker whenever a vehicle is hydrated;
      // it is the same "vehicle exists" indicator hydration.reconnect-* uses.
      if (/DATE/.test(bodyAfter)) {
        return {
          status: FAIL,
          detail: 'a vehicle written in private mode was still present after a page reload — records leaked past the session-only wall',
        }
      }

      // Belt and braces: the banner must still be up after reload — leaving
      // private mode is a browser action, so the session-only signal must remain
      // present for as long as the profile setting says storage is off.
      const bannerAfter = await page
        .locator('[data-test="session-only-banner"]')
        .first()
        .isVisible()
        .catch(() => false)
      if (!bannerAfter) {
        return {
          status: FAIL,
          detail: 'session-only banner did not remain visible after reload in private mode',
        }
      }

      return { status: PASS, evidence: { firstFocusable } }
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
    // AC-5 verifies all four hydration states render distinctly — the fourth
    // (:storage_unavailable) is driven near the end of the case by installing
    // blockIndexedDb on the context and opening a fresh page, which is a
    // context-level init script Playwright cannot remove. On a CDP-attached
    // browser (real Android Chrome) that would leak into every later case, so
    // the device runner restarts the browser around it.
    needsFreshContext: true,
    requirement: 'FR-10',
    async run({ page, context, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      await harness.evictStoreKeepingHint(page)

      // Poll HTML frames rather than sampling `innerText` once. The :hydrating
      // skeleton's only text is Copy.sr_checking/0 held in `.sr-only` carriers
      // (INV-24.3 announcement) — HTML always includes it, `innerText`
      // disagrees per engine. Sampling for the settled :data_missing heading
      // also survives the same variable IDB round-trip that the quota case
      // documents on WebKit.
      const evicted = await captureHtmlFramesUntil(
        page, baseUrl,
        html => DATA_MISSING.test(html),
        { budgetMs: 10_000 }
      )
      if (!evicted.resolved) {
        const last = evicted.frames.at(-1) || ''
        return { status: FAIL, detail: `evicted store did not render :data_missing within budget; last HTML head: ${last.slice(0, 200)}` }
      }

      // The :hydrating skeleton must have been on screen before the state
      // settled — a settled state with no preceding skeleton frame is an
      // INV-24.3 violation (empty claim before hydration resolved).
      const evictedEarly = evicted.frames.slice(0, -1)
      if (!evictedEarly.some(f => HYDRATING_HEADING.test(f))) {
        return {
          status: FAIL,
          detail: 'no captured frame before :data_missing resolution carried the :hydrating heading',
        }
      }

      // AC-5 mutual exclusion: in the settled :data_missing snapshot, ONLY
      // the data_missing heading may match. A regression that leaked another
      // state's copy (an empty-garage claim, a storage-unavailable phrase, or
      // the hydrating skeleton text) fails here on the engine it regressed on.
      const evictedSettled = evicted.frames.at(-1)
      const evictedBleed = otherHeadings('data_missing').filter(([, rx]) => rx.test(evictedSettled))
      if (evictedBleed.length) {
        return {
          status: FAIL,
          detail: `:data_missing snapshot also matched: ${evictedBleed.map(([k]) => k).join(', ')}`,
        }
      }

      // And a genuine first visit must read differently.
      await harness.clearAll(page)
      const fresh = await captureHtmlFramesUntil(
        page, baseUrl,
        html => EMPTY_HEADING.test(html),
        { budgetMs: 10_000 }
      )
      if (!fresh.resolved) {
        const last = fresh.frames.at(-1) || ''
        return { status: FAIL, detail: `fresh visit did not render :empty within budget; last HTML head: ${last.slice(0, 200)}` }
      }

      const freshSettled = fresh.frames.at(-1)
      if (DATA_MISSING.test(freshSettled)) {
        return { status: FAIL, detail: 'a genuine first visit rendered the data-missing state' }
      }

      const freshEarly = fresh.frames.slice(0, -1)
      if (!freshEarly.some(f => HYDRATING_HEADING.test(f))) {
        return {
          status: FAIL,
          detail: 'no captured frame before :empty resolution carried the :hydrating heading',
        }
      }

      const freshBleed = otherHeadings('empty').filter(([, rx]) => rx.test(freshSettled))
      if (freshBleed.length) {
        return {
          status: FAIL,
          detail: `:empty snapshot also matched: ${freshBleed.map(([k]) => k).join(', ')}`,
        }
      }

      // Drive :storage_unavailable in a fresh page under blocked IndexedDB.
      // The init script only takes effect on pages created AFTER it is
      // installed, so the existing `page` is untouched and the earlier phases
      // stand — the :storage_unavailable snapshot comes from a sibling page
      // whose IDB open throws SecurityError, which the LocalStore hook
      // translates into `storage_mode: :session_only` and the server resolves
      // to `local_state: :storage_unavailable`.
      await harness.blockIndexedDb(context)
      const suPage = await context.newPage()
      try {
        const su = await captureHtmlFramesUntil(
          suPage, baseUrl,
          html => STORAGE_UNAVAILABLE.test(html),
          { budgetMs: 10_000 }
        )
        if (!su.resolved) {
          const last = su.frames.at(-1) || ''
          return { status: FAIL, detail: `blocked-IDB page did not render :storage_unavailable; last HTML head: ${last.slice(0, 200)}` }
        }
        const suSettled = su.frames.at(-1)
        const suBleed = otherHeadings('storage_unavailable').filter(([, rx]) => rx.test(suSettled))
        if (suBleed.length) {
          return {
            status: FAIL,
            detail: `:storage_unavailable snapshot also matched: ${suBleed.map(([k]) => k).join(', ')}`,
          }
        }
      } finally {
        await suPage.close().catch(() => {})
      }

      return {
        status: PASS,
        evidence: {
          evictedFrames: evicted.frames.length,
          freshFrames: fresh.frames.length,
          statesVerified: Object.keys(STATE_HEADINGS),
        },
      }
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

      // Honest notice without a way to act on it is only half honest: a user
      // reading "not saved to this browser" needs an on-screen Export CTA
      // that gets their still-visible entry off this device (INV-24.5 /
      // FR-14). The layout renders one inside the unsaved-writes /
      // session-only banners on every page where the failure surfaces, so it
      // must be present AND in the viewport — offscreen below the fold is
      // not surfaced.
      const EXPORT_CTA = 'a:has-text("Export a file")'
      const exportCta = page.locator(EXPORT_CTA).first()
      const exportVisible = await exportCta.isVisible().catch(() => false)
      if (!exportVisible) {
        return {
          status: FAIL,
          detail: 'honest quota notice appeared but no Export CTA was rendered on the failure page',
        }
      }
      const inViewport = await exportCta.evaluate(el => {
        const r = el.getBoundingClientRect()
        return (
          r.width > 0 && r.height > 0 &&
          r.top < window.innerHeight && r.bottom > 0 &&
          r.left < window.innerWidth && r.right > 0
        )
      }).catch(() => false)
      if (!inViewport) {
        return {
          status: FAIL,
          detail: 'Export CTA present in DOM but not in the visible viewport after quota failure',
        }
      }

      // Prior state must survive: a failed write may not take existing records
      // with it.
      const after = await app.readStore(page)
      const lost = (before.vehicles || []).length > (after.vehicles || []).length
      if (lost) {
        return { status: FAIL, detail: 'a failed write destroyed previously stored records' }
      }

      return { status: PASS, evidence: { vehiclesBefore: (before.vehicles || []).length, vehiclesAfter: (after.vehicles || []).length, exportCtaInViewport: true } }
    },
  },

  {
    id: 'multitab.propagation-and-compare-and-set',
    // Installs removeBroadcastChannel — a context-level init script Playwright
    // cannot remove. Removing it deterministically forces B's in-memory seq
    // to stay stale (no sibling-tab wake-up), so the AC-11 stale-seq CAS
    // failure is driven from a real user action rather than injected. On a
    // CDP-attached browser (real Android Chrome) the init script would leak
    // into every later case, so the device runner restarts the browser.
    needsFreshContext: true,
    requirement: 'FR-13',
    async run({ context, baseUrl }) {
      // With BroadcastChannel disabled the sibling-tab wake-up never fires:
      // B's LiveView keeps whatever `seq` its own last hydrate assigned,
      // regardless of what A wrote to the shared IndexedDB afterward. That is
      // exactly the state a stale-seq put needs — with broadcast on, B would
      // rehydrate to A's newer seq the moment A commits, and no CAS could
      // possibly lose. Shared IDB still carries propagation on first
      // hydration and store equality, so the assertions below still hold.
      await harness.removeBroadcastChannel(context)

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
      // With broadcast off, B never patches its LiveView from A's write, but
      // the shared IDB is unchanged: readStore reads the same origin storage
      // from either tab, so store equality is still the right check.
      await app.logOilChange(a, baseUrl)
      await a.waitForTimeout(1500)
      await b.waitForTimeout(2500)

      const storeA = await app.readStore(a)
      const storeB = await app.readStore(b)

      if (JSON.stringify(storeA.events) !== JSON.stringify(storeB.events)) {
        await a.close(); await b.close()
        return { status: FAIL, detail: 'tabs diverged on the events store after a commit' }
      }

      // AC-11: force B's next mutation to lose the compare-and-set and verify
      // the VISIBLE reload notice (Copy.conflict_notice() — "Reloaded from
      // this browser's newer data") is what B ends up showing. B's in-memory
      // seq is still whatever its own hydrate gave it — A's oil-change commit
      // moved IndexedDB's meta.seq forward without waking B. A same-page
      // mutation (delete-vehicle, the only mutation the sticker page issues
      // without navigating) therefore stages with a stale seq; the client's
      // applyPut sees `foundSeq !== payload.seq - 1` and pushes
      // local_store:conflict, which the server's handle_conflict/2 converts
      // into @conflict_notice = true. The delete itself never lands (the CAS
      // abort keeps IDB untouched and the ensuing rehydrate restores B's
      // in-memory garage from what IDB actually holds).
      await b.click('[data-test="vehicle-bar"] button', { timeout: 5_000 })
      await b.waitForSelector('[data-test="garage-panel"]', { timeout: 5_000 })
      await b.click('[data-test="ask-delete-vehicle"]', { timeout: 5_000 })
      await b.waitForSelector('[data-test="delete-vehicle-modal"]', { timeout: 5_000 })
      await b.click('[data-test="confirm-delete-vehicle"]', { timeout: 5_000 })

      // Wait for the notice to render. The CAS abort → client conflict push →
      // server assign → LiveView patch round trip is engine-sensitive, so poll
      // rather than sample once.
      const noticeSelector = '[data-test="conflict-notice"]'
      await b.waitForSelector(noticeSelector, { timeout: 15_000 }).catch(() => {})
      const noticeText = await b
        .locator(noticeSelector)
        .first()
        .innerText()
        .catch(() => '')

      await a.close(); await b.close()

      // Match on an apostrophe-free substring — HEEx escapes the apostrophe in
      // "browser's" to `&#39;`, exactly the trap two_tab_conflict_test.exs
      // documents when asserting Copy.conflict_notice() through rendered DOM.
      if (!/Reloaded from this/.test(noticeText)) {
        return {
          status: FAIL,
          detail: `stale-seq CAS failure did not surface Copy.conflict_notice on tab B; conflict-notice element text was: ${noticeText.slice(0, 200)}`,
        }
      }

      return {
        status: PASS,
        evidence: { events: (storeA.events || []).length, conflictNoticeText: noticeText },
      }
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

  {
    // FR-9's second half: a payload whose schema_version is newer than the
    // server understands MUST land in read-only mode — banner rendered,
    // mutations refused, zero server → client write-back — because a single
    // local_store:put on a newer envelope would silently downgrade this
    // browser's data in the older format on disk (INV-24.2).
    //
    // The forward-migration sibling case above is UNPROVEN until a schema
    // bump ships (no prior-version fixture exists). This case covers the
    // OTHER FR-9 branch by driving it directly, which the DOS-M09-008
    // data-and-persistence contract explicitly permits: "seeded storage
    // states are constructed through the adapter's public API where
    // possible, and by direct IndexedDB seeding only for states the adapter
    // cannot legally produce (a store written by a newer version …)."
    id: 'migration.newer-than-server-read-only',
    requirement: 'FR-9',
    async run({ page, baseUrl }) {
      // Reach the origin so the harness can talk to localStorage/IDB, then
      // wipe everything so the seed is the only meta record the app sees.
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)

      // schema_version deliberately far past the server's current version
      // (currently 1), driving the {:error, {:newer_than_server, _}} branch
      // in Session.handle_hydrate/2. A non-zero seq matches what a real
      // newer-release store would have written.
      await harness.seedNewerSchemaMeta(page, { schemaVersion: 99, seq: 1 })

      // Inspect incoming WebSocket frames for the server→client
      // local_store:put push. Phoenix.LiveView.push_event delivers it
      // inside a LiveView diff frame, so the raw event name appears in
      // the JSON payload; a substring match on the fully-qualified name
      // is sufficient AND immune to Phoenix diff-shape churn.
      //
      // The existing traceProtocol helper wraps liveSocket.socket.push
      // (client→server only) and cannot see this. Registered here — after
      // clearAll closed the first navigation's socket and before the
      // gotoConnected below opens a new one — so no frame is missed.
      const putFrames = []
      page.on('websocket', ws => {
        ws.on('framereceived', frame => {
          const raw = typeof frame.payload === 'string' ? frame.payload : ''
          if (raw.includes('"local_store:put"')) putFrames.push(raw.slice(0, 300))
        })
      })

      await app.gotoConnected(page, baseUrl)
      // The hydrate round trip is <500ms in practice; give the newer-than-
      // server branch a generous ceiling to land its assigns AND give any
      // misbehaving write-back time to arrive on the socket.
      await page.waitForTimeout(3000)

      // (a) The read-only banner MUST render. Without it a user sees
      // inert controls with no explanation and no path to export
      // (INV-24.2, INV-25).
      const banner = page.locator('#read-only-notice')
      const bannerVisible = await banner.isVisible().catch(() => false)
      if (!bannerVisible) {
        const text = await page.innerText('body').catch(() => '')
        return {
          status: FAIL,
          detail: `read-only banner did not render for a newer-than-server hydrate; saw: ${text.slice(0, 200)}`,
        }
      }

      // (b) Mutation controls MUST NOT commit. Save-vehicle is the
      // canonical mutation. Session.mutations_enabled?/1 returns false in
      // read_only, so the confirm handler short-circuits with a flash
      // error and the URL never leaves /vehicle/select. Inline the
      // cascade rather than using setUpVehicle so the no-navigation
      // timeout is 5s instead of 45s.
      await app.gotoConnected(page, `${baseUrl}/vehicle/select`)
      await page.waitForSelector('select[name=year]')
      await page.selectOption('select[name=year]', '2021')
      await page.waitForFunction(() => document.querySelector('select[name=make_id]').options.length > 1)
      const makeValue = await page.$eval('select[name=make_id]', s => [...s.options].find(o => o.value)?.value)
      await page.selectOption('select[name=make_id]', makeValue)
      await page.waitForFunction(() => document.querySelector('select[name=model_id]').options.length > 1)
      const modelValue = await page.$eval('select[name=model_id]', s => [...s.options].find(o => o.value)?.value)
      await page.selectOption('select[name=model_id]', modelValue)
      await page.waitForFunction(() => document.querySelector('select[name=configuration_key]').options.length > 1)
      const configValue = await page.$eval('select[name=configuration_key]', s => [...s.options].find(o => o.value)?.value)
      await page.selectOption('select[name=configuration_key]', configValue)

      await page.waitForSelector('[data-test=confirm-vehicle]')
      await page.click('[data-test=confirm-vehicle]').catch(() => {
        // A disabled confirm button — because a `confirmable?` precondition
        // was not met — is itself proof the mutation control refused, and
        // no push_event fires. The put-frame check below still runs.
      })

      const navigated = await page
        .waitForURL(/\/vehicle$/, { timeout: 5_000 })
        .then(() => true)
        .catch(() => false)

      if (navigated) {
        return {
          status: FAIL,
          detail: 'save-vehicle succeeded while the browser held newer-than-server data — the mutation control was not disabled',
        }
      }

      // The banner MUST still be visible after the navigation attempt —
      // the layout renders it whenever @read_only is truthy, and every
      // remount re-runs hydrate against the still-newer store.
      const bannerStill = await page.locator('#read-only-notice').isVisible().catch(() => false)
      if (!bannerStill) {
        return { status: FAIL, detail: 'read-only banner did not persist across a mutation attempt' }
      }

      // Give any misbehaving server → client write-back a moment to arrive
      // after the click resolved.
      await page.waitForTimeout(1500)

      // (c) The frame inspector caught every WebSocket message carrying
      // the local_store:put event name. A single one on a newer envelope
      // silently downgrades this browser's data in the older format on
      // disk — the exact regression FR-9 forbids and INV-24.2 pins.
      if (putFrames.length > 0) {
        return {
          status: FAIL,
          detail: `newer-than-server hydrate produced ${putFrames.length} local_store:put frame(s) on the socket; first: ${putFrames[0]}`,
        }
      }

      return {
        status: PASS,
        evidence: { bannerVisible: true, putFramesReceived: 0 },
      }
    },
  },
]
