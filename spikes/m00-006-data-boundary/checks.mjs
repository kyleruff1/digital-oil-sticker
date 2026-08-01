#!/usr/bin/env node
// DOS-M00-006 automated checks (test plan, Automated section):
//  1. Deterministic rebuild — re-import from cached fixtures; hashes and row
//     counts must equal the recorded baseline.
//  2. Traceability — every normalized fact resolves to a preserved source
//     record, raw response hash, and retrieval time.
//  3. Unknown preservation — fields absent in the source stay null; the known
//     missing-field samples must remain unknown; no zeros/defaults appear.
//  4. License hygiene — fixtures contain only official vPIC/FuelEconomy.gov
//     responses (green lane); no other hosts, no bulk downloads.

import { readFileSync, readdirSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'

const base = new URL('./', import.meta.url)
const read = p => readFileSync(new URL(p, base), 'utf8')
const sha256 = s => createHash('sha256').update(s, 'utf8').digest('hex')
let failures = 0
const check = (name, ok, detail = '') => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`); if (!ok) failures++ }

// 1. Deterministic rebuild
const before = JSON.parse(read('out/baseline-hashes.json'))
execFileSync(process.execPath, [new URL('import.mjs', base).pathname.replace(/^\/([A-Za-z]:)/, '$1')], { stdio: 'pipe' })
const after = JSON.parse(read('out/baseline-hashes.json'))
const normalizedSha = sha256(read('out/normalized.json'))
check('deterministic-rebuild', before.normalized_sha256 === after.normalized_sha256 && after.normalized_sha256 === normalizedSha,
  `baseline ${before.normalized_sha256.slice(0, 12)} == rebuilt ${after.normalized_sha256.slice(0, 12)}`)
check('row-counts-stable', JSON.stringify(before.row_counts) === JSON.stringify(after.row_counts), JSON.stringify(after.row_counts))

// 2. Traceability
const n = JSON.parse(read('out/normalized.json'))
const fixtureShas = new Map(readdirSync(new URL('fixtures/raw/', base)).filter(f => f.endsWith('.meta.json'))
  .map(f => { const m = JSON.parse(read('fixtures/raw/' + f)); return [m.name, m.sha256] }))
const facts = [...n.makes, ...n.models, ...n.vin_decodes, ...n.empty_model_years, ...n.fueleconomy_probes, n.vpic_variable_evidence]
const untraceable = facts.filter(f => {
  const p = f.provenance
  return !p || fixtureShas.get(p.source_record) !== p.source_revision_sha256 || !p.retrieved_at || !p.source_url
})
check('traceability', untraceable.length === 0, `${facts.length} facts, ${untraceable.length} untraceable`)

// 3. Unknown preservation
const f150 = n.vin_decodes.find(v => v.sample.includes('f150'))
const tesla = n.vin_decodes.find(v => v.sample.includes('tesla'))
check('unknown-preserved-f150', f150.configuration.trim === null && f150.configuration.series === null && f150.configuration.engine_model === null,
  'manufacturer-unsubmitted Trim/Series/EngineModel stay null')
check('ev-not-applicable', tesla.engine_oil_service === 'not_applicable', 'BEV maps to not_applicable, never an invented oil plan')
check('no-oil-facts-anywhere', n.vpic_variable_evidence.maintenance_oil_filter_variables.filter(v => /oil interval|oil capacity|viscosity|oil filter/i.test(v)).length === 0,
  `vPIC exposes ${n.vpic_variable_evidence.variable_count} variables; none are oil-interval/viscosity/capacity/filter-fitment`)
const flat = JSON.stringify(n)
check('no-default-intervals', !/"interval[^"]*":\s*(0|"0"|3000|5000)/.test(flat), 'no invented default intervals in the normalized output')
check('empty-year-preserved', n.empty_model_years.some(e => e.make_query === 'pontiac' && e.model_year === 2024 && e.result_count === 0),
  'discontinued make/year stays an explicit empty result')

// 4. License hygiene
const badHosts = [...fixtureShas.keys()].map(name => JSON.parse(read(`fixtures/raw/${name}.meta.json`)).url)
  .filter(u => !u.startsWith('https://vpic.nhtsa.dot.gov/') && !u.startsWith('https://www.fueleconomy.gov/'))
check('license-hygiene-hosts', badHosts.length === 0, 'only official vPIC and FuelEconomy.gov responses cached')
check('license-hygiene-size', fixtureShas.size <= 25, `${fixtureShas.size} cached responses — a representative slice, not a bulk download`)

console.log(failures === 0 ? '\nALL CHECKS PASS' : `\n${failures} CHECK(S) FAILED`)
process.exit(failures === 0 ? 0 : 1)
