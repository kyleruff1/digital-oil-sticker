// Shared EOLCS disposition literals for every catalog compile path
// (production, bootstrap, fixture). Recording a positive
// "rejected/prohibited" data_sources row proves DOS-M09-010 AC-1's audit
// trail is present even though EOLCS contributes zero data rows (the
// checkNoEolcsRows gate enforces that separately). The evidence snapshot
// pinned here satisfies AC-11.
//
// Every field below is load-bearing: changing any of them changes the
// disposition on record and re-hashes the artifact. Editing the evidence
// snapshot requires recomputing EOLCS_TERMS_SHA256 in the same commit,
// otherwise verifyEvidenceRefs fails the build.

import { uuidv5 } from '../normalize/keys.mjs'

export const EOLCS_SOURCE_KEY = 'eolcs_api_pending'
export const EOLCS_PROVIDER = 'API'
export const EOLCS_SOURCE_TYPE = 'external_directory'
export const EOLCS_DATASET_NAME =
  'API Engine Oil Licensing and Certification System (EOLCS) product directory'
export const EOLCS_CANONICAL_URL =
  'https://www.api.org/products-and-services/engine-oil/eolcs-directory'
export const EOLCS_ATTRIBUTION_TEXT =
  'EOLCS reference is recorded here as a policy gate; Digital Oil Sticker emits no EOLCS-derived rows.'

// SHA-256 of docs/data/evidence/eolcs-terms-2026-08-02.md — the dated
// EOLCS terms + robots.txt snapshot AC-11 pins.
export const EOLCS_TERMS_SHA256 =
  '6ceb0fba092c1f8e9f8a2c813a4485c927c623542b2c60bb8da416dbc5522d5c'
export const EOLCS_EVIDENCE_REF = 'docs/data/evidence/eolcs-terms-2026-08-02.md'

export const EOLCS_REVIEWED_AT = '2026-08-02'
export const EOLCS_REVIEWER = 'kyleruff1'

// The exact six-axis tuple recorded for EOLCS (FR-1). Every dimension is
// deliberate: the source is licensed content whose acquisition method is
// prohibited pending owner approval, so redistribution is also prohibited,
// trademark posture demands review before any use of the certification
// marks, product claims are outright prohibited, and the review status is
// a hard rejection rather than pending.
export const EOLCS_DISPOSITION = Object.freeze({
  copyright_basis: 'licensed',
  acquisition_basis: 'prohibited',
  redistribution_basis: 'prohibited',
  trademark_posture: 'review_required',
  claim_posture: 'prohibited',
  review_status: 'rejected',
})

// Stable UUIDv5 for the row; matches the historical id used by all three
// compile paths so joins survive a compile-path swap.
export const EOLCS_SOURCE_ID = uuidv5(`source ${EOLCS_SOURCE_KEY}`)

// Fully-populated data_sources row. Returned as a fresh object per call so
// callers can safely mutate (none currently do) without affecting others.
export function eolcsDispositionRow() {
  return {
    id: EOLCS_SOURCE_ID,
    source_key: EOLCS_SOURCE_KEY,
    provider: EOLCS_PROVIDER,
    source_type: EOLCS_SOURCE_TYPE,
    dataset_name: EOLCS_DATASET_NAME,
    canonical_url: EOLCS_CANONICAL_URL,
    source_version: null,
    raw_sha256: null,
    retrieved_at: null,
    effective_at: null,
    verified_at: null,
    attribution_text: EOLCS_ATTRIBUTION_TEXT,
    web_attribution_text: null,
    copyright_basis: EOLCS_DISPOSITION.copyright_basis,
    acquisition_basis: EOLCS_DISPOSITION.acquisition_basis,
    redistribution_basis: EOLCS_DISPOSITION.redistribution_basis,
    trademark_posture: EOLCS_DISPOSITION.trademark_posture,
    claim_posture: EOLCS_DISPOSITION.claim_posture,
    review_status: EOLCS_DISPOSITION.review_status,
    terms_sha256: EOLCS_TERMS_SHA256,
    evidence_ref: EOLCS_EVIDENCE_REF,
    reviewed_at: EOLCS_REVIEWED_AT,
    reviewer: EOLCS_REVIEWER,
  }
}
