import { gh, graphql } from '../lib/gh.mjs'
import { saveState } from '../lib/state.mjs'

// Desired Project field values for one catalog issue. Status is included only
// when the built-in Status field carries the managed option set. Estimate and
// dates are never set at bootstrap.
export function desiredFieldValues(issue, state) {
  const wants = []
  const single = (fieldName, optionName) => {
    const field = state.fields[fieldName]
    if (!field) throw new Error(`field ${fieldName} missing from state`)
    const optionId = field.options[optionName]
    if (!optionId) throw new Error(`field ${fieldName} has no option "${optionName}"`)
    wants.push({ fieldName, kind: 'single', fieldId: field.nodeId, optionId, display: optionName })
  }
  if (state.statusConfigured?.via !== 'manual-required') single('Status', issue.status)
  single('Priority', issue.priority)
  single('Workstream', issue.workstream)
  if (issue.risk) single('Risk', issue.risk)
  single('Target', issue.target)
  wants.push({ fieldName: 'Sequence', kind: 'number', fieldId: state.fields.Sequence.nodeId, number: issue.sequence, display: String(issue.sequence) })
  return wants
}

export function applyProjectItems(catalog, state) {
  const owner = catalog.repository.owner
  for (const issue of catalog.issues) {
    const s = state.issues[issue.id]
    if (!s?.number) throw new Error(`project-items: ${issue.id} has no created issue in state`)
    if (s.verified?.fields) continue

    if (!s.itemId) {
      const added = JSON.parse(gh(['project', 'item-add', String(state.project.number), '--owner', owner, '--url', s.url, '--format', 'json'], { write: true }))
      s.itemId = added.id
      saveState(state, 'project-items')
    }

    const wants = desiredFieldValues(issue, state)
    const aliases = wants.map((w, i) => {
      const value = w.kind === 'single'
        ? `{singleSelectOptionId: "${w.optionId}"}`
        : `{number: ${w.number}}`
      return `f${i}: updateProjectV2ItemFieldValue(input: {projectId: "${state.project.nodeId}", itemId: "${s.itemId}", fieldId: "${w.fieldId}", value: ${value}}) { projectV2Item { id } }`
    })
    // graphql() throws if any alias resolves null or errors are present.
    graphql(`mutation { ${aliases.join('\n')} }`, {}, { write: true })
    s.verified = { ...s.verified, fields: wants.map(w => w.fieldName) }
    saveState(state, 'project-items')
    console.log(`  ${issue.id}: item + ${wants.length} fields set`)
  }
}

// Fetch all project items with their field values in pages of 100.
export function fetchProjectItems(state) {
  const items = []
  let cursor = null
  for (;;) {
    const data = graphql(
      `query($projectId: ID!, $after: String) {
        node(id: $projectId) {
          ... on ProjectV2 {
            items(first: 100, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes {
                id
                content { ... on Issue { number } }
                fieldValues(first: 20) {
                  nodes {
                    ... on ProjectV2ItemFieldSingleSelectValue { field { ... on ProjectV2SingleSelectField { name } } name }
                    ... on ProjectV2ItemFieldNumberValue { field { ... on ProjectV2FieldCommon { name } } number }
                  }
                }
              }
            }
          }
        }
      }`,
      cursor ? { projectId: state.project.nodeId, after: cursor } : { projectId: state.project.nodeId },
    )
    const page = data.node.items
    items.push(...page.nodes)
    if (!page.pageInfo.hasNextPage) break
    cursor = page.pageInfo.endCursor
  }
  return items
}
