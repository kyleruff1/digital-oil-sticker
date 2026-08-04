# ADR-0008 — PWA installability, service-worker offline, and Web Push (go/no-go)

**Status:** Accepted 2026-08-02 · **Cites:** INV-3, INV-4, INV-6, INV-17, INV-19, INV-22, INV-23 ([CONSTITUTION.md](../product/CONSTITUTION.md)) · **Supersedes (in part):** [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) §"Consequences" and Risks row R1's forward reference to a future PWA decision · **Closes:** [DOS-M09-009](../../planning/issues/DOS-M09-009.md), the third bullet of [CONSTITUTION.md](../product/CONSTITUTION.md) §0.5

> This ADR is the terminating record for the three deferred decisions that Constitution §0.5 bullet three left open: web-app installability (H1), service-worker offline (H2), and Web Push (H3). Per FR-2 of DOS-M09-009 this ADR is dated on the day it is accepted; per CHANGE_CONTROL Rule 2a owner acceptance is by this commit landing on main under owner sign-off.

---

## Context

Constitution 2.0.0 §0.5 records three open deferred decisions — Web Push, service-worker/PWA offline, and native-mobile revival — and requires that none of them may be implied by MVP copy (INV-19). DOS-M09-009 exists to terminate the first two of those three (PWA installability and service-worker offline) and the third one enumerated in the ratification bullet (Web Push). Native revival is out of scope of this ADR and remains an open deferred decision.

The verdicts recorded here are **separable**: each of the three hypotheses is decided on its own evidence and constraints, and each carries its own re-open trigger. They are recorded together because the constitution's §0.5 bullet three names them together and because a single ADR closing the three-way deferral makes the FR-11 absence-guard extension a single technical commit rather than three.

### Evidence anchors already on the record

The three verdicts below cite [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) for load-bearing prior findings. The specific anchors are:

- **ADR-0004 §"Consequences" bullet "The app does not work offline at all"** — "LiveView renders on the server, so with no connection there is no UI beyond a disconnected shell — even for a garage already sitting in the user's own IndexedDB. This is the single largest honest loss of the pivot and no copy anywhere may soften it." The adjacent bullet: "A PWA / service-worker offline mode is an explicitly deferred, separate decision. It is not promised, not scheduled, and not implied by this ADR."
- **ADR-0004 Risks table row R1** ("Browser eviction of infrequently-used site storage") — names `navigator.storage.persist()`, honest storage-status UI, and export nudges as mitigations, and states: "A PWA-install path is the strongest known mitigation and is one of the arguments the future PWA decision must weigh."
- **ADR-0004 §"Content Security Policy"** — `connect-src 'self' wss://digitaloilsticker.com`, no third-party origins, no CDN, no external script of any kind.
- **ADR-0004 Risks table row R6** ("Web-serving rights for licensed catalog sources are unreviewed") plus the "One new obligation ADR-0003 did not anticipate" paragraph under "ADR-0003 → Unchanged" — the hard gate that no documented-facts or permission-needed source is served from the hosted app until `SOURCE_REGISTER.md` and `LICENSING_CHECKLIST.md` are re-reviewed for web serving.

### The FR-16 default

DOS-M09-009 FR-16 provides that any sub-decision whose supporting evidence has expired — or was never produced — defaults to **no-go**. The three verdicts below are each analyzed on their own merits; where the merits do not clear the bar the FR-16 default is what carries them.

## Decision — three separable verdicts

### H1 — Web app installability (PWA manifest + install path): **no-go**

**Reasoning.** The strongest argument for shipping installability is not user-facing polish; it is the durability mitigation named in ADR-0004 R1 — that a PWA-install path is the strongest known mitigation against browser eviction of infrequently-used site storage. Under the anonymous-client-side-storage architecture ratified in Constitution 2.0.0 (INV-23), the user's garage lives in IndexedDB and evictable browser storage is the whole persistence story. If installability materially reduces eviction risk on the target browser matrix, the argument for shipping it is R1 itself. If it does not, the argument collapses; installability is then a cosmetic add-to-home-screen affordance whose upside is not worth the copy and support surface it introduces.

The measured eviction figures that would substantiate the R1 argument are the deliverable of [DOS-M09-008](../../planning/issues/DOS-M09-008.md), which is outstanding. Per FR-16, the sub-decision whose supporting evidence has not been produced defaults to no-go. This is a defaulted refusal, not a merits refusal — the merits argument may exist, but it has not been made.

**Re-open trigger.** DOS-M09-008 lands measured eviction figures showing a meaningful durability difference between installed and non-installed states on the browser matrix. When and only when that measurement exists, this verdict may be revisited by a new ADR (not by amending this one).

### H2 — Service-worker offline: **no-go**

**Reasoning.** ADR-0004's "Consequences — Lost, honestly" section already records that the server-rendered LiveView architecture means no useful offline UI exists: "LiveView renders on the server, so with no connection there is no UI beyond a disconnected shell — even for a garage already sitting in the user's own IndexedDB." A service worker can cache assets, but the user-meaningful state (the user's garage, their sticker, their next-due decision) cannot be rendered without the server round-trip that LiveView requires. An offline shell that shows only a disconnected chrome is not an offline mode; it is a disconnected shell with an install prompt in front of it.

The one useful thing a service worker could serve offline is a slice of the catalog — the vehicle-lookup surface, in principle. But that raises a licensing question ADR-0003 and ADR-0004 R6 have not cleared: which catalog sources have hosted-web-serving rights, let alone rights to be served from a local cache written by a service worker on the user's device. That review has not been done for this purpose. Under INV-6 (a feature ships whole or not at all), a service-worker cache that offers a partial and unresolved-legality vehicle-lookup while offering no user-state UI cannot be shipped as an "offline mode" without misrepresenting what the user gets.

**Re-open trigger.** Both conditions must be met: the licensing lanes chosen under [ADR-0003](ADR-0003-data-boundaries.md), [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) R6, and [ADR-0007](ADR-0007-manufacturer-oil-schedule-sourcing.md) explicitly authorize catalog-slice caching on-device for offline serving, **and** an offline shell design exists that can render user-meaningful state without a server round-trip (e.g., a fundamentally different client-render architecture from the LiveView one ratified in ADR-0004).

### H3 — Web Push: **no-go**

**Reasoning.** Web Push is not a UI decision; it is a data-boundary decision. A Web Push subscription is a per-device, server-side endpoint plus keys that the application server holds and uses to push messages. In substance that is a durable per-person record — one row per device per user, held by the server — regardless of whether the record is labeled "subscription," "endpoint," or something else. That directly conflicts with INV-3 (no personal server-side records) and INV-23 (anonymous client-side storage; the server is not to hold per-user state).

Web Push additionally requires a third-party push service (FCM, APNs, Mozilla's autopush) in the message delivery path. Introducing that third-party origin into the product's delivery boundary breaches INV-4 (no third-party services in the delivery path) and INV-22 (the two-origin CSP that ADR-0004 §"Content Security Policy" locks to `'self'` plus the LiveView WebSocket, with no third-party origins).

Because a Web Push adoption would materially change ratified invariants (INV-3, INV-4, INV-22, INV-23), it is not a decision an ADR can make on its own under INV-17. INV-17 requires a ratified constitution revision to change ratified invariants; a ticket, a spike, or an ADR that quietly redefined "personal record" would not clear that bar. This verdict simply records what the constitution already forbids.

**Re-open trigger.** Either the constitution is amended (via the CHANGE_CONTROL revision process, not by this ADR) to admit a personal server-side record class covering push-subscription state, **or** a push mechanism is invented that does not require server-side per-device subscription state and does not require a third-party origin in the delivery path. Until one of those two things is true, this verdict is not re-openable.

## Consequences

### Copy consequences (per FR-15; handed to [DOS-M09-004](../../planning/issues/DOS-M09-004.md) and the M02 content contract)

- The app permanently states **"This app does not notify you when it is closed"** (already present as `Copy.does_not_notify/0`; this ADR ratifies that copy line as a standing commitment, not a placeholder).
- The app **never** describes itself as "offline," "offline-first," "works offline," or any semantic equivalent, in any copy surface (UI, marketing, help text, error states, metadata).
- The app **never** advertises install, "add to home screen," or any installability affordance beyond the passive `apple-touch-icon` bookmark asset — no install prompt, no `beforeinstallprompt` handling, no "install our app" copy, no dismissible install banner.

The M02 content contract carries these as forbidden phrases and forbidden affordances; DOS-M09-004 is the implementation card that lands the copy audit.

### Test / absence-guard consequences (FR-11 extension)

The FR-11 absence-guard at `app/test/digital_oil_sticker_web/live/no_deferred_capability_controls_test.exs` is **EXTENDED in the same commit that lands this ADR** to explicitly refuse — via script-pattern assertions of the same shape as the existing `serviceWorker\s*\.\s*register` / `navigator\s*\.\s*serviceWorker` pair — each of:

1. Service worker registration (already covered; retained and reasserted here for completeness).
2. Web app manifest links (already covered; retained).
3. Push permission requests — new script-pattern guard covering `Notification\.requestPermission`, `navigator\.permissions\.query\(\s*\{\s*name\s*:\s*['"]notifications['"]` and equivalents. The existing copy-level `"Enable notifications"` / `notif` / `push` stem coverage is retained but is not sufficient on its own; the new guard catches a permission-request call issued without matching UI copy.
4. Push subscription registration — new script-pattern guard covering `pushManager`, `PushManager\.subscribe`, `PushSubscription`, and equivalents. Not previously covered.
5. Background sync registration — new script-pattern guard covering `ServiceWorkerRegistration.*\.sync\.register` and `SyncManager`. Not previously covered; the existing `\bsync` stem catches only visible text like "Sync now" and does not catch a script-level `sync.register` call.

Item (6) of FR-11, disabled-but-visible controls advertising any of the above, is already covered by `assert_no_disabled_capability_control` and by the stem-based deny list (`assert_no_forbidden_stems`) against interactive controls and their ARIA attributes. Those checks are retained.

### Follow-up implementation consequences

- **No follow-up implementation issues are created.** The three verdicts are recorded refusals, not deferred work. There is no PWA epic, no service-worker epic, no push-notification epic. Any future work in these areas begins with the re-open trigger for the specific verdict, and with a new ADR — not by picking up an issue this one leaves behind.
- The [DOS-M09-008](../../planning/issues/DOS-M09-008.md) eviction-evidence work is a re-open trigger dependency for H1, not a scheduled follow-up of this ADR. That work is scheduled on its own merits (as evidence for the R1 mitigation story regardless of installability).
- The [DOS-M09-004](../../planning/issues/DOS-M09-004.md) copy audit is the downstream implementation card for the copy consequences above. It is a pre-existing card, not a new one this ADR spawns.

## Cross-references

- [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) — superseded in part: the forward reference in Risks row R1 to "the future PWA decision" is discharged by this ADR (H1 no-go); the deferral flag in the "A PWA / service-worker offline mode is an explicitly deferred, separate decision" bullet of §"Consequences" is discharged by this ADR (H2 no-go). The bullet's substantive finding — that no useful offline UI exists under LiveView — is not superseded; it is the load-bearing citation for H2 above.
- [CONSTITUTION.md](../product/CONSTITUTION.md) §0.5 bullet three — this ADR is the terminating record for the "Web Push, service-worker/PWA offline, and native-mobile revival are each recorded as open deferred decisions" clause, insofar as it names Web Push and service-worker/PWA offline. Native-mobile revival remains an open deferred decision governed by ADR-0001's superseded-deferred status and by the revival trigger conditions ADR-0004 records; nothing in this ADR touches it.
- **INV-3** (no personal server-side records) — cited by H3.
- **INV-4** (no third-party services in the delivery path) — cited by H3.
- **INV-6** (a feature ships whole or not at all) — cited by H2.
- **INV-17** (ratified invariants change only by a ratified constitution revision) — cited by H3.
- **INV-19** (no MVP copy implies deferred capabilities) — the standing constraint that FR-15 / the copy consequences above discharge.
- **INV-22** (two-origin CSP, no third-party origins) — cited by H3.
- **INV-23** (anonymous client-side storage; server holds no per-user state) — cited by H3.
- [DOS-M09-008](../../planning/issues/DOS-M09-008.md) — measured eviction evidence is the re-open trigger dependency for H1.
- [DOS-M09-004](../../planning/issues/DOS-M09-004.md) — downstream implementation card for the copy consequences above; the M02 content contract carries the forbidden-phrases / forbidden-affordances list.
