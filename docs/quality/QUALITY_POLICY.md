# Quality policy — flaky tests, severity, blockers, exceptions

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-006](../../planning/issues/DOS-M01-006.md) AC-10 / FR-7.
**Scope:** every automated check that gates merge to `main` or gates a Fly release.

## 1. Flaky-test quarantine

A test is **flaky** when the same commit produces different pass/fail results across runs with no code change to the system under test. Flakiness in a required gate is a defect against the *gate*, not the *code the gate is checking*.

- **First failure:** the failing PR is not merged. Author reruns; if it passes, author files a followup issue titled `flaky: <suite> / <test name>` and links the run. Merging still requires a green run on this PR.
- **Second confirmed flake within a rolling week:** the test is quarantined. Quarantine = the test file gets `@moduletag :quarantined` (Elixir) or `test.skip` (Vitest / Playwright) and a link to the followup issue in a comment above the tag. The quarantined test is executed in a separate non-blocking job so its status stays visible.
- **Ownership:** the quarantine comment names an owner and an expiration date. Default owner is whoever last edited the test file; explicit reassignment is fine.
- **Expiration:** 21 days from quarantine. The owner either resolves the flake or the test is deleted with a followup that specifies what coverage replaces it. A quarantined test never sits indefinitely.
- **What does not count as flaky:** an intermittent failure whose root cause is a real race or resource leak in the system under test. That gets fixed at the source, not quarantined.

## 2. Severity and triage

Defect severity is set at triage from the user impact, not the technical difficulty.

| Severity | Definition | Response time |
| --- | --- | --- |
| S1 — data loss / silent wrong answer | A user loses a record they believed was stored; the sticker or reminder shows a materially wrong date, mileage, or grade with no visible caveat; personal data leaves the browser. | Halt other work. Owner within 1 hour. |
| S2 — critical function down | Cannot log an oil change, cannot render the sticker, hydration always fails on a supported browser, deploy pipeline is red. | Owner within 1 business day. Blocks release. |
| S3 — significant defect | A supported path works but is visibly broken (bad copy, wrong-but-clearly-signalled state, a11y regression on a required flow). | Owner within 1 week. Blocks release only if severity escalates. |
| S4 — minor / cosmetic | Non-blocking visual, low-frequency edge case, deferred nice-to-have. | Scheduled. |

Every S1 spawns a post-incident note in [`docs/governance/RELEASE_LEDGER.md`](../governance/RELEASE_LEDGER.md) once the release is out — what shipped, what caught it, what would have caught it earlier.

## 3. Release blockers

A finding blocks a Fly release when **any** is true:

- It is S1 or S2.
- It regresses a Constitution 2.0.0 invariant (INV-3, INV-4, INV-15, INV-17, INV-22, INV-23, INV-24, INV-25, INV-26, INV-27) in a way an automated gate did not catch.
- It regresses a required accessibility path (AC-7 from [DOS-M01-005](../../planning/issues/DOS-M01-005.md): the four hydration states, keyboard focus survival on reconnect).
- It regresses the first-visit payload budget or the LiveView round-trip provisional threshold.

The blocker record lives on the release ledger row and is closed when the fix ships or the release is intentionally held.

## 4. Exceptions

A required check can be skipped only via an explicit exception record. Fields:

| Field | Meaning |
| --- | --- |
| `check` | Exact name of the required check being skipped. |
| `reason` | One paragraph, plain language, why skipping is safer than blocking. |
| `owner` | The human who signed off. |
| `expiration` | ISO date. The exception dies on this date whether or not it has been resolved. |
| `mitigation` | What compensates for the missing check while it is out. |

Exceptions live in [`docs/quality/EXCEPTIONS.md`](EXCEPTIONS.md) (create when first exception is filed). A required check with no matching exception, running or skipped, is a defect against the CI configuration.

## 5. What is not policy here

- The browser/engine support matrix — see [`SUPPORT_MATRIX.md`](SUPPORT_MATRIX.md).
- Which suites the conformance runner treats as Tier 1 — see the conformance runner code and the DOS-M09-008 issue body.
- The release-blocker gate list for M07 hardening — see [`RELEASE_GATES.md`](RELEASE_GATES.md) (pre-pivot mobile-store context; a rescoped version for the browser release lands in a later M07 card).
