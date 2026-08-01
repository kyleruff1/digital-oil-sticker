import { gh, graphql } from '../lib/gh.mjs'
import { saveState } from '../lib/state.mjs'
import { STATUS_OPTIONS } from '../lib/catalog.mjs'

// The eight managed custom fields (built-in Status is reused, never duplicated).
export const CUSTOM_FIELDS = [
  { name: 'Priority', dataType: 'SINGLE_SELECT', options: ['P0 Critical', 'P1 High', 'P2 Normal', 'P3 Low'] },
  { name: 'Workstream', dataType: 'SINGLE_SELECT', options: ['Product', 'UX', 'Architecture', 'vPIC/Data', 'Domain Rules', 'LiveView UI', 'Mob/iOS/Android', 'Notifications', 'QA', 'DevOps/Release', 'Documentation'] },
  { name: 'Estimate', dataType: 'NUMBER' },
  { name: 'Risk', dataType: 'SINGLE_SELECT', options: ['Low', 'Medium', 'High'] },
  { name: 'Target', dataType: 'SINGLE_SELECT', options: ['Gate', 'MVP', 'Launch', 'Post-MVP'] },
  { name: 'Sequence', dataType: 'NUMBER' },
  { name: 'Start date', dataType: 'DATE' },
  { name: 'Target date', dataType: 'DATE' },
]

export const VIEWS = [
  { name: 'Delivery board', layout: 'BOARD_LAYOUT' },
  { name: 'Ready queue', layout: 'TABLE_LAYOUT' },
  { name: 'Roadmap', layout: 'ROADMAP_LAYOUT' },
  { name: 'QA queue', layout: 'TABLE_LAYOUT' },
  { name: 'Blocked', layout: 'TABLE_LAYOUT' },
  { name: 'Post-MVP', layout: 'TABLE_LAYOUT' },
]

export function findProject(catalog) {
  const owner = catalog.repository.owner
  const out = JSON.parse(gh(['project', 'list', '--owner', owner, '--format', 'json', '--limit', '100']))
  return (out.projects ?? []).find(p => p.title === catalog.project.title) ?? null
}

export function fetchFields(state, owner) {
  const out = JSON.parse(gh(['project', 'field-list', String(state.project.number), '--owner', owner, '--format', 'json', '--limit', '100']))
  return out.fields ?? []
}

export function planProject(catalog) {
  const existing = findProject(catalog)
  const lines = existing
    ? [`REUSE project #${existing.number} "${catalog.project.title}" and link to repository`]
    : [`CREATE private project "${catalog.project.title}" owned by ${catalog.repository.owner}, linked to the repository`]
  lines.push(`CONFIGURE built-in Status options to: ${STATUS_OPTIONS.join(', ')} (attempted via API; manual checklist on failure)`)
  for (const f of CUSTOM_FIELDS) lines.push(`CREATE field ${f.name} (${f.dataType}${f.options ? ': ' + f.options.join(', ') : ''})`)
  for (const v of VIEWS) lines.push(`CREATE view "${v.name}" (${v.layout.replace('_LAYOUT', '').toLowerCase()}; filters/sort/grouping documented manually)`)
  return lines
}

export function applyProject(catalog, state) {
  const owner = catalog.repository.owner
  let project = findProject(catalog)
  if (!project) {
    project = JSON.parse(gh(['project', 'create', '--owner', owner, '--title', catalog.project.title, '--format', 'json'], { write: true }))
    console.log(`  created project #${project.number}`)
  } else {
    console.log(`  reusing project #${project.number} "${project.title}"`)
  }
  gh(['project', 'link', String(project.number), '--owner', owner, '--repo', `${owner}/${catalog.repository.name}`], { write: true, allowFail: true })
  state.project = { number: project.number, nodeId: project.id, url: project.url, title: catalog.project.title }
  saveState(state, 'project')
}

function optionLiteral(name) {
  return `{name: "${name.replace(/"/g, '\\"')}", color: GRAY, description: ""}`
}

export function applyFields(catalog, state) {
  const owner = catalog.repository.owner
  let fields = fetchFields(state, owner)
  const byName = new Map(fields.map(f => [f.name, f]))

  // 1. Built-in Status: attempt option replacement via updateProjectV2Field; never create a second Status field.
  const status = byName.get('Status')
  if (!status) throw new Error('built-in Status field not found on project')
  const haveOptions = (status.options ?? []).map(o => o.name)
  if (JSON.stringify(haveOptions) === JSON.stringify(STATUS_OPTIONS)) {
    state.statusConfigured = { via: 'already-configured' }
  } else {
    try {
      graphql(
        `mutation($fieldId: ID!) {
          updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: [${STATUS_OPTIONS.map(optionLiteral).join(', ')}]}) {
            projectV2Field { ... on ProjectV2SingleSelectField { id name options { id name } } }
          }
        }`,
        { fieldId: status.id },
        { write: true },
      )
      const readBack = fetchFields(state, owner).find(f => f.name === 'Status')
      const got = (readBack?.options ?? []).map(o => o.name)
      state.statusConfigured = JSON.stringify(got) === JSON.stringify(STATUS_OPTIONS)
        ? { via: 'api' }
        : { via: 'manual-required', reason: `API accepted but read-back shows: ${got.join(', ')}` }
    } catch (e) {
      state.statusConfigured = { via: 'manual-required', reason: e.message.slice(0, 500) }
      console.log('  Status options not editable via API — recorded for PROJECT_MANUAL_SETUP.md')
    }
  }
  saveState(state, 'fields')

  // 2. Custom fields
  for (const f of CUSTOM_FIELDS) {
    if (!byName.has(f.name)) {
      const args = ['project', 'field-create', String(state.project.number), '--owner', owner, '--name', f.name, '--data-type', f.dataType]
      if (f.options) args.push('--single-select-options', f.options.join(','))
      gh(args, { write: true })
      console.log(`  created field ${f.name}`)
    }
  }
  fields = fetchFields(state, owner)
  for (const f of [...CUSTOM_FIELDS, { name: 'Status' }]) {
    const remote = fields.find(x => x.name === f.name)
    if (!remote) throw new Error(`field read-back missing ${f.name}`)
    if (f.options) {
      const got = (remote.options ?? []).map(o => o.name)
      if (JSON.stringify(got) !== JSON.stringify(f.options)) throw new Error(`field ${f.name} options mismatch: ${got.join(', ')}`)
    }
    state.fields[f.name] = {
      nodeId: remote.id,
      dataType: remote.type,
      options: Object.fromEntries((remote.options ?? []).map(o => [o.name, o.id])),
    }
  }
  saveState(state, 'fields')

  // 3. Views: best-effort creation; presentation settings are documented manually.
  const existingViews = listViews(state)
  for (const v of VIEWS) {
    if (existingViews.some(x => x.name === v.name)) {
      state.views[v.name] = { ...state.views[v.name], exists: true }
      continue
    }
    try {
      graphql(
        `mutation($projectId: ID!, $name: String!) {
          createProjectV2View(input: {projectId: $projectId, name: $name, layout: ${v.layout}}) {
            projectV2View { id name }
          }
        }`,
        { projectId: state.project.nodeId, name: v.name },
        { write: true },
      )
      state.views[v.name] = { via: 'api', layoutOnly: true }
      console.log(`  created view "${v.name}" (${v.layout}; filters/grouping remain manual)`)
    } catch (e) {
      state.views[v.name] = { via: 'manual-required', reason: e.message.slice(0, 300) }
      console.log(`  view "${v.name}" not creatable via API — recorded for PROJECT_MANUAL_SETUP.md`)
    }
  }
  saveState(state, 'fields')
}

export function listViews(state) {
  try {
    const data = graphql(
      `query($projectId: ID!) {
        node(id: $projectId) { ... on ProjectV2 { views(first: 50) { nodes { id name layout } } } }
      }`,
      { projectId: state.project.nodeId },
    )
    return data.node?.views?.nodes ?? []
  } catch {
    return []
  }
}
