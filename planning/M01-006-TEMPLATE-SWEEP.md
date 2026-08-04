# M01-006 AC-8 — template sweep of downstream issue bodies

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-006](issues/DOS-M01-006.md) AC-8.
**Method:** grep for pre-pivot terms (`mob_notify`, `UserRepo`, `Mob 0.7`, "physical device", "native lifecycle") across `planning/issues/DOS-M0[2-9]-*.md`, then classified each hit by whether it lives in the current spec or in a `## Superseded pre-pivot spec (historical record)` section.

## Summary

| Category | Count | Action |
| --- | --- | --- |
| Hits in historical sections — correctly retired | 43 files | None needed; the audit trail must be preserved. |
| Hits in pivot-documentation prose ("no `UserRepo` in the deployment", "This FR replaces pre-pivot FR-N") | 15 files | None needed; these describe the retirement, which is the correct pattern. |
| Safe mechanical noun-swap (`UserRepo` → browser IndexedDB per DOS-M09-001) | **6 files, done** | Landed. |
| Full card rescope (whole card leans on pre-pivot architecture) | **1 file (DOS-M03-000), done** | Landed 2026-08-02. |
| Correctly-deferred cards (banner + preserved historical body) — DOS-M06-006, DOS-M08-004, DOS-M08-007 | 3 files | No action. |

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

## Rescoped owner work — landed in follow-up commit

### DOS-M03-000 — M03 epic entry criteria ✅

Rescoped 2026-08-02: added `> **RESCOPED FOR BROWSER MVP — 2026-08-02.**` banner; rewrote Outcome, Preconditions, FR-1, FR-5, AC-3, Test plan, and Rollout to name Fly.io image rollout mechanics instead of iOS/Android bundle install; preserved the entire pre-pivot spec verbatim under `## Superseded pre-pivot spec (historical record)`. Entry criteria now correctly point at M01-001, M01-003, M01-004 (all closed) and M09-001 (owns the client-side write path).

### DOS-M08-007 — no rescope required ✅ (survey correction)

My original flag was wrong. Re-reading DOS-M08-007 shows it already carries a `> **DEFERRED FOR MVP — Native re-entry track (2026-08-01).**` banner and the full body is preserved as historical for the deferred native track. This is the same correctly-deferred pattern as DOS-M06-006 and DOS-M08-004 (which I originally left alone). The `UserRepo` mentions at lines 21/22/90 are inside the deferred body — describing the deferred work, not currently binding. No action needed.

## Files left alone deliberately

- **DOS-M06-006** — the `mob_notify` half. Card is DEFERRED per PIVOT-2026-08-01. Its body correctly describes the deferred work; a rescope would erase the deferred-track record.
- **DOS-M08-004** — deferred `mob_notify` capacity work. Same reasoning.
- **DOS-M09-*** — every reference to `UserRepo` is retirement documentation ("the design it replaces leaned on all five"). Correct pattern; preserved.

## How to close M01-006 AC-8

AC-8 asks for QA sign-off that:
1. M02/M04/M05/M06/M07/M09 templates cite the M01-* suites instead of inventing ambiguous "test manually" steps.
2. No template still cites the retired suites as **binding**.

**AC-8 is now satisfied.** The 6 mechanical swaps + the DOS-M03-000 rescope + this survey resolve both clauses. Every remaining `UserRepo`/`mob_notify` mention is either (a) documented retirement prose in an active browser-first card, (b) inside a `## Superseded pre-pivot spec (historical record)` section, or (c) inside a `> **DEFERRED FOR MVP — Native re-entry track**` card whose whole body is preserved as historical.

Attach this file to issue #14 as the AC-8 evidence.
