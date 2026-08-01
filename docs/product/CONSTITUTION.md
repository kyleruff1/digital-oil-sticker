# Digital Oil Sticker — Product Constitution

**Revision:** 2.0.0 · **Status:** Ratified 2026-08-01 (supersedes 1.0.0) · **Owner workstream:** Product · **Implements:** [DOS-M00-001](https://github.com/kyleruff1/digital-oil-sticker/issues/2)

This is the precedence document for the Digital Oil Sticker product. Every subsequent issue cites the invariant it implements or is bound by; when tickets conflict, this document prevails and the discovery becomes a new issue or ADR (change control, [CHANGE_CONTROL.md](../governance/CHANGE_CONTROL.md)). Amendments require a new ratified revision with fresh sign-off — never in-place edits that keep an old sign-off attached. Revision 2.0.0 is such a new revision: it replaces the 1.0.0 text wholesale, carries its own sign-off dated 2026-08-01, and does not inherit the 2026-07-31 sign-off. Revision 1.0.0 remains readable in version-control history and is the authority for what the product promised before this date.

Key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as in RFC 2119. MUST = release blocker. SHOULD = default requiring an explicit recorded exception. MAY = optional. Invariants are numbered `INV-*` and cited by later issues. **Invariant numbers are never reused or renumbered across revisions.** A retired invariant keeps its number and is marked retired, with its replacement named, so that older issues citing it resolve to an honest answer instead of a different rule.

---

## 0. Revision history and what changed in 2.0.0

### 0.1 Why this revision exists

Four owner decisions locked on 2026-08-01 invalidated the platform premise of revision 1.0.0. They are recorded here because every amendment below traces to one of them.

- **LD-1 — Browser MVP.** The MVP ships as a **browser application**, not a native mobile application. The core value of the product is restated as **vendoring**: acquiring, rights-clearing, normalizing, and serving automobile plus oil/filter data. Delivery shell is a means; the vendored data is the product.
- **LD-2 — Anonymous client-side storage.** User data (garage, service history, odometer readings, reminder intent) lives in **anonymous browser storage** (IndexedDB, with `localStorage` only for small non-personal preferences). There are **no accounts and no server-side personal records**. Export/import is the only portability escape hatch.
- **LD-3 — Hosting.** Phoenix LiveView hosted on **Fly.io**. Netlify (already paid, team `cDiscourse`) remains available for static marketing, support, privacy, and attribution content. The owner owns `digitaloilsticker.com` and `digitaloilsticker.net`.
- **LD-4 — Native mobile deferred, not deleted.** Mob 0.7.20 native packaging moves to post-MVP. Recorded reasons: Mob is pre-1.0; five distinct Windows-host defects were found in a single session; upstream has no Windows CI; and the iOS half is unreachable with no Mac and no Xcode, so the DOS-M00-003 go/no-go **cannot complete as written**. Physical-device evidence captured on a Motorola Razr Ultra 2025 is **retained**, not discarded, and is the starting evidence for any future native revival.

### 0.2 The architectural consequence this revision must not hand-wave

Phoenix LiveView keeps UI state on the **server**. LD-2 puts the user's data on the **client**. These two facts do not compose for free, and revision 1.0.0 contains no rule that covers the gap. Revision 2.0.0 therefore introduces an explicit, testable **hydration protocol** (INV-24) rather than leaving the seam to implementation taste: a JS hook reads IndexedDB on mount and pushes state into the LiveView; the server holds it only in socket assigns for the lifetime of that socket and never persists a personal row; every mutation round-trips back to IndexedDB through `pushEvent`. INV-24 also binds the six conditions that make or break such a design in the field — first paint before hydration completes, storage eviction, quota exhaustion, private-browsing mode, multi-tab consistency, and the user clearing storage.

Three 1.0.0 promises simply **cannot hold** in a plain browser application, and are amended rather than quietly reinterpreted:

1. **Bundled offline catalog (INV-6/INV-7).** There is no app bundle to ship a catalog inside. The MVP queries the catalog from the server. Service-worker/PWA offline is a *separate future decision* and is **not** promised by the MVP.
2. **OS local notifications (INV-17).** `mob_notify` and OS-scheduled local notifications are unavailable in a browser. The MVP uses **in-app due/overdue state only**. Web Push requires a service worker and a third-party push service, and is explicitly deferred — with the honest note that it would introduce remote infrastructure and therefore sits in tension with the no-remote-infrastructure stance this product otherwise holds.
3. **Loopback-only binding (INV-2).** There is no on-device embedded endpoint to bind to `127.0.0.1`. The invariant is retired and replaced by hosted-transport rules (INV-22).

### 0.3 Invariant-by-invariant disposition

Every 1.0.0 invariant appears in this table. Nothing is silently dropped.

| # | 1.0.0 subject | Disposition in 2.0.0 | Why (locked decision / reason) |
| --- | --- | --- | --- |
| INV-1 | Native iOS/Android only; browser is dev-only | **Amended** | LD-1, LD-4. Inverted: browser-first is the production promise; native is deferred with evidence retained. |
| INV-2 | Embedded endpoint binds `127.0.0.1` only | **Retired — replaced by INV-22** | LD-1/LD-3. No embedded on-device endpoint exists. Loopback-only was a property of the on-device shell; it is meaningless for a hosted app and would read as a false security claim. Replaced by hosted-transport rules (HTTPS/WSS, CSRF, CSP, no third-party trackers). |
| INV-3 | No online accounts, no server-side personal record | **Retained, restated** | Unaffected by LD-1; reinforced by LD-2. Now also the constraint that makes LiveView's server-side state a boundary problem (see INV-24). |
| INV-4 | No telemetry, no third-party analytics, personal data never leaves the device | **Retained, scope-adjusted** | Unaffected in principle. "Never leaves the device" is restated as "never leaves the browser", and the new catalog-query network surface is closed by INV-26. |
| INV-5 | No implied backup | **Retained, strengthened by INV-25** | Unaffected and now *more* load-bearing: browser storage is more easily lost than app-container storage. |
| INV-6 | Bundled catalog; all core flows work in airplane mode | **Amended** | LD-1. No bundle exists. Replaced by a server-queried catalog with defined honest degradation; offline is not promised. |
| INV-7 | Connectivity never required | **Amended** | LD-1. Connectivity **is** required to reach the app and to query the catalog. The surviving half — locally held user data must remain readable and the app must degrade honestly — is stated explicitly. |
| INV-8 | Market and rolling 30-model-year window | **Retained** | Data contract; delivery-shell independent. LD-1 elevates it (vendoring is the core value). |
| INV-9 | Vehicle classes included/excluded | **Retained** | As above. |
| INV-10 | "Major manufacturers" testable definition | **Retained** | As above. |
| INV-11 | Support statuses; missing data never guessed | **Retained** | As above. |
| INV-12 | Estimate-only; no telematics/OBD | **Retained, restated** | Unaffected. A browser has even less vehicle access than a native app; the promise is unchanged. |
| INV-13 | Earlier threshold wins | **Retained, restated** | Forecast arithmetic is unaffected by delivery shell. |
| INV-14 | Vehicle controls prevail | **Retained, restated** | Safety-adjacent; unaffected. |
| INV-15 | No fabricated automotive facts; provenance required | **Retained, restated** | Core to LD-1's vendoring thesis. Redistribution rights must now cover **serving over the network**, not only offline redistribution. |
| INV-16 | Requirements, not brand folklore | **Retained, restated** | Unaffected. |
| INV-17 | OS local notifications only | **Amended** | LD-1. `mob_notify` is unavailable in a browser. MVP is in-app due/overdue state only; Web Push explicitly deferred with its infrastructure conflict recorded. |
| INV-18 | One-vehicle MVP, multi-vehicle-safe internals | **Retained, with a non-substantive clarification** | Unaffected. Clarified only that the client-side container is named the *garage* and is multi-vehicle-safe from day one, while the MVP UI still exposes one active vehicle. |
| INV-19 | Prohibited scope for v1 | **Amended** | LD-1. "Browser/PWA product" must be removed — it is now the product. Replaced with a prohibited list appropriate to a hosted browser product. |
| INV-20 | Estimate/reminder framing, source and model-year context | **Retained, restated** | Safety-adjacent; unaffected. |
| INV-21 | Required terminology | **Retained, restated in full** | Unaffected. |

### 0.4 Invariants added in 2.0.0

| # | Subject | Introduced because |
| --- | --- | --- |
| INV-22 | Hosted transport security (HTTPS/WSS, CSRF, CSP, no third-party trackers) | Replaces retired INV-2 for a hosted app (LD-3). |
| INV-23 | Anonymous client-side storage is the only home for personal data | LD-2. |
| INV-24 | LiveView hydration protocol and the server-state boundary | The LD-2 × LiveView consequence in §0.2. |
| INV-25 | Honest storage-loss messaging | LD-2; extends INV-5 to browser-specific loss conditions. |
| INV-26 | Impersonal catalog-query surface | LD-1/LD-2 create a network path that did not exist on-device; closes it. |
| INV-27 | Domain and static-content boundary (Fly.io app vs. Netlify static) | LD-3. |

### 0.5 Change-control obligations created by ratifying 2.0.0

Per [CHANGE_CONTROL.md](../governance/CHANGE_CONTROL.md) Rule 2a, the architecture changes ratified here require Architecture Decision Records before dependent implementation issues may be marked Ready. Ratification of this constitution does **not** by itself satisfy that rule.

- `ADR-0001-mob-liveview-on-device.md` MUST be moved to **superseded (deferred, evidence retained)** with the LD-4 reasons and the Motorola Razr Ultra 2025 evidence pointer recorded in it.
- `ADR-0002-netlify-static-boundary.md` MUST be updated for INV-27 (Netlify is now the *static* half of a two-origin product, not the static half of a native product).
- A new ADR MUST record browser delivery and hosted Phoenix LiveView on Fly.io (INV-1, INV-22, INV-27).
- A new ADR MUST record anonymous client-side storage and the hydration protocol (INV-23, INV-24, INV-25).
- Web Push, service-worker/PWA offline, and native-mobile revival are each recorded as **open deferred decisions**; none may be implied by MVP copy (INV-19).

---

## 1. Platform promise

- **INV-1 (MUST):** Production MVP ships as a **hosted browser application** built with Elixir and Phoenix LiveView, served over the public internet from Fly.io at an owner-controlled domain. Modern evergreen browsers on desktop and mobile are the production target. Native-packaged iOS and Android applications are **deferred to post-MVP** — deferred, not deleted (LD-4): the recorded reasons are that Mob 0.7.20 is pre-1.0, that five distinct Windows-host defects were found in a single session, that upstream carries no Windows CI, and that the iOS half is unreachable without a Mac and Xcode, so the DOS-M00-003 go/no-go cannot complete as written. Physical-device evidence captured on a Motorola Razr Ultra 2025 MUST be retained as the starting evidence for any future native revival. Reviving native requires a new ratified constitution revision, not a ticket.
- **INV-2 (RETIRED in 2.0.0 — replaced by INV-22):** In revision 1.0.0 this required the embedded Phoenix endpoint to bind only to `127.0.0.1`. That rule described a property of the **on-device shell**, which no longer exists. It is retired rather than reinterpreted, because restating a loopback promise for a publicly hosted app would be a false security claim. Its protective intent — that the endpoint is not casually reachable and that personal data is not exposed in transit — is carried forward by **INV-22 (hosted transport security)**, **INV-23 (client-only personal data)**, and **INV-26 (impersonal query surface)**. Issues that cite INV-2 MUST be re-pointed at those invariants during the re-plan.
- **INV-22 (MUST):** Hosted transport security replaces loopback binding. All application traffic MUST be served over HTTPS with HSTS; the LiveView socket MUST use WSS. CSRF protection MUST be enabled for the LiveView session and for every non-idempotent HTTP endpoint. A Content-Security-Policy MUST be served that forbids third-party script and connect origins. There MUST be no third-party analytics, tag managers, advertising pixels, session recorders, CDN-hosted fonts or scripts, or any other cross-origin beacon on any page of the application (this is INV-4 expressed at the transport layer). Cookies are limited to what the framework requires for session and CSRF; they MUST NOT carry personal data and MUST be `Secure`, `HttpOnly` where applicable, and `SameSite`-restricted.

## 2. No online accounts; anonymous client-side storage

- **INV-3 (MUST):** There is no registration, login, remote profile, identity provider, password reset, cloud synchronization, server-side personal record, or analytics identifier tied to a person. A **local profile** is a set of records held in one browser on one device, not an authenticated identity. Nothing in the hosted architecture may introduce a durable server-side identifier that could reconstitute a person across sessions.
- **INV-4 (MUST):** No telemetry or third-party analytics by default. Any diagnostic export is opt-in, local, reviewable, and redacted. Personal data (VIN, mileage, notes, vehicle identifiers, service history) MUST NOT leave the browser except through a user-initiated export file, and MUST NOT appear in server logs, error reports, crash traces, or fixtures. Server-side logging MUST be structured so that no request path, parameter, or assign snapshot containing personal data is written to disk or to any log sink.
- **INV-5 (MUST):** No interface may imply a local profile is backed up or recoverable unless an explicit export/import feature has shipped. Export/import is the sole portability escape hatch and is an MVP requirement, not a nicety (LD-2). Words like "saved", "synced", "your account", or "restore" MUST NOT appear in a way that implies remote durability.
- **INV-23 (MUST):** **Anonymous client-side storage is the only home for personal data.** The garage, service history, odometer readings, and reminder intent live in the browser's IndexedDB for the application origin; `localStorage` MAY hold only small non-personal preferences (units, time-zone choice, dismissed-notice flags). The server MUST NOT create, write, or read any personal row in any database, and the product MUST NOT ship a personal-data table, personal-data migration, or personal-data backup job. There is no user identifier, device identifier, or storage key that is transmitted to or derivable by the server.
- **INV-24 (MUST):** **Hydration protocol and the server-state boundary.** Phoenix LiveView holds UI state on the server; this product holds user data on the client. That seam MUST be implemented as a specified protocol, not left to implementation taste.
  - **INV-24.1 (MUST):** On mount, a JS hook reads the user's records from IndexedDB and pushes them to the LiveView. The server holds them **only in socket assigns, for the lifetime of that socket**, and MUST NOT persist, cache, replicate, or forward them. Socket termination discards them. A server restart or a Fly.io machine replacement MUST NOT lose user data, because the server was never the system of record.
  - **INV-24.2 (MUST):** Every mutation writes back to IndexedDB through a `pushEvent` → hook round trip. A mutation is not considered committed — and MUST NOT be rendered as committed — until the hook confirms the client write. Optimistic UI MAY be used only if a failed client write visibly reverts the change and reports it.
  - **INV-24.3 (MUST):** **First paint before hydration completes.** The static render and the pre-hydration live render MUST show a neutral loading/empty state that is honest about not yet knowing whether data exists. The UI MUST NOT flash "no vehicles yet", "welcome, let's add your first vehicle", or any other empty-garage claim before hydration resolves; a user with a full garage must never be told, even for one frame, that their garage is empty. Hydration MUST either resolve or surface an explicit failure state; it MUST NOT hang silently.
  - **INV-24.4 (MUST):** **Storage eviction.** Browsers may evict origin storage under pressure. The product MUST request persistent storage where the API is available, MUST NOT assume the request is granted, and MUST detect an evicted/empty store on hydration and present it as the storage-loss state defined by INV-25 rather than as a fresh install.
  - **INV-24.5 (MUST):** **Quota.** Writes MUST handle quota-exceeded errors explicitly: the failure is surfaced to the user in plain language, the prior state is preserved, and the user is offered export. Silent write failure is a release blocker. The measurable storage budget is in §9.
  - **INV-24.6 (MUST):** **Private-browsing and blocked storage.** Where IndexedDB is unavailable, restricted, or discarded at session end (private/incognito modes, hardened privacy settings, embedded webviews), the app MUST detect this on mount and tell the user before they enter data that anything they record will be lost when the window closes. It MUST NOT silently degrade to in-memory state that looks durable.
  - **INV-24.7 (MUST):** **Multi-tab consistency.** Two tabs on the same origin share one IndexedDB but hold two independent LiveView sockets with two independent copies in assigns. The product MUST define and implement a single-writer or last-write-wins-with-notification discipline (for example via `BroadcastChannel` or storage-change events) such that a mutation in one tab is reflected in the other, and MUST NOT allow a stale tab to overwrite newer records without the user being told. Concurrent-tab behavior is a required test case, not an edge case.
  - **INV-24.8 (MUST):** **User clears storage.** If the browser clears site data, **the data is gone.** There is no server copy and no recovery path. The UI MUST NOT imply otherwise (INV-5) and MUST present the honest loss message defined by INV-25.
- **INV-25 (MUST):** **Honest storage-loss messaging.** At a minimum, onboarding and the export surface MUST state, in plain language, that records live only in this browser on this device; that clearing site data, browser storage eviction, private-browsing sessions, uninstalling or resetting the browser, or switching devices will lose them; that there is no account and no server copy; and that export is the only way to keep or move them. This messaging MUST be reachable at any time, not only at first visit, and MUST NOT be softened into implied durability. A detected empty-or-evicted store MUST be distinguishable in copy from a genuine first visit.
- **INV-26 (MUST):** **The catalog-query surface is impersonal.** Catalog requests (identity, schedules, oil requirements, filter fitment, product claims) MUST NOT carry a VIN, an odometer reading, a note, a free-text field, a record identifier, or any stable client identifier, in the path, query string, body, headers, or socket payload. Queries carry only the impersonal selectors needed to resolve a vehicle configuration. The server MUST NOT be able to reconstruct a user's garage from its request stream. This invariant exists because the browser architecture creates a network path that the 1.0.0 on-device architecture did not have.
- **INV-27 (MUST):** **Domain and static-content boundary.** The interactive application is served from the Fly.io-hosted Phoenix LiveView origin on an owner-controlled domain (`digitaloilsticker.com`, with `digitaloilsticker.net` reserved and redirected). Static marketing, support, privacy, and source-attribution content MAY be served from the existing paid Netlify account (team `cDiscourse`). Static content MUST NOT collect personal data, MUST NOT carry trackers or third-party scripts (INV-4, INV-22), MUST NOT imply an account exists, and MUST NOT restate automotive facts that lack a provenance record (INV-15). Attribution required by any data license MUST be published on this boundary and MUST stay in sync with `SOURCE_REGISTER.md`.

## 3. Data availability and connectivity (replaces "offline-first")

- **INV-6 (MUST — amended):** The bundled-catalog-at-first-launch promise of 1.0.0 **does not hold** for a browser application and is not restated in a weaker form. What replaces it: the vehicle catalog is **queried from the server** over the LiveView socket or HTTP; the client stores only the user's own records plus whatever the browser incidentally caches. The MVP therefore requires connectivity to select a vehicle, to resolve schedules and oil requirements, and to render source attribution. Service-worker or PWA offline caching is an **explicitly separate future decision** and MUST NOT be promised, implied, or partially shipped by the MVP.
- **INV-7 (MUST — amended):** Because connectivity is now required, the product owes honesty about its absence instead of independence from it. When the socket is down or a catalog query fails, the app MUST show an explicit connection state, MUST NOT present a stale or partial catalog result as authoritative, and MUST NOT fabricate a fallback interval (INV-15). The user's own locally held records MUST remain readable to the extent the client can render them without a catalog round trip, and no queued or pending mutation may be silently dropped on reconnect. LiveView reconnect MUST re-run the INV-24 hydration path rather than assume surviving server-side assigns.

## 4. Coverage contract (ratifies the §5 planning default)

- **INV-8 (MUST):** Market: United States. Rolling window: last 30 model years — for the 2026 baseline, 1997–2026 inclusive; the window advances with each yearly catalog refresh decision.
- **INV-9 (MUST):** Vehicle classes: passenger cars, multipurpose passenger vehicles, and light pickups/vans that use engine oil. Gasoline, diesel, and hybrid configurations are included when a licensed source supports them. Battery-electric vehicles MAY appear for honest identification and show "engine oil service not applicable"; an oil plan is never invented. Heavy commercial, motorcycles, powersports, off-highway, and non-U.S. schedules are excluded from the MVP.
- **INV-10 (MUST):** "Major manufacturers" means: makes present in the NHTSA vPIC identity spine for the rolling window, ranked by U.S. light-duty registration presence, with the testable definition and measured coverage ratified by the coverage-definition and catalog-baseline issues (DOS-M00-006 and DOS-M03-001 under the 1.0.0 plan; IDs may be re-scoped). The definition is re-examined at each catalog refresh (update cadence: with every catalog `data_version` release). Trim/build completeness depends on authoritative source coverage and cannot be inferred.
- **INV-11 (MUST):** Catalog presence and recommendation support are separate statuses: `identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, `unsupported`. Missing data is shown as unknown or unsupported — never guessed.

## 5. Core user promise

- **INV-12 (MUST):** The app estimates when an oil change may be due from recorded mileage, elapsed time, manufacturer guidance when available, product guidance when licensed/verified, and user-entered driving samples. It does **not** read the odometer, connect to the vehicle, or diagnose anything (**no telematics, no OBD**). A browser application has no vehicle access whatsoever, and no future connectivity feature may change this promise without a new ratified revision.
- **INV-13 (MUST):** Earlier threshold wins: a plan is due at the earlier of its sourced calendar threshold and projected mileage threshold. The prediction MAY warn earlier; it MUST NOT extend the OEM interval.
- **INV-14 (MUST):** Vehicle controls prevail: for vehicles with an oil-life monitor or condition-based maintenance, the app labels its date as an estimate and directs the user to follow the vehicle indicator and owner documentation when they disagree.
- **INV-15 (MUST):** No fabricated automotive facts. Every displayed interval, viscosity/specification, capacity, oil-product claim, and filter fitment has provenance and a license permitting the distribution the product actually performs. **Amended emphasis for 2.0.0:** the required right is now a license permitting **serving the data over a network from a hosted service**, which is not automatically implied by a right to redistribute inside an installed application bundle. Any source cleared under 1.0.0 for offline bundle redistribution MUST be re-reviewed against the hosted-serving use before it ships (CHANGE_CONTROL Rule 2b).
- **INV-16 (MUST):** Requirements, not brand folklore: oil compatibility is the intersection of vehicle requirements and a specific product/SKU's published claims; a brand name or viscosity alone never proves compatibility. Filter compatibility is part-number/configuration-specific.

## 6. Reminders and notifications

- **INV-17 (MUST — amended):** OS-scheduled **local** notifications (`mob_notify`) are unavailable in a browser and are no longer part of the MVP. The MVP uses **in-app due/overdue state only**: due status is computed on load and while the app is open, and the UI MUST state plainly that the app does not notify the user when it is closed. The product MUST NOT imply background alerting of any kind. **Web Push is an explicitly deferred post-MVP decision**, and the deferral records its cost honestly: Web Push requires a service worker and a third-party push service (APNs/FCM via the browser vendor's endpoint), which introduces remote infrastructure and a per-browser subscription endpoint, and therefore sits in tension with the no-remote-infrastructure and no-durable-identifier stance of INV-3, INV-4, and INV-23. Adopting it requires an ADR and a new constitution revision, not a ticket. OS local notifications return to scope only if native mobile is revived under INV-1.

## 7. Vehicles and scope shape

- **INV-18 (MUST):** One-vehicle MVP, multi-vehicle-safe internals: the first releasable slice exposes one active vehicle, but IDs, tables, events, stored object shapes, and reminder identifiers safely support many vehicles. *Clarification (non-substantive, 2.0.0):* the client-side container holding the user's vehicles is named the **garage** and is multi-vehicle-safe from the first write, so that multi-vehicle UI is a presentation change and never a data migration. Multi-vehicle UI remains post-MVP.
- **INV-19 (MUST — amended):** Prohibited scope for the MVP (post-MVP or never, per [SCOPE.md](SCOPE.md)). "Browser/PWA product" is **removed** from this list — it is now the product (LD-1). The list appropriate to a hosted browser product is:
  - remote accounts, login, or any hidden server-side storage of personal records;
  - cloud sync, shared garages, or any cross-device continuity other than user-initiated export/import;
  - server-side user identifiers, fingerprinting, or any durable client identifier readable by the server;
  - telemetry, third-party analytics, advertising pixels, session recording, or any cross-origin beacon;
  - Web Push, service workers used for push, and background sync (deferred, INV-17);
  - service-worker/PWA offline caching and any offline promise (deferred, INV-6);
  - native mobile packaging and app-store distribution (deferred, INV-1);
  - telematics/OBD integration, shop booking, commerce, ads, and social features;
  - predictive maintenance beyond oil changes; fleet administration;
  - guaranteed notification delivery of any kind;
  - user-generated content that is published, shared, or transmitted off the device.

  A deferred item MUST NOT be implied by MVP copy, marketing content, or a disabled-but-visible control.

## 8. Safety-adjacent copy (ratifies §6 terminology)

- **INV-20 (MUST):** Results are called an "estimate" or "reminder", preserve source and effective model-year context, and direct the user to the owner's manual or a qualified service provider when data is missing or conflicting.
- **INV-21 (MUST):** Required terminology: "Meets the recorded requirements" (never "manufacturer approved" unless the source documents an OEM approval); "Estimated due date" with a confidence label; "Source unavailable" / "Exact configuration not verified" rather than a generic value. Oil-life monitor, calendar interval, mileage interval, normal service, and severe service stay distinct terms. **Added for 2.0.0:** "Stored in this browser" is the required framing for user data; "saved to your account", "synced", "backed up", and "restore" MUST NOT be used (INV-5, INV-25).

## 9. Measurable targets

Values marked *provisional* stand until measurement on the deployed Fly.io environment supplies real numbers; revision then happens by explicit re-ratification, never a silent edit. A row without an owner fails review. The 1.0.0 rows for cold tap-to-interactive, warm start, on-device Phoenix readiness, packaged app size, bundled catalog size, minimum supported OS, and airplane-mode offline readiness are **removed** — each measured a property of the native on-device shell that no longer exists (INV-1, INV-6). Accessibility and user-data growth carry forward with their original ratification recorded alongside their 2.0.0 re-ratification.

| Target | Value | Owner | Ratified | Verified by |
| --- | --- | --- | --- | --- |
| Page load — LCP | *provisional* p75 ≤ 2.5 s on a 4G-class connection, mid-tier mobile device; no run > 4.0 s | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Page load — TTI / first interaction ready | *provisional* p75 ≤ 3.5 s; interactive controls MUST NOT accept input before hydration state is known (INV-24.3) | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| LiveView WebSocket connect | *provisional* static-to-live transition p95 ≤ 1.0 s after HTML paint; automatic reconnect p95 ≤ 2.0 s, re-running hydration (INV-7) | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Hydration completion | *provisional* IndexedDB read → `pushEvent` → assigns populated, p95 ≤ 300 ms after socket join; honest loading state until then | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Server response p95 | *provisional* HTTP TTFB p95 ≤ 400 ms; LiveView event round trip p95 ≤ 150 ms, measured from the client | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Catalog query p95 | *provisional* first paged catalog result p95 ≤ 250 ms server-side; subsequent filter p95 ≤ 150 ms; write + forecast recompute p95 ≤ 150 ms | kyleruff1 (Eng) | 2026-08-01 | Data Acquisition & Catalog (Vendoring) |
| First-visit payload budget | *provisional* initial HTML + CSS + JS ≤ 250 KiB compressed; total first-visit transfer ≤ 500 KiB; **zero** third-party origins (INV-22) | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Repeat-visit payload budget | *provisional* ≤ 60 KiB compressed on a warm HTTP cache, excluding catalog query results | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Client storage footprint | ≤ 1 MiB per 1,000 text-only records; total origin footprint held under a 5 MiB working ceiling, well below typical origin quota; quota-exceeded handled visibly (INV-24.5) | kyleruff1 (Data) | rc1 2026-07-31, re-ratified 2026-08-01 | Browser Delivery & Hosted Transport |
| Browser support matrix | *provisional* current and prior stable release of Chrome, Edge, Firefox, and Safari (desktop), plus iOS Safari 16+ and Android Chrome; IndexedDB availability probed at runtime (INV-24.6) | kyleruff1 (Eng) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Multi-tab consistency | two-tab mutation test passes with no silent stale overwrite (INV-24.7) | kyleruff1 (QA) | 2026-08-01 | Browser Delivery & Hosted Transport |
| Privacy on the wire | 24 h idle capture shows zero outbound requests beyond the application origin; no request carries a personal field (INV-4, INV-26) | kyleruff1 (QA) | rc1 2026-07-31, re-ratified 2026-08-01 | Browser Delivery & Hosted Transport |
| Accessibility | WCAG 2.2 AA where applicable: text contrast ≥ 4.5:1 (UI components and graphical objects ≥ 3:1); usable at 200% zoom and at 320 CSS px reflow width with no loss of content or function; **full keyboard operability with a visible focus indicator and no keyboard traps**; target size ≥ 24×24 CSS px (≥ 44×44 SHOULD where touch is primary); full screen-reader operability including live-region announcement of due-state and hydration changes | kyleruff1 (Design) | rc1 2026-07-31, re-ratified 2026-08-01 | UX & Content Contract |
| Honest-degradation coverage | every INV-7, INV-24.3–24.8, and INV-25 state has a specified screen and an automated or scripted test | kyleruff1 (QA) | 2026-08-01 | UX & Content Contract |

## 10. Traceability table (invariant → verification milestone)

Milestones are referred to **by name** because the 2.0.0 re-plan re-scopes the issue set: existing `DOS-Mnn-nnn` identifiers MUST be treated as indicative only and MAY be renumbered, split, or retired during the re-plan. Data invariants continue to map to the data milestone (M03), UX and content invariants to the UX milestone (M02), and hosting, transport, and client-storage invariants to a **new browser milestone**.

| Invariant | Verified by (milestone name) |
| --- | --- |
| INV-1 platform (browser-first, native deferred) | **Browser Delivery & Hosted Transport** · release gate in Hardening & Release |
| INV-2 *(retired)* | n/a — verification obligation transfers to INV-22, INV-23, INV-26 |
| INV-3 no accounts / no server-side personal record | **Browser Delivery & Hosted Transport** (schema + code audit: no personal table exists) · **UX & Content Contract** |
| INV-4 no telemetry / no exfiltration | **Browser Delivery & Hosted Transport** (idle-traffic capture, log audit, CSP report review) |
| INV-5 no implied backup | **UX & Content Contract** · export/import slice in the Single-Vehicle MVP milestone |
| INV-6 catalog availability (server-queried) | **Data Acquisition & Catalog (Vendoring)** · **Browser Delivery & Hosted Transport** |
| INV-7 honest degradation without connectivity | **Browser Delivery & Hosted Transport** (socket-down and query-failure states) · **UX & Content Contract** |
| INV-8/9 coverage window & classes | **Data Acquisition & Catalog (Vendoring)** |
| INV-10 major manufacturers | **Data Acquisition & Catalog (Vendoring)** |
| INV-11 support statuses | **Data Acquisition & Catalog (Vendoring)** · **UX & Content Contract** |
| INV-12 estimate-only promise | **UX & Content Contract** · Forecasting milestone |
| INV-13 earlier threshold wins | Forecasting milestone (property tests) |
| INV-14 vehicle controls prevail | Forecasting milestone · **UX & Content Contract** |
| INV-15 provenance, incl. hosted-serving rights | **Data Acquisition & Catalog (Vendoring)** (source-rights re-review per CHANGE_CONTROL 2b) |
| INV-16 requirements not folklore | **Data Acquisition & Catalog (Vendoring)** · **UX & Content Contract** |
| INV-17 in-app due state only; push deferred | **UX & Content Contract** · Forecasting milestone |
| INV-18 multi-vehicle-safe internals (garage) | Client domain & persistence milestone · post-MVP multi-vehicle milestone |
| INV-19 prohibited scope | every milestone exit gate · Hardening & Release (threat model) |
| INV-20/21 safety copy & terminology | **UX & Content Contract** · Hardening & Release |
| INV-22 hosted transport security | **Browser Delivery & Hosted Transport** (TLS/HSTS/CSP/CSRF checks, third-party-origin scan) |
| INV-23 client-side storage is the only home | **Browser Delivery & Hosted Transport** · client domain & persistence milestone |
| INV-24 hydration protocol (all sub-clauses) | **Browser Delivery & Hosted Transport** (protocol conformance) · **UX & Content Contract** (24.3 empty-state copy) |
| INV-25 honest storage-loss messaging | **UX & Content Contract** |
| INV-26 impersonal catalog-query surface | **Browser Delivery & Hosted Transport** (request-payload audit) · **Data Acquisition & Catalog (Vendoring)** |
| INV-27 domain & static-content boundary | **Browser Delivery & Hosted Transport** · Hardening & Release |

## 11. Tabletop review record (three required scenarios)

1. **First visit, no data yet.** A person opens `digitaloilsticker.com` for the first time. Expected: HTTPS page loads and paints a neutral loading state; the LiveView socket connects over WSS; the hydration hook probes IndexedDB, finds nothing, and reports an empty store — and only *then* does the UI present the genuine first-visit onboarding (INV-24.3). Onboarding states that records will live in this browser only, that there is no account, and that export is the only way to keep or move them (INV-3, INV-25). Unit and time-zone choice is offered. Year → make → model selection queries the catalog from the server, carrying only impersonal selectors (INV-26); the schedule and oil requirements render with source attribution or an explicit `unsupported` / `identity_only` state (INV-11, INV-15). An oil change can be recorded; the write round-trips to IndexedDB and is not shown as committed until the client write confirms (INV-24.2). A due date is computed and labeled an estimate (INV-13, INV-20). No permission prompt appears before value is clear, and no third-party origin is contacted at any point (INV-22). If the browser is in private-browsing mode or IndexedDB is blocked, the user is told *before* entering data that nothing will persist (INV-24.6).
2. **The user clears browser storage, or switches to a different device.** Expected: the data is **gone**, and the product says so. On the next visit, hydration finds an empty or evicted store; because this is distinguishable from a genuine first visit, the UI presents the storage-loss message rather than a cheerful welcome (INV-24.4, INV-24.8, INV-25). There is no server copy, no account to sign into, and no recovery link — and none was ever implied (INV-3, INV-5). On a *different* device the situation is identical: the second browser is simply a different, empty origin store; the product never presents cross-device continuity it does not have (INV-19). With an export file taken beforehand, import on the new browser restores the garage, service history, and reminder intent into that browser's IndexedDB; reminder state is recomputed locally as in-app due/overdue status, not restored from any server and not registered with any push service (INV-17, INV-23). The honest framing throughout is "stored in this browser", never "restored to your account" (INV-21).
3. **Missing maintenance data for an otherwise selectable vehicle.** Expected: the vehicle is selectable as `identity_only` (INV-11); the schedule area states "Source unavailable" and, where the trim or engine could not be resolved, "Exact configuration not verified" (INV-21); the user may enter their owner's-manual interval manually, clearly labeled as user-entered, and due calculation works from it, stored client-side like any other personal record (INV-12, INV-20, INV-23); no generic default interval is fabricated to fill the gap, and no oil or filter product is presented as compatible on brand or viscosity alone (INV-15, INV-16). If the gap is caused by the catalog query failing rather than by genuinely absent data, the two cases are visually distinct: a connection problem is shown as a connection problem, never as "no data for this vehicle" (INV-7).

## 12. Sign-off

One unchanged revision is reviewed by the representatives below; ratification of revision 2.0.0 is recorded on issue [#2](https://github.com/kyleruff1/digital-oil-sticker/issues/2). This is a solo-founder project: one person may hold multiple roles, but each role's review is recorded explicitly. The 1.0.0 sign-off dated 2026-07-31 is **not** carried forward and does not attach to this text.

| Role | Representative | Status |
| --- | --- | --- |
| Product | kyleruff1 | ratified 2026-08-01 (revision 2.0.0) |
| Engineering | kyleruff1 | ratified 2026-08-01 (revision 2.0.0) |
| Design | kyleruff1 | ratified 2026-08-01 (revision 2.0.0) |
| Data | kyleruff1 | ratified 2026-08-01 (revision 2.0.0) |
| QA | kyleruff1 | ratified 2026-08-01 (revision 2.0.0) |

Ratification was recorded by the owner in the working session of 2026-08-01, superseding revision 1.0.0 (ratified 2026-07-31). Provisional targets in §9 carry their own ratification dates and re-ratify on measurement against the deployed environment. The ADRs required by §0.5 are obligations created by this ratification and remain outstanding until written and accepted.
