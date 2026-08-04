# Operator-access rule and scoped privacy claim

**Status:** DRAFT — owner sign-off required to close [DOS-M09-007](../../planning/issues/DOS-M09-007.md) AC-15.
**Authority:** [CONSTITUTION.md](../product/CONSTITUTION.md) INV-3, INV-4, INV-5, INV-15, INV-22, INV-23, INV-26; [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) §"Security and privacy boundary for a hosted application", specifically §"LiveDashboard and operator access — stated honestly".

This document exists so the privacy claim the product publishes to users matches, word for word in substance, the boundary the code enforces — and so the operator-access rule that scopes it is written down in exactly one place. It is the counterpart to [DOS-M09-007](../../planning/issues/DOS-M09-007.md), whose enforcement suite is the evidence behind the claim.

## Section 1 — Operator-access rule

No operator — including `kyleruff1`, any contractor, or anyone else holding production access — accesses socket-assigns memory, log lines containing personal fragments, or any runtime state that could reveal a user's records. Access to production Fly.io machines is limited to deploy, rollback, and diagnostic activities that do not read personal state. If diagnosing a user-reported bug requires reading their state, the operator asks the user for an export file rather than probing production.

This rule is operational, not technical: `fly ssh console` and remote IEx grant the technical ability to inspect a running process, including a live session's `socket.assigns` (ADR-0004 §"LiveDashboard and operator access — stated honestly"). The rule bounds that ability rather than pretending it does not exist — overclaiming here would be exactly the kind of dishonesty INV-5 and INV-15 prohibit.

Console access is for diagnosing the **application**, not for diagnosing **users**.

## Section 2 — Scoped privacy claim (published-to-users statement)

The statement below is the published-to-users privacy claim. Its scope matches FR-18 word for word in substance, and it is the only wording that may appear on the Netlify static privacy page or the in-app privacy screen without a new ADR and a privacy re-review:

> This app stores your records ONLY in your browser (IndexedDB). We keep no server-side copy of your garage, service history, odometer readings, notes, or any personal identifier. Nothing you enter is transmitted to us. Export a file to keep or move your data — that is the only path.
>
> The operator does not access the running application's memory to read user data. Fly.io production access is scoped to deploy/rollback/diagnostic activities that do not read personal state.

The claim is scoped to server storage and to operator behavior. It does not — and must not — inflate into a claim that no operator could ever technically observe a live session; that would be a false security claim in the same way a restated loopback promise would be (see the retirement of INV-2 in CONSTITUTION.md §"Invariants" and its replacement by INV-22, INV-23, INV-26).

## Section 3 — Linkage

Cross-references binding this document to the invariants it derives from and the evidence that proves it:

| Reference | Where it lives | What it contributes |
| --- | --- | --- |
| INV-3 (no server-side personal record) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | The underlying prohibition the claim publishes. |
| INV-4 (no telemetry, personal data never leaves the browser, never appears in server logs) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | The logging half of what the operator rule enforces. |
| INV-22 (hosted transport security) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | The public-boundary replacement for retired INV-2; the transport this claim is made on. |
| INV-23 (anonymous client-side storage is the only home for personal data) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | The rule that makes IndexedDB the only home for the records named in Section 2. |
| INV-26 (impersonal catalog-query surface) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | Closes the network path opened by the pivot, so "nothing you enter is transmitted to us" holds against the query stream too. |
| INV-5 (no overclaiming) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | Prohibits overclaiming; the normative basis for Section 2's "no server-side copy" phrasing and for Section 1's operational-not-technical framing of operator access. |
| INV-15 (anti-overclaim on technical impossibility) | [CONSTITUTION.md](../product/CONSTITUTION.md) §"Invariants" | Anti-overclaim invariant; the reason Section 2 is scoped to server storage and operator behavior rather than to a technical impossibility claim. |
| ADR-0004 §"Security and privacy boundary" | [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) | The full boundary spec — transport, CSRF/session, CSP, logging, and the operator-honesty text this document ratifies. |
| DOS-M07-001 threat-model card (per DOS-M09-007 AC-16) | [DOS-M07-001](../../planning/issues/DOS-M07-001.md) | Consumes this document as the honest privacy-content input to the reviewed threat model. |
| DOS-M09-007 enforcement suite | [DOS-M09-007](../../planning/issues/DOS-M09-007.md) | Produces the tested evidence — repo-list assertion, schema/migration scan, scripted-session log-scan, request-payload audit — that makes the Section 2 claim falsifiable rather than aspirational. |

**Division of labor.** The scoped privacy claim in Section 2 is the published-to-users statement. The [DOS-M09-007](../../planning/issues/DOS-M09-007.md) card is the enforcement evidence. Neither document alone is sufficient: the claim without the enforcement suite would be a promise; the enforcement suite without the written claim would be code without a corresponding public commitment.

## Owner sign-off

AC-15 closes only when the owner has signed off on this document as written. Any edit to Section 1 (the operator rule) or to the quoted paragraph in Section 2 (the published claim) requires re-sign-off; a new ADR is required if the claim is narrowed or broadened in substance.
