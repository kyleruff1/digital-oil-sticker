// Deterministic SQLite emit (DOS-M03-010): fixed pragmas before first write,
// PK-sorted inserts, indexes already in schema.sql (acceptable at this row
// volume), ANALYZE + VACUUM, journal_mode=DELETE for read-only image opens,
// timestamps from SOURCE_DATE_EPOCH only. Uses node:sqlite (Node >= 22).

import { DatabaseSync } from 'node:sqlite'
import { readFileSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))

export function sourceDateEpoch(fallbackIso) {
  const sde = process.env.SOURCE_DATE_EPOCH
  if (sde && /^\d+$/.test(sde)) return new Date(Number(sde) * 1000).toISOString()
  if (!fallbackIso) throw new Error('SOURCE_DATE_EPOCH unset and no input-manifest fallback provided (Date.now() is forbidden for determinism)')
  return fallbackIso
}

// rows: { table_name: [ {col: value}, ... ] } — inserted PK-sorted.
export function buildCatalog({ outPath, metadata, rows }) {
  if (existsSync(outPath)) rmSync(outPath)
  mkdirSync(dirname(outPath), { recursive: true })
  const db = new DatabaseSync(outPath)
  db.exec(`PRAGMA page_size = 4096; PRAGMA journal_mode = DELETE; PRAGMA auto_vacuum = NONE; PRAGMA encoding = 'UTF-8';`)
  db.exec('PRAGMA foreign_keys = ON;')
  db.exec('BEGIN;')
  db.exec(readFileSync(join(HERE, 'schema.sql'), 'utf8'))

  const metaStmt = db.prepare('INSERT INTO catalog_metadata (key, value) VALUES (?, ?)')
  for (const key of Object.keys(metadata).sort()) metaStmt.run(key, String(metadata[key]))

  const insertOrder = [
    'data_sources', 'makes', 'models', 'vehicle_configurations', 'aliases',
    'oil_brands', 'oil_products', 'oil_product_claims',
    'maintenance_schedules', 'oil_requirements',
    'filter_brands', 'filter_products', 'filter_fitments',
  ]
  const counts = {}
  for (const table of insertOrder) {
    const list = rows[table] ?? []
    counts[table] = list.length
    if (!list.length) continue
    const cols = Object.keys(list[0]).sort()
    const stmt = db.prepare(`INSERT INTO ${table} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`)
    const pk = cols.includes('id') ? 'id' : cols.includes('configuration_key') ? 'configuration_key' : cols[0]
    const sorted = [...list].sort((a, b) => String(a[pk]).localeCompare(String(b[pk])))
    for (const row of sorted) {
      stmt.run(...cols.map(c => row[c] === undefined ? null : row[c]))
    }
  }
  db.exec('COMMIT;')

  const fk = db.prepare('PRAGMA foreign_key_check').all()
  if (fk.length) throw new Error(`foreign_key_check failed: ${JSON.stringify(fk.slice(0, 5))}`)
  const integrity = db.prepare('PRAGMA integrity_check').all()
  if (integrity.length !== 1 || integrity[0].integrity_check !== 'ok') throw new Error('integrity_check failed')
  db.exec('ANALYZE;')
  db.exec('VACUUM;')
  const jm = db.prepare('PRAGMA journal_mode').get()
  if ((jm.journal_mode ?? Object.values(jm)[0]) !== 'delete') throw new Error('journal_mode must be delete for read-only image opens')
  db.close()

  const bytes = readFileSync(outPath)
  const sha256 = createHash('sha256').update(bytes).digest('hex')
  return { sha256, size: bytes.length, counts }
}

export function writeManifest(manifestPath, manifest) {
  mkdirSync(dirname(manifestPath), { recursive: true })
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
}
