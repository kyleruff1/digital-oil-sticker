# Release Gates

Launch hardening is in scope for v1. Nothing ships to production until every gate below passes with attached evidence.

## Verification principle

**No gate passes without attached evidence; read-back over claims.** Do not report success for an object or behavior that was not read back and verified. A green checkbox with no artifact behind it is a failed gate. Evidence means test output, device recordings, migration logs, coverage/build reports, store-console screenshots, or signed artifacts — attached to the gate's issue, naming the device/OS/build where hardware is involved.

## Launch-hardening gates (still in v1)

- Data-quality sign-off against a deliberately difficult golden vehicle set (see `docs/quality/GOLDEN_VEHICLES.md`).
- Import/export or another approved local recovery mechanism.
- Accessibility, performance, privacy, migration, corruption-recovery, killed-app, reboot, time-zone, and DST validation.
- Store signing, beta, store listings, release/rollback runbooks.

## M07 gate list

The M07 epic (DOS-M07-000 — Hardening, Closed Beta, and Store Release) closes only when all of the following gates are closed:

| Gate | Title |
| --- | --- |
| DOS-M07-001 | Threat-model and lock down the local-only privacy boundary |
| DOS-M07-002 | Meet the mobile accessibility and inclusive-design release bar |
| DOS-M07-003 | Enforce startup, interaction, storage, memory, and battery budgets |
| DOS-M07-004 | Execute the cross-platform offline, migration, and notification QA matrix |
| DOS-M07-005 | Establish CI, supply-chain, migration, and signed-build quality gates |
| DOS-M07-006 | Run a privacy-preserving closed beta and defect triage program |
| DOS-M07-007 | Prepare, stage, monitor, and recover the production release |

## Epic exit gate

DOS-M07-001 through DOS-M07-007 are closed; no unresolved severity-1/severity-2 defect or release-blocking accessibility/privacy/security finding exists; the complete critical-journey/device matrix passes; backup and upgrade recovery are proven; store disclosures match observed traffic and SDK inventory; rollback/forward-fix owners and commands are rehearsed; release approval is recorded.

## Standing constraints on every gate

- Physical-device evidence is required where a gate touches hardware behavior; emulator runs do not substitute (see `docs/quality/TEST_STRATEGY.md`).
- Evidence artifacts must be redacted: no private VIN, mileage, notes, or vehicle identifiers.
- A gate that discovers new work spawns a new issue; it does not silently enlarge the gate's scope.
