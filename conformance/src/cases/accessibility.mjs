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
