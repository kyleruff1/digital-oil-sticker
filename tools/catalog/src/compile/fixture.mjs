// Deterministic FIXTURE catalog for dev/test (license-clean: real identity
// facts from the cached M00-006 vPIC slice + visibly synthetic oil rows).
// Emits TWO data_versions so stale-cursor and removed-configuration paths
// are testable: fixture-a (primary, app/priv/catalog/catalog.sqlite3) and
// fixture-b (one configuration removed, different data_version).

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { buildCatalog, writeManifest } from './build.mjs'
import { normalizeKey, nullify, makeId, modelId, configurationKey, uuidv5 } from '../normalize/keys.mjs'

const FIXTURE_TS = '2026-08-01T00:00:00Z' // fixed: fixtures are fully deterministic

const REAL_MAKES = new Set(['TESLA', 'TOYOTA', 'BMW', 'FORD', 'HONDA', 'DODGE', 'RAM', 'PONTIAC'])

export function buildFixtures({ repoRoot, outDir }) {
  const spike = JSON.parse(readFileSync(join(repoRoot, 'spikes/m00-006-data-boundary/out/normalized.json'), 'utf8'))

  const srcVpic = {
    id: uuidv5('source vpic-fixture'),
    source_key: 'vpic_api_fixture_slice', provider: 'NHTSA', source_type: 'public_api',
    dataset_name: 'vPIC M00-006 cached slice (fixture)', canonical_url: 'https://vpic.nhtsa.dot.gov/api/',
    source_version: 'm00-006', raw_sha256: null, retrieved_at: FIXTURE_TS, effective_at: null, verified_at: FIXTURE_TS,
    attribution_text: 'Vehicle identity data from the NHTSA Product Information Catalog (vPIC).',
    web_attribution_text: 'Vehicle identity: NHTSA vPIC',
    copyright_basis: 'factual_extraction', acquisition_basis: 'public_api',
    redistribution_basis: 'factual_republication', trademark_posture: 'plain_text_reference',
    claim_posture: 'identity_only', review_status: 'approved',
    terms_sha256: null, evidence_ref: 'docs/data/FACTUAL_USE_AND_MARKS_POLICY.md',
    reviewed_at: FIXTURE_TS, reviewer: 'owner',
  }
  const srcSynthetic = {
    ...srcVpic,
    id: uuidv5('source synthetic-fixture'),
    source_key: 'synthetic_fixture', provider: 'Digital Oil Sticker', source_type: 'direct_observation',
    dataset_name: 'Visibly synthetic UI fixture rows', canonical_url: 'about:fixture',
    attribution_text: 'Synthetic fixture data — never production.',
    web_attribution_text: null,
    copyright_basis: 'factual_extraction', acquisition_basis: 'direct_observation',
    redistribution_basis: 'factual_republication', claim_posture: 'unverified_product_fact',
  }

  const makesMap = new Map()
  for (const m of spike.makes) {
    const display = m.name
    if (!REAL_MAKES.has(String(display).toUpperCase())) continue
    const norm = normalizeKey(display)
    makesMap.set(m.vpic_make_id, {
      id: makeId(norm), vpic_make_id: m.vpic_make_id,
      display_name: display, normalized_name: norm,
      support_status: 'identity_only',
      first_window_year: null, last_window_year: null, window_year_count: null,
      source_id: srcVpic.id,
    })
  }

  const modelsMap = new Map()
  for (const mo of spike.models) {
    const make = makesMap.get(mo.vpic_make_id)
    if (!make) continue
    const display = nullify(mo.name)
    if (!display) continue
    const norm = normalizeKey(display)
    const key = `${make.id}|${norm}`
    if (!modelsMap.has(key)) {
      modelsMap.set(key, {
        id: modelId(make.id, norm), make_id: make.id, vpic_model_id: mo.vpic_model_id,
        display_name: display, normalized_name: norm, source_id: srcVpic.id,
        _year: mo.model_year,
      })
    }
  }

  // One identity_only configuration per (model, year); plus a BEV and a
  // NULL-electrification row for Status.derive coverage.
  const configs = []
  for (const mo of spike.models) {
    const make = makesMap.get(mo.vpic_make_id)
    if (!make) continue
    const display = nullify(mo.name)
    if (!display) continue
    const model = modelsMap.get(`${make.id}|${normalizeKey(display)}`)
    const isTesla = make.display_name.toUpperCase() === 'TESLA'
    configs.push({
      configuration_key: configurationKey([mo.model_year, make.id, model.id, null, null]),
      model_year: mo.model_year, make_id: make.id, model_id: model.id,
      vpic_vehicle_type_id: mo.vehicle_type_id ?? null, vehicle_type_name: nullify(mo.vehicle_type_name),
      trim: null, series: null, body_class: null, drive_type: null,
      fuel_primary: isTesla ? 'Electricity' : null, fuel_secondary: null,
      electrification_level: isTesla ? 'BEV' : null,
      engine_cylinders: null, displacement_l: null, engine_descriptor: null,
      transmission: null, transmission_descriptor: null, epa_size_class: null, start_stop: null,
      provider_namespace: null, provider_key: null,
      completeness_code: 'identity_only',
      support_status: isTesla ? 'not_applicable' : 'identity_only',
      engine_oil_service: isTesla ? 'not_applicable' : null,
      crosswalk_status: null,
      search_text: `${mo.model_year} ${make.display_name} ${display}`.toLowerCase(),
      source_id: srcVpic.id,
    })
  }
  configs.sort((a, b) => a.configuration_key.localeCompare(b.configuration_key))
  const dedupedConfigs = [...new Map(configs.map(c => [c.configuration_key, c])).values()]

  // Visibly synthetic oil rows for UI/product-select tests (never production).
  const brandId = uuidv5('oil_brand acmesyntheticfixture')
  const oilBrands = [{
    id: brandId, display_name: 'ACME SYNTHETIC FIXTURE', normalized_name: 'acmesyntheticfixture',
    market: 'US', source_id: srcSynthetic.id, source_observed_at: FIXTURE_TS,
  }]
  const productId = uuidv5('oil_product acme fixture full synthetic')
  const oilProducts = [{
    id: productId, brand_id: brandId, product_family: 'Fixture Full Synthetic', product_variant: null,
    display_name: 'ACME SYNTHETIC FIXTURE Full Synthetic 5W-30', normalized_name: 'fixturefullsynthetic5w30',
    product_url: 'about:fixture', data_sheet_url: null, source_observed_at: FIXTURE_TS,
    source_type: 'direct_observation', verification_status: 'unverified', source_id: srcSynthetic.id,
  }]
  const oilClaims = [{
    id: uuidv5('claim acme 5w30'), product_id: productId, claim_type: 'sae_viscosity_grade',
    claim_code: '5W-30', claim_source: 'synthetic fixture', observed_at: FIXTURE_TS,
    verification_status: 'unverified', source_id: srcSynthetic.id,
  }]

  const aliases = [{
    id: uuidv5('alias make scion'), entity_type: 'make',
    entity_id: [...makesMap.values()].find(m => m.normalized_name === 'toyota')?.id ?? makeId('toyota'),
    normalized_alias: 'scion', display_alias: 'Scion', alias_kind: 'rename', source_id: srcVpic.id,
  }]

  const commonRows = {
    data_sources: [srcVpic, srcSynthetic],
    makes: [...makesMap.values()],
    models: [...modelsMap.values()].map(({ _year, ...m }) => m),
    aliases,
    oil_brands: oilBrands, oil_products: oilProducts, oil_product_claims: oilClaims,
  }
  const meta = version => ({
    schema_version: '1', catalog_version: version, data_version: version,
    generated_at: FIXTURE_TS, min_app_version: '0.1.0',
    window_start_year: '1997', window_end_year: '2026', market: 'US',
    search_normalization_version: '1',
    feature_identity: 'enabled', feature_configurations: 'enabled',
    feature_schedules: 'absent', feature_oil_requirements: 'absent',
    feature_oil_products: 'enabled_fixture_only', feature_filters: 'absent',
  })

  const outA = join(outDir, 'catalog-fixture-a.sqlite3')
  const a = buildCatalog({ outPath: outA, metadata: meta('fixture-a'), rows: { ...commonRows, vehicle_configurations: dedupedConfigs } })
  // fixture-b: one configuration removed (the first) — the removed-reference case.
  const outB = join(outDir, 'catalog-fixture-b.sqlite3')
  const b = buildCatalog({ outPath: outB, metadata: meta('fixture-b'), rows: { ...commonRows, vehicle_configurations: dedupedConfigs.slice(1) } })

  writeManifest(join(outDir, 'catalog-manifest.json'), {
    manifest_version: 1, kind: 'fixture', generated_at: FIXTURE_TS,
    artifacts: {
      'catalog.sqlite3': { data_version: 'fixture-a', sha256: a.sha256, size: a.size, counts: a.counts },
      'catalog-fixture-b.sqlite3': { data_version: 'fixture-b', sha256: b.sha256, size: b.size, counts: b.counts },
    },
    removed_in_b: dedupedConfigs[0].configuration_key,
  })
  return { a, b, removed: dedupedConfigs[0].configuration_key }
}
