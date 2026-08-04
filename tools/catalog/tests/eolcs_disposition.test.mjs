// DOS-M09-010 AC-1 / AC-11 positive test: the fixture build must record the
// EOLCS "rejected/prohibited" disposition row with the exact six-axis tuple
// and a live evidence snapshot. Guards against a silent drop of the audit
// trail — checkNoEolcsRows proves EOLCS isn't SOURCING rows, but only this
// test proves the disposition itself is present in the built artifact with
// the fields AC-1 demands.
//
// Runs under Node >= 22's built-in test runner:
//   node --test tools/catalog/tests/eolcs_disposition.test.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'
import { existsSync, mkdtempSync, rmSync, statSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DatabaseSync } from 'node:sqlite'
import { buildFixtures } from '../src/compile/fixture.mjs'
import {
  EOLCS_SOURCE_KEY,
  EOLCS_TERMS_SHA256,
  EOLCS_EVIDENCE_REF,
  EOLCS_DISPOSITION,
} from '../src/compile/eolcs_disposition.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))
const TOOLS_ROOT = join(HERE, '..')
const REPO_ROOT = join(TOOLS_ROOT, '..', '..')

// Build the fixture once for both assertions (kept module-scoped so an
// accidental second build doesn't hide non-determinism).
const OUT_DIR = mkdtempSync(join(tmpdir(), 'dos-m09-010-eolcs-'))
buildFixtures({ repoRoot: REPO_ROOT, toolsRoot: TOOLS_ROOT, outDir: OUT_DIR })

test.after(() => {
  rmSync(OUT_DIR, { recursive: true, force: true })
})

for (const artifact of ['catalog-fixture-a.sqlite3', 'catalog-fixture-b.sqlite3']) {
  test(`${artifact} records the EOLCS disposition row with the exact six-axis tuple`, () => {
    const db = new DatabaseSync(join(OUT_DIR, artifact))
    try {
      const row = db
        .prepare(
          `SELECT source_key, copyright_basis, acquisition_basis, redistribution_basis,
                  trademark_posture, claim_posture, review_status,
                  terms_sha256, evidence_ref, reviewed_at, reviewer
             FROM data_sources
            WHERE source_key = ?`
        )
        .get(EOLCS_SOURCE_KEY)

      assert.ok(row, `expected data_sources row for source_key=${EOLCS_SOURCE_KEY} in ${artifact}`)

      // AC-1: the exact six-axis tuple.
      assert.equal(row.copyright_basis, EOLCS_DISPOSITION.copyright_basis)
      assert.equal(row.acquisition_basis, EOLCS_DISPOSITION.acquisition_basis)
      assert.equal(row.redistribution_basis, EOLCS_DISPOSITION.redistribution_basis)
      assert.equal(row.trademark_posture, EOLCS_DISPOSITION.trademark_posture)
      assert.equal(row.claim_posture, EOLCS_DISPOSITION.claim_posture)
      assert.equal(row.review_status, EOLCS_DISPOSITION.review_status)

      // AC-11: terms_sha256 not null and evidence_ref resolves to a file.
      assert.ok(row.terms_sha256, 'terms_sha256 must be present for AC-11')
      assert.equal(row.terms_sha256, EOLCS_TERMS_SHA256)
      assert.ok(row.evidence_ref, 'evidence_ref must be present for AC-11')
      assert.equal(row.evidence_ref, EOLCS_EVIDENCE_REF)

      const absEvidence = join(REPO_ROOT, row.evidence_ref)
      assert.ok(
        existsSync(absEvidence),
        `evidence_ref ${row.evidence_ref} must exist on disk (${absEvidence})`
      )
      assert.ok(
        statSync(absEvidence).isFile(),
        `evidence_ref ${row.evidence_ref} must be a regular file`
      )

      // Provenance sanity: reviewed_at and reviewer are pinned in the shared constant.
      assert.equal(row.reviewed_at, '2026-08-02')
      assert.equal(row.reviewer, 'kyleruff1')
    } finally {
      db.close()
    }
  })
}
