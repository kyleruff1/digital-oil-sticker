import { existsSync, statSync } from 'node:fs'
import { parseYaml } from './yaml.mjs'
import { readTextLF, sha256, readJsonIf, assertAcyclic } from './util.mjs'

export const ROADMAP_PATH = 'planning/roadmap.yml'
export const HASHES_PATH = 'planning/hashes.json'
export const MAX_BODY_BYTES = 60_000

// Pivot 2026-08-01 added M09 (browser platform): 10 children + 1 epic.
// M10 (shop integration) adds 4 drafted children + 1 epic; DOS-M10-005..009
// are allocated in the epic's Included roster but not yet drafted on disk.
export const EXPECTED_CHILD_COUNTS = { M00: 6, M01: 6, M02: 8, M03: 11, M04: 10, M05: 7, M06: 7, M07: 7, M08: 7, M09: 10, M10: 4 }
export const EXPECTED_TOTAL = 94

export const H2_SECTIONS = [
  'Outcome',
  'Why this matters and what it unblocks',
  'Context and source of truth',
  'Included',
  'Excluded',
  'Preconditions',
  'Functional requirements',
  'Technical implementation contract',
  'UX and content states',
  'Acceptance criteria',
  'Test plan',
  'Rollout and rollback',
  'Documentation and evidence',
  'Dependency rationale',
  'Risks, decisions, and open questions',
  'Definition of done',
]
// A RESCOPE card may append one optional trailing section that preserves the
// pre-pivot spec verbatim for the historical record. The heading is fixed so
// authors cannot smuggle in arbitrary trailing sections under a similar name.
export const OPTIONAL_TRAILING_H2 = 'Superseded pre-pivot spec (historical record)'
const H3_STANDARD = [
  'Components and ownership boundaries',
  'Data and persistence',
  'Interfaces and events',
  'Failure and recovery behavior',
  'Security and privacy',
  'Accessibility and performance',
]
const H3_SPIKE = [
  'Hypothesis',
  'Timebox',
  'Alternatives considered',
  'Success and failure criteria',
  'Mandatory ADR and follow-ups',
]
// Hosted browser issues (M09) exercise a browser matrix rather than a device
// matrix; either heading satisfies the manual-testing requirement.
const H3_MANUAL_MATRIX = ['Manual/device matrix', 'Manual/browser matrix']

export const PRIORITIES = ['P0 Critical', 'P1 High', 'P2 Normal', 'P3 Low']
export const RISKS = ['Low', 'Medium', 'High']
export const TARGETS = ['Gate', 'MVP', 'Launch', 'Post-MVP']
export const WORKSTREAMS = ['Product', 'UX', 'Architecture', 'vPIC/Data', 'Domain Rules', 'LiveView UI', 'Mob/iOS/Android', 'Notifications', 'QA', 'DevOps/Release', 'Documentation']
export const STATUS_OPTIONS = ['Backlog', 'Ready', 'In Progress', 'In Review', 'In QA', 'Blocked', 'Done']

function splitList(v) {
  if (v === '' || v === undefined) return []
  return String(v).split(',').map(s => s.trim()).filter(Boolean)
}

export function loadCatalog() {
  const doc = parseYaml(readTextLF(ROADMAP_PATH), ROADMAP_PATH)
  const issues = (doc.issues ?? []).map(i => ({
    ...i,
    labels: splitList(i.labels),
    blockedBy: splitList(i.blocked_by),
    sequence: Number(i.sequence),
  }))
  return {
    repository: { ...doc.repository, topics: splitList(doc.repository?.topics) },
    project: doc.project,
    labels: doc.labels ?? [],
    milestones: doc.milestones ?? [],
    fields: doc.fields ?? [],
    issues,
  }
}

function sectionsOf(body) {
  const h2 = []
  let current = null
  for (const line of body.split('\n')) {
    const m2 = line.match(/^## (.+?)\s*$/)
    const m3 = line.match(/^### (.+?)\s*$/)
    if (m2) {
      current = { title: m2[1], h3: [], content: '' }
      h2.push(current)
    } else if (m3 && current) {
      current.h3.push(m3[1])
      current.content += line + '\n'
    } else if (current) {
      current.content += line + '\n'
    }
  }
  return h2
}

// Implements the master prompt's Phase A local validation checks. Returns a
// list of problem strings; empty means valid.
export function validateCatalog(catalog) {
  const problems = []
  const p = msg => problems.push(msg)
  const hashes = readJsonIf(HASHES_PATH, {})
  const ids = new Set()
  const sequences = new Set()
  const milestoneIds = new Set(catalog.milestones.map(m => m.id))
  const labelNames = new Set(catalog.labels.map(l => l.name))
  const epicByMilestone = new Map()

  if (catalog.labels.length !== 18) p(`expected 18 managed labels, found ${catalog.labels.length}`)
  const expectedMilestones = Object.keys(EXPECTED_CHILD_COUNTS).length
  if (catalog.milestones.length !== expectedMilestones) {
    p(`expected ${expectedMilestones} milestones, found ${catalog.milestones.length}`)
  }

  for (const issue of catalog.issues) {
    if (issue.type === 'epic') {
      if (epicByMilestone.has(issue.milestone)) p(`${issue.milestone}: more than one epic`)
      epicByMilestone.set(issue.milestone, issue.id)
    }
  }

  const counts = {}
  for (const issue of catalog.issues) {
    const where = issue.id ?? '(missing id)'
    if (!/^DOS-M\d{2}-\d{3}$/.test(issue.id ?? '')) { p(`${where}: malformed roadmap id`); continue }
    if (ids.has(issue.id)) p(`${where}: duplicate roadmap id`)
    ids.add(issue.id)
    counts[issue.milestone] = counts[issue.milestone] ?? { epic: 0, child: 0 }
    counts[issue.milestone][issue.type === 'epic' ? 'epic' : 'child']++

    if (!issue.title?.startsWith(`${issue.id} — `)) p(`${where}: title must start with "${issue.id} — "`)
    if (!milestoneIds.has(issue.milestone)) p(`${where}: unknown milestone ${issue.milestone}`)
    if (!['epic', 'child'].includes(issue.type)) p(`${where}: bad type ${issue.type}`)
    if (!['standard', 'spike', 'data'].includes(issue.variant)) p(`${where}: bad variant ${issue.variant}`)
    if (issue.type === 'child' && issue.parent !== epicByMilestone.get(issue.milestone)) {
      p(`${where}: parent must be its milestone epic (${epicByMilestone.get(issue.milestone)}), got "${issue.parent}"`)
    }
    if (issue.type === 'epic' && issue.parent) p(`${where}: epic must have no parent`)
    for (const l of issue.labels) if (!labelNames.has(l)) p(`${where}: unmanaged label ${l}`)
    if (issue.type === 'epic' && (issue.labels.length !== 1 || issue.labels[0] !== 'kind:epic')) p(`${where}: epic labels must be exactly [kind:epic]`)
    if (issue.type === 'child' && issue.labels.filter(l => l.startsWith('kind:')).length !== 1) p(`${where}: child needs exactly one kind:* label`)
    for (const b of issue.blockedBy) if (!/^DOS-M\d{2}-\d{3}$/.test(b)) p(`${where}: malformed blocker ${b}`)
    if (issue.blockedBy.includes(issue.id)) p(`${where}: blocks itself`)
    if (!PRIORITIES.includes(issue.priority)) p(`${where}: bad priority "${issue.priority}"`)
    if (issue.risk !== '' && !RISKS.includes(issue.risk)) p(`${where}: bad risk "${issue.risk}"`)
    if (!TARGETS.includes(issue.target)) p(`${where}: bad target "${issue.target}"`)
    if (!WORKSTREAMS.includes(issue.workstream)) p(`${where}: bad workstream "${issue.workstream}"`)
    if (!STATUS_OPTIONS.includes(issue.status)) p(`${where}: bad status "${issue.status}"`)
    if ('estimate' in issue || 'assignee' in issue || 'start_date' in issue || 'target_date' in issue || 'due_on' in issue) {
      p(`${where}: estimates, assignees, and dates must not be set at bootstrap`)
    }
    if (!Number.isInteger(issue.sequence) || issue.sequence <= 0) p(`${where}: bad sequence`)
    if (sequences.has(issue.sequence)) p(`${where}: duplicate sequence ${issue.sequence}`)
    sequences.add(issue.sequence)

    // Body file checks
    if (!existsSync(issue.body)) { p(`${where}: body file missing: ${issue.body}`); continue }
    let body
    try {
      body = readTextLF(issue.body)
    } catch (e) {
      p(`${where}: ${e.message}`)
      continue
    }
    const bytes = Buffer.byteLength(body, 'utf8')
    if (bytes > MAX_BODY_BYTES) p(`${where}: body ${bytes} bytes exceeds ${MAX_BODY_BYTES} (fail, never truncate)`)
    const lines = body.split('\n')
    if (lines[0] !== `<!-- roadmap-id: ${issue.id} -->`) p(`${where}: first line must be the roadmap-id marker`)
    if (lines[1] !== '<!-- roadmap-schema: 1 -->') p(`${where}: second line must be the roadmap-schema marker`)
    const markerCount = (body.match(/<!-- roadmap-id: /g) ?? []).length
    if (markerCount !== 1) p(`${where}: exactly one roadmap-id marker required, found ${markerCount}`)
    if (!issue.body.endsWith(`${issue.id}.md`)) p(`${where}: body path must be planning/issues/${issue.id}.md`)

    const secs = sectionsOf(body)
    const titles = secs.map(s => s.title)
    const isRescope =
      titles.length === H2_SECTIONS.length + 1 &&
      titles[titles.length - 1] === OPTIONAL_TRAILING_H2
    const canonicalTitles = isRescope ? [...H2_SECTIONS, OPTIONAL_TRAILING_H2] : H2_SECTIONS
    if (JSON.stringify(titles) !== JSON.stringify(canonicalTitles)) {
      p(`${where}: H2 sections differ from canonical template (got: ${titles.join(' | ') || 'none'})`)
    } else {
      const validatedSecs = isRescope ? secs.slice(0, -1) : secs
      for (const s of validatedSecs) {
        const text = s.content.replace(/^###.+$/gm, '').trim()
        if (text === '' && s.h3.length === 0) p(`${where}: section "${s.title}" is empty (use "N/A — reason")`)
      }
      const tech = validatedSecs.find(s => s.title === 'Technical implementation contract')
      const test = validatedSecs.find(s => s.title === 'Test plan')
      if (issue.type === 'child') {
        const wanted = issue.variant === 'spike' ? H3_SPIKE : H3_STANDARD
        for (const h of wanted) if (!tech.h3.includes(h)) p(`${where}: missing "### ${h}"`)
        if (issue.variant === 'data' && !tech.h3.includes('Data change specifics')) p(`${where}: data issue missing "### Data change specifics"`)
        if (!test.h3.includes('Automated')) p(`${where}: missing "### Automated" under Test plan`)
        if (!H3_MANUAL_MATRIX.some(h => test.h3.includes(h))) {
          p(`${where}: Test plan needs one of ${H3_MANUAL_MATRIX.map(h => `"### ${h}"`).join(' or ')}`)
        }
      }
      const fr = validatedSecs.find(s => s.title === 'Functional requirements')
      const ac = validatedSecs.find(s => s.title === 'Acceptance criteria')
      if (!/FR-\d+/.test(fr.content) && !/N\/A — /.test(fr.content)) p(`${where}: functional requirements must be numbered FR-*`)
      if (!/- \[ \] AC-\d+/.test(ac.content)) p(`${where}: acceptance criteria must be "- [ ] AC-n:" checkboxes`)
      if (issue.variant === 'data' && !/(license|rights|provenance|attribution)/i.test(ac.content)) {
        p(`${where}: data issue acceptance criteria must cover provenance/rights`)
      }
    }

    const expected = hashes[issue.id]
    if (!expected) p(`${where}: no specification hash recorded (run: roadmap-sync hash --write)`)
    else if (expected !== sha256(body)) p(`${where}: body hash differs from recorded specification hash`)
  }

  // Blockers resolve within the managed catalog
  for (const issue of catalog.issues) {
    for (const b of issue.blockedBy) if (!ids.has(b)) p(`${issue.id}: blocker ${b} not in catalog`)
  }

  // Fixed inventory
  let epicTotal = 0, childTotal = 0
  for (const [ms, expected] of Object.entries(EXPECTED_CHILD_COUNTS)) {
    const got = counts[ms] ?? { epic: 0, child: 0 }
    if (got.epic !== 1) p(`${ms}: expected exactly 1 epic, found ${got.epic}`)
    if (got.child !== expected) p(`${ms}: expected ${expected} children, found ${got.child}`)
    epicTotal += got.epic
    childTotal += got.child
  }
  if (epicTotal + childTotal !== EXPECTED_TOTAL) p(`expected ${EXPECTED_TOTAL} issues total, found ${epicTotal + childTotal}`)

  try {
    assertAcyclic(catalog.issues)
  } catch (e) {
    p(e.message)
  }

  return problems
}
