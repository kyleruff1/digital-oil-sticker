// Interim BOOTSTRAP catalog: the real M00-006 vPIC slice (8 makes), zero oil
// rows (feature_oil_products=withheld), clearly versioned "-bootstrap".
// Purpose: bring the site back up with honest real data while the full
// 73-make enumeration finishes; superseded by the production build.

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { buildCatalog, writeManifest } from './build.mjs'
import { normalizeKey, nullify, makeId, modelId, configurationKey, uuidv5 } from '../normalize/keys.mjs'

const TS = '2026-08-01T00:00:00Z'
const REAL_MAKES = new Set(['TESLA', 'TOYOTA', 'BMW', 'FORD', 'HONDA', 'DODGE', 'RAM', 'PONTIAC'])

export function buildBootstrap({ repoRoot, appRoot }) {
  const spike = JSON.parse(readFileSync(join(repoRoot, 'spikes/m00-006-data-boundary/out/normalized.json'), 'utf8'))

  const src = {
    id: uuidv5('source vpic-bootstrap'),
    source_key: 'vpic_api_bootstrap_slice', provider: 'NHTSA', source_type: 'public_api',
    dataset_name: 'vPIC M00-006 cached slice (bootstrap)', canonical_url: 'https://vpic.nhtsa.dot.gov/api/',
    source_version: 'm00-006', raw_sha256: null, retrieved_at: TS, effective_at: null, verified_at: TS,
    attribution_text: 'Vehicle identity data from the NHTSA Product Information Catalog (vPIC). NHTSA does not endorse this application.',
    web_attribution_text: 'Vehicle identity: NHTSA vPIC',
    copyright_basis: 'factual_extraction', acquisition_basis: 'public_api',
    redistribution_basis: 'factual_republication', trademark_posture: 'plain_text_reference',
    claim_posture: 'identity_only', review_status: 'approved',
    terms_sha256: null, evidence_ref: 'docs/data/FACTUAL_USE_AND_MARKS_POLICY.md',
    reviewed_at: TS, reviewer: 'owner',
  }

  const makesMap = new Map()
  for (const m of spike.makes) {
    if (!REAL_MAKES.has(String(m.name).toUpperCase())) continue
    const norm = normalizeKey(m.name)
    makesMap.set(m.vpic_make_id, {
      id: makeId(norm), vpic_make_id: m.vpic_make_id, display_name: m.name, normalized_name: norm,
      support_status: 'identity_only', first_window_year: null, last_window_year: null,
      window_year_count: null, source_id: src.id,
    })
  }

  const modelsMap = new Map()
  const configs = new Map()
  for (const mo of spike.models) {
    const make = makesMap.get(mo.vpic_make_id)
    const display = nullify(mo.name)
    if (!make || !display) continue
    const norm = normalizeKey(display)
    const mkey = `${make.id}|${norm}`
    if (!modelsMap.has(mkey)) {
      modelsMap.set(mkey, {
        id: modelId(make.id, norm), make_id: make.id, vpic_model_id: mo.vpic_model_id,
        display_name: display, normalized_name: norm, source_id: src.id,
      })
    }
    const model = modelsMap.get(mkey)
    const bev = make.display_name.toUpperCase() === 'TESLA'
    const key = configurationKey([mo.model_year, make.id, model.id, null, null])
    configs.set(key, {
      configuration_key: key, model_year: mo.model_year, make_id: make.id, model_id: model.id,
      vpic_vehicle_type_id: mo.vehicle_type_id ?? null, vehicle_type_name: nullify(mo.vehicle_type_name),
      trim: null, series: null, body_class: null, drive_type: null,
      fuel_primary: bev ? 'Electricity' : null, fuel_secondary: null,
      electrification_level: bev ? 'BEV' : null,
      engine_cylinders: null, displacement_l: null, engine_descriptor: null,
      transmission: null, transmission_descriptor: null, epa_size_class: null, start_stop: null,
      provider_namespace: null, provider_key: null,
      completeness_code: 'identity_only',
      support_status: bev ? 'not_applicable' : 'identity_only',
      engine_oil_service: bev ? 'not_applicable' : null,
      crosswalk_status: null,
      search_text: `${mo.model_year} ${make.display_name} ${display}`.toLowerCase(),
      source_id: src.id,
    })
  }

  const outPath = join(appRoot, 'priv', 'catalog', 'catalog.sqlite3')
  const result = buildCatalog({
    outPath,
    metadata: {
      schema_version: '1', catalog_version: '2026.08.0-bootstrap', data_version: '2026.08.0-bootstrap',
      generated_at: TS, min_app_version: '0.1.0',
      window_start_year: '1997', window_end_year: '2026', market: 'US',
      search_normalization_version: '1',
      feature_identity: 'enabled', feature_configurations: 'enabled',
      feature_schedules: 'absent', feature_oil_requirements: 'absent',
      feature_oil_products: 'withheld', feature_filters: 'absent',
    },
    rows: {
      data_sources: [src],
      makes: [...makesMap.values()],
      models: [...modelsMap.values()],
      vehicle_configurations: [...configs.values()],
      aliases: [],
      oil_brands: [], oil_products: [], oil_product_claims: [],
    },
  })

  writeManifest(join(appRoot, 'priv', 'catalog', 'catalog-manifest.json'), {
    manifest_version: 1, kind: 'bootstrap-interim', catalog_version: '2026.08.0-bootstrap',
    schema_version: '1', built_at: TS, payload_sha256: result.sha256, size: result.size,
    counts: result.counts,
    note: 'Interim 8-make slice; superseded by the full 73-make production build.',
  })
  return result
}
