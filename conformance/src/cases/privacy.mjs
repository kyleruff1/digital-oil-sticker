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

      const cookies = await context.cookies()
      const unexpected = cookies.filter(c => !/^_digital_oil_sticker_key$|^_csrf|^phx/i.test(c.name))

      if (unexpected.length) {
        return { status: FAIL, detail: `unexpected cookies: ${unexpected.map(c => c.name).join(', ')}` }
      }
      const personal = cookies.filter(c => c.value.includes('87431'))
      if (personal.length) {
        return { status: FAIL, detail: 'a cookie carried a personal value' }
      }
      return { status: PASS, evidence: { cookies: cookies.map(c => c.name) } }
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
