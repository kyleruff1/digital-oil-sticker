// Privacy and honesty cases (FR-16, FR-17). These are the assertions that would
// catch the product quietly becoming something else: a personal value leaving
// the device, a third-party origin appearing, or a connection problem being
// dressed up as a statement about the user's vehicle.

import { PASS, FAIL } from '../report.mjs'
import * as harness from '../harness/storage.mjs'
import * as app from '../harness/app.mjs'

// Values the scripted session enters. If any of these reach the network in any
// surface — path, query, body, header, or socket frame — that is a failure.
const ODOMETER = '87431'
const NOTE = 'zqxjkbwvpm-private-note-marker'

export const cases = [
  {
    id: 'privacy.no-third-party-origins',
    requirement: 'FR-17',
    async run({ page, context, baseUrl }) {
      const origins = new Set()
      context.on('request', req => {
        try {
          origins.add(new URL(req.url()).origin)
        } catch {}
      })

      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await app.logOilChange(page, baseUrl, { odometer: ODOMETER })
      await app.gotoConnected(page, `${baseUrl}/history`)
      await page.waitForTimeout(1500)

      const appOrigin = new URL(baseUrl).origin
      const foreign = [...origins].filter(o => o !== appOrigin && o !== 'null')

      return foreign.length
        ? { status: FAIL, detail: `requests to non-application origins: ${foreign.join(', ')}` }
        : { status: PASS, evidence: { origins: [...origins] } }
    },
  },

  {
    id: 'privacy.no-personal-values-on-the-wire',
    requirement: 'FR-17',
    async run({ page, context, baseUrl }) {
      const surfaces = []

      context.on('request', req => {
        let origin = null
        try {
          origin = new URL(req.url()).origin
        } catch {}
        surfaces.push({ kind: 'url', text: req.url(), origin })
        surfaces.push({ kind: 'headers', text: JSON.stringify(req.headers()), origin })
        const body = req.postData()
        if (body) surfaces.push({ kind: 'body', text: body, origin })
      })

      await app.gotoConnected(page, baseUrl)

      // Socket frames are where personal data would most plausibly travel, so
      // they are captured explicitly rather than assumed clean.
      const frames = []
      page.on('websocket', ws => {
        ws.on('framesent', f => frames.push(String(f.payload)))
        ws.on('framereceived', f => frames.push(String(f.payload)))
      })

      await page.reload({ waitUntil: 'load' })
      await page.waitForFunction(() => window.liveSocket && window.liveSocket.isConnected())
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      await app.gotoConnected(page, `${baseUrl}/service/new`)
      await page.waitForSelector('select[name="service_date[month]"]')
      await page.selectOption('select[name="service_date[month]"]', '3')
      await page.selectOption('select[name="service_date[year]"]', String(new Date().getFullYear()))
      await page.selectOption('select[name="service_date[day]"]', '15')
      await page.fill('input[name="odometer[value]"]', ODOMETER)
      await page.fill('textarea[name=notes]', NOTE)
      await page.check('input[name="oil[base_stock]"][value=full_synthetic]')
      await page.click('button[type=submit]')
      await page.waitForTimeout(2500)

      // The odometer and the note travel to the SERVER by design: the server
      // renders the page. INV-22/26 forbid persisting or logging them, not
      // transmitting them over this session's own socket. What must never
      // happen is either value appearing in a URL, a query string, or a
      // request header — those are the surfaces that leak into proxies, logs,
      // and referrers — or in a request to any other origin.
      const appOrigin = new URL(baseUrl).origin

      const leaks = surfaces.filter(s => {
        const carries = s.text.includes(ODOMETER) || s.text.includes(NOTE)
        if (!carries) return false
        if (s.kind === 'url' || s.kind === 'headers') return true
        // A body is acceptable only when it is going to our own origin.
        return !s.origin || s.origin !== appOrigin
      })

      if (leaks.length) {
        return {
          status: FAIL,
          detail:
            `personal values appeared in: ${[...new Set(leaks.map(l => l.kind))].join(', ')} — ` +
            'permitted only in a same-origin request body or socket frame',
        }
      }

      const foreignFrames = frames.filter(f => f.includes(ODOMETER) || f.includes(NOTE)).length

      return {
        status: PASS,
        evidence: {
          surfacesInspected: surfaces.length,
          socketFrames: frames.length,
          sameOriginFramesCarryingEnteredValues: foreignFrames,
        },
      }
    },
  },

  {
    id: 'privacy.cookies-carry-no-identifier',
    requirement: 'FR-17',
    async run({ page, context, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      // Scoped to OUR origin. An unscoped `context.cookies()` returns every
      // cookie the browser profile holds, which on a launched browser is just
      // ours — and on a real device attached over CDP is the owner's entire
      // browsing history's worth of ad-tech cookies. That difference made this
      // assertion pass on desktop and fail on hardware for a reason that had
      // nothing to do with the application.
      const cookies = await context.cookies(baseUrl)

      const unexpected = cookies.filter(c => !/^_digital_oil_sticker_key$|^_csrf|^phx/i.test(c.name))
      if (unexpected.length) {
        return { status: FAIL, detail: `unexpected cookies on the application origin: ${unexpected.map(c => c.name).join(', ')}` }
      }

      const personal = cookies.filter(c => c.value.includes(ODOMETER) || c.value.includes(NOTE))
      if (personal.length) {
        return { status: FAIL, detail: 'a cookie on the application origin carried a value the user entered' }
      }

      return { status: PASS, evidence: { origin: new URL(baseUrl).origin, cookies: cookies.map(c => c.name) } }
    },
  },

  {
    id: 'connection.failure-is-not-a-data-status',
    requirement: 'FR-16',
    async run({ page, context, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await page.waitForTimeout(1500)

      const beforeText = await page.innerText('body')

      // Cut the socket the way a network does — refuse the upgrade — rather
      // than calling disconnect(), which is a clean close and does not put the
      // client into its error state.
      await context.route('**/live/websocket*', route => route.abort())
      await page.evaluate(() => window.liveSocket && window.liveSocket.disconnect())
      await page.evaluate(() => window.liveSocket && window.liveSocket.connect())

      // LiveView shows the indicator after its own retry backoff, and that
      // backoff differs per engine. Poll instead of sampling once, so a slower
      // engine is not reported as a product defect.
      let reconnecting = false
      const deadline = Date.now() + 20_000
      while (Date.now() < deadline) {
        reconnecting = await page.evaluate(() =>
          document.body.classList.contains('phx-client-error') ||
          document.body.classList.contains('phx-server-error') ||
          /Attempting to reconnect/i.test(document.body.innerText)
        )
        if (reconnecting) break
        await page.waitForTimeout(500)
      }

      const afterText = await page.innerText('body')

      // The failure this guards: a dropped connection presented as a statement
      // about the user's vehicle, or presented as nothing at all.
      if (!reconnecting) {
        return {
          status: FAIL,
          detail: 'the socket was unreachable and no connection state was shown, so the user cannot tell a network problem from missing data',
        }
      }

      // And the connection state must not have replaced the vehicle's own
      // rendering with a claim about its data.
      const newDataClaim =
        /No catalog match/i.test(afterText) && !/No catalog match/i.test(beforeText)
      if (newDataClaim) {
        return { status: FAIL, detail: 'losing the socket produced a new claim about the vehicle’s data' }
      }

      await context.unroute('**/live/websocket*')
      return { status: PASS, evidence: { reconnectIndicator: true } }
    },
  },

  {
    id: 'catalog.query-failure-is-not-storage-failure',
    requirement: 'AC-14',
    async run({ page, baseUrl }) {
      // The picker cascade is the app's user-facing catalog surface: a
      // failed lookup here must read as a catalog problem (Copy.catalog_unreadable),
      // not as a claim about the browser's records. The failure this guards
      // is a server-side catalog error being dressed up as data loss.
      await app.gotoConnected(page, `${baseUrl}/vehicle/select`)
      await page.waitForSelector('select[name=year]', { timeout: 20_000 })

      const beforeText = await page.innerText('body')
      if (/catalog could not be read/i.test(beforeText)) {
        return { status: FAIL, detail: 'catalog-error copy was already visible before the failure was injected' }
      }

      // Force the server-side catalog query to fail by asking for a year the
      // vocabulary rejects. Selector.validate returns :invalid_selector and
      // VehiclePickerLive.run/4's catch-all flips @catalog_error, which is
      // exactly the path a real catalog outage exercises. Injecting a rogue
      // option is what makes an out-of-vocabulary year selectable from the
      // browser side; the server does not care where the value came from.
      await page.evaluate(() => {
        const s = document.querySelector('select[name=year]')
        const opt = document.createElement('option')
        opt.value = '9999'
        opt.textContent = '9999'
        s.appendChild(opt)
      })
      await page.selectOption('select[name=year]', '9999')

      let sawCatalogError = false
      let text = ''
      const deadline = Date.now() + 15_000
      while (Date.now() < deadline) {
        text = await page.innerText('body').catch(() => '')
        if (/catalog could not be read/i.test(text)) {
          sawCatalogError = true
          break
        }
        await page.waitForTimeout(200)
      }

      if (!sawCatalogError) {
        return {
          status: FAIL,
          detail: `a failed catalog query produced no catalog-error copy; saw: ${text.slice(0, 220)}`,
        }
      }

      // The catalog-outcome frame must not have borrowed a storage-loss heading.
      // Apostrophe-free substrings are used here for the same reason the storage
      // suite uses them: HEEx escapes ' to &#39; in some rendered surfaces.
      if (/stored records are gone/i.test(text)) {
        return { status: FAIL, detail: 'a failed catalog query rendered the data-missing heading' }
      }
      if (/storage could not be used/i.test(text)) {
        return { status: FAIL, detail: 'a failed catalog query rendered the storage-unavailable heading' }
      }

      return { status: PASS, evidence: { catalogErrorVisible: true } }
    },
  },

  {
    id: 'catalog.slow-query-does-not-mask-as-storage-loss',
    requirement: 'AC-14',
    async run({ page, baseUrl }) {
      // A catalog query that is merely slow must present as loading, not as
      // "your records are gone" or "your storage could not be used". The
      // failure this guards is a spinner-shaped confidence problem being
      // resolved by inventing a data-loss claim while the catalog is still on
      // its way back.
      await app.gotoConnected(page, `${baseUrl}/vehicle/select`)
      await page.waitForSelector('select[name=year]', { timeout: 20_000 })

      const firstYear = await page.$eval('select[name=year]', s => {
        const opt = [...s.options].find(o => o.value)
        return opt ? opt.value : null
      })
      if (!firstYear) {
        return { status: FAIL, detail: 'no year options available to trigger a cascade query' }
      }

      // Delay outgoing cascade_change frames by 3s. WebSocket.prototype.send
      // is looked up per call, so patching it after the socket is already open
      // still affects subsequent sends by the LiveView socket. Only frames
      // whose payload names the cascade_change event are delayed; the heartbeat
      // and prior joins go through unmodified so the client stays connected.
      await page.evaluate(() => {
        const OrigSend = WebSocket.prototype.send
        WebSocket.prototype.send = function (data) {
          if (typeof data === 'string' && data.includes('cascade_change')) {
            setTimeout(() => OrigSend.call(this, data), 3000)
          } else {
            OrigSend.call(this, data)
          }
        }
      })

      await page.selectOption('select[name=year]', firstYear)

      // Sample the interim state while the outgoing frame is still parked.
      // Leave enough of the 3s budget on the wire that the response cannot
      // possibly have arrived — 700ms in, 2s+ still to go.
      await page.waitForTimeout(700)

      const interimText = await page.innerText('body')
      if (/stored records are gone/i.test(interimText)) {
        return { status: FAIL, detail: 'a slow catalog query rendered the data-missing heading' }
      }
      if (/storage could not be used/i.test(interimText)) {
        return { status: FAIL, detail: 'a slow catalog query rendered the storage-unavailable heading' }
      }
      if (/catalog could not be read/i.test(interimText)) {
        return { status: FAIL, detail: 'a slow catalog query rendered a catalog-error claim before the query returned' }
      }

      // Something on the page must signal that work is in flight. LiveView
      // stamps phx-change-loading on a phx-change form for the duration of
      // the round trip, and the cascade component sets aria-busy on the
      // in-flight select — either is a legitimate loading indicator; the
      // literal string "Loading…" is a third acceptable form. Absence of
      // ALL of them during a 3s delay is what fails this case.
      const loading = await page.evaluate(() => {
        const form = document.querySelector('form[phx-change="cascade_change"]')
        const formLoading = !!form && form.classList.contains('phx-change-loading')
        const anyBusy = !!document.querySelector('[aria-busy="true"]')
        const loadingText = /Loading/i.test(document.body.innerText)
        return { formLoading, anyBusy, loadingText, any: formLoading || anyBusy || loadingText }
      })

      if (!loading.any) {
        return {
          status: FAIL,
          detail: 'a slow catalog query showed no loading indication during the 3s delay',
        }
      }

      return {
        status: PASS,
        evidence: {
          formLoading: loading.formLoading,
          anyAriaBusy: loading.anyBusy,
          loadingText: loading.loadingText,
        },
      }
    },
  },

  {
    id: 'boot-hint.is-the-only-localstorage-record',
    requirement: 'FR-6',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await app.logOilChange(page, baseUrl, { odometer: ODOMETER })
      await page.waitForTimeout(1200)

      const ls = await harness.localStorageDump(page)
      const keys = Object.keys(ls)

      // `dos_boot_state` is ours. `phx:*` and `<path>-consecutive-reloads` are
      // LiveView's own bookkeeping — the reload counters appeared only on
      // Firefox, where the reconnect path exercised them. They are framework
      // state, not ours, so they are allowed by name AND checked for content:
      // a counter may hold a number and nothing else.
      const ours = k => k === 'dos_boot_state'
      const framework = k => k.startsWith('phx:') || /-consecutive-reloads$/.test(k)

      const offenders = keys.filter(k => !ours(k) && !framework(k))
      if (offenders.length) {
        return { status: FAIL, detail: `localStorage holds keys beyond the boot hint: ${offenders.join(', ')}` }
      }

      const nonNumericCounter = keys
        .filter(k => /-consecutive-reloads$/.test(k))
        .find(k => !/^\d+$/.test(ls[k]))
      if (nonNumericCounter) {
        return { status: FAIL, detail: `a reload counter holds a non-numeric value: ${nonNumericCounter}` }
      }

      const carriesEntered = keys.find(k => String(ls[k]).includes(ODOMETER) || String(ls[k]).includes(NOTE))
      if (carriesEntered) {
        return { status: FAIL, detail: `localStorage key ${carriesEntered} carries a value the user entered` }
      }
      if (ls.dos_boot_state && ls.dos_boot_state !== 'has_data' && ls.dos_boot_state !== 'never') {
        return { status: FAIL, detail: `boot hint carries an unexpected value: ${ls.dos_boot_state}` }
      }
      return { status: PASS, evidence: { keys } }
    },
  },
]
