// DOS-M09-010 AC-6 / FR-3 build gate: fail the catalog build if any
// oil_products / oil_brands / oil_product_claims row is sourced from EOLCS.
//
// EOLCS bulk scraping and directory mirroring are prohibited pending an
// approved acquisition basis (see docs/data/FACTUAL_USE_AND_MARKS_POLICY.md
// and planning/issues/DOS-M09-010.md). This is defence-in-depth against a
// future data change accidentally shipping an EOLCS-sourced row: the artifact
// itself is scanned after the write, so any regression fails closed at build
// time naming the source, dimension, and offending table (matching the
// issue's failure/recovery contract).
//
// The three product tables are not in the schema today; when the tables land
// this gate is already in place. If a target table is missing, that table is
// silently skipped (nothing to check) and the remaining tables are still
// verified.

const EOLCS_TABLES = ['oil_products', 'oil_brands', 'oil_product_claims']

// Match either a source_key that begins with 'eolcs' (case-insensitive) or a
// provider whose canonical name contains 'EOLCS'. Using both dimensions means
// a rename in one field alone cannot silently bypass the gate.
const EOLCS_SOURCE_PREDICATE =
  "(lower(ds.source_key) LIKE 'eolcs%' OR upper(ds.provider) LIKE '%EOLCS%')"

export function checkNoEolcsRows(db) {
  const existing = new Set(
    db
      .prepare(
        `SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (${EOLCS_TABLES.map(() => '?').join(', ')})`
      )
      .all(...EOLCS_TABLES)
      .map(r => r.name)
  )

  const hasSources = db
    .prepare("SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'data_sources'")
    .get()
  if (!hasSources && existing.size > 0) {
    throw new Error(
      'DOS-M09-010 AC-6: data_sources table is missing but at least one of ' +
        `${EOLCS_TABLES.join(', ')} is present — cannot verify source disposition.`
    )
  }

  const checked = [...existing].sort()
  const offenders = []
  for (const table of checked) {
    const rows = db
      .prepare(
        `SELECT t.rowid AS rowid,
                t.source_id AS source_id,
                ds.source_key AS source_key,
                ds.provider AS provider
           FROM ${table} AS t
           JOIN data_sources AS ds ON ds.id = t.source_id
          WHERE ${EOLCS_SOURCE_PREDICATE}`
      )
      .all()
    for (const r of rows) offenders.push({ table, ...r })
  }

  if (offenders.length) {
    const first = offenders[0]
    throw new Error(
      `DOS-M09-010 AC-6: ${offenders.length} EOLCS-sourced row(s) reached the catalog artifact ` +
        `(e.g. ${first.table} rowid=${first.rowid} source_key=${first.source_key} provider=${first.provider}). ` +
        'EOLCS bulk scraping / directory mirroring is prohibited pending an approved acquisition basis ' +
        '(FR-3). See docs/data/FACTUAL_USE_AND_MARKS_POLICY.md and planning/issues/DOS-M09-010.md AC-6.'
    )
  }

  return { checked, offenders }
}
