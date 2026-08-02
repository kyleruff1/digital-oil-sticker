// Per-engine timing and payload measurement (DOS-M09-005 FR-23 / AC-18).
//
// This case is a PRODUCER, not a gate. The §9 rows it feeds — first-page
// latency, first-visit and repeat-visit payload — are ratified *provisional*
// values, and the card is explicit about what happens to measurements: they
// are submitted as a re-ratification proposal, never silently enforced and
// never silently edited into §9. So the case passes when measurement
// SUCCEEDED, and the numbers ride along as evidence for the release record.
//
// Honesty constraints, recorded in the evidence rather than papered over:
//
//   * One sample from one machine on one network is not a p95. The evidence
//     says `single_sample: true` so nobody quotes these against a percentile
//     budget without noticing what they are.
//   * A fresh Playwright context has an empty cache, so "first visit" is real.
//     An attached device browser (the Android runner) keeps Chrome's actual
//     cache; the case detects which world it is in from the document's own
//     transferSize and labels the run cold or warm rather than assuming.
//   * Engines differ in whether they report Resource Timing transfer sizes.
//     A missing number is null with `reported: false`, not a guess and not a
//     zero pretending to be a measurement.

import { PASS, FAIL } from '../report.mjs'
import * as harness from '../harness/storage.mjs'

// §9 provisional budgets, for an informational comparison in the evidence.
// Comparison only — see the header for why these do not gate.
const PROVISIONAL = {
  repeat_visit_payload_bytes: 60 * 1024, // ≤ 60 KiB compressed, warm cache
  first_page_ms: 250, // p95 budget; our single sample is not a p95
}

export const cases = [
  {
    id: 'timings.measured',
    requirement: 'FR-23',
    async run({ page, baseUrl }) {
      // Empty the store by way of robots.txt, not the app: the usual
      // gotoConnected -> clearAll pattern loads the document and all of its
      // assets BEFORE the measurement, which silently turns "first visit"
      // into a warm-cache visit. robots.txt resolves the origin for clearAll
      // without touching anything the measurement counts.
      await page.goto(`${baseUrl}/robots.txt`, { waitUntil: 'load' })
      await harness.clearAll(page)

      // --- first visit -----------------------------------------------------
      // Plain goto, not gotoConnected: the measurement wants the page's own
      // timeline from navigation start, and the helper's post-connect settle
      // would sit between the marks we read.
      await page.goto(baseUrl, { waitUntil: 'load' })

      const socketConnectMs = await page.evaluate(
        () =>
          new Promise(resolve => {
            const poll = setInterval(() => {
              if (window.liveSocket && window.liveSocket.isConnected()) {
                clearInterval(poll)
                resolve(Math.round(performance.now()))
              }
            }, 10)
            setTimeout(() => {
              clearInterval(poll)
              resolve(null)
            }, 20_000)
          })
      )

      if (socketConnectMs === null) {
        return { status: FAIL, detail: 'the LiveView socket never connected within 20s, so nothing downstream could be timed' }
      }

      // Hydration completion: the moment the view stops being a skeleton and
      // renders a resolved state — for a cleared store that is the empty-state
      // heading, for a populated one the sticker's DATE viewport.
      const hydrationMs = await page.evaluate(
        () =>
          new Promise(resolve => {
            const resolved = () =>
              /Set up your first vehicle|DATE/.test(document.body.innerText) &&
              !document.querySelector('.dos-skeleton')
            if (resolved()) return resolve(Math.round(performance.now()))
            const poll = setInterval(() => {
              if (resolved()) {
                clearInterval(poll)
                resolve(Math.round(performance.now()))
              }
            }, 25)
            setTimeout(() => {
              clearInterval(poll)
              resolve(null)
            }, 20_000)
          })
      )

      const first = await readNavigationTimings(page)

      // --- repeat visit ----------------------------------------------------
      // Same document, warm HTTP cache. phx-track-static digests are what §9's
      // 60 KiB row is about: on a warm cache the static assets must not be
      // re-transferred.
      await page.reload({ waitUntil: 'load' })
      await page
        .waitForFunction(() => window.liveSocket && window.liveSocket.isConnected(), null, { timeout: 20_000 })
        .catch(() => {})
      const repeat = await readNavigationTimings(page)

      const evidence = {
        single_sample: true,
        // Three cache worlds, not two — and the third was discovered by the
        // detector mislabelling it. On the Android tablet the DOCUMENT
        // transferred (LiveView pages are never cached) while every static
        // asset came from Chrome's persistent cache from an earlier run, so a
        // 4.6 KB "first visit" wore a `cold` label that made the desktop
        // engines' 70 KB look like a regression. The document alone cannot
        // decide; the assets have to be counted.
        cache_state_first_visit: cacheLabel(first),
        first_visit: {
          ttfb_ms: first.ttfb_ms,
          dom_content_loaded_ms: first.dom_content_loaded_ms,
          load_ms: first.load_ms,
          socket_connect_ms: socketConnectMs,
          hydration_complete_ms: hydrationMs,
          payload_transfer_bytes: first.total_transfer_bytes,
          payload_reported: first.sizes_reported,
          resource_count: first.resource_count,
        },
        repeat_visit: {
          ttfb_ms: repeat.ttfb_ms,
          load_ms: repeat.load_ms,
          payload_transfer_bytes: repeat.total_transfer_bytes,
          payload_reported: repeat.sizes_reported,
          resource_count: repeat.resource_count,
        },
        provisional_budget_comparison: {
          note: 'informational only — provisional §9 values are re-ratified from evidence, never gated here',
          repeat_visit_within_60KiB:
            repeat.sizes_reported && repeat.total_transfer_bytes !== null
              ? repeat.total_transfer_bytes <= PROVISIONAL.repeat_visit_payload_bytes
              : null,
          ttfb_within_250ms_single_sample: first.ttfb_ms !== null ? first.ttfb_ms <= PROVISIONAL.first_page_ms : null,
        },
      }

      if (hydrationMs === null) {
        // Resolution itself is asserted by the hydration cases; here it only
        // means the timing could not be taken.
        return { status: FAIL, detail: 'hydration did not resolve within 20s, so its completion time could not be measured', evidence }
      }

      return { status: PASS, evidence }
    },
  },
]

function cacheLabel(nav) {
  if (nav.document_transfer_bytes === null) return 'unknown'
  if (nav.document_transfer_bytes === 0) return 'warm'
  if (nav.resource_count > 0 && nav.resources_transferred === 0) return 'document-only (assets cached)'
  return 'cold'
}

async function readNavigationTimings(page) {
  return page.evaluate(() => {
    const nav = performance.getEntriesByType('navigation')[0]
    const resources = performance.getEntriesByType('resource')

    // Some engines report transferSize as 0 for everything rather than not at
    // all; a page where the DOCUMENT claims zero bytes was either cached or
    // unreported, and summing zeros as "the payload" would be a fabricated
    // measurement either way.
    const sizesReported = typeof nav?.transferSize === 'number' && (nav.transferSize > 0 || resources.some(r => r.transferSize > 0))

    const round = value => (typeof value === 'number' ? Math.round(value) : null)

    return {
      ttfb_ms: nav ? round(nav.responseStart - nav.startTime) : null,
      dom_content_loaded_ms: nav ? round(nav.domContentLoadedEventEnd - nav.startTime) : null,
      load_ms: nav ? round(nav.loadEventEnd - nav.startTime) : null,
      document_transfer_bytes: nav && typeof nav.transferSize === 'number' ? nav.transferSize : null,
      total_transfer_bytes: sizesReported
        ? (nav?.transferSize ?? 0) + resources.reduce((sum, r) => sum + (r.transferSize || 0), 0)
        : null,
      sizes_reported: sizesReported,
      resource_count: resources.length,
      resources_transferred: resources.filter(r => r.transferSize > 0).length,
    }
  })
}
