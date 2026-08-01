// Our own oil model: engine classification + interval rule generation.
// Classification uses ONLY fields we hold in the catalog (fuel type,
// electrification, direct-injection marker, displacement, cylinders).
//
// Deliberately NOT classified: forced induction. The EPA/DOE engine
// descriptor records it on only ~39 of 33k rows, so a "turbo" class would be
// mostly false negatives. We would rather omit a factor than assert one we
// cannot see.

import { readFileSync } from 'node:fs'
import { join } from 'node:path'
import { uuidv5 } from '../normalize/keys.mjs'

export function loadScience(toolsRoot) {
  return JSON.parse(readFileSync(join(toolsRoot, 'data', 'curated', 'oil_science.json'), 'utf8'))
}

/**
 * Classify one vehicle_configuration row into an engine class code.
 * Order matters: drivetrain type first (it decides whether engine oil applies
 * at all), then fuel, then injection, then size.
 */
export function classifyEngine(config) {
  const fuel = (config.fuel_primary || '').toLowerCase()
  const elec = (config.electrification_level || '').toUpperCase()
  const desc = (config.engine_descriptor || '').toUpperCase()
  const cyl = config.engine_cylinders
  const displ = config.displacement_l

  if (elec === 'BEV' || fuel === 'electricity') return 'bev'
  if (fuel === 'hydrogen') return 'fcv'
  if (fuel === 'diesel') return 'diesel_light'
  if (elec === 'HEV' || elec === 'PHEV' || /HYBRID|PHEV/.test(desc)) return 'hybrid_gas'

  const gasoline = fuel.includes('gasoline') || fuel.includes('e85') || fuel.includes('flex')
  if (!gasoline) return 'gas_other'

  // SIDI = spark-ignition direct injection. Fuel dilution shortens oil life.
  if (/SIDI|\bDI\b|DIRECT INJ/.test(desc)) return 'gas_direct_injection'

  if (cyl == null && displ == null) return 'gas_other'
  if ((displ != null && displ <= 2.0) || (cyl != null && cyl <= 4)) return 'gas_small'
  if ((displ != null && displ <= 4.0) || (cyl != null && cyl <= 6)) return 'gas_mid'
  return 'gas_large'
}

/**
 * Generate the interval rule set: one row per
 * (engine class x base stock x service condition).
 *
 * recommended = published_high * engine_factor * condition_factor, but never
 * above the published range and never below the published low. The safety
 * fallback (miles_low) is the published low scaled the same way, and it is
 * what the app uses whenever a combination has no explicit rule.
 */
export function buildIntervalRules(science) {
  const rules = []

  for (const ec of science.engine_classes) {
    if (ec.engine_oil === 'not_applicable') continue

    for (const bs of science.base_stocks) {
      for (const sc of science.service_conditions) {
        const factor = (ec.interval_factor ?? 1.0) * sc.factor

        const low = Math.max(500, roundTo(bs.published_miles_low * factor, 250))
        const recommendedRaw = bs.published_miles_high * factor
        // Never exceed the published high, never fall below our own low.
        const recommended = Math.max(low, Math.min(roundTo(recommendedRaw, 250), bs.published_miles_high))

        const months = sc.code === 'severe' ? Math.max(3, Math.round(bs.published_months_cap / 2)) : bs.published_months_cap

        rules.push({
          id: uuidv5(`interval ${ec.code} ${bs.code} ${sc.code} v${science.model_version}`),
          engine_class_code: ec.code,
          base_stock_code: bs.code,
          service_condition: sc.code,
          miles_low: low,
          miles_recommended: recommended,
          months_cap: months,
          model_version: science.model_version,
          reasoning: [
            `${bs.display_name}: published ${bs.published_miles_low.toLocaleString()}-${bs.published_miles_high.toLocaleString()} mi.`,
            ec.interval_factor && ec.interval_factor !== 1.0
              ? `${ec.display_name}: x${ec.interval_factor} (${firstSentence(ec.reasoning)})`
              : `${ec.display_name}: no adjustment.`,
            sc.code === 'severe' ? `Severe service: x${sc.factor}.` : 'Normal service: x1.0.',
            `Time cap ${months} months.`,
          ].join(' '),
        })
      }
    }
  }

  return rules
}

export function oilModelRows(science) {
  const grades = science.oil_grades.map(g => ({
    code: g.code,
    winter: g.winter,
    operating: g.operating,
    common: g.common ? 1 : 0,
    notes: g.notes ?? null,
  }))

  const baseStocks = science.base_stocks.map(b => ({
    code: b.code,
    display_name: b.display_name,
    published_miles_low: b.published_miles_low,
    published_miles_high: b.published_miles_high,
    published_months_cap: b.published_months_cap,
    reasoning: b.reasoning,
  }))

  const engineClasses = science.engine_classes.map(e => ({
    code: e.code,
    display_name: e.display_name,
    engine_oil: e.engine_oil,
    interval_factor: e.interval_factor ?? null,
    requires_service_category: e.requires_service_category ?? null,
    reasoning: e.reasoning,
  }))

  const classGrades = []
  for (const e of science.engine_classes) {
    ;(e.typical_grades ?? []).forEach((grade, i) => {
      classGrades.push({ engine_class_code: e.code, grade_code: grade, rank: i + 1 })
    })
  }

  const conditions = science.service_conditions.map(s => ({
    code: s.code,
    display_name: s.display_name,
    factor: s.factor,
    reasoning: s.reasoning,
    questions: s.questions ? JSON.stringify(s.questions) : null,
  }))

  const metadata = {
    model_version: science.model_version,
    authored_by: science.authored_by,
    authored_at: science.authored_at,
    basis_statement: science.basis_statement,
    safety_rule: science.safety_rule,
  }

  return {
    oil_model_metadata: Object.entries(metadata).map(([key, value]) => ({ key, value: String(value) })),
    oil_grades: grades,
    oil_base_stocks: baseStocks,
    engine_classes: engineClasses,
    engine_class_grades: classGrades,
    service_conditions: conditions,
    interval_rules: buildIntervalRules(science),
  }
}

function roundTo(n, step) {
  return Math.round(n / step) * step
}

function firstSentence(s) {
  const i = s.indexOf('. ')
  return i === -1 ? s : s.slice(0, i + 1).trim()
}
