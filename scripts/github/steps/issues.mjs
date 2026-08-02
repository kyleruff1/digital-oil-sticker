import { apiJson, apiList } from '../lib/gh.mjs'
import { saveState } from '../lib/state.mjs'
import { readTextLF, sha256 } from '../lib/util.mjs'

const MARKER_RE = /<!-- roadmap-id: (DOS-M\d{2}-\d{3}) -->/

// Managed-issue identity is the roadmap-id body marker, discovered via the
// paginated REST issue list (never the Search API, which lags and rate-limits
// separately). Pull requests share the endpoint and are filtered out.
export function buildRemoteIssueMap(repo) {
  const rows = apiList(
    `repos/${repo.owner}/${repo.name}/issues?state=all&per_page=100`,
    '{number, id, node_id, title, body, html_url, state, is_pr: (has("pull_request")), labels: [.labels[].name], milestone: (.milestone.title // "")}',
  )
  const map = new Map()
  for (const row of rows) {
    if (row.is_pr) continue
    const m = (row.body ?? '').match(MARKER_RE)
    if (m) {
      if (map.has(m[1])) throw new Error(`duplicate remote issues carry roadmap-id ${m[1]}: #${map.get(m[1]).number} and #${row.number}`)
      map.set(m[1], row)
    }
  }
  return map
}

export function planIssues(catalog, exists) {
  if (!exists) return [`CREATE ${catalog.issues.length} repository issues (9 epics + 68 children), serially with read-back verification`]
  const remote = buildRemoteIssueMap(catalog.repository)
  const lines = []
  for (const issue of catalog.issues) {
    const have = remote.get(issue.id)
    if (!have) { lines.push(`CREATE issue ${issue.id} — "${issue.title}"`); continue }
    const localSha = sha256(readTextLF(issue.body))
    const remoteSha = sha256((have.body ?? '').replace(/\r\n/g, '\n'))
    lines.push(localSha === remoteSha && have.title === issue.title
      ? `SKIP issue ${issue.id} (identical, #${have.number})`
      : `DIVERGENT issue ${issue.id} (#${have.number}) — apply will STOP for approval`)
  }
  return lines
}

// `updateDivergent` (false by default) opts into pushing the local body/title
// over a remote that differs. Without it, divergent issues collect into an
// error at the end of the pass — the standing safety rule — because the
// synchronizer's default philosophy is that GitHub-side edits should be
// reconciled BACK into the local body files, not silently clobbered. Callers
// pass `true` only after the owner has explicitly approved a bulk update
// (RESCOPE-style rewrite that produced N divergent bodies deliberately).
export function applyIssues(catalog, state, milestoneNumbers, updateDivergent = false) {
  const repo = catalog.repository
  const remote = buildRemoteIssueMap(repo)
  const divergent = []
  let created = 0, skipped = 0, updated = 0

  for (const issue of catalog.issues) {
    const body = readTextLF(issue.body)
    const localSha = sha256(body)
    const have = remote.get(issue.id)
    if (have) {
      const remoteSha = sha256((have.body ?? '').replace(/\r\n/g, '\n'))
      // This synchronizer manages issue CONTENT, not lifecycle. A closed issue
      // whose title and body still match its specification is satisfied work,
      // not divergence — never reopen or re-create it.
      if (remoteSha === localSha && have.title === issue.title) {
        state.issues[issue.id] = {
          ...state.issues[issue.id],
          number: have.number, databaseId: have.id, nodeId: have.node_id, url: have.html_url,
          bodySha256: localSha, remoteState: have.state,
          verified: { ...(state.issues[issue.id]?.verified ?? {}), created: true },
        }
        saveState(state, 'issues')
        skipped++
        continue
      }
      const diffs = [
        have.title !== issue.title ? 'title' : null,
        remoteSha !== localSha ? 'body' : null,
      ].filter(Boolean).join(' + ')
      if (!updateDivergent) {
        divergent.push(`${issue.id} (#${have.number}): remote ${diffs} differs from managed specification`)
        continue
      }
      // Owner-approved update path: PATCH the body and title, then read back
      // and verify byte-for-byte. A read-back mismatch is a hard stop, same as
      // the CREATE path — silent partial updates are worse than a clean abort.
      const patched = apiJson(`repos/${repo.owner}/${repo.name}/issues/${have.number}`, {
        method: 'PATCH', body: { title: issue.title, body },
      })
      const patchedSha = sha256((patched.body ?? '').replace(/\r\n/g, '\n'))
      const readbackProblems = []
      if (patched.title !== issue.title) readbackProblems.push('title mismatch')
      if (patchedSha !== localSha) readbackProblems.push('body hash mismatch')
      if (readbackProblems.length) {
        throw new Error(`${issue.id} update read-back failed on #${have.number}: ${readbackProblems.join('; ')} — stopping at checkpoint`)
      }
      state.issues[issue.id] = {
        ...state.issues[issue.id],
        number: have.number, databaseId: have.id, nodeId: have.node_id, url: have.html_url,
        bodySha256: localSha, remoteState: have.state,
        verified: { ...(state.issues[issue.id]?.verified ?? {}), created: true, updated: true },
      }
      saveState(state, 'issues')
      updated++
      console.log(`  #${String(have.number).padStart(3)} ${issue.id} updated + verified (${diffs}) (${created + skipped + updated}/${catalog.issues.length})`)
      continue
    }

    const milestoneNumber = milestoneNumbers[issue.milestone]
    if (!milestoneNumber) throw new Error(`${issue.id}: milestone ${issue.milestone} has no remote number in state`)
    const res = apiJson(`repos/${repo.owner}/${repo.name}/issues`, {
      method: 'POST',
      body: { title: issue.title, body, labels: issue.labels, milestone: milestoneNumber },
    })

    // Immediate read-back: silent metadata omission is a failure, not a warning.
    const back = apiJson(`repos/${repo.owner}/${repo.name}/issues/${res.number}`)
    const backSha = sha256((back.body ?? '').replace(/\r\n/g, '\n'))
    const backLabels = (back.labels ?? []).map(l => l.name).sort().join(',')
    const problems = []
    if (back.title !== issue.title) problems.push('title mismatch')
    if (backSha !== localSha) problems.push('body hash mismatch')
    if (back.state !== 'open') problems.push(`state ${back.state}`)
    if (backLabels !== [...issue.labels].sort().join(',')) problems.push(`labels [${backLabels}]`)
    if ((back.milestone?.number ?? null) !== milestoneNumber) problems.push('milestone missing/mismatched')
    if (problems.length) throw new Error(`${issue.id} read-back failed on #${res.number}: ${problems.join('; ')} — stopping at checkpoint`)

    state.issues[issue.id] = {
      number: back.number, databaseId: back.id, nodeId: back.node_id, url: back.html_url,
      bodySha256: localSha, verified: { created: true },
    }
    saveState(state, 'issues')
    created++
    console.log(`  #${String(back.number).padStart(3)} ${issue.id} created + verified (${created + skipped}/${catalog.issues.length})`)
  }

  if (divergent.length) {
    throw new Error(
      'divergent managed issues require approval before update (re-run with --update-divergent after owner review):\n  ' +
      divergent.join('\n  '),
    )
  }
  const parts = [`${created} created`, `${skipped} already-identical`]
  if (updated) parts.push(`${updated} updated`)
  console.log(`  issues: ${parts.join(', ')}`)
}

export function applyRelations(catalog, state) {
  const repo = catalog.repository
  const num = id => {
    const s = state.issues[id]
    if (!s?.number) throw new Error(`relations: ${id} has no created issue in state`)
    return s
  }

  // Native sub-issue parent per child, batched read-back per epic.
  const epics = catalog.issues.filter(i => i.type === 'epic')
  for (const epic of epics) {
    const epicState = num(epic.id)
    const children = catalog.issues.filter(i => i.type === 'child' && i.parent === epic.id)
    const existing = new Set(
      apiList(`repos/${repo.owner}/${repo.name}/issues/${epicState.number}/sub_issues?per_page=100`, '.number'),
    )
    for (const child of children) {
      const childState = num(child.id)
      if (!existing.has(childState.number)) {
        apiJson(`repos/${repo.owner}/${repo.name}/issues/${epicState.number}/sub_issues`, {
          method: 'POST', body: { sub_issue_id: childState.databaseId },
        })
      }
    }
    const after = new Set(apiList(`repos/${repo.owner}/${repo.name}/issues/${epicState.number}/sub_issues?per_page=100`, '.number'))
    for (const child of children) {
      if (!after.has(num(child.id).number)) throw new Error(`sub-issue read-back: ${child.id} not under ${epic.id}`)
      state.issues[child.id].verified = { ...state.issues[child.id].verified, parent: true }
    }
    state.issues[epic.id].verified = { ...state.issues[epic.id].verified, subIssues: children.length }
    saveState(state, 'relations')
    console.log(`  ${epic.id}: ${children.length} sub-issues verified`)
  }

  // Native blocked-by dependencies.
  let edges = 0
  for (const issue of catalog.issues) {
    if (!issue.blockedBy.length) continue
    const issueState = num(issue.id)
    const existing = new Set(
      apiList(`repos/${repo.owner}/${repo.name}/issues/${issueState.number}/dependencies/blocked_by?per_page=100`, '.number'),
    )
    for (const blockerId of issue.blockedBy) {
      const blocker = num(blockerId)
      if (!existing.has(blocker.number)) {
        apiJson(`repos/${repo.owner}/${repo.name}/issues/${issueState.number}/dependencies/blocked_by`, {
          method: 'POST', body: { issue_id: blocker.databaseId },
        })
      }
      edges++
    }
    const after = new Set(apiList(`repos/${repo.owner}/${repo.name}/issues/${issueState.number}/dependencies/blocked_by?per_page=100`, '.number'))
    for (const blockerId of issue.blockedBy) {
      if (!after.has(num(blockerId).number)) throw new Error(`blocked-by read-back: ${issue.id} missing blocker ${blockerId}`)
    }
    state.issues[issue.id].verified = { ...state.issues[issue.id].verified, blockedBy: issue.blockedBy.length }
    saveState(state, 'relations')
  }
  console.log(`  blocked-by: ${edges} edges verified`)
}
