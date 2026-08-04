// DOS-M09-010 AC-6 gate tests. Runs under Node >= 22's built-in test runner:
//   node --test tools/catalog/tests/no_eolcs_rows.test.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { DatabaseSync } from 'node:sqlite'
import { checkNoEolcsRows } from '../src/checks/no_eolcs_rows.mjs'

// Minimal schema mirroring only the shape the gate reads: data_sources plus
// the three product tables each carrying source_id -> data_sources(id). Keeps
// the fixture readable without pulling the full catalog schema.
const BASE_SCHEMA = `
  CREATE TABLE data_sources (
    id TEXT PRIMARY KEY,
    source_key TEXT NOT NULL,
    provider TEXT NOT NULL
  );
  CREATE TABLE oil_products (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES data_sources(id)
  );
  CREATE TABLE oil_brands (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES data_sources(id)
  );
  CREATE TABLE oil_product_claims (
    id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES data_sources(id)
  );
`

function newDb(extraSql = '') {
  const db = new DatabaseSync(':memory:')
  db.exec(BASE_SCHEMA + extraSql)
  return db
}

test('passes when no product tables carry an EOLCS-sourced row', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s-vpic', 'vpic_api', 'NHTSA');
    INSERT INTO oil_products VALUES ('p1', 's-vpic');
    INSERT INTO oil_brands VALUES ('b1', 's-vpic');
  `)
  const r = checkNoEolcsRows(db)
  assert.equal(r.offenders.length, 0)
  assert.deepEqual(r.checked, ['oil_brands', 'oil_product_claims', 'oil_products'])
  db.close()
})

test('throws when an oil_products row is EOLCS-sourced by source_key', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s-eolcs', 'eolcs', 'API');
    INSERT INTO oil_products VALUES ('p1', 's-eolcs');
  `)
  assert.throws(
    () => checkNoEolcsRows(db),
    /DOS-M09-010 AC-6.*EOLCS-sourced row/i
  )
  db.close()
})

test('throws when an oil_brands row is EOLCS-sourced by provider', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s-eolcs2', 'api_directory', 'EOLCS');
    INSERT INTO oil_brands VALUES ('b1', 's-eolcs2');
  `)
  assert.throws(
    () => checkNoEolcsRows(db),
    /DOS-M09-010 AC-6/i
  )
  db.close()
})

test('throws when an oil_product_claims row is EOLCS-sourced', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s-eolcs3', 'eolcs_directory_2026', 'API/EOLCS');
    INSERT INTO oil_product_claims VALUES ('c1', 's-eolcs3');
  `)
  assert.throws(
    () => checkNoEolcsRows(db),
    /DOS-M09-010 AC-6/i
  )
  db.close()
})

test('error message names table + source_key so the offender is identifiable', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s-eolcs4', 'eolcs', 'API');
    INSERT INTO oil_products VALUES ('p1', 's-eolcs4');
    INSERT INTO oil_product_claims VALUES ('c1', 's-eolcs4');
  `)
  let err
  try {
    checkNoEolcsRows(db)
  } catch (e) {
    err = e
  }
  assert.ok(err, 'expected checkNoEolcsRows to throw')
  assert.match(err.message, /oil_products|oil_product_claims/)
  assert.match(err.message, /source_key=eolcs/)
  assert.match(err.message, /2 EOLCS-sourced row/)
  db.close()
})

test('gracefully skips product tables that are absent from the schema', () => {
  // Only data_sources exists (mirrors today's schema.sql before the product
  // tables land). The gate must be a no-op, not an error.
  const db = new DatabaseSync(':memory:')
  db.exec(`CREATE TABLE data_sources (
    id TEXT PRIMARY KEY, source_key TEXT NOT NULL, provider TEXT NOT NULL
  );`)
  const r = checkNoEolcsRows(db)
  assert.deepEqual(r.checked, [])
  assert.deepEqual(r.offenders, [])
  db.close()
})

test('checks each present product table independently when others are missing', () => {
  const db = new DatabaseSync(':memory:')
  db.exec(`
    CREATE TABLE data_sources (
      id TEXT PRIMARY KEY, source_key TEXT NOT NULL, provider TEXT NOT NULL
    );
    CREATE TABLE oil_products (
      id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES data_sources(id)
    );
    INSERT INTO data_sources VALUES ('s-eolcs', 'eolcs', 'API');
    INSERT INTO oil_products VALUES ('p1', 's-eolcs');
  `)
  assert.throws(() => checkNoEolcsRows(db), /oil_products/)
  db.close()
})

test('is case-insensitive on source_key and provider', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s1', 'EOLCS', 'api');
    INSERT INTO oil_products VALUES ('p1', 's1');
  `)
  assert.throws(() => checkNoEolcsRows(db), /DOS-M09-010 AC-6/)
  db.close()
})

test('does not flag look-alike sources whose names do not include EOLCS', () => {
  const db = newDb(`
    INSERT INTO data_sources VALUES ('s1', 'oem_publication', 'Some OEM');
    INSERT INTO data_sources VALUES ('s2', 'fueleconomy_gov_bulk', 'DOE/EPA');
    INSERT INTO oil_products VALUES ('p1', 's1');
    INSERT INTO oil_brands VALUES ('b1', 's2');
  `)
  const r = checkNoEolcsRows(db)
  assert.equal(r.offenders.length, 0)
  db.close()
})
