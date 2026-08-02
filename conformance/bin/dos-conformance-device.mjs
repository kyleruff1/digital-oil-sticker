#!/usr/bin/env node
// Run the conformance assertions against a REAL Android device over adb.
//
//   node bin/dos-conformance-device.mjs --serial 192.168.86.50:44845 \
//                                       --base-url https://digital-oil-sticker.fly.dev
//
// Why this is a separate runner rather than another engine in the main one:
// a CDP-attached Android Chrome is not a browser Playwright launched, and two
// things the main runner relies on are simply unavailable.
//
//   * `browser.newContext()` fails — Android Chrome exposes one browser
//     context, so cases cannot each get a clean one.
//   * `context.addInitScript()` works but cannot be REMOVED, so a harness
//     installed by one case would silently change every case after it.
//
// The isolation the main runner gets from a fresh context is obtained here by
// force-stopping and relaunching Chrome on the device, which is slow (~10s) and
// therefore done only for the cases that actually install an init script.
//
// What this buys: SUPPORT_MATRIX.md records Android Chrome as *unproven*
// because desktop Chromium shares the engine but not the platform — not its
// storage eviction, not its real quota, not its touch targets. Results from
// here are measured on the platform itself.

import { writeFileSync, mkdirSync, readFileSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
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

const CHROME_PKG = 'com.android.chrome'
const DEVTOOLS_SOCKET = 'localabstract:chrome_devtools_remote'

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

const CASES = [...BUNDLE_CASES, ...storageCases, ...privacyCases, ...a11yCases]

function parseArgs(argv) {
  const args = {
    baseUrl: 'https://digital-oil-sticker.fly.dev',
    release: 'device',
    out: join(HERE, '..', 'reports'),
    port: 9222,
    adb: process.env.ADB_PATH || 'adb',
  }
  for (let i = 2; i < argv.length; i++) {
    const [flag, inline] = argv[i].split('=')
    const value = inline ?? argv[++i]
    if (flag === '--serial') args.serial = value
    else if (flag === '--base-url') args.baseUrl = value
    else if (flag === '--release') args.release = value
    else if (flag === '--out') args.out = value
    else if (flag === '--port') args.port = Number(value)
    else if (flag === '--adb') args.adb = value
  }
  if (!args.serial) throw new Error('--serial is required (see `adb devices`)')
  return args
}

function adb(args, adbArgs) {
  return execFileSync(args.adb, ['-s', args.serial, ...adbArgs], {
    encoding: 'utf8',
    env: { ...process.env, ADB_MDNS_OPENSCREEN: '0' },
  }).trim()
}

function deviceFacts(args) {
  const prop = name => adb(args, ['shell', `getprop ${name}`])
  const chrome = adb(args, ['shell', `dumpsys package ${CHROME_PKG} | grep -m1 versionName`])

  return {
    model: `${prop('ro.product.manufacturer')} ${prop('ro.product.model')}`,
    android_release: prop('ro.build.version.release'),
    android_sdk: prop('ro.build.version.sdk'),
    chrome_version: (chrome.match(/versionName=(\S+)/) || [])[1] ?? 'unknown',
    screen: adb(args, ['shell', 'wm size']).replace('Physical size: ', ''),
    density: adb(args, ['shell', 'wm density']).replace('Physical density: ', ''),
  }
}

/**
 * Restart Chrome and reattach. This is what stands in for a fresh browser
 * context: force-stopping clears the init scripts a previous case installed,
 * which is otherwise impossible to undo on an attached browser.
 */
async function startSession(args, { restart }) {
  if (restart) {
    adb(args, ['shell', `am force-stop ${CHROME_PKG}`])
    await sleep(1500)
  }

  adb(args, ['shell', 'input keyevent KEYCODE_WAKEUP'])
  adb(args, ['shell', `am start -a android.intent.action.VIEW -d "${args.baseUrl}/robots.txt" ${CHROME_PKG}`])

  // The devtools socket appears a moment after the process does.
  for (let attempt = 0; attempt < 30; attempt++) {
    await sleep(1000)
    const socket = adb(args, ['shell', 'cat /proc/net/unix | grep -o "@chrome_devtools_remote.*" || true'])
    if (socket.includes('chrome_devtools_remote')) break
  }

  try {
    adb(args, ['forward', '--remove-all'])
  } catch {
    // Nothing forwarded yet.
  }
  adb(args, ['forward', `tcp:${args.port}`, DEVTOOLS_SOCKET])

  const browser = await playwright.chromium.connectOverCDP(`http://localhost:${args.port}`)
  const context = browser.contexts()[0]
  if (!context) throw new Error('Chrome exposed no browser context over CDP')
  return { browser, context }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms))

async function main() {
  const args = parseArgs(process.argv)
  const matrix = loadMatrix(REPO_ROOT)
  const startedAt = new Date().toISOString()
  const report = new Report({ release: args.release, startedAt, matrix })

  const facts = deviceFacts(args)
  console.error(`device: ${facts.model} — Android ${facts.android_release} (SDK ${facts.android_sdk})`)
  console.error(`chrome: ${facts.chrome_version}, screen ${facts.screen} @ ${facts.density}dpi\n`)

  const engineKey = 'android-chrome'
  const engine = report.engine(engineKey, {
    engine: 'Chromium (Android)',
    tier: 1,
    host_os: `Android ${facts.android_release} (SDK ${facts.android_sdk})`,
    device: facts.model,
    version: facts.chrome_version,
    screen: facts.screen,
    density: facts.density,
    // The whole point: this is the platform itself, not a stand-in for it.
    proxy: false,
    proxy_for: null,
    launched: true,
  })

  // Non-isolating cases share one Chrome session; the rest each get a restart.
  const ordered = [...CASES.filter(c => !c.needsFreshContext), ...CASES.filter(c => c.needsFreshContext)]

  let session = await startSession(args, { restart: true })

  for (const testCase of ordered) {
    if (testCase.needsFreshContext) {
      await session.browser.close().catch(() => {})
      session = await startSession(args, { restart: true })
    }

    const page = await session.context.newPage()
    const started = Date.now()

    let outcome
    try {
      outcome = await withTimeout(
        testCase.run({
          page,
          context: session.context,
          browser: session.browser,
          baseUrl: args.baseUrl,
          engine: { key: engineKey },
        }),
        180_000,
        'case timed out after 180s'
      )
    } catch (err) {
      outcome = { status: FAIL, detail: `threw: ${firstLine(err.message)}` }
    }

    report.record(engineKey, {
      id: testCase.id,
      requirement: testCase.requirement,
      status: outcome.status,
      detail: outcome.detail,
      evidence: { ...(outcome.evidence ?? {}), ms: Date.now() - started },
    })

    const mark = outcome.status === PASS ? 'ok  ' : outcome.status === FAIL ? 'FAIL' : 'UNPR'
    console.error(`  ${mark} ${testCase.id}${outcome.detail ? ` — ${outcome.detail.slice(0, 110)}` : ''}`)

    await page.close().catch(() => {})
  }

  await session.browser.close().catch(() => {})

  report.fillUnrun(
    CASES.map(c => ({ id: c.id, requirement: c.requirement })),
    'assertion did not run on this device'
  )
  engine.device_facts = facts

  const finished = new Date().toISOString()
  const json = report.toJSON(finished, loadBaseline())

  mkdirSync(args.out, { recursive: true })
  const file = join(args.out, `device-${args.release}-${finished.replace(/[:.]/g, '-')}.json`)
  writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
  writeFileSync(join(args.out, 'latest-device.json'), JSON.stringify(json, null, 2) + '\n')

  console.error('\n' + format(json))
  console.error(`\nreport: ${file}`)

  process.exit(json.verdict.release_blocked ? 1 : 0)
}

function loadBaseline() {
  const path = join(HERE, '..', 'baseline.json')
  if (!existsSync(path)) return []
  return JSON.parse(readFileSync(path, 'utf8')).unproven ?? []
}

function firstLine(message) {
  return String(message).split('\n')[0]
}

function withTimeout(promise, ms, message) {
  return Promise.race([promise, new Promise((_, reject) => setTimeout(() => reject(new Error(message)), ms))])
}

main().catch(err => {
  console.error(err)
  process.exit(2)
})
