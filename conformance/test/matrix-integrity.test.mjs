// Matrix-integrity and report-writer tests (test plan "Automated").
// Run with: node --test test/
//
// These are the assertions about the SUITE rather than about the app: that the
// matrix and the runner cannot drift apart, and that `unproven` really does
// block. A report writer that quietly treats "did not run" as "fine" would
// invalidate every other result in this directory.

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

import { loadMatrix } from '../src/matrix.mjs'
import { Report, verdict, PASS, FAIL, UNPROVEN } from '../src/report.mjs'

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const matrix = loadMatrix(REPO_ROOT)

test('the matrix declares at least one engine and every one has a driver', () => {
  assert.ok(matrix.engines.length >= 1)
  for (const e of matrix.engines) {
    assert.ok(['chromium', 'firefox', 'webkit'].includes(e.key), `${e.engine} has no driver`)
    assert.ok(Number.isInteger(e.tier), `${e.engine} has no tier`)
  }
})

test('an engine the matrix calls a proxy records what it stands in for', () => {
  for (const e of matrix.engines.filter(e => e.proxy)) {
    assert.ok(e.proxy_for, `${e.engine} is a proxy but does not say for what`)
  }
})

test('the matrix states a staleness window as a number of days', () => {
  assert.ok(matrix.stalenessDays > 0 && matrix.stalenessDays <= 365)
})

test('every engine the runner can drive is one the matrix names', async () => {
  // The correspondence FR-1 requires, in the direction that matters: the runner
  // must not be able to run something the document does not promise.
  const { default: runnerSource } = await import('node:fs').then(fs => ({
    default: fs.readFileSync(join(REPO_ROOT, 'conformance', 'bin', 'dos-conformance.mjs'), 'utf8'),
  }))

  // The runner selects engines only from the parsed matrix.
  assert.ok(
    runnerSource.includes('for (const engineRow of matrix.engines)'),
    'the runner must iterate the matrix, not a hardcoded engine list'
  )
})

test('a status outside pass/fail/unproven is rejected', () => {
  const report = new Report({ release: 'test', startedAt: 'now', matrix })
  report.engine('chromium', { tier: 1 })

  assert.throws(
    () => report.record('chromium', { id: 'x', requirement: 'FR-0', status: 'skipped' }),
    /only pass\/fail\/unproven/
  )
})

test('a non-pass without a reason is rejected', () => {
  const report = new Report({ release: 'test', startedAt: 'now', matrix })
  report.engine('chromium', { tier: 1 })

  assert.throws(
    () => report.record('chromium', { id: 'x', requirement: 'FR-0', status: FAIL }),
    /without a reason/
  )
})

test('unproven blocks the release exactly as fail does', () => {
  const failing = verdict([
    { key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'a', status: FAIL, detail: 'broke' }] },
  ])
  const unproven = verdict([
    { key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'a', status: UNPROVEN, detail: 'never ran' }] },
  ])

  assert.equal(failing.release_blocked, true)
  assert.equal(unproven.release_blocked, true)
})

test('an engine that could not be launched blocks, rather than vanishing', () => {
  const v = verdict([{ key: 'webkit', tier: 1, launched: false, assertions: [] }])

  assert.equal(v.release_blocked, true)
  assert.match(v.blocking[0].reason, /could not be executed/)
})

test('a stale engine blocks even when every assertion passed', () => {
  const v = verdict([
    { key: 'firefox', tier: 1, launched: true, stale: true, assertions: [{ id: 'a', status: PASS }] },
  ])

  assert.equal(v.release_blocked, true)
})

test('tier 2 is reported without blocking', () => {
  const v = verdict([
    { key: 'chromium', tier: 2, launched: true, assertions: [{ id: 'a', status: FAIL, detail: 'broke' }] },
  ])

  assert.equal(v.release_blocked, false)
})

test('an assertion no engine ran is filled in as unproven, not dropped', () => {
  const report = new Report({ release: 'test', startedAt: 'now', matrix })
  report.engine('chromium', { tier: 1, launched: true })
  report.record('chromium', { id: 'ran', requirement: 'FR-1', status: PASS })

  report.fillUnrun(
    [
      { id: 'ran', requirement: 'FR-1' },
      { id: 'never-ran', requirement: 'FR-2' },
    ],
    'engine did not run this assertion'
  )

  const json = report.toJSON('later')
  const missing = json.engines[0].assertions.find(a => a.id === 'never-ran')

  assert.equal(missing.status, UNPROVEN)
  assert.equal(json.verdict.release_blocked, true)
})

test('a clean tier 1 run does not block', () => {
  const v = verdict([
    { key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'a', status: PASS }, { id: 'b', status: PASS }] },
  ])

  assert.equal(v.release_blocked, false)
})

// -- baseline behaviour ------------------------------------------------------
//
// The baseline exists so the gate is not permanently red. These assert it
// cannot quietly become a permission slip.

import { readFileSync } from 'node:fs'

const BASELINE = JSON.parse(readFileSync(join(REPO_ROOT, 'conformance', 'baseline.json'), 'utf8')).unproven

test('every baseline entry says why it is unrunnable and what would make it runnable', () => {
  for (const entry of BASELINE) {
    assert.ok(entry.id, 'entry has no assertion id')
    assert.ok(entry.reason && entry.reason.length > 10, `${entry.id} has no reason`)
    assert.ok(entry.runnable_when && entry.runnable_when.length > 10, `${entry.id} does not say what would make it runnable`)
    assert.match(entry.accepted_on, /^\d{4}-\d{2}-\d{2}$/, `${entry.id} has no acceptance date`)
  }
})

test('a baselined unproven assertion does not block', () => {
  const v = verdict(
    [{ key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'known', status: UNPROVEN, detail: 'cannot run' }] }],
    [{ id: 'known', reason: 'x', runnable_when: 'y' }]
  )

  assert.equal(v.release_blocked, false)
  assert.equal(v.accepted_unproven.length, 1)
})

test('an unproven assertion that is NOT baselined still blocks', () => {
  const v = verdict(
    [{ key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'new', status: UNPROVEN, detail: 'cannot run' }] }],
    [{ id: 'known', reason: 'x', runnable_when: 'y' }]
  )

  assert.equal(v.release_blocked, true)
})

test('a FAILING assertion blocks even when its id is baselined', () => {
  // The baseline is for assertions that cannot RUN. One that runs and comes
  // out wrong is a regression, and no entry may excuse it.
  const v = verdict(
    [{ key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'known', status: FAIL, detail: 'broke' }] }],
    [{ id: 'known', reason: 'x', runnable_when: 'y' }]
  )

  assert.equal(v.release_blocked, true)
})

test('a baselined assertion that starts passing blocks, so the entry gets removed', () => {
  const v = verdict(
    [{ key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'known', status: PASS }] }],
    [{ id: 'known', reason: 'the import path does not exist', runnable_when: 'y' }]
  )

  assert.equal(v.release_blocked, true)
  assert.match(v.blocking[0].reason, /baselined as unproven but it PASSED/)
})

test('a baseline entry naming an assertion the suite no longer produces blocks', () => {
  const v = verdict(
    [{ key: 'chromium', tier: 1, launched: true, assertions: [{ id: 'real', status: PASS }] }],
    [{ id: 'deleted-long-ago', reason: 'x', runnable_when: 'y' }]
  )

  assert.equal(v.release_blocked, true)
  assert.match(v.blocking[0].reason, /does not produce/)
})

test('device-exercised rows are separated from launchable engines, not silently dropped', () => {
  // The Android row lives in the same table because the matrix is the single
  // authority, but the desktop sweep must not try to launch it. Before this was
  // explicit, the row was excluded only because "**Chromium (Android)**" did
  // not happen to match the engine regex — an accident, not an exclusion.
  assert.ok(Array.isArray(matrix.devices), 'the matrix exposes no device rows')

  const launchable = new Set(matrix.engines.map(e => e.key))
  assert.equal(launchable.size, matrix.engines.length, 'an engine is listed twice')

  for (const d of matrix.devices) {
    assert.ok(d.engine && d.host_os, 'a device row is missing its engine or host')
    assert.ok(Number.isInteger(d.tier), `${d.engine} has no tier`)
  }
})

test('an engine row with no known driver is a loud failure, not a skip', () => {
  // Guards the direction that matters: adding a browser to the matrix without
  // teaching the runner to drive it must not quietly reduce coverage.
  const source = readFileSync(join(REPO_ROOT, 'conformance', 'src', 'matrix.mjs'), 'utf8')

  assert.match(source, /throw new Error\(/)
  assert.match(source, /no known driver/)
})
