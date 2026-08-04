// Accessibility assertions (FR-14 of §9, AC-17). axe-core is injected from the
// installed package rather than a CDN, because the privacy case asserts zero
// third-party origins and a test that violated that would be self-defeating.

import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { PASS, FAIL, UNPROVEN } from '../report.mjs'
import * as harness from '../harness/storage.mjs'
import * as app from '../harness/app.mjs'

const require = createRequire(import.meta.url)
const AXE_SOURCE = readFileSync(require.resolve('axe-core/axe.min.js'), 'utf8')

async function axeOn(page) {
  await page.evaluate(AXE_SOURCE)
  return page.evaluate(async () => {
    const results = await window.axe.run(document, {
      runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'] },
    })
    return results.violations.map(v => ({
      id: v.id,
      impact: v.impact,
      help: v.help,
      nodes: v.nodes.length,
      target: v.nodes[0]?.target?.join(' ') ?? null,
    }))
  })
}

const ROUTES = ['/', '/vehicle', '/service/new', '/history', '/settings/storage']

// The mandated hydration announcement, verbatim from
// DigitalOilStickerWeb.Copy.sr_checking/0 in
// `app/lib/digital_oil_sticker_web/copy.ex`. If that string moves, this
// duplicate must move too — the copy-lint on the app side is the source of
// truth, but this suite is a separate process that cannot import Elixir, and
// asserting the wrong text is worse than not asserting at all.
const SR_CHECKING = 'Checking this browser for your records…'

// WCAG 2.5.5 Target Size (Enhanced) is 44 CSS px on each axis; the AA
// baseline (2.5.8) is 24 px, but every button here is the app's OWN
// mutating action and the DOS spec targets the enhanced size on mobile.
const TARGET_SIZE_MIN_PX = 44

// Mobile viewport for the target-size sweep. iPhone SE-class width is the
// narrowest device the support matrix names, so a control that clears 44 px
// here clears it everywhere.
const MOBILE_VIEWPORT = { width: 375, height: 812 }

async function fillVehicleCascade(page) {
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
}

/** Extract enough about the currently-focused element to reason about focus
 * indicators, viewport intersection, and cycle detection. */
async function snapshotActiveElement(page) {
  return page.evaluate(() => {
    const el = document.activeElement
    if (!el || el === document.body || el === document.documentElement) {
      return { atBody: true }
    }
    const cs = getComputedStyle(el)
    const r = el.getBoundingClientRect()
    // A stable identity for cycle detection: the DOM path, so two visits to
    // the same node compare equal even if its textContent shifted.
    const path = (() => {
      const parts = []
      let node = el
      while (node && node.nodeType === 1 && parts.length < 20) {
        const nth = node.parentNode ? [...node.parentNode.children].indexOf(node) : 0
        parts.unshift(`${node.tagName.toLowerCase()}:${nth}`)
        node = node.parentNode
      }
      return parts.join('/')
    })()
    return {
      atBody: false,
      path,
      tag: el.tagName.toLowerCase(),
      label:
        el.getAttribute('data-test') ||
        el.getAttribute('aria-label') ||
        el.getAttribute('name') ||
        (el.textContent || '').trim().slice(0, 40) ||
        el.tagName.toLowerCase(),
      matchesFocusVisible: (() => {
        try { return el.matches(':focus-visible') } catch { return null }
      })(),
      outlineStyle: cs.outlineStyle,
      outlineWidth: parseFloat(cs.outlineWidth) || 0,
      outlineColor: cs.outlineColor,
      boxShadow: cs.boxShadow,
      rect: {
        top: r.top, left: r.left, bottom: r.bottom, right: r.right,
        width: r.width, height: r.height,
      },
      viewport: { w: window.innerWidth, h: window.innerHeight },
    }
  })
}

function hasVisibleFocusIndicator(snap) {
  if (snap.atBody) return true
  // :focus-visible must apply for keyboard focus, AND some visual affordance
  // must be present. Outline is the primary hook; a non-none box-shadow (the
  // Tailwind/daisyUI focus ring) counts too.
  const outlineVisible = snap.outlineStyle !== 'none' && snap.outlineWidth > 0
  const shadowVisible = snap.boxShadow && snap.boxShadow !== 'none'
  return snap.matchesFocusVisible !== false && (outlineVisible || shadowVisible)
}

function isFocusedElementInViewport(snap) {
  if (snap.atBody) return true
  const r = snap.rect
  // A partially-visible focused element still counts — the browser is only
  // obligated to bring it into view, not to center it. A hidden 0x0 element
  // fails on the width/height guard.
  return (
    r.width > 0 && r.height > 0 &&
    r.right > 0 && r.bottom > 0 &&
    r.left < snap.viewport.w && r.top < snap.viewport.h
  )
}

async function tabThroughRoute(page, { max = 60 } = {}) {
  await page.evaluate(() => document.body.focus())
  const trace = []
  for (let i = 0; i < max; i++) {
    await page.keyboard.press('Tab')
    const snap = await snapshotActiveElement(page)
    trace.push(snap)
    // Body reached AFTER we have visited at least one focusable — Tab exited
    // the document, which is what "no keyboard trap" means.
    if (snap.atBody && i > 0) return { trace, exited: true }
    // Cycled back to the first focused element without hitting body: the
    // page cycles focus internally without ever handing control to the
    // browser chrome. Some engines do this; still counts as "not trapped"
    // for the purposes of AC-17 as long as the cycle is complete.
    if (i > 0 && !snap.atBody && trace[0] && !trace[0].atBody && snap.path === trace[0].path) {
      return { trace, exited: false, cycled: true }
    }
  }
  return { trace, exited: false, cycled: false }
}

export const cases = [
  {
    id: 'a11y.no-wcag-aa-violations',
    requirement: 'AC-17',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await app.logOilChange(page, baseUrl)

      const findings = []
      for (const route of ROUTES) {
        await app.gotoConnected(page, `${baseUrl}${route}`)
        await page.waitForTimeout(1800)
        const violations = await axeOn(page)
        if (violations.length) findings.push({ route, violations })
      }

      if (findings.length) {
        const summary = findings
          .map(f => `${f.route}: ${f.violations.map(v => `${v.id}(${v.impact}, ${v.nodes})`).join(', ')}`)
          .join(' | ')
        return { status: FAIL, detail: `WCAG 2.1 AA violations — ${summary}`, evidence: findings }
      }
      return { status: PASS, evidence: { routes: ROUTES } }
    },
  },

  {
    id: 'a11y.reflow-at-320px',
    requirement: 'AC-17',
    async run({ page, baseUrl }) {
      await page.setViewportSize({ width: 320, height: 800 })
      await app.gotoConnected(page, baseUrl)
      await page.waitForTimeout(1500)

      const overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
      }))

      // A horizontally scrolling page at 320px is the reflow failure WCAG 1.4.10
      // describes; a few pixels of rounding is not.
      if (overflow.scrollWidth > overflow.clientWidth + 2) {
        return {
          status: FAIL,
          detail: `page scrolls horizontally at 320px (${overflow.scrollWidth} > ${overflow.clientWidth})`,
        }
      }
      return { status: PASS, evidence: overflow }
    },
  },

  {
    id: 'a11y.keyboard-operability',
    requirement: 'AC-17',
    async run({ page, baseUrl }) {
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)
      await app.logOilChange(page, baseUrl)

      const findings = []
      for (const route of ROUTES) {
        await app.gotoConnected(page, `${baseUrl}${route}`)
        await page.waitForTimeout(1000)

        const { trace, exited, cycled } = await tabThroughRoute(page)

        if (!exited && !cycled) {
          findings.push({
            route,
            issue: 'keyboard trap: Tab never returned to body and did not cycle within the budget',
            tabsAttempted: trace.length,
            lastElement: trace.at(-1)?.label ?? null,
          })
          continue
        }

        for (let i = 0; i < trace.length; i++) {
          const snap = trace[i]
          if (snap.atBody) continue

          if (!hasVisibleFocusIndicator(snap)) {
            findings.push({
              route,
              issue: 'no visible focus indicator',
              tabIndex: i + 1,
              element: `${snap.tag}:${snap.label}`,
              matchesFocusVisible: snap.matchesFocusVisible,
              outlineStyle: snap.outlineStyle,
              outlineWidth: snap.outlineWidth,
              boxShadow: snap.boxShadow,
            })
          }

          if (!isFocusedElementInViewport(snap)) {
            findings.push({
              route,
              issue: 'focused element not scrolled into viewport',
              tabIndex: i + 1,
              element: `${snap.tag}:${snap.label}`,
              rect: snap.rect,
              viewport: snap.viewport,
            })
          }
        }
      }

      if (findings.length) {
        const summary = findings
          .slice(0, 5)
          .map(f => `${f.route}: ${f.issue}${f.element ? ` on ${f.element}` : ''}`)
          .join(' | ')
        return {
          status: FAIL,
          detail: `keyboard operability — ${summary}${findings.length > 5 ? ` (+${findings.length - 5} more)` : ''}`,
          evidence: { findings },
        }
      }
      return { status: PASS, evidence: { routes: ROUTES } }
    },
  },

  {
    id: 'a11y.target-size',
    requirement: 'AC-17',
    async run({ page, baseUrl }) {
      await page.setViewportSize(MOBILE_VIEWPORT)
      await app.gotoConnected(page, baseUrl)
      await harness.clearAll(page)
      await app.setUpVehicle(page, baseUrl)

      const findings = []
      const measurements = []

      async function measure(selector, label) {
        const rect = await page.$eval(selector, el => {
          const r = el.getBoundingClientRect()
          return { width: r.width, height: r.height }
        })
        measurements.push({ label, width: rect.width, height: rect.height })
        if (rect.width < TARGET_SIZE_MIN_PX || rect.height < TARGET_SIZE_MIN_PX) {
          findings.push({ label, rect })
        }
      }

      // The primary mutating control on the sticker page — the CTA a user
      // taps to record a service. Only rendered in :sticker mode, which
      // requires the vehicle set up above.
      await app.gotoConnected(page, baseUrl)
      await page.waitForSelector('a[href="/service/new"].btn', { timeout: 10_000 })
      await measure('a[href="/service/new"].btn', 'Log an oil change (home CTA)')

      // Save the (re-)confirmed vehicle. Filling the cascade brings the
      // confirm-vehicle button into DOM; we measure without clicking it.
      await app.gotoConnected(page, `${baseUrl}/vehicle/select`)
      await fillVehicleCascade(page)
      await measure('[data-test=confirm-vehicle]', 'Save this vehicle')

      // Save the oil-change record. The submit button is present in the
      // form's DOM without needing the fields filled first.
      await app.gotoConnected(page, `${baseUrl}/service/new`)
      await page.waitForSelector('button[type=submit]')
      await measure('button[type=submit]', 'Save to this browser (oil change)')

      if (findings.length) {
        const summary = findings
          .map(f => `${f.label}: ${f.rect.width.toFixed(1)}x${f.rect.height.toFixed(1)}px < ${TARGET_SIZE_MIN_PX}px`)
          .join(' | ')
        return {
          status: FAIL,
          detail: `target size below ${TARGET_SIZE_MIN_PX} CSS px on mobile — ${summary}`,
          evidence: { measurements, findings },
        }
      }
      return { status: PASS, evidence: { measurements, minPx: TARGET_SIZE_MIN_PX } }
    },
  },

  {
    id: 'a11y.zoom-200pct',
    requirement: 'AC-17',
    async run({ page, baseUrl }) {
      // Playwright's default viewport is 1280x720; halving the width to
      // 640 CSS px simulates the same content at 200% zoom without needing
      // a real page-zoom control (which Playwright does not expose). WCAG
      // 1.4.4 Resize Text at 200% forbids horizontal scrolling of the
      // primary content at that scale.
      await page.setViewportSize({ width: 640, height: 720 })
      await app.gotoConnected(page, baseUrl)
      await page.waitForTimeout(1500)

      const overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        innerWidth: window.innerWidth,
      }))

      if (overflow.scrollWidth > overflow.innerWidth + 2) {
        return {
          status: FAIL,
          detail: `horizontal scroll appeared at 200% zoom (${overflow.scrollWidth} > ${overflow.innerWidth})`,
          evidence: overflow,
        }
      }
      return { status: PASS, evidence: overflow }
    },
  },

  {
    id: 'a11y.live-region-announces-hydration',
    requirement: 'AC-17',
    // Installs a context-level init script that patches WebSocket to block
    // the LiveView channel until we let go of it. Playwright cannot remove
    // context init scripts, so a CDP-attached browser would carry this
    // block into every later case — the device runner restarts the browser
    // around it.
    needsFreshContext: true,
    async run({ page, context, baseUrl }) {
      // Suppress the LiveView WebSocket so the client-side LocalStore hook
      // never fires local_store:hydrate. The server therefore stays in
      // :hydrating and its initial HTTP render — which already carries the
      // sr-only sr_checking announcement — is the state we observe.
      await context.addInitScript(() => {
        const RealWS = window.WebSocket
        window.__dosBlockLive = true
        window.WebSocket = new Proxy(RealWS, {
          construct(target, args) {
            const url = String(args[0] ?? '')
            if (window.__dosBlockLive && url.includes('/live/websocket')) {
              // Redirect the LV socket at an unreachable localhost port so
              // the hook stays un-mounted. Throwing here would surface as a
              // noisy error in the LiveSocket transport; a dead endpoint
              // just leaves it retrying quietly.
              return Reflect.construct(target, ['ws://127.0.0.1:1'])
            }
            return Reflect.construct(target, args)
          },
        })
      })

      await page.goto(baseUrl, { waitUntil: 'domcontentloaded' })

      // The initial HTTP-rendered sticker view carries an sr-only span with
      // Copy.sr_checking() while :hydrating. Poll briefly — the DOM lands
      // one microtask after domcontentloaded on some engines.
      let carriesChecking = false
      const carrierDeadline = Date.now() + 5000
      while (Date.now() < carrierDeadline) {
        carriesChecking = await page.evaluate(text => {
          return [...document.querySelectorAll('.sr-only')].some(el => (el.textContent || '').includes(text))
        }, SR_CHECKING).catch(() => false)
        if (carriesChecking) break
        await page.waitForTimeout(100)
      }

      if (!carriesChecking) {
        return {
          status: FAIL,
          detail: `sr-only region did not carry Copy.sr_checking() while hydrate was suppressed — the live-region announcement is missing on the :hydrating render`,
        }
      }

      // Let the socket connect and hydrate. Turn the flag off first, then
      // ask the LiveSocket to reconnect; the transport constructs a fresh
      // WebSocket, which our Proxy now passes through untouched.
      await page.evaluate(() => { window.__dosBlockLive = false })
      await page.evaluate(() => {
        if (window.liveSocket) {
          try { window.liveSocket.disconnect() } catch {}
          window.liveSocket.connect()
        }
      })

      await page.waitForFunction(
        () =>
          window.liveSocket &&
          window.liveSocket.isConnected() &&
          document.querySelector('.phx-connected, [data-phx-main]'),
        null,
        { timeout: 20_000 }
      )
      await page.waitForTimeout(1500)

      // Once hydrate resolves, the :hydrating skeleton (and its sr-only
      // carrier) is removed from the DOM. If it is still there, the live
      // region did not update — a screen reader would still be hearing
      // "checking" long after the state settled.
      const stillChecking = await page.evaluate(text => {
        return [...document.querySelectorAll('.sr-only')].some(el => (el.textContent || '').includes(text))
      }, SR_CHECKING)

      if (stillChecking) {
        return {
          status: FAIL,
          detail: `sr-only region still carried Copy.sr_checking() after hydrate resolved — the announcement did not update`,
        }
      }

      return { status: PASS, evidence: { carriedWhileSuppressed: true, clearedAfterHydrate: true } }
    },
  },

  {
    id: 'a11y.screen-reader-operability',
    requirement: 'AC-17',
    async run() {
      return {
        status: UNPROVEN,
        detail:
          'screen-reader operability is a manual assertion (NVDA/JAWS/VoiceOver) and cannot be driven by automation. ' +
          'Scheduled in the manual matrix; not passing until a human runs it.',
      }
    },
  },
]
