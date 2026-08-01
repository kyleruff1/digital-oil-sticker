#!/usr/bin/env node
// The conformance runner (DOS-M09-008).
//
//   node bin/dos-conformance.mjs --base-url https://digital-oil-sticker.fly.dev
//
// Runs every case on every engine SUPPORT_MATRIX.md names, writes a
// machine-readable report, and exits non-zero when a Tier 1 engine produced
// anything other than a pass — including an engine that could not be launched
// at all, which is the failure mode a "skip" would hide.

import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as playwright from 'playwright'

import { loadMatrix } from '../src/matrix.mjs'
import { Report, format, PASS, FAIL, UNPROVEN } from '../src/report.mjs'
import * as bundle from '../src/checks/bundle.mjs'
import { cases as storageCases } from '../src/cases/storage.mjs'
import { cases as privacyCases } from '../src/cases/privacy.mjs'
import { cases as a11yCases } from '../src/cases/accessibility.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..', '..')

const ALL_CASES = [...storageCases, ...privacyCases, ...a11yCases]

// Static bundle checks are per-engine too: a build could serve different assets
// to different engines, and asserting only on one would miss it.
const BUNDLE_CASES = [
  {
    id: 'bundle.no-user-agent-branching',
    requirement: 'FR-4',
    async run({ page, baseUrl }) {
      return bundle.userAgentBranching(await bundle.fetchBundles(page, baseUrl))
    },
  },
  {
    id: 'bundle.no-deferred-capabilities',
    requirement: 'FR-22',
    async run({ page, baseUrl }) {
      const sources = await bundle.fetchBundles(page, baseUrl)
      const scan = bundle.deferredCapabilities(sources)
      if (scan.status !== PASS) return scan
      const manifest = await bundle.manifestAbsent(page)
      if (manifest.status !== PASS) return manifest
      return bundle.noRuntimeServiceWorker(page)
    },
  },
]

const CASES = [...BUNDLE_CASES, ...ALL_CASES]

function parseArgs(argv) {
  const args = { baseUrl: 'http://localhost:4000', release: 'dev', out: join(HERE, '..', 'reports') }
  for (let i = 2; i < argv.length; i++) {
    const [flag, inline] = argv[i].split('=')
    const value = inline ?? argv[++i]
    if (flag === '--base-url') args.baseUrl = value
    else if (flag === '--release') args.release = value
    else if (flag === '--out') args.out = value
    else if (flag === '--engine') args.only = value
    else if (flag === '--rehearse-red') args.rehearseRed = true
  }
  return args
}

async function main() {
  const args = parseArgs(process.argv)
  const matrix = loadMatrix(REPO_ROOT)
  const startedAt = new Date().toISOString()
  const report = new Report({ release: args.release, startedAt, matrix })

  const expected = CASES.map(c => ({ id: c.id, requirement: c.requirement }))

  for (const engineRow of matrix.engines) {
    if (args.only && args.only !== engineRow.key) continue

    const engineEntry = report.engine(engineRow.key, {
      engine: engineRow.engine,
      tier: engineRow.tier,
      host_os: engineRow.host_os,
      proxy: engineRow.proxy,
      proxy_for: engineRow.proxy_for,
      launched: false,
      version: null,
    })

    let browser
    try {
      browser = await playwright[engineRow.key].launch()
    } catch (err) {
      // An engine that will not start is unproven, not absent. At Tier 1 this
      // blocks the release; silently skipping it is exactly what FR-20 forbids.
      console.error(`  ${engineRow.key}: launch failed — ${err.message}`)
      continue
    }

    engineEntry.launched = true
    engineEntry.version = browser.version()
    console.error(`
${engineRow.key} ${engineEntry.version}${engineRow.proxy ? ' (proxy)' : ''}`)

    try {
      for (const testCase of CASES) {
        // Each case gets a clean context: no cookie, store, or init script may
        // leak between cases, or a harness installed by one would silently
        // change another's result.
        const context = await browser.newContext()
        const page = await context.newPage()
        const started = Date.now()

        let outcome
        try {
          outcome = await withTimeout(
            testCase.run({ page, context, browser, baseUrl: args.baseUrl, engine: engineRow }),
            120_000,
            `case timed out after 120s`
          )
        } catch (err) {
          outcome = { status: FAIL, detail: `threw: ${err.message}` }
        }

        // A deliberate red run proves the gate actually blocks (AC-18).
        if (args.rehearseRed && testCase.id === 'bundle.no-user-agent-branching') {
          outcome = { status: FAIL, detail: 'RED-RUN REHEARSAL: injected failure to prove the release gate blocks' }
        }

        report.record(engineRow.key, {
          id: testCase.id,
          requirement: testCase.requirement,
          status: outcome.status,
          detail: outcome.detail,
          evidence: { ...(outcome.evidence ?? {}), ms: Date.now() - started },
        })

        const mark = outcome.status === PASS ? 'ok  ' : outcome.status === FAIL ? 'FAIL' : 'UNPR'
        console.error(`  ${mark} ${testCase.id}${outcome.detail ? ` — ${outcome.detail.slice(0, 120)}` : ''}`)

        await context.close().catch(() => {})
      }
    } catch (err) {
      // The browser itself died (crash, OOM, driver disconnect). Whatever this
      // engine had not reached is unproven, which blocks at Tier 1 — but the
      // remaining engines still run, because aborting the whole sweep would
      // turn one crashed engine into no evidence at all.
      console.error(`  ${engineRow.key}: engine stopped responding — ${firstLine(err.message)}`)
      engineEntry.crashed = firstLine(err.message)
    }

    await browser.close().catch(() => {})
  }

  report.fillUnrun(expected, 'engine did not run this assertion')

  const finished = new Date().toISOString()
  const json = report.toJSON(finished)

  mkdirSync(args.out, { recursive: true })
  const file = join(args.out, `conformance-${args.release}-${finished.replace(/[:.]/g, '-')}.json`)
  writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
  writeFileSync(join(args.out, 'latest.json'), JSON.stringify(json, null, 2) + '\n')

  console.error('\n' + format(json))
  console.error(`\nreport: ${file}`)

  process.exit(json.verdict.release_blocked ? 1 : 0)
}

function firstLine(message) {
  return String(message).split('\n')[0]
}

function withTimeout(promise, ms, message) {
  return Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() => reject(new Error(message)), ms)),
  ])
}

main().catch(err => {
  console.error(err)
  process.exit(2)
})
