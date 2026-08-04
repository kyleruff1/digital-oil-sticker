// DOS-M09-010 AC-1 / AC-11 post-build gate: every data_sources row whose
// evidence_ref names a file must actually resolve to that file, and — when
// the row also carries a terms_sha256 — the *terms snapshot* the hash was
// computed over must still match. This is defence-in-depth against a
// snapshot being renamed, moved, or edited without the disposition row
// being updated in lockstep. AC-11 requires dated terms/evidence snapshots
// for every source whose access conditions matter; this check keeps those
// snapshots honest across time.
//
// Runs against the freshly built SQLite artifact (not the in-memory row
// set) so any future write path — bootstrap, fixture, production — is
// covered by the same predicate.
//
// evidence_ref vs terms_sha256:
// For some sources (EOLCS) the evidence_ref field points at the same file
// whose SHA-256 lives in terms_sha256, so the row is self-checking. For
// others (vPIC), evidence_ref points at a memo/policy document while
// terms_sha256 hashes a separate dated terms snapshot — the (source_key ->
// terms file) mapping below records that split. A fragment anchor on
// evidence_ref (`docs/x.md#section`) is stripped before file resolution;
// the file on disk is the whole document, not the anchor.

import { createHash } from 'node:crypto'
import { readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

// Sources whose terms_sha256 hashes a file DIFFERENT from evidence_ref.
// Absent keys fall back to evidence_ref (with any fragment stripped). Kept
// exported so the compile paths and tests reference exactly one source of
// truth for the mapping.
export const TERMS_FILE_BY_SOURCE_KEY = Object.freeze({
  vpic_api: 'docs/data/evidence/vpic-terms-2026-08-02.md',
  vpic_api_bootstrap_slice: 'docs/data/evidence/vpic-terms-2026-08-02.md',
  vpic_api_fixture_slice: 'docs/data/evidence/vpic-terms-2026-08-02.md',
})

function stripAnchor(ref) {
  return ref.replace(/#.*$/, '')
}

export function verifyEvidenceRefs(db, { repoRoot }) {
  if (!repoRoot) {
    throw new Error(
      'DOS-M09-010 AC-11: verifyEvidenceRefs requires repoRoot to resolve evidence_ref paths.'
    )
  }

  const hasTable = db
    .prepare("SELECT 1 AS ok FROM sqlite_master WHERE type = 'table' AND name = 'data_sources'")
    .get()
  if (!hasTable) {
    throw new Error(
      'DOS-M09-010 AC-11: data_sources table is missing — cannot verify evidence refs.'
    )
  }

  const rows = db
    .prepare(
      `SELECT source_key, evidence_ref, terms_sha256
         FROM data_sources
        WHERE evidence_ref IS NOT NULL
        ORDER BY source_key`
    )
    .all()

  const problems = []
  const checked = []

  for (const r of rows) {
    // 1) evidence_ref itself must resolve to a real file on disk.
    const refPath = stripAnchor(r.evidence_ref)
    const refAbs = join(repoRoot, refPath)
    try {
      const s = statSync(refAbs)
      if (!s.isFile()) {
        problems.push(
          `${r.source_key}: evidence_ref ${r.evidence_ref} is not a regular file`
        )
        continue
      }
    } catch (e) {
      problems.push(
        `${r.source_key}: evidence_ref ${r.evidence_ref} does not exist (${e.code ?? e.message})`
      )
      continue
    }

    // 2) If a terms_sha256 is recorded, the terms snapshot file (which may
    //    differ from evidence_ref) must exist and hash to that value.
    let shaChecked = false
    let termsFile = null
    if (r.terms_sha256) {
      termsFile = TERMS_FILE_BY_SOURCE_KEY[r.source_key] ?? refPath
      const termsAbs = join(repoRoot, termsFile)
      let bytes
      try {
        bytes = readFileSync(termsAbs)
      } catch (e) {
        problems.push(
          `${r.source_key}: terms file ${termsFile} does not exist (${e.code ?? e.message}); ` +
            'terms_sha256 cannot be verified.'
        )
        continue
      }
      const actual = createHash('sha256').update(bytes).digest('hex')
      if (actual !== r.terms_sha256) {
        problems.push(
          `${r.source_key}: terms_sha256 mismatch for ${termsFile} — ` +
            `recorded ${r.terms_sha256}, actual ${actual}. ` +
            'Re-review the snapshot and update terms_sha256 in the same commit.'
        )
        continue
      }
      shaChecked = true
    }

    checked.push({
      source_key: r.source_key,
      evidence_ref: r.evidence_ref,
      terms_file: termsFile,
      sha_checked: shaChecked,
    })
  }

  if (problems.length) {
    throw new Error(
      `DOS-M09-010 AC-1/AC-11: ${problems.length} data_sources row(s) have stale evidence:\n  ` +
        problems.join('\n  ') +
        '\nSee docs/data/FACTUAL_USE_AND_MARKS_POLICY.md and planning/issues/DOS-M09-010.md AC-11.'
    )
  }

  return { checked, problems }
}
