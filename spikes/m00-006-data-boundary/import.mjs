#!/usr/bin/env node
// DOS-M00-006 deterministic import: reads ONLY the cached fixtures under
// fixtures/raw/ (never the network) and produces out/normalized.json plus
// out/baseline-hashes.json. Rules:
//  - vPIC empty strings and "Not Applicable" placeholders become explicit
//    null (unknown) — never zero, a default, or an inferred value.
//  - Every normalized fact carries provenance: the fixture name (source
//    record), the response SHA-256 (source revision), and retrieval time.
//  - Output ordering is fully sorted so identical inputs give identical bytes.

import { readFileSync, writeFileSync, mkdirSync, readdirSync } from 'node:fs'
import { createHash } from 'node:crypto'

const DIR = new URL('./fixtures/raw/', import.meta.url)
const OUT = new URL('./out/', import.meta.url)
mkdirSync(OUT, { recursive: true })

const sha256 = s => createHash('sha256').update(s, 'utf8').digest('hex')
const nullify = v => {
  if (v === undefined || v === null) return null
  const s = String(v).trim()
  return s === '' || s === 'Not Applicable' ? null : s
}

function fixture(name) {
  const body = readFileSync(new URL(`${name}.body`, DIR), 'utf8')
  const meta = JSON.parse(readFileSync(new URL(`${name}.meta.json`, DIR), 'utf8'))
  if (sha256(body) !== meta.sha256) throw new Error(`${name}: cached body does not match recorded sha256 — fixture corrupted`)
  return { body, meta, prov: { source_record: name, source_revision_sha256: meta.sha256, source_url: meta.url, retrieved_at: meta.retrieved_at, authority: meta.url.includes('vpic.nhtsa.dot.gov') ? 'NHTSA vPIC (green lane, 17 U.S.C. §105)' : 'DOE/EPA FuelEconomy.gov (green lane, 17 U.S.C. §105)' } }
}

const names = readdirSync(DIR).filter(f => f.endsWith('.meta.json')).map(f => f.replace(/\.meta\.json$/, '')).sort()

const makes = new Map()
const models = []
const vinDecodes = []
const emptyModelYears = []
let variableEvidence = null
const fegProbes = []

for (const name of names) {
  const { body, meta, prov } = fixture(name)
  if (name === 'vpic-variable-list') {
    const j = JSON.parse(body)
    const varNames = j.Results.map(r => r.Name).sort()
    const maintenanceLike = varNames.filter(v => /oil|maintenance|interval|filter|viscosity|capacity|service/i.test(v))
    variableEvidence = { variable_count: j.Count, maintenance_oil_filter_variables: maintenanceLike, provenance: prov }
  } else if (name.startsWith('vpic-models-')) {
    const j = JSON.parse(body)
    const [, , make, yearStr] = name.split('-')
    const model_year = Number(yearStr)
    if (j.Count === 0) {
      emptyModelYears.push({ make_query: make, model_year, result_count: 0, meaning: 'no models listed for this make/year (discontinued or not produced) — unknown-or-absent, never defaulted', provenance: prov })
    }
    for (const r of j.Results) {
      makes.set(r.Make_ID, { vpic_make_id: r.Make_ID, name: nullify(r.Make_Name), provenance: prov })
      models.push({ vpic_make_id: r.Make_ID, vpic_model_id: r.Model_ID, model_year, name: nullify(r.Model_Name), provenance: prov })
    }
  } else if (name.startsWith('vpic-vin-')) {
    const j = JSON.parse(body)
    const r = j.Results[0]
    const pick = k => nullify(r[k])
    vinDecodes.push({
      sample: name.replace('vpic-vin-', ''),
      vin_masked: (r.VIN ?? '').slice(0, 8) + '…',
      identity: { make: pick('Make'), model: pick('Model'), model_year: pick('ModelYear'), vehicle_type: pick('VehicleType'), body_class: pick('BodyClass') },
      configuration: { trim: pick('Trim'), series: pick('Series'), drive_type: pick('DriveType'), fuel_primary: pick('FuelTypePrimary'), engine_model: pick('EngineModel'), engine_cylinders: pick('EngineCylinders'), displacement_l: pick('DisplacementL'), electrification_level: pick('ElectrificationLevel') },
      engine_oil_service: r.FuelTypePrimary === 'Electric' && /BEV/.test(r.ElectrificationLevel ?? '') ? 'not_applicable' : 'unknown_from_this_source',
      maintenance_fields_present: false,
      decode_error: { code: pick('ErrorCode'), text: pick('ErrorText') },
      unknown_fields: Object.keys(r).filter(k => nullify(r[k]) === null).length,
      total_fields: Object.keys(r).length,
      provenance: prov,
    })
  } else if (name.startsWith('feg-')) {
    const options = [...body.matchAll(/<text>([^<]+)<\/text>/g)].map(m => m[1]).sort()
    fegProbes.push({ probe: name, option_count: options.length, options: options.slice(0, 20), evidence: 'engine/transmission-level configuration menu exists for U.S. models — enrichment candidate only; no oil/filter facts', provenance: prov })
  }
}

models.sort((a, b) => a.vpic_make_id - b.vpic_make_id || a.model_year - b.model_year || a.vpic_model_id - b.vpic_model_id)
vinDecodes.sort((a, b) => a.sample.localeCompare(b.sample))
emptyModelYears.sort((a, b) => a.make_query.localeCompare(b.make_query) || a.model_year - b.model_year)

const normalized = {
  spike: 'DOS-M00-006',
  import_rules: ['empty string and Not Applicable -> null (unknown)', 'no defaults, no inference, no invented trims', 'every fact carries source_record + source_revision_sha256 + retrieved_at'],
  vpic_variable_evidence: variableEvidence,
  makes: [...makes.values()].sort((a, b) => a.vpic_make_id - b.vpic_make_id),
  models,
  vin_decodes: vinDecodes,
  empty_model_years: emptyModelYears,
  fueleconomy_probes: fegProbes,
  counts: { makes: makes.size, models: models.length, vin_decodes: vinDecodes.length, empty_model_years: emptyModelYears.length },
}

const json = JSON.stringify(normalized, null, 2) + '\n'
writeFileSync(new URL('normalized.json', OUT), json, 'utf8')
writeFileSync(new URL('baseline-hashes.json', OUT), JSON.stringify({ normalized_sha256: sha256(json), row_counts: normalized.counts }, null, 2) + '\n', 'utf8')
console.log('import OK:', JSON.stringify(normalized.counts), 'normalized sha=', sha256(json).slice(0, 16))
