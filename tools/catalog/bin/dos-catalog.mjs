#!/usr/bin/env node
// Digital Oil Sticker catalog pipeline CLI.
//   node tools/catalog/bin/dos-catalog.mjs discover     # vPIC type IDs + makes-for-type + FEG bulk + allowlist proposal
//   node tools/catalog/bin/dos-catalog.mjs enumerate    # the make×year×type model grid (courteous, resumable)
// All network responses cache under tools/catalog/data/raw with provenance
// envelopes; warm reruns are zero-request.

import { mkdirSync, writeFileSync, readFileSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { makeClient } from '../src/http/rate_limited_client.mjs'
import { fetchVehicleTypeIds, fetchMakesForType, fetchTypesForMake, fetchModelsForMakeIdYearType, LIGHT_DUTY_TYPES } from '../src/sources/vpic.mjs'
import { fetchBulkCsv, bulkRowsInWindow, WINDOW_START, WINDOW_END } from '../src/sources/fueleconomy.mjs'
import { normalizeKey } from '../src/normalize/keys.mjs'

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const RAW = join(ROOT, 'data', 'raw')
const OUT = join(ROOT, 'data')
const client = makeClient({ rawDir: RAW })

const [, , cmd = 'discover'] = process.argv

if (cmd === 'discover') await discover()
else if (cmd === 'enumerate') await enumerate()
else if (cmd === 'fixture') {
  const { buildFixtures } = await import('../src/compile/fixture.mjs')
  const repoRoot = join(ROOT, '..', '..')
  const outDir = join(repoRoot, 'app', 'priv', 'catalog')
  const r = buildFixtures({ repoRoot, outDir })
  console.log(`fixture-a sha=${r.a.sha256.slice(0, 12)} rows=${JSON.stringify(r.a.counts)}`)
  console.log(`fixture-b sha=${r.b.sha256.slice(0, 12)} (removed ${r.removed.slice(0, 12)}…)`)
} else if (cmd === 'compile') {
  const { buildProduction } = await import('../src/compile/production.mjs')
  const repoRoot = join(ROOT, '..', '..')
  const dataVersion = process.argv[3] ?? '2026.08.0'
  const { result, coverage } = buildProduction({ toolsRoot: ROOT, appRoot: join(repoRoot, 'app'), dataVersion })
  console.log(`catalog ${dataVersion} sha=${result.sha256.slice(0, 12)} bytes=${result.size}`)
  console.log(`coverage: ${JSON.stringify(coverage, null, 2).slice(0, 800)}`)
} else {
  console.error(`unknown command ${cmd} (discover | enumerate | fixture | compile)`)
  process.exit(1)
}

async function discover() {
  const typeIds = await fetchVehicleTypeIds(client)
  console.log(`vehicle types pinned: ${typeIds.map(t => `${t.name}=${t.id}`).join(', ')}`)

  const byType = {}
  const vpicMakes = new Map() // make_id -> {name, types:Set}
  for (const t of LIGHT_DUTY_TYPES) {
    const makes = await fetchMakesForType(client, t)
    byType[t] = makes.length
    for (const m of makes) {
      const e = vpicMakes.get(m.make_id) ?? { make_id: m.make_id, make_name: m.make_name, types: new Set() }
      e.types.add(t)
      vpicMakes.set(m.make_id, e)
    }
  }
  console.log(`vPIC light-duty makes: car=${byType.car} mpv=${byType.mpv} truck=${byType.truck} → ${vpicMakes.size} distinct`)

  const { csv, meta } = await fetchBulkCsv(client)
  const rows = bulkRowsInWindow(csv)
  console.log(`FEG vehicles.csv: ${meta.content_length} bytes (${meta.fromCache ? 'cache' : 'network'}); ${rows.length} rows in ${WINDOW_START}-${WINDOW_END}`)

  // FEG make presence: normalized name -> {display, years}
  const fegMakes = new Map()
  for (const r of rows) {
    const key = normalizeKey(r.make)
    const e = fegMakes.get(key) ?? { display: r.make, years: new Set() }
    e.years.add(r.year)
    fegMakes.set(key, e)
  }

  const vpicByNorm = new Map()
  for (const m of vpicMakes.values()) vpicByNorm.set(normalizeKey(m.make_name), m)

  const allow = []
  const quarantine = []
  for (const [norm, feg] of [...fegMakes].sort((a, b) => a[0].localeCompare(b[0]))) {
    const v = vpicByNorm.get(norm)
    if (v) {
      allow.push({
        normalized: norm,
        display: feg.display,
        vpic_make_id: v.make_id,
        vpic_name: v.make_name,
        types: [...v.types].sort(),
        feg_window_years: feg.years.size,
        tier: feg.years.size >= 15 ? 'B' : 'A-only',
      })
    } else {
      quarantine.push({ normalized: norm, display: feg.display, feg_window_years: feg.years.size, reason: 'no vPIC light-duty make match' })
    }
  }
  const excluded = [...vpicMakes.values()]
    .filter(m => !fegMakes.has(normalizeKey(m.make_name)))
    .map(m => ({ vpic_make_id: m.make_id, name: m.make_name, types: [...m.types].sort(), reason: 'not present in FEG window (no light-duty retail evidence)' }))
    .sort((a, b) => a.name.localeCompare(b.name))

  mkdirSync(join(OUT, 'allowlist'), { recursive: true })
  const proposal = {
    generated_from: ['vpic GetMakesForVehicleType car/mpv/truck', 'fueleconomy.gov vehicles.csv'],
    window: [WINDOW_START, WINDOW_END],
    tier: 'A',
    approved: false,
    makes: allow,
    quarantine,
    excluded_count: excluded.length,
  }
  writeFileSync(join(OUT, 'allowlist', 'makes.json'), JSON.stringify(proposal, null, 2) + '\n')
  writeFileSync(join(OUT, 'allowlist', 'excluded.json'), JSON.stringify(excluded, null, 2) + '\n')
  console.log(`allowlist proposal: ${allow.length} makes (Tier B subset: ${allow.filter(a => a.tier === 'B').length}); quarantined: ${quarantine.length}; excluded vPIC light-duty: ${excluded.length}`)
  console.log(`requests this run: ${client.counters.requests} (cache hits ${client.counters.cache_hits})`)
}

async function enumerate() {
  const allowPath = join(OUT, 'allowlist', 'makes.json')
  if (!existsSync(allowPath)) throw new Error('run discover first')
  const allow = JSON.parse(readFileSync(allowPath, 'utf8'))
  if (!allow.approved) throw new Error('allowlist not approved: set "approved": true in data/allowlist/makes.json after owner review')

  const years = []
  for (let y = WINDOW_START; y <= WINDOW_END; y++) years.push(y)

  const coverage = [] // one terminal status per cell
  const t0 = Date.now()
  let cells = 0, fetched = 0
  for (const make of allow.makes) {
    // Only enumerate the light-duty types this make actually has.
    const makeTypes = (await fetchTypesForMake(client, make.vpic_make_id))
      .map(t => ({ ...t, slug: typeSlug(t.type_name) }))
      .filter(t => t.slug && make.types.includes(t.slug))
    for (const year of years) {
      for (const t of makeTypes) {
        cells++
        try {
          const { count, fromCache } = await fetchModelsForMakeIdYearType(client, make.vpic_make_id, year, t.slug)
          if (!fromCache) fetched++
          coverage.push([make.vpic_make_id, year, t.slug, count === 0 ? 'empty_confirmed' : 'complete', count])
        } catch (e) {
          coverage.push([make.vpic_make_id, year, t.slug, 'failed', String(e.kind ?? e.message).slice(0, 60)])
        }
        if (cells % 200 === 0) {
          const rate = fetched / ((Date.now() - t0) / 1000 || 1)
          console.log(`cells ${cells} | network ${fetched} | cache ${client.counters.cache_hits} | ${rate.toFixed(2)} req/s`)
        }
      }
    }
  }
  writeFileSync(join(OUT, 'coverage-cells.json'), JSON.stringify({ generated_at: new Date().toISOString(), cells: coverage }, null, 2) + '\n')
  const failed = coverage.filter(c => c[3] === 'failed').length
  console.log(`enumeration done: ${cells} cells, ${fetched} network requests, ${failed} failed, ${(Date.now() - t0) / 60000 | 0} min`)
  if (failed > 0) process.exitCode = 2
}

function typeSlug(name) {
  const n = String(name ?? '').toLowerCase()
  if (n.includes('passenger car')) return 'car'
  if (n.includes('multipurpose')) return 'mpv'
  if (n === 'truck' || n.includes('truck ')) return 'truck'
  return null
}
