import { gh } from '../lib/gh.mjs'
import { readTextLF, sha256 } from '../lib/util.mjs'
import { STATUS_OPTIONS } from '../lib/catalog.mjs'
import { fetchLabels, fetchMilestones, diffLabels } from './meta.mjs'
import { fetchFields, CUSTOM_FIELDS, listViews } from './project.mjs'
import { buildRemoteIssueMap } from './issues.mjs'
import { desiredFieldValues, fetchProjectItems } from './items.mjs'
import { apiList } from '../lib/gh.mjs'

// Full read-back verification (master prompt Phase E). Compares every remote
// object against the catalog and returns a list of discrepancies; never repairs.
export function verifyAll(catalog, state) {
  const bad = []
  const repo = catalog.repository

  const view = JSON.parse(gh(['repo', 'view', `${repo.owner}/${repo.name}`, '--json', 'visibility,description,hasIssuesEnabled,url,repositoryTopics']))
  if (view.visibility.toLowerCase() !== repo.visibility) bad.push(`repo visibility ${view.visibility} != ${repo.visibility}`)
  if (view.description !== repo.description) bad.push('repo description differs')
  if (!view.hasIssuesEnabled) bad.push('repo issues disabled')
  const topics = (view.repositoryTopics ?? []).map(t => typeof t === 'string' ? t : t.name)
  for (const t of repo.topics) if (!topics.includes(t)) bad.push(`repo topic missing: ${t}`)

  const labelDiff = diffLabels(catalog, fetchLabels(repo))
  for (const l of labelDiff.create) bad.push(`label missing: ${l.name}`)
  for (const d of labelDiff.divergent) bad.push(`label divergent: ${d.want.name}`)

  const milestones = new Map(fetchMilestones(repo).map(m => [m.title, m]))
  for (const m of catalog.milestones) {
    const remote = milestones.get(m.title)
    if (!remote) bad.push(`milestone missing: ${m.title}`)
    else if (remote.due_on) bad.push(`milestone has forbidden due date: ${m.title}`)
  }

  const fields = fetchFields(state, repo.owner)
  for (const f of CUSTOM_FIELDS) {
    const remote = fields.find(x => x.name === f.name)
    if (!remote) { bad.push(`project field missing: ${f.name}`); continue }
    if (f.options) {
      const got = (remote.options ?? []).map(o => o.name)
      if (JSON.stringify(got) !== JSON.stringify(f.options)) bad.push(`field ${f.name} options: [${got.join(', ')}]`)
    }
  }
  const status = fields.find(x => x.name === 'Status')
  const statusOk = JSON.stringify((status?.options ?? []).map(o => o.name)) === JSON.stringify(STATUS_OPTIONS)
  if (!statusOk && state.statusConfigured?.via !== 'manual-required') bad.push('Status options unmanaged but state claims configured')

  const remoteIssues = buildRemoteIssueMap(repo)
  for (const issue of catalog.issues) {
    const have = remoteIssues.get(issue.id)
    if (!have) { bad.push(`issue missing: ${issue.id}`); continue }
    if (have.title !== issue.title) bad.push(`${issue.id}: title differs`)
    // Closed is legitimate for completed work; the synchronizer verifies
    // content and relationships, not lifecycle state.
    if (sha256((have.body ?? '').replace(/\r\n/g, '\n')) !== sha256(readTextLF(issue.body))) bad.push(`${issue.id}: body hash differs`)
    if ([...have.labels].sort().join(',') !== [...issue.labels].sort().join(',')) bad.push(`${issue.id}: labels [${have.labels.join(', ')}]`)
    if (have.milestone !== catalog.milestones.find(m => m.id === issue.milestone)?.title) bad.push(`${issue.id}: milestone "${have.milestone}"`)
    const s = state.issues[issue.id]
    if (!s || s.number !== have.number) bad.push(`${issue.id}: state.json number mismatch`)
  }

  for (const epic of catalog.issues.filter(i => i.type === 'epic')) {
    const children = catalog.issues.filter(i => i.parent === epic.id).map(i => state.issues[i.id]?.number).sort((a, b) => a - b)
    const remote = apiList(`repos/${repo.owner}/${repo.name}/issues/${state.issues[epic.id].number}/sub_issues?per_page=100`, '.number').sort((a, b) => a - b)
    if (JSON.stringify(children) !== JSON.stringify(remote)) bad.push(`${epic.id}: sub-issues [${remote.join(', ')}] != expected [${children.join(', ')}]`)
  }
  for (const issue of catalog.issues.filter(i => i.blockedBy.length)) {
    const expected = issue.blockedBy.map(b => state.issues[b]?.number).sort((a, b) => a - b)
    const remote = apiList(`repos/${repo.owner}/${repo.name}/issues/${state.issues[issue.id].number}/dependencies/blocked_by?per_page=100`, '.number').sort((a, b) => a - b)
    if (JSON.stringify(expected) !== JSON.stringify(remote)) bad.push(`${issue.id}: blocked-by [${remote.join(', ')}] != expected [${expected.join(', ')}]`)
  }

  const items = fetchProjectItems(state)
  const itemByNumber = new Map(items.filter(i => i.content?.number).map(i => [i.content.number, i]))
  for (const issue of catalog.issues) {
    const s = state.issues[issue.id]
    const item = itemByNumber.get(s?.number)
    if (!item) { bad.push(`${issue.id}: not in project`); continue }
    const values = new Map()
    for (const v of item.fieldValues.nodes) {
      if (v.field?.name) values.set(v.field.name, v.name ?? v.number)
    }
    for (const want of desiredFieldValues(issue, state)) {
      const got = values.get(want.fieldName)
      const expected = want.kind === 'number' ? want.number : want.display
      if (got !== expected) bad.push(`${issue.id}: field ${want.fieldName} = ${JSON.stringify(got)} != ${JSON.stringify(expected)}`)
    }
    for (const forbidden of ['Estimate', 'Start date', 'Target date']) {
      if (values.has(forbidden)) bad.push(`${issue.id}: forbidden field ${forbidden} has a value`)
    }
  }

  return {
    problems: bad,
    counts: {
      issues: catalog.issues.length,
      epics: catalog.issues.filter(i => i.type === 'epic').length,
      children: catalog.issues.filter(i => i.type === 'child').length,
      projectItems: items.length,
    },
    views: listViews(state).map(v => v.name),
  }
}
