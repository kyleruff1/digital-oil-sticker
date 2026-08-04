# M01-006 AC-8 — template sweep of downstream issue bodies

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-006](issues/DOS-M01-006.md) AC-8.
**Method:** grep for pre-pivot terms (`mob_notify`, `UserRepo`, `Mob 0.7`, "physical device", "native lifecycle") across `planning/issues/DOS-M0[2-9]-*.md`, then classified each hit by whether it lives in the current spec or in a `## Superseded pre-pivot spec (historical record)` section.

## Summary

| Category | Count | Action |
| --- | --- | --- |
| Hits in historical sections — correctly retired | 43 files | None needed; the audit trail must be preserved. |
| Hits in pivot-documentation prose ("no `UserRepo` in the deployment", "This FR replaces pre-pivot FR-N") | 15 files | None needed; these describe the retirement, which is the correct pattern. |
| Safe mechanical noun-swap (`UserRepo` → browser IndexedDB per DOS-M09-001) | **6 files, done in this commit** | Landed. |
| Owner-only rescopes (whole card leans on pre-pivot architecture) | **2 files, flagged below** | Owner decision required. |

**No "test manually" phrases found anywhere.** Every issue that describes testing already names a specific check or is deferred to a QA card.

## Landed in this commit — mechanical noun-swaps

| Card | Line | Change |
| --- | --- | --- |
| DOS-M02-006 | Context L21 | "Master prompt §8 `UserRepo` tables" → browser IndexedDB `events`/`readings` stores per DOS-M09-001, with an explicit "pre-pivot `UserRepo` tables are retired" clause. Server-side `CatalogRepo` tables unchanged. |
| DOS-M03-007 | Rollback L120 | "historical user snapshots … persist in UserRepo" → "persist in the browser's IndexedDB `dos_local` per DOS-M09-001; there is no server-side `UserRepo` (INV-23, ADR-0004 §4)". |
| DOS-M03-008 | FR-9 L46 | "UserRepo snapshot semantics" → "browser IndexedDB `events` store snapshot semantics per DOS-M09-001". |
| DOS-M03-010 | Security L76 | "UserRepo is a separate database" → "personal data lives in the browser's IndexedDB `dos_local` per DOS-M09-001". |
| DOS-M06-003 | Components L63 | "loading a consistent input snapshot from `UserRepo`" → "from the LiveView's hydrated `socket.assigns.garage` (populated from IndexedDB via the ADR-0004 hydration protocol)". |
| DOS-M06-004 | Rollback L141 | "OLM note field follows the §8 `UserRepo` contract" → "follows the browser IndexedDB `events` store layout per DOS-M09-001". |

Each change preserves the intent of the requirement while naming the current architecture. None changes the acceptance criteria or the test surface.

## Flagged for owner rescope — beyond a template sweep

### DOS-M03-000 — M03 epic entry criteria (lines 41, 47)

Current text names "Mob 0.7.20 with the BEAM and LiveView running inside physical iOS/Android apps" as the entry criterion for M03. Under ADR-0004 the M03 catalog work runs against a hosted Fly.io app, not a packaged native app, and depends on M01 (not M00) preconditions plus DOS-M09-001 for the client-side persistence surface it will feed.

**Recommendation:** add a `> RESCOPED FOR BROWSER MVP — 2026-08-01.` banner and move the existing entry criteria into a `## Superseded pre-pivot spec (historical record)` section. Replace with:
- Entry criteria: DOS-M01-001 pinned toolchain, DOS-M01-003 CatalogRepo schema (both closed), DOS-M09-001 IndexedDB schema decided (owner of the client-side write path M03 data ends up in).
- FR-1: The Fly.io Phoenix LiveView + Docker-baked `CatalogRepo` architecture baseline is recorded (ADR-0004) and unchallenged by any approved contrary ADR before gated catalog implementation begins.

This is a scope decision, not a noun-swap. Not landed in this commit.

### DOS-M08-007 — post-MVP catalog update flow (lines 21, 22, 90)

Current text describes catalog updates as an on-device staged copy over an on-device `UserRepo`, referencing master prompt §4.2 and §8. Under ADR-0004 catalog updates are Fly image rollouts, and there is no `UserRepo` to preserve — the user's data lives in the browser and is untouched by a catalog release regardless.

M08 is post-MVP. The right move is:
- **If M08 stays on the roadmap in its post-MVP position:** add a RESCOPED banner and re-plan the update flow around Fly image rollouts (mostly a mechanical rewrite pointing at the DOS-M09-006 pipeline).
- **If M08 is being deferred or restructured:** flag it and defer the rewrite until the roadmap decision.

Not landed in this commit. Awaits owner call.

## Files left alone deliberately

- **DOS-M06-006** — the `mob_notify` half. Card is DEFERRED per PIVOT-2026-08-01. Its body correctly describes the deferred work; a rescope would erase the deferred-track record.
- **DOS-M08-004** — deferred `mob_notify` capacity work. Same reasoning.
- **DOS-M09-*** — every reference to `UserRepo` is retirement documentation ("the design it replaces leaned on all five"). Correct pattern; preserved.

## How to close M01-006 AC-8

AC-8 asks for QA sign-off that:
1. M02/M04/M05/M06/M07/M09 templates cite the M01-* suites instead of inventing ambiguous "test manually" steps.
2. No template still cites the retired suites as **binding**.

The 6 mechanical swaps + this survey resolve #1 for every card that had a leak; every remaining "UserRepo" or "mob_notify" mention is either (a) documented retirement prose, (b) in a historical section, or (c) in the deferred M06-006 / M08-004 native-track cards. The 2 flagged rescopes (M03-000, M08-007) are the last outstanding items — both need owner planning decisions before rewriting.

Attach this file to issue #14 as the AC-8 evidence; when the 2 flagged rescopes land, this file's "Flagged for owner rescope" section becomes empty and the AC closes.
