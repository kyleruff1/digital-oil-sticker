# Web-Serving Rights Re-Review (DOS-M00-006)

Date: 2026-08-02
Reviewer: kyleruff1 (owner)
Trigger: ADR-0004 pivot from bundled on-device redistribution to hosted web serving.

## Purpose

DOS-M00-000 AC-1 requires DOS-M00-006's terminal state to include a "web-serving-rights re-review recorded." The pivot from an on-device bundled catalog to a server-side read-only catalog served over HTTPS changes the redistribution vector. This document records the re-review of `SOURCE_REGISTER.md` and `LICENSING_CHECKLIST.md` against the hosted model.

## Finding: green-lane sources (vPIC, FuelEconomy.gov, EPA) — unaffected

The green-lane sources are U.S. Government works under 17 U.S.C. §105. The shift from bundling factual data inside a signed device package to serving it from a hosted Phoenix application over HTTPS does not change the copyright analysis. Government factual data is not copyrightable regardless of delivery mechanism.

The factual-use posture ratified in the plan (2026-08-01, rev 2) confirms: vPIC and FuelEconomy.gov are approved at the source level on the basis of NHTSA's express open-data authorization and the factual nature of the extracted fields, not a blanket §105 claim. Operational controls (ID endpoints, rate/Retry-After, cache/resume, provenance, attribution, no implied endorsement, no VINs in telemetry) apply identically to the hosted model.

No change to `SOURCE_REGISTER.md` entries for vPIC, FuelEconomy.gov, or EPA certification data.

## Finding: documented-facts lane (OEM documents, EOLCS, oil-brand TDS) — gated, unchanged

The documented-facts lane extracts discrete factual fields into an independently designed schema with original wording. Whether those facts are stored in a bundled SQLite file or a server-side read-only SQLite file does not change the factual-use analysis under Feist. The `LICENSING_CHECKLIST.md` items ("no vendored source PDFs, protected images, prose, or table layouts") apply identically.

**EOLCS** remains gated: `robots.txt = Disallow: /`, API terms prohibit reproduction/derivatives without written authorization, and it is a private trade association directory — not covered by §105. Build 1 ships zero EOLCS rows. The `rights_disposition` / source-level disposition scheme ensures no EOLCS-sourced row is served until the acquisition and redistribution method is approved (DOS-M09-010, AC-9).

No change to `SOURCE_REGISTER.md` entries for documented-facts lane sources.

## Finding: permission-needed lane (filter finders) — gated, unchanged

Interactive commercial sites that prohibit automated extraction remain gated regardless of delivery mechanism. The `LICENSING_CHECKLIST.md` requirement for "an offered download/API, written permission, or a supplier-provided file" applies identically to the hosted model.

No change to `SOURCE_REGISTER.md` entries for permission-needed lane sources.

## Finding: LICENSING_CHECKLIST.md procurement section — minor language update needed

The "one-time-snapshot procurement requirements" section references "offline end-user storage" and "inclusion in signed build/catalog artifacts." Under the hosted model:

- "Offline end-user storage" → not applicable for catalog data (catalog is server-side only; personal data in browser IndexedDB is user-entered, not licensed).
- "Inclusion in signed build/catalog artifacts" → becomes "inclusion in the Docker release image as a read-only SQLite file."

These are delivery-mechanism details, not rights changes. The substantive requirement — perpetual rights to normalize and redistribute the acquired version — is identical. A future update to `LICENSING_CHECKLIST.md` may clarify the hosted language, but no source disposition changes.

## Conclusion

The pivot from bundled on-device redistribution to hosted web serving does not change the rights analysis for any registered source. Green-lane sources remain unaffected. Documented-facts and permission-needed sources remain gated by their existing disposition controls. The `SOURCE_REGISTER.md` and `LICENSING_CHECKLIST.md` are adequate for the hosted model with no substantive changes required.

This re-review satisfies DOS-M00-000 AC-1 (DOS-M00-006 terminal state) and the manual evidence requirement in the M00 test plan.
