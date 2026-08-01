#!/usr/bin/env node
// Assembles planning/roadmap.yml from planning/fragments/M*.json plus the
// master prompt's section-12 Project metadata defaults. Deterministic: same
// fragments in, same YAML out. Run `roadmap-sync.mjs hash --write` afterwards.

import { readFileSync } from 'node:fs'
import { writeFileAtomic, fail } from './lib/util.mjs'
import { quote } from './lib/yaml.mjs'
import { CUSTOM_FIELDS } from './steps/project.mjs'
import { STATUS_OPTIONS, EXPECTED_CHILD_COUNTS } from './lib/catalog.mjs'

const REPO = {
  owner: 'kyleruff1',
  name: 'digital-oil-sticker',
  visibility: 'private',
  description: 'Offline-first digital oil-change record and reminder built with Elixir, Phoenix LiveView, Mob, and SQLite',
  topics: ['elixir', 'phoenix-liveview', 'mob', 'sqlite', 'ios', 'android', 'offline-first', 'vehicle-maintenance'],
}
const PROJECT_TITLE = 'Digital Oil Sticker — Product Roadmap'

const LABELS = [
  ['kind:epic', '6F42C1', 'Milestone epic parent issue'],
  ['kind:feature', '1D76DB', 'User-facing capability'],
  ['kind:task', '0E8A16', 'Process or pipeline or infrastructure work'],
  ['kind:spike', 'FBCA04', 'Timeboxed proof or investigation'],
  ['kind:bug', 'D73A4A', 'Defect'],
  ['kind:docs', '0075CA', 'Documentation or specification deliverable'],
  ['platform:ios', 'BFDADC', 'iOS-specific work'],
  ['platform:android', 'C2E0C6', 'Android-specific work'],
  ['platform:netlify', 'F9D0C4', 'Netlify static site work'],
  ['quality:accessibility', '5319E7', 'Accessibility is the central subject'],
  ['quality:privacy', 'B60205', 'Privacy is the central subject'],
  ['quality:security', 'D93F0B', 'Security is the central subject'],
  ['quality:performance', 'FEF2C0', 'Performance is the central subject'],
  ['needs:decision', 'D4C5F9', 'Blocked on a product or architecture decision'],
  ['needs:design', 'C5DEF5', 'Needs UX design or specification'],
  ['needs:data-validation', 'BFD4F2', 'Needs data quality or coverage validation'],
  ['needs:qa', 'F9C74F', 'Needs QA execution or evidence'],
  ['needs:license', 'E99695', 'Blocked on data-source rights or licensing'],
]

const MILESTONES = [
  ['M00', 'M00 — Decisions and proof', 'Freeze the feasible product architecture before feature development.'],
  ['M01', 'M01 — Engineering foundation', 'Establish a reproducible, offline-safe engineering platform.'],
  ['M02', 'M02 — UX and content contract', 'Freeze the mobile interaction and language model before feature UI is built.'],
  ['M03', 'M03 — Data acquisition and offline catalog', 'Acquire rights-approved sources and compile a deterministic offline catalog.'],
  ['M04', 'M04 — Local domain and persistence', 'Implement the dual on-device Ecto/SQLite repositories and their lifecycles.'],
  ['M05', 'M05 — Single-vehicle offline MVP', 'Deliver the single-vehicle, local-only, offline MVP.'],
  ['M06', 'M06 — Forecasting and local reminders', 'Usage forecasting and on-device local notifications.'],
  ['M07', 'M07 — Hardening, beta, and release', 'Hardening, closed beta, and store release.'],
  ['M08', 'M08 — Post-MVP multi-vehicle and catalog operations', 'Post-MVP multi-vehicle garage and signed catalog operations.'],
  ['M09', 'M09 — Hosted browser platform and anonymous client storage', 'Browser-first delivery: Fly.io hosting, anonymous IndexedDB client storage, and the LiveView hydration protocol (pivot 2026-08-01).'],
]

// Section 12 epic-level DAG.
const EPIC_DAG = {
  M00: [], M01: ['M00'], M02: ['M00'], M03: ['M00'],
  M04: ['M01', 'M03'], M05: ['M02', 'M04'], M06: ['M05'],
  M07: ['M03', 'M06'], M08: ['M07'],
  // Pivot 2026-08-01: browser delivery depends on the frozen UX contract and
  // the catalog/domain work; it does not depend on the deferred native track.
  M09: ['M02', 'M04'],
}

// Section 12 metadata defaults. The two M03 source-rights/data-contract gates
// share the M00 gate treatment.
const GATE_IDS = new Set(['DOS-M03-001', 'DOS-M03-002'])
function defaults(issue, milestone) {
  const gate = milestone === 'M00' || GATE_IDS.has(issue.id)
  const priority = gate ? 'P0 Critical' : milestone === 'M08' ? 'P3 Low' : 'P1 High'
  const risk = gate ? 'High' : ''
  const target = gate ? 'Gate' : milestone === 'M07' ? 'Launch' : milestone === 'M08' ? 'Post-MVP' : 'MVP'
  return {
    priority: issue.priorityOverride ?? priority,
    risk: issue.riskOverride ?? risk,
    target: issue.targetOverride ?? target,
  }
}

const milestoneIds = MILESTONES.map(m => m[0])
const issues = []
for (const [idx, ms] of milestoneIds.entries()) {
  const frag = JSON.parse(readFileSync(`planning/fragments/${ms}.json`, 'utf8'))
  if (frag.milestone !== ms) fail(`${ms}.json declares milestone ${frag.milestone}`)
  const epic = frag.issues.find(i => i.type === 'epic')
  const children = frag.issues.filter(i => i.type === 'child')
  if (!epic || epic.id !== `DOS-${ms}-000`) fail(`${ms}: missing epic DOS-${ms}-000`)
  if (children.length !== EXPECTED_CHILD_COUNTS[ms]) fail(`${ms}: expected ${EXPECTED_CHILD_COUNTS[ms]} children, fragment has ${children.length}`)

  for (const issue of frag.issues) {
    const isEpic = issue.type === 'epic'
    const position = isEpic ? 0 : Number(issue.id.slice(-3))
    const d = defaults(issue, ms)
    const blockedBy = isEpic
      ? EPIC_DAG[ms].map(up => `DOS-${up}-000`)
      : [...new Set(issue.blockedBy ?? [])].sort()
    issues.push({
      id: issue.id,
      title: issue.title,
      type: issue.type,
      variant: issue.variant ?? 'standard',
      milestone: ms,
      parent: isEpic ? '' : `DOS-${ms}-000`,
      blockedBy,
      labels: issue.labels,
      body: `planning/issues/${issue.id}.md`,
      // Backlog is the bootstrap default; a fragment may record a deliberate
      // lifecycle state (Done for completed gates, Blocked for work deferred
      // by an approved change-control decision) so the committed catalog stays
      // the source of truth for what the Project should show.
      status: issue.statusOverride ?? 'Backlog',
      workstream: issue.workstream,
      sequence: (idx + 1) * 100 + position,
      ...d,
    })
  }
}
issues.sort((a, b) => a.sequence - b.sequence)

const out = []
out.push('# Machine-readable roadmap catalog. Generated by scripts/github/assemble-roadmap.mjs')
out.push('# from planning/fragments/*.json — edit fragments (or body files) and regenerate;')
out.push('# do not hand-edit. Strict YAML subset (see scripts/github/lib/yaml.mjs).')
out.push('schema: 1')
out.push('repository:')
out.push(`  owner: ${REPO.owner}`)
out.push(`  name: ${REPO.name}`)
out.push(`  visibility: ${REPO.visibility}`)
out.push(`  description: ${quote(REPO.description)}`)
out.push(`  topics: ${REPO.topics.join(', ')}`)
out.push('project:')
out.push(`  title: ${quote(PROJECT_TITLE)}`)
out.push(`  status_options: ${STATUS_OPTIONS.join(', ')}`)
out.push('labels:')
for (const [name, color, description] of LABELS) {
  out.push(`  - name: ${name}`)
  out.push(`    color: ${color}`)
  out.push(`    description: ${quote(description)}`)
}
out.push('milestones:')
for (const [id, title, description] of MILESTONES) {
  out.push(`  - id: ${id}`)
  out.push(`    title: ${quote(title)}`)
  out.push(`    description: ${quote(description)}`)
}
out.push('fields:')
for (const f of CUSTOM_FIELDS) {
  out.push(`  - name: ${quote(f.name)}`)
  out.push(`    type: ${f.dataType}`)
  if (f.options) out.push(`    options: ${f.options.join(', ')}`)
}
out.push('issues:')
for (const i of issues) {
  out.push(`  - id: ${i.id}`)
  out.push(`    title: ${quote(i.title)}`)
  out.push(`    type: ${i.type}`)
  out.push(`    variant: ${i.variant}`)
  out.push(`    milestone: ${i.milestone}`)
  out.push(`    parent: ${i.parent}`)
  out.push(`    blocked_by: ${i.blockedBy.join(', ')}`)
  out.push(`    labels: ${i.labels.join(', ')}`)
  out.push(`    body: ${i.body}`)
  out.push(`    status: ${i.status}`)
  out.push(`    priority: ${i.priority}`)
  out.push(`    workstream: ${i.workstream}`)
  out.push(`    risk: ${i.risk}`)
  out.push(`    target: ${i.target}`)
  out.push(`    sequence: ${i.sequence}`)
}
writeFileAtomic('planning/roadmap.yml', out.join('\n') + '\n')
console.log(`wrote planning/roadmap.yml with ${issues.length} issues`)
