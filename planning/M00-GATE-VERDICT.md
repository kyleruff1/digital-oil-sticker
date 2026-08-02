# M00 Gate Verdict

Date: 2026-08-02
Epic: DOS-M00-000 — Freeze the feasible product architecture before feature development
Verdict: **PASSED**

## Child terminal states (AC-1)

| Child | Terminal state | Evidence |
| --- | --- | --- |
| DOS-M00-001 | Done — Constitution 2.0.0 ratified | `docs/product/CONSTITUTION.md` rev 2.0.0, dated 2026-08-01 |
| DOS-M00-002 | Done — ADR-0004 Accepted | `docs/architecture/ADR-0004-browser-first-client-and-hosting.md`, dated 2026-08-01 |
| DOS-M00-003 | Done — suspended verdict recorded, evidence retained | Card body records DEFERRED disposition; Motorola Razr Ultra 2025 evidence, five-defect record, WSL2 containment recommendation retained; revival triggers in ADR-0004 §"Trigger conditions" |
| DOS-M00-004 | Done — persistence contract written, enforcement tests listed | `planning/M00-004-PERSISTENCE-CONTRACT-EVIDENCE.md`; ADR-0004 protocol sections; enforcement tests mapped to DOS-M09-*/DOS-M01-* owners |
| DOS-M00-005 | Done — deferred verdict recorded, in-app fallback owned by rescoped M06 | Card body records DEFERRED disposition; `mob_notify` deferred with the native track; in-app due-state fallback owned by rescoped DOS-M06-* |
| DOS-M00-006 | Done — ADR-0003 accepted, web-serving-rights re-review recorded | `docs/architecture/ADR-0003-data-boundaries.md`; `docs/data/WEB_SERVING_RIGHTS_REVIEW.md` confirming vPIC/FEG unaffected, EOLCS gated |

## Physical-device gate (AC-2)

No physical-device iPhone/Android gate is required. The DOS-M00-003 disposition records the suspended verdict per ADR-0004 §"ADR-0001 → Deferred", names the retained evidence, and points to the revival trigger conditions. No physical-device retest was performed.

## No unresolved architecture TBD (AC-3)

All four items from FR-6 are explicitly closed:

1. **Personal data server-side?** No — INV-3, INV-23. Personal data exists only in browser IndexedDB.
2. **Catalog bundled or served?** Served — ADR-0004 §"Consequences → Lost — honestly". Connectivity required.
3. **OS local notifications?** No — INV-17 amended. In-app only.
4. **PWA/Web Push promised?** No — each is a deferred decision tracked as DOS-M09-010.

## Limitation register (AC-4)

`planning/M00-LIMITATION-REGISTER.md` contains the six FR-7 entries, each with owner (kyleruff1), user-facing fallback, and review date:

1. No offline capability — review 2027-02-01
2. No OS local notifications — review 2027-02-01
3. Storage eviction risk — review 2027-02-01
4. Single-region, single-machine availability — review 2027-02-01
5. Void pre-pivot latency and packaged-size budgets — review at M07
6. Operator-console honesty caveat — review 2027-02-01

## No invariant failure (AC-5)

No binding invariant failed downstream. No replacement-architecture ADR was required. The pivot itself (ADR-0004) was ratified as a planned architecture change, not an invariant failure response.

## No feature milestone started before this gate (AC-6)

No feature milestone (M01–M09) has started. All downstream statuses are Backlog. M09 opens only after both M00 and M01 close per the pivot's dependency-order note.

## Invariant renumbering sweep (AC-7)

Grep sweep completed 2026-08-02. Every citation of INV-2 in downstream cards is in "retired/replaced by INV-22" context. Every citation of INV-1/INV-6/INV-7/INV-17/INV-19 references the amended 2.0.0 forms, not the pre-pivot 1.0.0 forms. No downstream issue cites a superseded invariant as binding.

## Milestones released

This gate verdict releases the following milestones per FR-9:

- **M01** (Engineering foundation) — may begin; blocked_by DOS-M00-000 is now satisfied
- **M02** (UX and content contract) — may begin; M00 blockers satisfied
- **M03** (Data acquisition) — may begin; M00 blockers satisfied
- **M09** (Hosted browser platform) — opens only after both M00 **and** M01 close

## Evidence not leaked (security check)

No secrets, certificates, personal path components, or personal data were leaked into the repository or attachments during M00 work. The operator-console honesty caveat is recorded in the limitation register rather than overclaimed.
