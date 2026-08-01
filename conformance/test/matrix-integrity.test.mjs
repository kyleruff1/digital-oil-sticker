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
