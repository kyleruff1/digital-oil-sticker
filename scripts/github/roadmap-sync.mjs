#!/usr/bin/env node
// Idempotent roadmap synchronizer for the digital-oil-sticker planning bootstrap.
// Dry-run is the default; `apply` requires the explicit --apply flag.
//
//   node scripts/github/roadmap-sync.mjs validate
//   node scripts/github/roadmap-sync.mjs hash --write
//   node scripts/github/roadmap-sync.mjs plan
//   node scripts/github/roadmap-sync.mjs apply --apply [--only <step>] [--update-divergent]
//   node scripts/github/roadmap-sync.mjs verify
//
// --update-divergent (owner opt-in): during the `issues` step, PATCH title +
// body on any remote issue that differs from its managed specification, with
// read-back verification. Without the flag, divergent issues abort the pass
// (the standing safety rule — silent update of GitHub content is never OK).
//
// Steps: repo, labels, milestones, project, fields, issues, relations, project-items

import { loadCatalog, validateCatalog, HASHES_PATH } from './lib/catalog.mjs'
import { loadState, saveState } from './lib/state.mjs'
import { readTextLF, sha256, writeFileAtomic, fail } from './lib/util.mjs'
import { gh } from './lib/gh.mjs'
import { repoExists, planRepo, applyRepo, planLabels, applyLabels, planMilestones, applyMilestones } from './steps/meta.mjs'
import { planProject, applyProject, applyFields } from './steps/project.mjs'
import { planIssues, applyIssues, applyRelations } from './steps/issues.mjs'
import { applyProjectItems } from './steps/items.mjs'
import { verifyAll } from './steps/verify.mjs'

const [, , command = 'plan', ...rest] = process.argv
const flags = new Set(rest.filter(a => a.startsWith('--')))
const only = rest.includes('--only') ? rest[rest.indexOf('--only') + 1] : null

function requireValid(catalog) {
  const problems = validateCatalog(catalog)
  if (problems.length) {
    console.error(`VALIDATION FAILED (${problems.length} problems):`)
    for (const p of problems) console.error(`  - ${p}`)
    process.exit(1)
  }
  const epics = catalog.issues.filter(i => i.type === 'epic').length
  const children = catalog.issues.length - epics
  console.log(`validate: OK — ${catalog.issues.length} issues (${epics} epics, ${children} children), ${catalog.labels.length} labels, ${catalog.milestones.length} milestones, DAG acyclic, hashes match`)
}

function checkAuth() {
  const out = gh(['auth', 'status'], { allowFail: true })
  if (out === null) fail('gh is not authenticated; run `gh auth login` (never store a token in this repo)')
  if (!/'project'|\bproject\b/.test(out)) fail("the gh credential lacks the 'project' scope required for Project mutations; run `gh auth refresh -s project`")
}

const STEPS = ['repo', 'labels', 'milestones', 'project', 'fields', 'issues', 'relations', 'project-items']

function main() {
  if (command === 'hash') {
    const catalog = loadCatalog()
    const hashes = {}
    for (const issue of catalog.issues) hashes[issue.id] = sha256(readTextLF(issue.body))
    if (flags.has('--write')) {
      writeFileAtomic(HASHES_PATH, JSON.stringify(hashes, null, 2) + '\n')
      console.log(`wrote ${Object.keys(hashes).length} specification hashes to ${HASHES_PATH}`)
    } else {
      console.log(JSON.stringify(hashes, null, 2))
    }
    return
  }

  if (command === 'validate') {
    requireValid(loadCatalog())
    return
  }

  if (command === 'plan') {
    const catalog = loadCatalog()
    requireValid(catalog)
    checkAuth()
    const exists = repoExists(catalog.repository)
    const sections = [
      ['repo', planRepo(catalog)],
      ['labels', planLabels(catalog, exists)],
      ['milestones', planMilestones(catalog, exists)],
      ['project+fields', planProject(catalog)],
      ['issues', planIssues(catalog, exists)],
      ['relations', [
        `CREATE native sub-issue links: 68 children under 9 epics`,
        `CREATE native blocked-by edges: ${catalog.issues.reduce((n, i) => n + i.blockedBy.length, 0)} (epic DAG + catalog dependencies)`,
      ]],
      ['project-items', [`ADD 77 issues to the Project and set Status/Priority/Workstream/Risk/Target/Sequence per roadmap.yml (Estimate and dates stay blank)`]],
    ]
    console.log('\nDRY-RUN PLAN (no mutations performed):')
    for (const [name, lines] of sections) {
      console.log(`\n[${name}]`)
      for (const l of lines) console.log(`  ${l}`)
    }
    const creates = sections.flatMap(([, l]) => l).filter(l => l.startsWith('CREATE')).length
    console.log(`\nSummary: ${creates} CREATE lines; repository exists: ${exists}. Run \`apply --apply\` after approval.`)
    return
  }

  if (command === 'apply') {
    if (!flags.has('--apply')) fail('apply requires the explicit --apply flag (dry-run is the default elsewhere)')
    const catalog = loadCatalog()
    requireValid(catalog)
    checkAuth()
    const state = loadState()
    const todo = only ? [only] : STEPS
    for (const step of todo) {
      console.log(`\n== apply: ${step} ==`)
      switch (step) {
        case 'repo': applyRepo(catalog, state); break
        case 'labels': applyLabels(catalog, state); break
        case 'milestones': applyMilestones(catalog, state); break
        case 'project': applyProject(catalog, state); break
        case 'fields': applyFields(catalog, state); break
        case 'issues': {
          const nums = Object.fromEntries(Object.entries(state.milestones).map(([id, m]) => [id, m.number]))
          applyIssues(catalog, state, nums, flags.has('--update-divergent'))
          break
        }
        case 'relations': applyRelations(catalog, state); break
        case 'project-items': applyProjectItems(catalog, state); break
        default: fail(`unknown step ${step} (valid: ${STEPS.join(', ')})`)
      }
      saveState(state, step)
    }
    console.log('\napply complete — run `verify` for the full read-back check')
    return
  }

  if (command === 'verify') {
    const catalog = loadCatalog()
    requireValid(catalog)
    checkAuth()
    const state = loadState()
    if (!state.repo || !state.project) fail('verify: no applied state found (planning/state.json)')
    const result = verifyAll(catalog, state)
    console.log(`counts: ${JSON.stringify(result.counts)}`)
    console.log(`views present: ${result.views.join(', ') || '(none)'}`)
    if (result.problems.length) {
      console.error(`\nVERIFY FAILED — ${result.problems.length} discrepancies:`)
      for (const p of result.problems) console.error(`  - ${p}`)
      process.exit(1)
    }
    console.log('verify: OK — every managed object read back and matched')
    return
  }

  fail(`unknown command ${command} (validate | hash | plan | apply | verify)`)
}

main()
