#!/usr/bin/env node
//
// DEPLOY REHEARSAL — DOS-M09-005 AC-11 / AC-12
// =============================================================================
//
// What this is
// ------------
// ADR-0004 makes a specific, falsifiable promise about deploying this app:
//
//   "Deploys drop every WebSocket. With one machine, a deploy is a brief
//    disconnect; clients auto-reconnect with backoff and remount, which
//    re-runs hydration. [...] It also means a deploy during a user's unsaved
//    mutation must not lose it — pending writes are re-driven after remount
//    from client storage, which is the source of truth."
//    — docs/architecture/ADR-0004-browser-first-client-and-hosting.md,
//      §"WebSocket and LiveView considerations"
//
// Nothing in the repository proves that. The conformance suite's
// `hydration.reconnect-no-skeleton-teardown` case comes closest, but it
// disconnects the socket from inside the browser
// (`liveSocket.disconnect(); liveSocket.connect()`), which is a client-side
// simulation of a network blip. A deploy is not a blip: the server process is
// destroyed, the machine is replaced, the socket's LiveView pid and every
// assign it held — hydration state, the pending-write ledger, the
// `unsaved_writes` notice — cease to exist, and a *different* machine answers
// the reconnect. This script attaches real sessions to the real host and
// measures what a real deploy does to them.
//
// It deliberately does NOT deploy anything. See "Why it cannot run unattended".
//
//
// How to run it
// -------------
//   cd conformance
//   npm ci
//   npx playwright install chromium firefox webkit
//
//   node src/rehearsal/deploy.mjs \
//     --base-url https://digital-oil-sticker.fly.dev \
//     --release  m09-005-ac11
//
// The script sets up its sessions, prints a baseline read of `GET /version`,
// and then blocks with instructions. In a SECOND terminal, you deploy:
//
//   cd app
//   flyctl deploy --app digital-oil-sticker \
//     --build-arg GIT_SHA="$(git rev-parse HEAD)" \
//     --build-arg BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
//
// or, once the owner has provisioned `FLY_API_TOKEN` (as of this writing
// `flyctl tokens list` and `gh secret list` are both empty, so every release
// so far was pushed from a workstation):
//
//   gh workflow run deploy.yml -f reason="DOS-M09-005 AC-11/AC-12 rehearsal"
//
// The script polls `GET /version` and continues when the release identity
// changes. It then releases its instrumentation, lets the sessions settle, and
// writes a report in the conformance suite's own shape.
//
// IMPORTANT — the trigger signal. By default the script waits for `git_sha` to
// change. `git_sha` is a Docker build arg baked into the image, so redeploying
// an UNCHANGED tree produces a new release with the SAME `git_sha` and this
// script will wait forever. If you are rehearsing with a redeploy of the same
// commit — which is the cheap, correct way to rehearse, because machine
// replacement is what breaks sockets — use `--signal release` or
// `--signal machine` and read the caveat that prints with the result.
//
// Flags:
//   --base-url <url>     default http://localhost:4000
//   --release <id>       label written into the report
//   --engine <key>       run one engine only (chromium | firefox | webkit);
//                        default is every engine SUPPORT_MATRIX.md lists
//   --signal <field>     sha (default) | release | machine — which /version
//                        field must change before the deploy counts as observed
//   --wait-min <n>       default 45 — how long to wait for the operator
//   --settle-polls <n>   default 10 — consecutive polls the new identity must
//                        hold before the deploy is called finished
//   --poll-ms <n>        default 2000
//   --out <dir>          default conformance/reports
//
// Exit code is the conformance gate's: non-zero when a Tier 1 engine produced
// anything that is not a pass, INCLUDING an assertion that never ran. Aborting
// with Ctrl-C still writes a report, with everything unreached marked
// `unproven` — an abandoned rehearsal must not be indistinguishable from one
// that was never started.
//
//
// Why it cannot run unattended
// ----------------------------
// 1. It needs a real deploy of the real production app while real sessions are
//    attached. There is no staging environment. Deploying is an owner action
//    with production blast radius, and this script has no credential to do it:
//    no `FLY_API_TOKEN` exists anywhere in the repo or the Fly account.
// 2. Even with a token, a script that both triggers the deploy and grades it
//    would be grading its own homework — the interesting failures (a machine
//    that never becomes ready, a rolling replacement that half-completes) are
//    exactly the ones an automated trigger would paper over by retrying.
// 3. A deploy interrupts anyone who is actually using the app. Whether that is
//    acceptable on merge or only on request is an open product decision
//    recorded in .github/workflows/deploy.yml; until the owner settles it, a
//    human asks for each deploy, including this one.
//
//
// What this does NOT prove
// ------------------------
// Read this before quoting any number out of the report.
//
// * DESKTOP ENGINES ONLY, on Windows 11. Playwright's `webkit` is a WebKit
//   build, not Safari and not iOS — see the caveat in
//   docs/quality/SUPPORT_MATRIX.md. Real iOS and real Android deploy behaviour
//   is UNPROVEN and cannot be inferred from these results: mobile browsers
//   freeze backgrounded tabs, suspend timers, tear down sockets on screen lock,
//   and on iOS may kill the tab's process outright. None of that is exercised
//   here. A passing run says nothing about a phone in a pocket.
// * ONE DEPLOY IS ONE SAMPLE. The constitution's §9 row for reconnect is a p95
//   ("automatic reconnect p95 <= 2.0 s", itself marked *provisional*). A single
//   rehearsal cannot evaluate a p95 and this script does not pretend to. It
//   reports the window it measured, once, and asserts only that reconnection
//   happened without user action.
// * THE DISCONNECT WINDOW IS BRACKETED, NOT PINNED. Between the last frame the
//   client received and the moment it noticed the socket close, nothing was
//   exchanged, so the instant the server stopped serving is unknown. The report
//   gives an upper and a lower bound and the client's own measured heartbeat
//   interval. Do not quote the upper bound as "the outage".
// * IT CANNOT SEE THE FLEET. `GET /version` goes through the Fly proxy and is
//   answered by whichever machine takes the request. Two machines are currently
//   running in `ord` while `app/fly.toml` declares `min_machines_running = 1` —
//   an unrecorded posture the owner still has to settle. With more than one
//   machine, observing the new identity at the proxy does NOT prove every
//   machine rolled; proving that needs `flyctl status` alongside this run. The
//   measured window is a property of whatever machine count happened to be live.
// * IT DOES NOT TEST LONG-LIVED SESSIONS. Every session here was created
//   minutes earlier. A tab left open overnight, through a laptop sleep, is a
//   different case and is unmeasured.
// * IT DOES NOT TEST THE DEPLOY ITSELF — no rollback, no failed readiness
//   check, no half-rolled fleet, no image that will not boot. Those are
//   deploy-pipeline assertions and belong to the workflow, not here.
// * IT PROVES NOTHING ABOUT RECORD DURABILITY IN GENERAL. The user's records
//   live in the browser (INV-23); the server never held them, so no deploy can
//   destroy them. What a deploy CAN destroy is server-side socket state: the
//   hydration state machine, the pending-write ledger, and the persistent
//   "Not saved to this browser" notice that INV-24.5 says must not be cleared
//   by time or navigation. That is what this measures.
// * NETWORK CONDITIONS ARE THE OPERATOR'S. Nothing here is measured on a
//   constrained or high-latency link.
//
//
// A note on what lands in the report
// ----------------------------------
// The evidence blocks carry counts, store names, timestamps and record IDs —
// never record CONTENTS, even though every record here is synthetic harness
// data. A report format that is capable of carrying records will eventually
// carry somebody's, and this file is release evidence that gets attached to
// builds. The shape refuses the capability rather than relying on discipline.
//
// =============================================================================

import { writeFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import * as playwright from 'playwright'

import { loadMatrix } from '../matrix.mjs'
import { Report, format, PASS, FAIL, UNPROVEN } from '../report.mjs'
import * as app from '../harness/app.mjs'
import * as harness from '../harness/storage.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const REPO_ROOT = join(HERE, '..', '..', '..')

// Copy that would be a LIE in a given session's situation. Sources are
// DigitalOilStickerWeb.Copy; these mirror the regexes in src/cases/storage.mjs
// and must be kept in step with that module and with the copy-lint test.
const EMPTY_GARAGE = String.raw`Set up your first vehicle|No vehicle is set up`
const DATA_MISSING = String.raw`stored records are gone`
const STORAGE_UNAVAILABLE = String.raw`storage could not be used`

// Per-page markers that say "this view is back", used to timestamp recovery.
//
// On the sticker page this button is rendered ONLY in `:sticker` mode, so it
// separates "hydration resolved and the user's sticker is back" from "the page
// painted something". The navbar link reads "Log oil change" without the
// article, so it cannot match by accident.
const STICKER_MARKER = 'Log an oil change'
const PICKER_MARKER = 'Choose a vehicle'
// The oil-change form's submit button. Weaker than the sticker marker on
// purpose, and the weakness is stated where it is used: OilChangeLive renders
// the form whatever the hydration state is, so on that page "usable" can only
// mean "socket connected and the form is present", not "hydration resolved".
const FORM_MARKER = 'Save to this browser'
const UNSAVED_NOTICE = 'Not saved to this browser'

// Every assertion this script knows how to make. Used to fill in `unproven`
// for anything that did not run, which at Tier 1 blocks exactly as a failure
// does — "we did not look" is not "we looked and it was fine".
const ASSERTIONS = [
  { id: 'deploy.observed', requirement: 'AC-11' },

  { id: 'deploy.idle.reconnected', requirement: 'INV-7' },
  { id: 'deploy.idle.rehydrated', requirement: 'INV-24.1' },
  { id: 'deploy.idle.no-false-storage-claim', requirement: 'INV-24.3' },
  { id: 'deploy.idle.records-identical', requirement: 'INV-23' },

  { id: 'deploy.mid-selection.reconnected', requirement: 'INV-7' },
  { id: 'deploy.mid-selection.no-false-storage-claim', requirement: 'INV-25' },
  { id: 'deploy.mid-selection.uncommitted-choice-not-committed', requirement: 'INV-24.2' },
  { id: 'deploy.mid-selection.operable-after-reconnect', requirement: 'INV-7' },

  { id: 'deploy.pending-write.reconnected', requirement: 'INV-7' },
  { id: 'deploy.pending-write.no-false-storage-claim', requirement: 'INV-24.3' },
  { id: 'deploy.pending-write.prior-records-survived', requirement: 'INV-24.5' },
  { id: 'deploy.pending-write.resolved-honestly', requirement: 'INV-24.2' },
]

// ---------------------------------------------------------------------------
// arguments
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const args = {
    baseUrl: 'http://localhost:4000',
    release: 'deploy-rehearsal',
    out: join(HERE, '..', '..', 'reports'),
    only: null,
    signal: 'sha',
    waitMin: 45,
    settlePolls: 10,
    pollMs: 2000,
  }
  for (let i = 2; i < argv.length; i++) {
    const [flag, inline] = argv[i].split('=')
    const value = inline ?? argv[++i]
    if (flag === '--base-url') args.baseUrl = value.replace(/\/+$/, '')
    else if (flag === '--release') args.release = value
    else if (flag === '--out') args.out = value
    else if (flag === '--engine') args.only = value
    else if (flag === '--signal') args.signal = value
    else if (flag === '--wait-min') args.waitMin = Number(value)
    else if (flag === '--settle-polls') args.settlePolls = Number(value)
    else if (flag === '--poll-ms') args.pollMs = Number(value)
    else throw new Error(`unknown flag ${flag}`)
  }
  if (!['sha', 'release', 'machine'].includes(args.signal)) {
    throw new Error(`--signal must be sha, release, or machine (got ${args.signal})`)
  }
  return args
}

const SIGNAL_FIELD = { sha: 'git_sha', release: 'fly_release_version', machine: 'fly_machine_id' }

// ---------------------------------------------------------------------------
// release identity, read from the live host
// ---------------------------------------------------------------------------

/** `GET /version`, the release identifier DigitalOilSticker.Release.identifier/0
 * emits. Non-personal build metadata only. */
async function fetchVersion(baseUrl) {
  const res = await fetch(`${baseUrl}/version`, { headers: { 'cache-control': 'no-store' } })
  if (!res.ok) throw new Error(`GET /version answered ${res.status}`)
  return res.json()
}

function identityLine(v) {
  return [
    `  git_sha                 ${v.git_sha}`,
    `  built_at                ${v.built_at}`,
    `  app_version             ${v.app_version}`,
    `  fly_release_version     ${v.fly_release_version ?? '(absent)'}`,
    `  fly_machine_id          ${v.fly_machine_id ?? '(absent)'}`,
    `  fly_region              ${v.fly_region ?? '(absent)'}`,
    `  catalog_data_version    ${v.catalog_data_version}`,
    `  catalog_payload_sha256  ${v.catalog_payload_sha256}`,
  ].join('\n')
}

// ---------------------------------------------------------------------------
// in-page instrumentation
// ---------------------------------------------------------------------------

/**
 * Installs, for every page in this context and across full page reloads:
 *
 *   * socket lifecycle timestamps, taken from the Phoenix Socket's own public
 *     callbacks (`onOpen`/`onClose`/`onError`/`onMessage`) rather than from
 *     anything internal, so what is measured is what the client itself sees;
 *   * a continuous scan for copy that would be a lie in this session's
 *     situation, driven by a MutationObserver plus a 200 ms sampler, so a
 *     claim that flashed for a few frames cannot hide between Playwright polls.
 *     Each hit records whether the watcher was ARMED when it fired: during
 *     set-up a session legitimately passes through the empty-garage state on
 *     its way to having records, and asserting on those frames would fail the
 *     run for copy that was true when it was shown;
 *   * a "view is usable again" timestamp, armed by the socket close and
 *     satisfied only when the socket is connected AND the session's own marker
 *     text is on screen — a painted skeleton does not count;
 *   * an opt-in ack sink, used by the pending-write session only.
 *
 * Every event is pushed OUT of the page immediately through an exposed
 * binding. Nothing is buffered in the page, because a full reload (which
 * LiveView performs after enough failed rejoins) would take the buffer with it
 * and silently shorten the measured window.
 */
async function installWatcher(context, { sessionId, healthy, forbidden, sink }) {
  await context.exposeFunction(`__dosDeploy_${sessionId}`, entry => {
    sink.push(entry)
    return true
  })

  await context.addInitScript(
    ({ sessionId, healthy, forbidden }) => {
      const now = () => Date.now()
      // Resolved on every call, never captured. This init script runs at
      // document-start and the exposed binding may not be installed yet;
      // capturing `undefined` once would silently lose every event for the
      // life of the page, which is the one failure this script must not have.
      const send = e => {
        try {
          const push = window[`__dosDeploy_${sessionId}`]
          if (push) push({ session: sessionId, ...e })
        } catch {
          // The binding is torn down during navigation teardown; a lost event
          // is better than an exception inside the app's own event loop.
        }
      }

      // Defaults, established on every page load. Both are flipped later by
      // init scripts appended from Node — not by `page.evaluate` alone —
      // because LiveView performs a full page reload after enough failed
      // rejoins, and a value set only on the live page would silently revert
      // to its default at exactly the moment being measured.
      if (typeof window.__dosDropAcks !== 'boolean') window.__dosDropAcks = false
      if (typeof window.__dosWatchArmed !== 'boolean') window.__dosWatchArmed = false

      const patterns = forbidden.map(src => ({ src, re: new RegExp(src, 'i') }))
      const alreadySeen = new Set()
      let awaitingHealthy = false

      const scan = () => {
        const text = (document.body && document.body.innerText) || ''
        const armed = window.__dosWatchArmed === true

        for (const p of patterns) {
          // Keyed by armed state as well as pattern, so a claim seen during
          // set-up does not suppress the same claim after arming.
          const key = `${p.src}|${armed}`
          if (!alreadySeen.has(key) && p.re.test(text)) {
            alreadySeen.add(key)
            // The excerpt exists so a failure names the screen the user saw.
            send({ kind: 'forbidden-claim', pattern: p.src, armed, at: now(), excerpt: text.slice(0, 240) })
          }
        }

        if (
          awaitingHealthy &&
          text.includes(healthy) &&
          window.liveSocket &&
          window.liveSocket.isConnected()
        ) {
          awaitingHealthy = false
          send({ kind: 'view-usable', at: now() })
        }
      }

      const startScanning = () => {
        // Announced here rather than at document-start, so the count of these
        // is a reliable count of page loads: by DOMContentLoaded the exposed
        // binding is certainly present.
        send({ kind: 'watcher-installed', at: now() })
        scan()
        new MutationObserver(scan).observe(document.documentElement, {
          subtree: true,
          childList: true,
          characterData: true,
          attributes: true,
        })
        // Belt and braces: a change driven entirely by CSS (a class flip that
        // reveals a banner) does not always produce a text mutation.
        setInterval(scan, 200)
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', startScanning, { once: true })
      } else {
        startScanning()
      }

      const wire = () => {
        const socket = window.liveSocket && window.liveSocket.socket
        if (!socket || socket.__dosDeployWired) return !!socket
        socket.__dosDeployWired = true

        send({
          kind: 'socket-wired',
          at: now(),
          // Read off the running client rather than assumed: it bounds how
          // stale "the last frame we received" can be.
          heartbeat_interval_ms:
            typeof socket.heartbeatIntervalMs === 'number' ? socket.heartbeatIntervalMs : null,
        })

        socket.onOpen(() => send({ kind: 'socket-open', at: now() }))
        socket.onError(() => send({ kind: 'socket-error', at: now() }))
        socket.onMessage(() => send({ kind: 'socket-message', at: now() }))
        socket.onClose(() => {
          awaitingHealthy = true
          send({ kind: 'socket-close', at: now() })
        })

        // Ack suppression, on the same boundary the conformance harness
        // already wraps (see app.mjs traceProtocol): the socket's own push.
        // A different flag name so the two wrappers compose rather than one
        // silently declining to install.
        if (!socket.__dosAckDropWrapped) {
          socket.__dosAckDropWrapped = true
          const realPush = socket.push.bind(socket)
          socket.push = data => {
            try {
              if (
                window.__dosDropAcks &&
                data &&
                data.event === 'event' &&
                data.payload &&
                data.payload.event === 'local_store:ack'
              ) {
                send({ kind: 'ack-dropped', at: now() })
                return
              }
            } catch {
              // fall through and push
            }
            return realPush(data)
          }
        }
        return true
      }

      const timer = setInterval(() => {
        if (wire()) clearInterval(timer)
      }, 20)
    },
    { sessionId, healthy, forbidden }
  )
}

/**
 * Set an in-page flag so that it survives a full page reload.
 *
 * `page.evaluate` alone is not enough. LiveView gives up and reloads the page
 * after enough failed rejoins, which is exactly the scenario being measured;
 * a flag set only on the live page would quietly revert to its default at the
 * worst possible moment. Appending an init script makes the value part of every
 * subsequent load, and Playwright runs init scripts in the order they were
 * added, so a later call wins over an earlier one.
 */
async function setSessionFlag(session, name, value) {
  await session.context.addInitScript(
    ({ name, value }) => {
      window[name] = value
    },
    { name, value }
  )
  await session.page.evaluate(({ name, value }) => { window[name] = value }, { name, value }).catch(() => {})
}

/**
 * Reduce the raw event stream into disconnect/reconnect cycles that began at or
 * after the moment the operator was told to deploy.
 *
 * The anchor is `armedAt`, not the moment `/version` reported the change: with
 * more than one machine the socket can die before the new identity is visible
 * at the proxy, and anchoring on the observation would silently truncate the
 * window.
 */
function reconnectCycles(events, armedAt) {
  const ordered = [...events].sort((a, b) => a.at - b.at)
  const cycles = []
  let lastMessageAt = null
  let heartbeat = null
  let reloads = 0
  let current = null

  for (const e of ordered) {
    if (e.kind === 'socket-wired' && e.heartbeat_interval_ms != null) heartbeat = e.heartbeat_interval_ms
    if (e.kind === 'watcher-installed' && e.at >= armedAt) reloads += 1

    // Always advanced, never gated on whether a cycle is open. A cycle records
    // the last frame at the moment it OPENS, so frames arriving after a
    // reconnect belong to the next cycle — gating this was a bug that made a
    // second disconnect report the first one's last frame and inflated its
    // measured window by the whole first outage.
    if (e.kind === 'socket-message') {
      lastMessageAt = e.at
      continue
    }

    if (e.kind === 'socket-close' && e.at >= armedAt && !current) {
      current = { closed_at: e.at, last_frame_at: lastMessageAt, reopened_at: null, usable_at: null }
      continue
    }
    if (!current) continue

    if (e.kind === 'socket-open' && current.reopened_at === null) current.reopened_at = e.at
    if (e.kind === 'view-usable') {
      current.usable_at = e.at
      cycles.push(finish(current, heartbeat))
      current = null
    }
  }

  if (current) cycles.push(finish(current, heartbeat))
  return { cycles, reloads, heartbeat_interval_ms: heartbeat }
}

function finish(cycle, heartbeat) {
  const { closed_at, last_frame_at, reopened_at, usable_at } = cycle
  return {
    ...cycle,
    heartbeat_interval_ms: heartbeat,
    // The server stopped serving at some instant T with last_frame <= T <= close.
    // The outage the user lived through is therefore bracketed, not a number.
    outage_upper_bound_ms: usable_at != null && last_frame_at != null ? usable_at - last_frame_at : null,
    outage_lower_bound_ms: usable_at != null ? usable_at - closed_at : null,
    transport_gap_ms: reopened_at != null ? reopened_at - closed_at : null,
    completed: usable_at != null,
  }
}

// ---------------------------------------------------------------------------
// store comparison
// ---------------------------------------------------------------------------

function storesThatChanged(before, after) {
  const names = [...new Set([...Object.keys(before ?? {}), ...Object.keys(after ?? {})])]
  return names.filter(n => JSON.stringify(before?.[n]) !== JSON.stringify(after?.[n]))
}

/** Records present before and absent after, identified by their id field only
 * — contents never enter the report. */
function recordsLost(before, after) {
  const lost = []
  for (const [store, rows] of Object.entries(before ?? {})) {
    if (!Array.isArray(rows)) continue
    const survivors = new Set((after?.[store] ?? []).map(r => JSON.stringify(r)))
    for (const row of rows) {
      if (!survivors.has(JSON.stringify(row))) lost.push({ store, id: idOf(store, row) })
    }
  }
  return lost
}

function idOf(store, row) {
  const key = `${store.replace(/s$/, '')}_id`
  return row?.[key] ?? row?.id ?? '(no id field)'
}

function counts(store) {
  return Object.fromEntries(
    Object.entries(store ?? {}).map(([k, v]) => [k, Array.isArray(v) ? v.length : v == null ? 0 : 1])
  )
}

// ---------------------------------------------------------------------------
// session setup — three concurrent states, one per browser context
// ---------------------------------------------------------------------------

/**
 * (a) Idle on the sticker page with a vehicle and a logged change.
 *
 * The plainest case, and the one that matters most: somebody has the app open
 * and is not touching it when the machine goes away.
 */
async function setUpIdleSession(browser, baseUrl) {
  const session = await newSession(browser, 'idle', {
    healthy: STICKER_MARKER,
    // This session has records and working storage, so every one of the three
    // storage states would be a lie about their data.
    forbidden: [EMPTY_GARAGE, DATA_MISSING, STORAGE_UNAVAILABLE],
  })
  const { page } = session

  await app.gotoConnected(page, baseUrl)
  await harness.clearAll(page)
  await app.setUpVehicle(page, baseUrl)
  await app.logOilChange(page, baseUrl)

  await app.gotoConnected(page, baseUrl)
  await page.waitForFunction(marker => document.body.innerText.includes(marker), STICKER_MARKER, {
    timeout: 20_000,
  })

  session.before = {
    store: await app.readStore(page),
    sticker: await stickerSnapshot(page),
    url: page.url(),
  }
  return session
}

/**
 * (b) Mid-selection in the vehicle cascade with an uncommitted choice.
 *
 * The confirm panel is on screen and the user has NOT pressed save. The picker
 * calls its own cascade state disposable, so this session is not asserting that
 * the selection survives — it is asserting that a deploy never turns an
 * uncommitted choice into a stored vehicle, and that the page comes back
 * operable rather than merely painted.
 */
async function setUpMidSelectionSession(browser, baseUrl) {
  const session = await newSession(browser, 'mid-selection', {
    healthy: PICKER_MARKER,
    // This session genuinely has no records, so the empty-garage copy would be
    // TRUE and is not forbidden. Claiming the records are gone, or that storage
    // could not be used, would both be lies.
    forbidden: [DATA_MISSING, STORAGE_UNAVAILABLE],
  })
  const { page } = session

  await app.gotoConnected(page, baseUrl)
  await harness.clearAll(page)
  await app.gotoConnected(page, `${baseUrl}/vehicle/select`)
  await page.waitForSelector('select[name=year]')

  await page.selectOption('select[name=year]', '2021')
  await page.waitForFunction(() => document.querySelector('select[name=make_id]').options.length > 1)
  const makeValue = await page.$eval('select[name=make_id]', s => [...s.options].find(o => o.value)?.value)
  await page.selectOption('select[name=make_id]', makeValue)

  await page.waitForFunction(() => document.querySelector('select[name=model_id]').options.length > 1)
  const modelValue = await page.$eval('select[name=model_id]', s => [...s.options].find(o => o.value)?.value)
  await page.selectOption('select[name=model_id]', modelValue)

  await page.waitForFunction(() =>
    document.querySelector('select[name=configuration_key]').options.length > 1
  )
  const configValue = await page.$eval('select[name=configuration_key]', s =>
    [...s.options].find(o => o.value)?.value
  )
  await page.selectOption('select[name=configuration_key]', configValue)

  // The confirm panel proves the choice is complete and uncommitted. It is
  // never clicked.
  await page.waitForSelector('[data-test=confirm-panel]')

  session.before = {
    store: await app.readStore(page),
    cascade: await cascadeSnapshot(page),
    url: page.url(),
  }
  return session
}

/**
 * (c) A mutation staged but deliberately unacknowledged.
 *
 * `Session.stage_mutation/4` assigns a mutation_id, pushes `local_store:put`,
 * arms a 2 s ack timeout, and hands navigation to the ack. Suppressing the
 * client's `local_store:ack` frame therefore leaves the server holding a
 * pending write it will never hear about — which is precisely the in-flight
 * state ADR-0004 claims survives a deploy.
 *
 * Whether the browser nonetheless committed the record to IndexedDB is NOT
 * assumed here; it is measured before the deploy and reported, because the two
 * cases lead to different honest outcomes afterwards.
 */
async function setUpPendingWriteSession(browser, baseUrl) {
  const session = await newSession(browser, 'pending-write', {
    // This session ends on /service/new, not on the sticker.
    healthy: FORM_MARKER,
    forbidden: [EMPTY_GARAGE, DATA_MISSING, STORAGE_UNAVAILABLE],
  })
  const { page } = session

  // Acks must work while the baseline records are being created — the harness
  // gates navigation on them.
  await app.gotoConnected(page, baseUrl)
  await harness.clearAll(page)
  await app.setUpVehicle(page, baseUrl)
  await app.logOilChange(page, baseUrl)

  await app.gotoConnected(page, baseUrl)
  await page.waitForFunction(marker => document.body.innerText.includes(marker), STICKER_MARKER, {
    timeout: 20_000,
  })

  const committed = await app.readStore(page)

  // From here on the browser's acks never reach the server.
  await setSessionFlag(session, '__dosDropAcks', true)

  await stageChangeWithoutAck(page, baseUrl)
  // The server's ack timeout is 2 s (Session @ack_timeout_ms); give it room to
  // fire so the pre-deploy notice state is a measurement, not a race.
  await page.waitForTimeout(4000)

  session.before = {
    store: committed,
    storeAfterStaging: await app.readStore(page),
    unsavedNoticeShown: await hasUnsavedNotice(page),
    url: page.url(),
  }
  session.stagedLanded =
    JSON.stringify(counts(session.before.storeAfterStaging)) !== JSON.stringify(counts(committed))
  return session
}

/**
 * The oil-change form, filled and submitted, with no expectation that it
 * commits.
 *
 * `app.logOilChange` cannot be reused here: it is DEFINED by the commit — it
 * waits for the ack-gated navigation and retries the whole flow once when that
 * does not happen, which would remount the LiveView, discard the pending-write
 * ledger this session exists to hold, and stage a second duplicate write. The
 * selectors below are deliberately identical to that helper's; if the form
 * changes, both change together.
 */
async function stageChangeWithoutAck(page, baseUrl) {
  await app.gotoConnected(page, `${baseUrl}/service/new`)
  await page.waitForSelector('select[name="service_date[month]"]')

  await page.selectOption('select[name="service_date[month]"]', '3')
  await page.selectOption('select[name="service_date[year]"]', String(new Date().getFullYear()))
  await page.selectOption('select[name="service_date[day]"]', '15')
  await page.fill('input[name="odometer[value]"]', '57000')
  await page.check('input[name="oil[base_stock]"][value=full_synthetic]')

  const grade = await page.$eval(
    'select[name="oil[grade]"]',
    s => [...s.querySelectorAll('optgroup option')].map(o => o.value)[0] ?? null
  )
  if (grade) await page.selectOption('select[name="oil[grade]"]', grade)

  // Confirm the server actually received the form before submitting, for the
  // same reason app.logOilChange does: a dropped change event looks exactly
  // like a product defect from the outside.
  await page.waitForFunction(
    () =>
      document.querySelector('select[name="service_date[day]"]').value === '15' &&
      document.querySelector('input[name="odometer[value]"]').value !== '',
    null,
    { timeout: 10_000 }
  )

  await page.click('button[type=submit]')
}

async function newSession(browser, id, { healthy, forbidden }) {
  const context = await browser.newContext()
  const page = await context.newPage()
  const events = []
  const consoleErrors = []

  page.on('pageerror', err => consoleErrors.push(firstLine(err.message)))
  page.on('console', msg => {
    if (msg.type() === 'error') consoleErrors.push(firstLine(msg.text()))
  })

  // The suite's own protocol trace, so hydrate/put/ack ordering across the
  // deploy is on the record alongside the timings.
  const protocol = await app.traceProtocol(page)
  await installWatcher(context, { sessionId: id.replace(/-/g, '_'), healthy, forbidden, sink: events })

  return { id, context, page, events, protocol, consoleErrors, before: null }
}

async function stickerSnapshot(page) {
  return page.evaluate(() =>
    Object.fromEntries(
      ['sticker-date', 'sticker-mileage', 'sticker-grade'].map(t => [
        t,
        document.querySelector(`[data-test=${t}]`)?.innerText ?? null,
      ])
    )
  )
}

async function cascadeSnapshot(page) {
  return page.evaluate(() =>
    Object.fromEntries(
      ['year', 'make_id', 'model_id', 'configuration_key'].map(n => [
        n,
        document.querySelector(`select[name=${n}]`)?.value ?? null,
      ])
    )
  )
}

async function hasUnsavedNotice(page) {
  return page.evaluate(
    marker =>
      !!document.querySelector('[data-test=unsaved-writes]') ||
      (document.body.innerText || '').includes(marker),
    UNSAVED_NOTICE
  )
}

// ---------------------------------------------------------------------------
// the wait — the operator deploys, this polls
// ---------------------------------------------------------------------------

async function waitForDeploy(args, baseline, armedAt) {
  const field = SIGNAL_FIELD[args.signal]
  const deadline = armedAt + args.waitMin * 60_000
  const observations = []
  let stable = 0
  let firstChangeAt = null

  while (Date.now() < deadline) {
    await sleep(args.pollMs)

    let current
    try {
      current = await fetchVersion(args.baseUrl)
    } catch (err) {
      // A machine being replaced answers with an error or not at all. That is
      // the deploy happening, not a reason to give up.
      observations.push({ at: Date.now(), error: firstLine(err.message) })
      stable = 0
      continue
    }

    observations.push({
      at: Date.now(),
      git_sha: current.git_sha,
      fly_release_version: current.fly_release_version,
      fly_machine_id: current.fly_machine_id,
    })

    if (current[field] === baseline[field]) {
      stable = 0
      continue
    }

    if (firstChangeAt === null) {
      firstChangeAt = Date.now()
      console.error(`\n  ${field} changed: ${baseline[field]} -> ${current[field]}`)
      console.error(`  holding for ${args.settlePolls} consecutive polls before measuring...`)
    }

    stable += 1
    if (stable >= args.settlePolls) {
      return { observed: true, current, firstChangeAt, stableAt: Date.now(), observations }
    }
  }

  return { observed: false, current: null, firstChangeAt, stableAt: null, observations }
}

// ---------------------------------------------------------------------------
// assertions
// ---------------------------------------------------------------------------

function assertReconnected(session, armedAt) {
  const { cycles, reloads, heartbeat_interval_ms } = reconnectCycles(session.events, armedAt)
  const evidence = { cycles, reloads, heartbeat_interval_ms, console_errors: session.consoleErrors.slice(0, 10) }

  if (cycles.length === 0) {
    return {
      status: FAIL,
      detail:
        'the socket never closed during the deploy — either the session was already dead before the ' +
        'deploy, or the client never noticed. Neither is a session that survived one.',
      evidence,
    }
  }

  const incomplete = cycles.filter(c => !c.completed)
  if (incomplete.length) {
    return {
      status: FAIL,
      detail: `${incomplete.length} of ${cycles.length} disconnect(s) never reached a usable view again`,
      evidence,
    }
  }

  const first = cycles[0]
  return {
    status: PASS,
    detail: null,
    evidence: {
      ...evidence,
      // Stated as a bracket on purpose. See the header.
      outage_ms_between: [first.outage_lower_bound_ms, first.outage_upper_bound_ms],
    },
  }
}

function assertNoFalseClaim(session, forbiddenNames) {
  const all = session.events.filter(e => e.kind === 'forbidden-claim')
  // Pre-arm hits are reported, never asserted on: a session that is being set
  // up passes legitimately through the empty-garage state on its way to having
  // records, and that copy was true when it was shown.
  const preflight = all.filter(e => e.armed !== true)
  const hits = all.filter(e => e.armed === true)

  const evidence = {
    patterns_watched: forbiddenNames,
    frames_flagged: hits.length,
    preflight_hits_not_asserted_on: preflight.map(h => ({ pattern: h.pattern, at: h.at })),
  }

  if (hits.length === 0) return { status: PASS, evidence }

  return {
    status: FAIL,
    detail:
      `the app told this session ${hits.length === 1 ? 'a claim' : 'claims'} that were untrue of its data: ` +
      hits.map(h => `/${h.pattern}/`).join(', '),
    evidence: { ...evidence, hits: hits.map(h => ({ pattern: h.pattern, at: h.at, excerpt: h.excerpt })) },
  }
}

// ---------------------------------------------------------------------------
// per-engine run
// ---------------------------------------------------------------------------

async function measureIdle(session, report, engineKey, armedAt) {
  report.record(engineKey, {
    id: 'deploy.idle.reconnected',
    requirement: 'INV-7',
    ...assertReconnected(session, armedAt),
  })

  report.record(engineKey, {
    id: 'deploy.idle.no-false-storage-claim',
    requirement: 'INV-24.3',
    ...assertNoFalseClaim(session, ['empty-garage', 'data-missing', 'storage-unavailable']),
  })

  const after = await stickerSnapshot(session.page)
  const same = JSON.stringify(after) === JSON.stringify(session.before.sticker)
  report.record(engineKey, {
    id: 'deploy.idle.rehydrated',
    requirement: 'INV-24.1',
    status: same ? PASS : FAIL,
    detail: same
      ? null
      : 'the sticker did not come back to the values it held before the deploy; hydration did not ' +
        'restore the view the user was looking at',
    evidence: { before: session.before.sticker, after },
  })

  const afterStore = await app.readStore(session.page)
  const changed = storesThatChanged(session.before.store, afterStore)
  report.record(engineKey, {
    id: 'deploy.idle.records-identical',
    requirement: 'INV-23',
    status: changed.length === 0 ? PASS : FAIL,
    detail:
      changed.length === 0
        ? null
        : `a deploy changed browser-held records in an idle session; stores that differ: ${changed.join(', ')}`,
    evidence: { before: counts(session.before.store), after: counts(afterStore), changed },
  })
}

async function measureMidSelection(session, report, engineKey, armedAt) {
  report.record(engineKey, {
    id: 'deploy.mid-selection.reconnected',
    requirement: 'INV-7',
    ...assertReconnected(session, armedAt),
  })

  report.record(engineKey, {
    id: 'deploy.mid-selection.no-false-storage-claim',
    requirement: 'INV-25',
    ...assertNoFalseClaim(session, ['data-missing', 'storage-unavailable']),
  })

  const afterStore = await app.readStore(session.page)
  const vehicles = (afterStore.vehicles ?? []).length
  report.record(engineKey, {
    id: 'deploy.mid-selection.uncommitted-choice-not-committed',
    requirement: 'INV-24.2',
    status: vehicles === 0 ? PASS : FAIL,
    detail:
      vehicles === 0
        ? null
        : `a choice the user never confirmed became ${vehicles} stored vehicle(s) across the deploy`,
    evidence: { before: counts(session.before.store), after: counts(afterStore) },
  })

  // Operable, not merely painted: drive one real cascade change and require the
  // catalog round trip to come back.
  const cascadeAfter = await cascadeSnapshot(session.page)
  let operable = false
  let operableDetail = null
  let probeYear = null
  try {
    // A year taken from the options the page is actually offering, not a
    // literal: a hardcoded year that the catalog does not carry would fail this
    // assertion for a reason that has nothing to do with the deploy.
    probeYear = await session.page.$eval('select[name=year]', s => {
      const values = [...s.options].map(o => o.value).filter(Boolean)
      return values.find(v => v !== s.value) ?? null
    })
    if (probeYear === null) throw new Error('the year select offers no second option to switch to')

    await session.page.selectOption('select[name=year]', probeYear)
    await session.page.waitForFunction(
      () => document.querySelector('select[name=make_id]').options.length > 1,
      null,
      { timeout: 20_000 }
    )
    operable = true
  } catch (err) {
    operableDetail = firstLine(err.message)
  }

  report.record(engineKey, {
    id: 'deploy.mid-selection.operable-after-reconnect',
    requirement: 'INV-7',
    status: operable ? PASS : FAIL,
    detail: operable
      ? null
      : `after reconnect the cascade did not answer a new selection: ${operableDetail ?? 'no makes loaded'}`,
    evidence: {
      probe_year: probeYear,
      // Reported, not asserted: the picker documents its cascade state as
      // disposable, so a reset here is honest behaviour, not a defect. What
      // would be a defect is a silently committed vehicle, asserted above.
      selection_before: session.before.cascade,
      selection_after: cascadeAfter,
      selection_survived: JSON.stringify(cascadeAfter) === JSON.stringify(session.before.cascade),
    },
  })
}

async function measurePendingWrite(session, report, engineKey, armedAt) {
  report.record(engineKey, {
    id: 'deploy.pending-write.reconnected',
    requirement: 'INV-7',
    ...assertReconnected(session, armedAt),
  })

  report.record(engineKey, {
    id: 'deploy.pending-write.no-false-storage-claim',
    requirement: 'INV-24.3',
    ...assertNoFalseClaim(session, ['empty-garage', 'data-missing', 'storage-unavailable']),
  })

  const afterStore = await app.readStore(session.page)
  const lost = recordsLost(session.before.store, afterStore)
  report.record(engineKey, {
    id: 'deploy.pending-write.prior-records-survived',
    requirement: 'INV-24.5',
    status: lost.length === 0 ? PASS : FAIL,
    detail:
      lost.length === 0
        ? null
        : `${lost.length} record(s) committed before the deploy are no longer in this browser`,
    evidence: { lost, before: counts(session.before.store), after: counts(afterStore) },
  })

  const noticeAfter = await hasUnsavedNotice(session.page)
  const stagedPresent =
    JSON.stringify(counts(afterStore)) !== JSON.stringify(counts(session.before.store))

  // Two honest outcomes, one dishonest one. Either the write is now in the
  // browser (re-driven after remount, or already durable because IndexedDB
  // accepted it while the ack was being dropped), or the app is still telling
  // the user it was not saved. Neither, and the user believes they recorded an
  // oil change that does not exist.
  const honest = stagedPresent || noticeAfter
  report.record(engineKey, {
    id: 'deploy.pending-write.resolved-honestly',
    requirement: 'INV-24.2',
    status: honest ? PASS : FAIL,
    detail: honest
      ? null
      : 'a write that was in flight when the machine was replaced is neither in this browser nor ' +
        'reported as unsaved. The user was shown the entry, the entry is gone, and nothing says so. ' +
        'ADR-0004 claims pending writes are re-driven after remount; this run says they are not.',
    evidence: {
      staged_reached_indexeddb_before_deploy: session.stagedLanded,
      unsaved_notice_before_deploy: session.before.unsavedNoticeShown,
      unsaved_notice_after_deploy: noticeAfter,
      staged_record_present_after_deploy: stagedPresent,
      acks_dropped: session.events.filter(e => e.kind === 'ack-dropped').length,
      // The browser had the record while the app said it did not. Over-warning
      // is the safe direction and is not a failure, but it is a real gap
      // between what the server believes and what the browser holds.
      over_warned_before_deploy: !!(session.stagedLanded && session.before.unsavedNoticeShown),
      protocol_events_after_reconnect: session.protocol.filter(e => e.at >= armedAt).map(e => e.event),
    },
  })
}

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

let REPORT = null
let ARGS = null

async function main() {
  ARGS = parseArgs(process.argv)
  const matrix = loadMatrix(REPO_ROOT)
  const startedAt = new Date().toISOString()
  REPORT = new Report({ release: ARGS.release, startedAt, matrix })

  installAbortHandler()

  const baseline = await fetchVersion(ARGS.baseUrl)
  console.error(`deploy rehearsal — ${ARGS.baseUrl}\n\nbaseline release identity:\n${identityLine(baseline)}`)

  const engines = []

  for (const engineRow of matrix.engines) {
    if (ARGS.only && ARGS.only !== engineRow.key) continue

    const entry = REPORT.engine(engineRow.key, {
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
      // An engine that will not start is unproven, not absent — and at Tier 1
      // that blocks, exactly as in the conformance runner.
      console.error(`  ${engineRow.key}: launch failed — ${firstLine(err.message)}`)
      continue
    }

    entry.launched = true
    entry.version = browser.version()
    console.error(`\n${engineRow.key} ${entry.version}${engineRow.proxy ? ' (proxy)' : ''} — setting up 3 sessions`)

    try {
      const idle = await setUpIdleSession(browser, ARGS.baseUrl)
      console.error('  ok   (a) idle on the sticker, vehicle + logged change')
      const mid = await setUpMidSelectionSession(browser, ARGS.baseUrl)
      console.error('  ok   (b) mid-cascade, choice complete and unconfirmed')
      const pending = await setUpPendingWriteSession(browser, ARGS.baseUrl)
      console.error(
        `  ok   (c) mutation staged, ack suppressed ` +
          `(reached IndexedDB anyway: ${pending.stagedLanded}; ` +
          `"not saved" notice up: ${pending.before.unsavedNoticeShown})`
      )
      engines.push({ engineRow, browser, sessions: { idle, mid, pending } })
    } catch (err) {
      console.error(`  ${engineRow.key}: session setup failed — ${firstLine(err.message)}`)
      entry.crashed = `session setup failed: ${firstLine(err.message)}`
      await browser.close().catch(() => {})
    }
  }

  if (engines.length === 0) {
    console.error('\nno engine reached a set-up state; nothing can be measured')
    return finishReport(startedAt)
  }

  // Arm the false-claim watchers only now. Everything before this point is
  // set-up, during which a session legitimately passes through states whose
  // copy would be a lie afterwards.
  for (const { sessions } of engines) {
    for (const session of Object.values(sessions)) {
      await setSessionFlag(session, '__dosWatchArmed', true)
    }
  }

  const armedAt = Date.now()
  printOperatorInstructions(baseline, engines)

  const deploy = await waitForDeploy(ARGS, baseline, armedAt)

  for (const { engineRow } of engines) {
    if (!deploy.observed) {
      REPORT.record(engineRow.key, {
        id: 'deploy.observed',
        requirement: 'AC-11',
        status: UNPROVEN,
        detail:
          `no change in ${SIGNAL_FIELD[ARGS.signal]} was observed at ${ARGS.baseUrl}/version within ` +
          `${ARGS.waitMin} minutes. Nothing about deploy behaviour was measured; this is unproven, not a pass.`,
        evidence: { polls: deploy.observations.length, signal: ARGS.signal },
      })
      continue
    }

    const shaChanged = deploy.current.git_sha !== baseline.git_sha
    REPORT.record(engineRow.key, {
      id: 'deploy.observed',
      requirement: 'AC-11',
      status: PASS,
      detail: null,
      evidence: {
        signal: ARGS.signal,
        armed_at: armedAt,
        first_change_at: deploy.firstChangeAt,
        stable_at: deploy.stableAt,
        before: pickIdentity(baseline),
        after: pickIdentity(deploy.current),
        code_identity_changed: shaChanged,
        // Honest about the blind spot: /version is answered by whichever
        // machine the proxy picked. Two machines are running in ord while
        // fly.toml declares min_machines_running = 1.
        proves_every_machine_rolled: false,
        machine_ids_seen: [...new Set(deploy.observations.map(o => o.fly_machine_id).filter(Boolean))],
        note: shaChanged
          ? null
          : 'git_sha did not change: machines were replaced but the code identity is the same. ' +
            'This proves machine replacement, not that a new build reached users.',
      },
    })
  }

  if (!deploy.observed) {
    console.error('\nthe deploy was never observed. Every assertion is unproven.')
    await closeAll(engines)
    return finishReport(startedAt)
  }

  console.error('\ndeploy observed — releasing instrumentation and letting sessions settle')

  // Release ack suppression before measuring, so that anything the app tries to
  // re-drive after remount completes against an untampered client. Anything it
  // re-drove BEFORE this point is still visible in the protocol trace.
  for (const { sessions } of engines) {
    await setSessionFlag(sessions.pending, '__dosDropAcks', false)
  }

  // Long enough for a reconnect with backoff plus a full hydrate round trip.
  // This is a settle allowance, not a measurement: every number in the report
  // comes from the in-page timestamps, not from this sleep.
  await sleep(20_000)

  for (const { engineRow, sessions } of engines) {
    console.error(`\n${engineRow.key} — measuring`)
    try {
      await measureIdle(sessions.idle, REPORT, engineRow.key, armedAt)
      await measureMidSelection(sessions.mid, REPORT, engineRow.key, armedAt)
      await measurePendingWrite(sessions.pending, REPORT, engineRow.key, armedAt)
    } catch (err) {
      REPORT.engine(engineRow.key).crashed = `measurement failed: ${firstLine(err.message)}`
      console.error(`  ${engineRow.key}: measurement failed — ${firstLine(err.message)}`)
    }
  }

  await closeAll(engines)
  return finishReport(startedAt)
}

function printOperatorInstructions(baseline, engines) {
  const total = engines.length * 3
  console.error(`
${'='.repeat(78)}
ARMED. ${total} session(s) across ${engines.length} engine(s) are attached and holding
their target states. NOTHING WILL DEPLOY UNTIL YOU DEPLOY IT.

In another terminal:

    cd app
    flyctl deploy --app digital-oil-sticker \\
      --build-arg GIT_SHA="$(git rev-parse HEAD)" \\
      --build-arg BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  or, once FLY_API_TOKEN exists as a repository secret:

    gh workflow run deploy.yml -f reason="DOS-M09-005 AC-11/AC-12 rehearsal"

Waiting for ${SIGNAL_FIELD[ARGS.signal]} at ${ARGS.baseUrl}/version to change
from: ${baseline[SIGNAL_FIELD[ARGS.signal]] ?? '(absent)'}
Timeout: ${ARGS.waitMin} min. Ctrl-C writes a report with every assertion
unproven — an abandoned rehearsal is never recorded as a pass.

While you wait, run 'flyctl status --app digital-oil-sticker' in a third
terminal and keep the output. This script cannot see the fleet; it only sees
whatever machine the proxy hands it.
${'='.repeat(78)}
`)
}

function pickIdentity(v) {
  return {
    git_sha: v.git_sha,
    built_at: v.built_at,
    app_version: v.app_version,
    fly_release_version: v.fly_release_version ?? null,
    fly_machine_id: v.fly_machine_id ?? null,
    catalog_payload_sha256: v.catalog_payload_sha256,
  }
}

async function closeAll(engines) {
  for (const { browser } of engines) await browser.close().catch(() => {})
}

function finishReport(startedAt) {
  REPORT.fillUnrun(ASSERTIONS, 'this assertion did not run; the rehearsal did not reach it')

  const finished = new Date().toISOString()
  const json = REPORT.toJSON(finished)
  json.rehearsal = {
    kind: 'deploy',
    base_url: ARGS.baseUrl,
    signal: ARGS.signal,
    started_at: startedAt,
    // Restated in the artifact so a report read on its own carries its own
    // limits rather than depending on somebody having read this file.
    not_proven: [
      'desktop engines on Windows 11 only; Playwright webkit is not Safari and not iOS',
      'real iOS and Android deploy behaviour (backgrounded tabs, screen lock, process kill)',
      'any p95 — this is one deploy, one sample',
      'that every machine in the fleet rolled; /version is answered by one machine behind the proxy',
      'long-lived or slept sessions',
      'the deploy pipeline itself: rollback, failed readiness, half-rolled fleet',
    ],
  }

  mkdirSync(ARGS.out, { recursive: true })
  const file = join(ARGS.out, `deploy-rehearsal-${ARGS.release}-${finished.replace(/[:.]/g, '-')}.json`)
  writeFileSync(file, JSON.stringify(json, null, 2) + '\n')
  // Deliberately NOT reports/latest.json: that name belongs to the conformance
  // sweep and overwriting it would let a rehearsal masquerade as a full run.
  writeFileSync(join(ARGS.out, 'latest-deploy-rehearsal.json'), JSON.stringify(json, null, 2) + '\n')

  console.error('\n' + format(json))
  console.error(`\nreport: ${file}`)
  return json.verdict.release_blocked ? 1 : 0
}

// Ctrl-C must still produce evidence. A rehearsal somebody walked away from
// and a rehearsal that was never started have to look different on disk.
function installAbortHandler() {
  let aborting = false
  for (const signal of ['SIGINT', 'SIGTERM']) {
    process.on(signal, () => {
      if (aborting) process.exit(2)
      aborting = true
      console.error(`\n${signal} — writing a partial report; everything unreached is unproven`)
      try {
        finishReport(new Date().toISOString())
      } catch (err) {
        console.error(`could not write the partial report: ${firstLine(err.message)}`)
      }
      process.exit(1)
    })
  }
}

function firstLine(message) {
  return String(message).split('\n')[0]
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms))
}

main()
  .then(code => process.exit(code ?? 0))
  .catch(err => {
    console.error(err)
    process.exit(2)
  })
