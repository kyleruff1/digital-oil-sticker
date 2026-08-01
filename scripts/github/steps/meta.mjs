import { gh, apiJson, apiList } from '../lib/gh.mjs'
import { saveState } from '../lib/state.mjs'

export function repoExists(repo) {
  return gh(['repo', 'view', `${repo.owner}/${repo.name}`, '--json', 'name'], { allowFail: true }) !== null
}

export function planRepo(catalog) {
  const r = catalog.repository
  const exists = repoExists(r)
  return exists
    ? [`SKIP/RECONCILE repo ${r.owner}/${r.name} (already exists — apply will stop unless it was created by this synchronizer)`]
    : [`CREATE ${r.visibility} repository ${r.owner}/${r.name} ("${r.description}"), push local main, topics: ${r.topics.join(', ')}`]
}

export function applyRepo(catalog, state) {
  const r = catalog.repository
  const full = `${r.owner}/${r.name}`
  if (repoExists(r)) {
    if (!state.repo) {
      throw new Error(`${full} already exists but was not created by this synchronizer. Stopping — never repurpose an existing repository automatically.`)
    }
    console.log(`  repo ${full} exists (created earlier by this run) — skipping create`)
  } else {
    gh(['repo', 'create', full, `--${r.visibility}`, '--description', r.description, '--source', '.', '--push'], { write: true })
    console.log(`  created ${full} and pushed main`)
  }
  const view = JSON.parse(gh(['repo', 'view', full, '--json', 'id,name,owner,url,visibility,hasIssuesEnabled,description']))
  if (!view.hasIssuesEnabled) gh(['repo', 'edit', full, '--enable-issues'], { write: true })
  const topicArgs = r.topics.flatMap(t => ['--add-topic', t])
  if (topicArgs.length) gh(['repo', 'edit', full, ...topicArgs], { write: true })
  state.repo = { owner: r.owner, name: r.name, nodeId: view.id, url: view.url, visibility: view.visibility }
  saveState(state, 'repo')
}

export function fetchLabels(repo) {
  return apiList(`repos/${repo.owner}/${repo.name}/labels?per_page=100`, '{name, color, description}')
}

export function diffLabels(catalog, remote) {
  const byName = new Map(remote.map(l => [l.name, l]))
  const create = [], divergent = [], identical = []
  for (const want of catalog.labels) {
    const have = byName.get(want.name)
    if (!have) create.push(want)
    else if (have.color.toLowerCase() !== want.color.toLowerCase() || (have.description ?? '') !== want.description) divergent.push({ want, have })
    else identical.push(want)
  }
  return { create, divergent, identical }
}

export function planLabels(catalog, exists) {
  if (!exists) return catalog.labels.map(l => `CREATE label ${l.name} (#${l.color})`)
  const { create, divergent, identical } = diffLabels(catalog, fetchLabels(catalog.repository))
  return [
    ...create.map(l => `CREATE label ${l.name} (#${l.color})`),
    ...identical.map(l => `SKIP label ${l.name} (identical)`),
    ...divergent.map(d => `DIVERGENT label ${d.want.name}: remote #${d.have.color} "${d.have.description}" vs managed #${d.want.color} "${d.want.description}" — apply will STOP`),
  ]
}

export function applyLabels(catalog, state) {
  const repo = catalog.repository
  const { create, divergent, identical } = diffLabels(catalog, fetchLabels(repo))
  if (divergent.length) {
    throw new Error('divergent existing labels; refusing to overwrite without approval:\n' +
      divergent.map(d => `  ${d.want.name}: remote #${d.have.color} "${d.have.description}" vs managed #${d.want.color} "${d.want.description}"`).join('\n'))
  }
  for (const l of identical) state.labels[l.name] = { verified: true }
  for (const l of create) {
    gh(['label', 'create', l.name, '--repo', `${repo.owner}/${repo.name}`, '--color', l.color, '--description', l.description], { write: true })
    state.labels[l.name] = { verified: false }
    saveState(state, 'labels')
    console.log(`  created label ${l.name}`)
  }
  const after = diffLabels(catalog, fetchLabels(repo))
  if (after.create.length || after.divergent.length) throw new Error('label read-back mismatch after apply')
  for (const l of catalog.labels) state.labels[l.name] = { verified: true }
  saveState(state, 'labels')
}

export function fetchMilestones(repo) {
  return apiList(`repos/${repo.owner}/${repo.name}/milestones?state=all&per_page=100`, '{number, title, description, due_on}')
}

export function planMilestones(catalog, exists) {
  if (!exists) return catalog.milestones.map(m => `CREATE milestone "${m.title}" (no due date)`)
  const have = new Map(fetchMilestones(catalog.repository).map(m => [m.title, m]))
  return catalog.milestones.map(m => have.has(m.title) ? `SKIP milestone "${m.title}" (exists)` : `CREATE milestone "${m.title}" (no due date)`)
}

export function applyMilestones(catalog, state) {
  const repo = catalog.repository
  const have = new Map(fetchMilestones(repo).map(m => [m.title, m]))
  for (const m of catalog.milestones) {
    let remote = have.get(m.title)
    if (!remote) {
      remote = apiJson(`repos/${repo.owner}/${repo.name}/milestones`, { method: 'POST', body: { title: m.title, description: m.description ?? '' } })
      console.log(`  created milestone ${m.title} (#${remote.number})`)
    }
    if (remote.due_on) throw new Error(`milestone "${m.title}" has a due date; bootstrap milestones must not`)
    state.milestones[m.id] = { number: remote.number, title: m.title }
    saveState(state, 'milestones')
  }
  const readBack = new Map(fetchMilestones(repo).map(m => [m.title, m]))
  for (const m of catalog.milestones) if (!readBack.has(m.title)) throw new Error(`milestone read-back missing "${m.title}"`)
}
