// The conformance report (FR-19, FR-20, AC-18).
//
// The whole point of this module is that there is no third outcome that can be
// mistaken for a pass. An assertion is `pass`, `fail`, or `unproven`, and
// `unproven` is not a softer word for "skipped" — at Tier 1 it fails the run
// exactly as `fail` does. A case that never ran is a case we do not know about,
// and a release must not treat "we did not look" as "we looked and it was fine".

export const PASS = 'pass'
export const FAIL = 'fail'
export const UNPROVEN = 'unproven'

export const REPORT_SCHEMA_VERSION = 1

export class Report {
  constructor({ release, startedAt, matrix }) {
    this.release = release
    this.startedAt = startedAt
    this.matrix = matrix
    this.engines = new Map()
  }

  engine(key, meta) {
    if (!this.engines.has(key)) {
      this.engines.set(key, { key, ...meta, assertions: [] })
    }
    return this.engines.get(key)
  }

  record(engineKey, assertion) {
    const { id, requirement, status, detail, evidence } = assertion

    if (![PASS, FAIL, UNPROVEN].includes(status)) {
      throw new Error(`assertion ${id} has status ${status}; only pass/fail/unproven exist`)
    }
    if (status !== PASS && !detail) {
      throw new Error(`assertion ${id} is ${status} without a reason — an unexplained non-pass is not reportable`)
    }

    this.engine(engineKey).assertions.push({ id, requirement, status, detail: detail ?? null, evidence: evidence ?? null })
  }

  // Every assertion the suite knows how to make, for every engine that did not
  // run it. Called at the end so a crashed or skipped case cannot vanish.
  fillUnrun(expectedIds, reason) {
    for (const engine of this.engines.values()) {
      const seen = new Set(engine.assertions.map(a => a.id))
      for (const { id, requirement } of expectedIds) {
        if (!seen.has(id)) {
          engine.assertions.push({ id, requirement, status: UNPROVEN, detail: reason, evidence: null })
        }
      }
    }
  }

  toJSON(finishedAt) {
    const engines = [...this.engines.values()].map(e => ({
      ...e,
      totals: countBy(e.assertions),
    }))

    return {
      report_schema_version: REPORT_SCHEMA_VERSION,
      release: this.release,
      started_at: this.startedAt,
      finished_at: finishedAt,
      matrix_revision: this.matrix.revision,
      engines,
      verdict: verdict(engines),
    }
  }
}

function countBy(assertions) {
  return assertions.reduce(
    (acc, a) => ({ ...acc, [a.status]: (acc[a.status] ?? 0) + 1 }),
    { [PASS]: 0, [FAIL]: 0, [UNPROVEN]: 0 }
  )
}

/**
 * The release gate. A Tier 1 engine must be all-pass; anything else — a
 * failure, an assertion that did not run, a stale engine, or an engine that
 * could not be launched at all — blocks. Tier 2 is reported and does not block.
 */
export function verdict(engines) {
  const blocking = []

  for (const engine of engines) {
    if (engine.tier !== 1) continue

    if (engine.launched === false) {
      blocking.push({ engine: engine.key, reason: 'tier 1 engine could not be executed', status: UNPROVEN })
      continue
    }
    if (engine.crashed) {
      blocking.push({ engine: engine.key, reason: `tier 1 engine stopped responding: ${engine.crashed}`, status: UNPROVEN })
    }
    if (engine.stale) {
      blocking.push({ engine: engine.key, reason: 'tier 1 engine last run is older than the staleness window', status: UNPROVEN })
    }
    for (const a of engine.assertions) {
      if (a.status !== PASS) {
        blocking.push({ engine: engine.key, assertion: a.id, reason: a.detail, status: a.status })
      }
    }
  }

  return { release_blocked: blocking.length > 0, blocking }
}

/**
 * Human-readable summary. Deliberately prints `unproven` in the same column as
 * `fail` so a skimmed terminal cannot leave the impression of a clean run.
 */
export function format(report) {
  const lines = []
  lines.push(`conformance ${report.release} — matrix ${report.matrix_revision}`)

  for (const e of report.engines) {
    const t = e.totals
    const proxy = e.proxy ? ` (proxy for ${e.proxy_for})` : ''
    const launch = e.launched === false ? ' NOT LAUNCHED' : ''
    lines.push(
      `  tier ${e.tier} ${e.key} ${e.version ?? '?'}${proxy}${launch}: ` +
        `${t.pass} pass, ${t.fail} fail, ${t.unproven} unproven`
    )
    for (const a of e.assertions.filter(a => a.status !== PASS)) {
      lines.push(`    ${a.status.toUpperCase()} ${a.id} [${a.requirement}] — ${a.detail}`)
    }
  }

  const v = report.verdict
  lines.push(v.release_blocked ? `RELEASE BLOCKED — ${v.blocking.length} blocking result(s)` : 'release not blocked')
  return lines.join('\n')
}
