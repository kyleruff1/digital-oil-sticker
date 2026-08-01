// Production catalog build: vPIC corpus (cached enumeration) + FEG bulk CSV
// crosswalk (exact-only) -> deterministic SQLite artifact + manifest +
// coverage report. Rights posture per docs/data/FACTUAL_USE_AND_MARKS_POLICY.md:
// vPIC and FEG approved at the source level; EOLCS contributes zero rows.

import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { buildCatalog, writeManifest, sourceDateEpoch } from './build.mjs'
import { normalizeKey, nullify, makeId, modelId, configurationKey, uuidv5 } from '../normalize/keys.mjs'
import { bulkRowsInWindow, WINDOW_START, WINDOW_END } from '../sources/fueleconomy.mjs'

const VPIC_LIMITATION_SENTENCE =
  'vPIC does not guarantee complete trims or engines and supplies no oil schedules, fluids, or filters.'

export function buildProduction({ toolsRoot, appRoot, dataVersion }) {
  const rawDir = join(toolsRoot, 'data', 'raw')
  const allow = JSON.parse(readFileSync(join(toolsRoot, 'data', 'allowlist', 'makes.json'), 'utf8'))
  if (!allow.approved) throw new Error('allowlist not approved')
  const allowByVpicId = new Map(allow.makes.map(m => [m.vpic_make_id, m]))

  // --- provenance: latest retrieval time drives SOURCE_DATE_EPOCH fallback --
  const metas = readdirSync(rawDir)
    .filter(f => f.endsWith('.meta.json'))
    .map(f => JSON.parse(readFileSync(join(rawDir, f), 'utf8')))
  const latestRetrieved = metas.map(m => m.retrieved_at).sort().at(-1)
  const generatedAt = sourceDateEpoch(latestRetrieved)

  const fegMeta = metas.find(m => m.name === 'feg-vehicles-csv')

  const srcVpic = sourceRow({
    key: 'vpic_api', provider: 'NHTSA', type: 'public_api',
    dataset: 'vPIC GetMakesForVehicleType + GetModelsForMakeIdYear corpus',
    url: 'https://vpic.nhtsa.dot.gov/api/',
    version: dataVersion, retrieved: latestRetrieved,
    attribution: 'Vehicle identity data from the NHTSA Product Information Catalog (vPIC). NHTSA does not endorse this application.',
    webAttribution: 'Vehicle identity: NHTSA vPIC',
    copyright: 'factual_extraction', acquisition: 'public_api',
    evidence: 'docs/data/FACTUAL_USE_AND_MARKS_POLICY.md#source-level-authorization',
  })
  const srcFeg = sourceRow({
    key: 'fueleconomy_gov_bulk', provider: 'DOE/EPA', type: 'official_bulk_download',
    dataset: 'FuelEconomy.gov vehicles.csv', url: 'https://www.fueleconomy.gov/feg/epadata/vehicles.csv',
    version: fegMeta?.retrieved_at ?? dataVersion, retrieved: fegMeta?.retrieved_at,
    rawSha: fegMeta?.sha256,
    attribution: 'Vehicle configuration data from FuelEconomy.gov (U.S. DOE/EPA). DOE and EPA do not endorse this application.',
    webAttribution: 'Configurations: FuelEconomy.gov (DOE/EPA)',
    copyright: 'government_public_domain', acquisition: 'official_bulk_download',
    evidence: 'docs/data/FACTUAL_USE_AND_MARKS_POLICY.md#source-level-authorization',
  })

  // --- vPIC corpus from cached enumeration ----------------------------------
  const makesMap = new Map() // normalized -> row
  const modelsMap = new Map() // makeUuid|norm -> row
  const modelYears = new Map() // modelUuid -> Set(years)
  const junkSkipped = []

  for (const meta of metas) {
    if (!meta.name.startsWith('vpic-models-')) continue
    const body = JSON.parse(readFileSync(join(rawDir, `${meta.name}.body`), 'utf8'))
    for (const r of body.Results ?? []) {
      const vpicMakeId = r.Make_ID ?? r.MakeId
      const allowRow = allowByVpicId.get(vpicMakeId)
      if (!allowRow) {
        junkSkipped.push(r.Make_Name ?? r.MakeName)
        continue
      }
      const makeNorm = allowRow.normalized
      if (!makesMap.has(makeNorm)) {
        makesMap.set(makeNorm, {
          id: makeId(makeNorm), vpic_make_id: vpicMakeId,
          display_name: allowRow.display, normalized_name: makeNorm,
          support_status: 'identity_only',
          first_window_year: null, last_window_year: null, window_year_count: allowRow.feg_window_years ?? null,
          source_id: srcVpic.id,
        })
      }
      const modelDisplay = nullify(r.Model_Name ?? r.ModelName)
      if (!modelDisplay) continue
      const modelNorm = normalizeKey(modelDisplay)
      if (!modelNorm) continue
      const makeUuid = makesMap.get(makeNorm).id
      const mkey = `${makeUuid}|${modelNorm}`
      if (!modelsMap.has(mkey)) {
        modelsMap.set(mkey, {
          id: modelId(makeUuid, modelNorm), make_id: makeUuid,
          vpic_model_id: r.Model_ID ?? r.ModelId ?? null,
          display_name: modelDisplay, normalized_name: modelNorm,
          source_id: srcVpic.id,
        })
        modelYears.set(modelsMap.get(mkey).id, new Map())
      }
      const yearMatch = meta.name.match(/^vpic-models-\d+-(\d{4})-(car|mpv|truck)$/)
      const year = yearMatch ? Number(yearMatch[1]) : null
      if (year) {
        const ym = modelYears.get(modelsMap.get(mkey).id)
        const prev = ym.get(year) ?? { typeId: r.VehicleTypeId ?? null, typeName: nullify(r.VehicleTypeName) }
        ym.set(year, prev)
      }
    }
  }

  // --- FEG crosswalk (exact-only on normalized make + baseModel/model) ------
  const fegCsv = readFileSync(join(rawDir, 'feg-vehicles-csv.body'), 'utf8')
  const fegRows = bulkRowsInWindow(fegCsv)
  const modelByMakeNorm = new Map()
  for (const [k, m] of modelsMap) {
    const [makeUuid, norm] = k.split('|')
    modelByMakeNorm.set(`${makeUuid}|${norm}`, m)
  }
  const makeUuidByNorm = new Map([...makesMap.values()].map(m => [m.normalized_name, m.id]))

  const configs = new Map()
  let fegMatched = 0
  let fegUnmatched = 0

  for (const r of fegRows) {
    const makeNorm = normalizeKey(r.make)
    const makeUuid = makeUuidByNorm.get(makeNorm)
    if (!makeUuid) {
      fegUnmatched++
      continue
    }
    const model =
      modelByMakeNorm.get(`${makeUuid}|${normalizeKey(r.baseModel)}`) ||
      modelByMakeNorm.get(`${makeUuid}|${normalizeKey(r.model)}`)
    if (!model) {
      fegUnmatched++
      continue
    }
    fegMatched++
    const bev = r.fuelType1 === 'Electricity' && !nullify(r.fuelType2)
    const key = configurationKey([r.year, makeUuid, model.id, 'feg', r.id])
    configs.set(key, {
      configuration_key: key,
      model_year: r.year, make_id: makeUuid, model_id: model.id,
      vpic_vehicle_type_id: null, vehicle_type_name: null,
      trim: nullify(r.model) === nullify(model.display_name) ? null : nullify(r.model),
      series: null, body_class: nullify(r.VClass), drive_type: nullify(r.drive),
      fuel_primary: nullify(r.fuelType1), fuel_secondary: nullify(r.fuelType2),
      electrification_level: bev ? 'BEV' : nullify(r.atvType) === 'EV' ? 'BEV' : nullify(r.atvType) === 'Hybrid' ? 'HEV' : null,
      engine_cylinders: intOrNull(r.cylinders), displacement_l: floatOrNull(r.displ),
      engine_descriptor: nullify(r.eng_dscr), transmission: nullify(r.trany),
      transmission_descriptor: nullify(r.trans_dscr), epa_size_class: nullify(r.VClass),
      start_stop: nullify(r.startStop),
      provider_namespace: 'fueleconomy.gov', provider_key: String(r.id),
      completeness_code: 'configuration_enriched',
      support_status: bev ? 'not_applicable' : 'identity_only',
      engine_oil_service: bev ? 'not_applicable' : null,
      crosswalk_status: 'exact',
      search_text: `${r.year} ${r.make} ${r.model}`.toLowerCase(),
      source_id: srcFeg.id,
    })
  }

  // vPIC-only identity rows for (model, year) pairs without any FEG config.
  const coveredYmm = new Set([...configs.values()].map(c => `${c.model_year}|${c.model_id}`))
  for (const model of modelsMap.values()) {
    for (const [year, t] of modelYears.get(model.id) ?? []) {
      if (coveredYmm.has(`${year}|${model.id}`)) continue
      const key = configurationKey([year, model.make_id, model.id, null, null])
      if (configs.has(key)) continue
      configs.set(key, {
        configuration_key: key,
        model_year: year, make_id: model.make_id, model_id: model.id,
        vpic_vehicle_type_id: t.typeId, vehicle_type_name: t.typeName,
        trim: null, series: null, body_class: null, drive_type: null,
        fuel_primary: null, fuel_secondary: null, electrification_level: null,
        engine_cylinders: null, displacement_l: null, engine_descriptor: null,
        transmission: null, transmission_descriptor: null, epa_size_class: null, start_stop: null,
        provider_namespace: null, provider_key: null,
        completeness_code: 'identity_only',
        support_status: 'identity_only',
        engine_oil_service: null,
        crosswalk_status: null,
        search_text: `${year}`.toLowerCase(),
        source_id: srcVpic.id,
      })
    }
  }

  // Aliases: Scion -> Toyota (absent from vPIC entirely), plus quarantined names.
  const aliases = []
  const toyota = makeUuidByNorm.get('toyota')
  if (toyota) {
    aliases.push({
      id: uuidv5('alias make scion'), entity_type: 'make', entity_id: toyota,
      normalized_alias: 'scion', display_alias: 'Scion', alias_kind: 'rename', source_id: srcVpic.id,
    })
  }

  const rows = {
    data_sources: [srcVpic, srcFeg],
    makes: [...makesMap.values()],
    models: [...modelsMap.values()],
    vehicle_configurations: [...configs.values()],
    aliases,
    oil_brands: [], oil_products: [], oil_product_claims: [],
  }

  const metadata = {
    schema_version: '1', catalog_version: dataVersion, data_version: dataVersion,
    generated_at: generatedAt, min_app_version: '0.1.0',
    window_start_year: String(WINDOW_START), window_end_year: String(WINDOW_END), market: 'US',
    search_normalization_version: '1',
    feature_identity: 'enabled', feature_configurations: 'enabled',
    feature_schedules: 'absent', feature_oil_requirements: 'absent',
    feature_oil_products: 'withheld', feature_filters: 'absent',
  }

  const outPath = join(appRoot, 'priv', 'catalog', 'catalog.sqlite3')
  const result = buildCatalog({ outPath, metadata, rows })

  const coverage = {
    generated_at: generatedAt,
    limitation: VPIC_LIMITATION_SENTENCE,
    makes: makesMap.size,
    models: modelsMap.size,
    configurations: configs.size,
    feg_rows_in_window: fegRows.length,
    feg_matched_exact: fegMatched,
    feg_unmatched: fegUnmatched,
    junk_rows_skipped: junkSkipped.length,
    bev_not_applicable: [...configs.values()].filter(c => c.support_status === 'not_applicable').length,
    by_completeness: countBy([...configs.values()], c => c.completeness_code),
  }
  const distDir = join(toolsRoot, 'dist')
  mkdirSync(distDir, { recursive: true })
  writeFileSync(join(distDir, 'coverage-report.json'), JSON.stringify(coverage, null, 2) + '\n')

  writeManifest(join(appRoot, 'priv', 'catalog', 'catalog-manifest.json'), {
    manifest_version: 1, kind: 'production', catalog_version: dataVersion, schema_version: '1',
    built_at: generatedAt,
    window: [WINDOW_START, WINDOW_END], market: 'US',
    payload_sha256: result.sha256, size: result.size, counts: result.counts,
    sources: [
      { key: 'vpic_api', retrieved_at: latestRetrieved },
      { key: 'fueleconomy_gov_bulk', retrieved_at: fegMeta?.retrieved_at, raw_sha256: fegMeta?.sha256 },
    ],
    features: { schedules: 'absent', oil_requirements: 'absent', oil_products: 'withheld', filters: 'absent' },
    limitation: VPIC_LIMITATION_SENTENCE,
  })

  return { result, coverage }

  function sourceRow(s) {
    return {
      id: uuidv5(`source ${s.key}`),
      source_key: s.key, provider: s.provider, source_type: s.type,
      dataset_name: s.dataset, canonical_url: s.url,
      source_version: s.version ?? null, raw_sha256: s.rawSha ?? null,
      retrieved_at: s.retrieved ?? null, effective_at: null, verified_at: s.retrieved ?? null,
      attribution_text: s.attribution, web_attribution_text: s.webAttribution ?? null,
      copyright_basis: s.copyright, acquisition_basis: s.acquisition,
      redistribution_basis: 'factual_republication', trademark_posture: 'plain_text_reference',
      claim_posture: 'identity_only', review_status: 'approved',
      terms_sha256: null, evidence_ref: s.evidence, reviewed_at: generatedAt, reviewer: 'owner',
    }
  }
}

function intOrNull(v) {
  const s = nullify(v)
  if (s === null) return null
  const n = Number(s)
  return Number.isInteger(n) ? n : null
}

function floatOrNull(v) {
  const s = nullify(v)
  if (s === null) return null
  const n = Number(s)
  return Number.isFinite(n) ? n : null
}

function countBy(list, fun) {
  const out = {}
  for (const item of list) {
    const k = fun(item)
    out[k] = (out[k] ?? 0) + 1
  }
  return out
}
