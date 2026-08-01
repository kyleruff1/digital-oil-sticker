# ADR-0004 — Browser-first client, anonymous client-side personal data, hosted Phoenix on Fly.io

**Status:** Accepted — 2026-08-01 (owner decision, all roles) · **Supersedes for MVP:** [ADR-0001](ADR-0001-mob-liveview-on-device.md) · **Amends:** [ADR-0002](ADR-0002-netlify-static-boundary.md) · **Preserves:** [ADR-0003](ADR-0003-data-boundaries.md) unchanged · **Evidence:** [`spikes/m00-003-mob-device/README.md`](../../spikes/m00-003-mob-device/README.md) · **Cites:** INV-3, INV-4, INV-5, INV-11, INV-12, INV-13, INV-15, INV-16, INV-20, INV-21 ([CONSTITUTION.md](../product/CONSTITUTION.md)) · **Conflicts with and requires re-ratification of:** INV-1, INV-2, INV-6, INV-7, INV-17, INV-19

---

## Context

### The product's value is the data, and the data is platform-independent

Digital Oil Sticker's defensible core is **vendoring**: acquiring automobile and oil/filter data, clearing its rights, normalizing it with provenance, and serving it honestly. [ADR-0003](ADR-0003-data-boundaries.md) established that this is hard and that it is the real work — vPIC supplies identity only (144 decode variables, **zero** oil-interval, viscosity, capacity, oil-product, or filter-fitment fields), while every maintenance fact needs its own licensed source, confidence tier, and conflict policy.

None of that work is native-mobile-specific. The catalog, the resolver, the confidence tiers, and the forecast arithmetic are Elixir domain code. The client is a rendering choice. Holding the entire data program hostage to a client-platform gate is a sequencing error.

### The native gate cannot complete as written

DOS-M00-003 is the go/no-go gate that [ADR-0001](ADR-0001-mob-liveview-on-device.md) made a precondition for all feature work. It cannot pass, for reasons that are not about effort:

**The iOS half is unreachable.** No Mac and no Xcode. The spike log records this as a blocking constraint from the outset. ADR-0001 §7 requires proof "end-to-end on physical iOS **and** Android devices". Half of that proof cannot be attempted at all, so the gate cannot resolve either way.

**The Android half exposed five distinct Windows-host defects in a single session** (`mob_dev` 0.6.23, Mob 0.7.20, `mob_new` 0.4.20). Four are numbered in the spike log, and a fifth is documented in its containment section:

1. `MobDev.OtpDownloader` joins a backslash `System.user_home!()` with forward-slash segments; `Path.wildcard/1` treats `\` as a glob escape, so `verify_erts/1` reports "OTP extraction produced no erts-* directory" **even when extraction succeeded**. (Blocking; `MOB_CACHE_DIR` with forward slashes is the only escape hatch.)
2. An undocumented `zig 0.15.x` requirement — Mob 0.7+ compiles the Android JNI layer with `build.zig` and the CMake fallback is dead (`mob_nif.c` no longer ships), yet zig appears in no prerequisite list.
3. `MobDev.NdkVersion.host/0` raises `unsupported host for NDK: {:win32, :nt}` although NDK 27.2.12479018 ships a `windows-x86_64` prebuilt toolchain. (Blocking; fixed locally with a one-clause `deps/` patch that any `mix deps.get` erases.)
4. `mix mob.install` writes `sdk.dir=C:\Users\...` into `local.properties`, where Java treats `\` as an escape character, surfacing as a misleading Kotlin `BuildFlowService` isolation error. (Blocking.)
5. The Android build path assumes ambient POSIX utilities: `gradle_assemble/0` invokes `System.cmd("bash", [gradlew, …])` while the generated project ships **no `gradlew.bat`**, and `ensure_jni_libs/2` and `push_otp_runas/5` shell out to `cp`. The build succeeded **only** because it ran from a Git-Bash/MSYS shell; from PowerShell or cmd these raise `:enoent`.

Further latent hazards found by static review: the host tag is triplicated across `ndk_version.ex`, `native_build.ex:941`, and `tflite_nif.ex:294`, and the latter two **silently fall back to `darwin-x86_64` on Windows** rather than failing loudly; `OtpDownloader.cache_dir/1` joins an unset `HOME` on native Windows; and `clear_stale_gradle_locks/0` globs a backslash path, so the Gradle-daemon lock cleanup it exists to perform never runs.

**Upstream has no Windows support and no Windows CI.** The hexdocs claim that Linux and Windows "deploy Android only" is not backed by code; both upstream repos test `ubuntu-latest` + `macos-15` only, and no Windows/WSL issue exists in either repo. Mob is pre-1.0 (0.7.20).

**What the physical-device work actually produced, and what it did not.** It produced a successful Windows-host Android debug build — `BUILD SUCCESSFUL in 2m 14s`, `app-debug.apk` at 77,264,396 bytes (73.7 MiB, universal/all-ABI) — with the Motorola Razr Ultra 2025 wired up for wireless adb over Tailscale (`ADB_MDNS_OPENSCREEN=0` required). It then **installed and launched on that physical device**: streamed install succeeded in 5.7 s over the tailnet, the native bridge initialized (`MobNIF: MobBridge cached OK`), the OTP release plus 1,115 BEAM files were pushed, the **embedded BEAM booted**, and **Phoenix served HTTP requests on device loopback** (Bandit 1.12.4 in-process). It confirmed the docs' runtime-decoupling claim (device `erts-17.0` prebuilt, independent of the host's OTP 28.4) and showed graceful degradation when EPMD was unreachable (`skipping dist` rather than crashing).

It did **not** complete the LiveView render on device — a `mob_new` generator defect (`code_reloader: true` emitted without the required `live_reload:` block) crashes `Phoenix.LiveReloader` on every request with `Access.get(false, :patterns, nil)`, and that config is baked at native-build time. Nor did it complete the lifecycle/safe-area matrix, the release-signed build, or **any** iOS work. So the reachable half of the gate is substantially proven at the runtime level but unproven at the level ADR-0001 §7 demands, and the iOS half is untouched.

This is a stack-and-host risk profile, not a defect count to grind down. The correct response is to stop paying for it now and keep the option.

### A browser client validates the data product immediately

A hosted Phoenix LiveView application ships from a URL: no store review, no signing identity, no Mac, no pre-1.0 native framework, no build host that requires Git Bash and a disposable `deps/` patch. Real users can exercise real catalog data this week. The Elixir domain contexts written for it are the same contexts a future native client would reuse.

### The honest cost of that choice

Phoenix LiveView keeps UI state **on the server**, in the socket process. The owner has chosen **client-side anonymous storage** for all personal data. These two facts are in direct tension and the tension is not hand-wavable: it forces an explicit hydration protocol, specified in full below. Getting this wrong produces either a silent server-side personal record (breaking the product's core promise) or a UI that loses the user's garage on every reconnect.

---

## Decision

1. **The MVP is a browser application.** A Phoenix LiveView application, hosted on **Fly.io**, served at **digitaloilsticker.com**. Not a native package. Not a PWA (see §"Consequences").

2. **The catalog is served from the server.** Vehicle identity, intervals, oil requirements, filter fitments, confidence tiers, and support statuses are queried server-side from a read-only catalog database and rendered through LiveView. [ADR-0003](ADR-0003-data-boundaries.md) is unchanged in full: provenance, confidence tiers, `identity_only`/`schedule_supported`/`full_product_supported`/`not_applicable`/`unsupported`, conflict handling, and the three-layer separation (raw source → normalized catalog → user overrides) all still bind. Nothing is fabricated; unknown stays unknown.

3. **All personal data lives in anonymous browser storage.** Garage (vehicles), service history, odometer readings, reminder intent, and preferences are held in **IndexedDB** in the user's browser. There are no accounts, no login, no identity provider, no cloud sync, and **no server-side personal record of any kind** — INV-3 is preserved, not weakened, by this pivot.

4. **The server persists NO personal rows.** The deployed application has exactly one Ecto repo, `DigitalOilSticker.CatalogRepo`, opened **read-only**. There is no `UserRepo` in the deployment. Personal data exists on the server only as transient values in `socket.assigns` for the lifetime of one LiveView connection, and is never written to disk, database, cache, ETS table, external store, or log.

5. **Export/import is the portability and recovery path.** A single versioned JSON file, produced and consumed entirely client-side. It is the *only* recovery mechanism, and the UI says so plainly (INV-5 still binds and is now more load-bearing than it was on-device).

6. **Domain contexts are client-agnostic on purpose.** `DigitalOilSticker.Catalog`, `.Garage`, `.Forecast`, and the resolver are plain Elixir with no dependency on `Phoenix.LiveView`, on the browser-storage protocol, or on any transport. The LiveView is one client over that contract. A future native client is a second client over the same contract, differing only in its storage adapter. **Native mobile is deferred, not deleted, and the domain work is not wasted.** This is enforced mechanically, not by intent — see §"Enforcement".

7. **Native mobile (Mob 0.7.20) is deferred to post-MVP** with explicitly recorded revival triggers (§"Trigger conditions that revive the native track"). The spike evidence, pinned toolchain matrix, defect analysis, and the WSL2 containment recommendation are all retained for that revival.

---

## The client-storage + LiveView hydration protocol

This section is normative. "The hook" means a `phx-hook` JavaScript hook named `LocalStore`, mounted on the application shell element.

### Why a protocol is required at all

LiveView renders from `socket.assigns` on the server. The server has no personal data and must never acquire any durably. Therefore every LiveView mount begins with an **empty** server-side view of the user's world and must be filled from the client. Because LiveView remounts on every reconnect — network blip, deploy, sleep/wake, tab restore — hydration is a **per-mount** operation, not a per-session one. It must be idempotent, cheap, and visually non-destructive.

### Storage layout

Origin-scoped IndexedDB database `dos_local`, opened at a monotonic IDB version. Object stores:

| Store | Key | Contents |
| --- | --- | --- |
| `meta` | `"meta"` (singleton) | `schema_version` (integer), `seq` (monotonic write counter), `created_at`, `last_write_at`, `persist_granted` (boolean or `null`) |
| `vehicles` | `vehicle_id` (client-generated UUIDv4) | vehicle selection, catalog reference keys, user overrides |
| `events` | `event_id` (UUIDv4) | oil-change and service events |
| `readings` | `reading_id` (UUIDv4) | odometer check-ins |
| `reminders` | `reminder_id` (UUIDv4) | reminder intent/thresholds |
| `prefs` | `"prefs"` (singleton) | units, time zone, display preferences |

`localStorage` is used for **nothing but** a tiny non-personal boot hint (`dos_boot_state`: one of `"never"`, `"has_data"`) that lets the shell choose the correct first-paint skeleton before IndexedDB opens. It contains no personal values.

### Payload envelope

Every hydrate, write-back, and export uses one envelope shape:

```
{
  "envelope": "dos_local",
  "schema_version": 1,
  "seq": 42,
  "tab_id": "<uuid, per browser tab, not persisted>",
  "generated_at": "2026-08-01T12:00:00Z",
  "data": { "vehicles": [...], "events": [...], "readings": [...],
            "reminders": [...], "prefs": {...} }
}
```

`tab_id` is ephemeral, regenerated per tab load, and is **not** a user identifier: it is never persisted to IndexedDB, never written to a cookie, and never logged.

### Mount and hydration sequence

1. **Static render (`connected?(socket) == false`).** The server renders the shell with `assigns.local_state == :hydrating`. It renders a **skeleton**, never an empty state.
2. **Socket connects.** Assigns still `:hydrating`. A `hydration_deadline` timer is armed (default 5 000 ms).
3. **Hook `mounted()`** opens `dos_local`, runs any client-side IDB upgrade, reads all stores in one `readonly` transaction, and calls `pushEvent("local_store:hydrate", envelope)`.
4. **Server `handle_event("local_store:hydrate", …)`** validates the envelope (see §"Validation"), migrates it if needed, places the result in assigns, and sets `assigns.local_state` to `:loaded` or `:empty`.
5. **If migration changed the payload**, the server immediately `push_event`s a `local_store:put` carrying the migrated payload so the client's storage is upgraded in the same round trip.
6. **If the deadline expires** with no hydrate event, the server sets `assigns.local_state = :storage_unavailable` and renders the storage-unavailable state — which is a **different state from `:empty`** and says so in words.

### First-paint and empty-state rules (normative)

- The three states `:hydrating`, `:empty`, and `:storage_unavailable` are **distinct** and render differently.
- The UI **MUST NOT** render "You have no vehicles yet" or any onboarding-from-zero flow while `local_state == :hydrating`. A returning user seeing an empty-garage flash reads it as data loss; that is an INV-5-adjacent failure even though nothing was lost.
- On **reconnect**, the client DOM from the previous render is retained by LiveView; the shell uses `phx-disconnected` styling to indicate reconnection rather than tearing down to a skeleton. Re-hydration replaces assigns underneath a stable view.
- If `dos_boot_state == "has_data"` but hydration returns zero records, the server renders an explicit **`:data_missing`** warning — not an empty state — telling the user their browser storage appears to have been cleared, and offering import. Silently showing a fresh empty garage to a user who had data is prohibited.

### Validation (server side)

Hydration input is **untrusted client input** and is validated exactly like any external payload:

- Parsed through an explicit embedded-schema changeset per `schema_version`. Unknown top-level keys are rejected; unknown keys *within a record* are preserved verbatim in assigns and written back unchanged (forward-compatibility, so an older deployment never destroys fields a newer one wrote).
- Hard caps, enforced server-side and rejected — never silently truncated: payload ≤ 1 MiB decoded; ≤ 200 vehicles; ≤ 5 000 events; ≤ 20 000 readings. Exceeding a cap yields an explicit error state with export offered.
- Type, range, and referential checks (event `vehicle_id` must exist in the payload's vehicles; odometer values non-negative and within sane bounds; dates parseable).
- Catalog references are resolved against `CatalogRepo` at render time and may come back `unsupported` if a `data_version` moved — that is a legitimate INV-11 state, rendered as such, not an error.
- Validation failure is never fatal to the session: the valid subset hydrates, the invalid records are held aside in a quarantine list, and the UI shows exactly what could not be read plus an export of the raw payload for recovery.

### Schema versioning and migration

- `schema_version` is a single monotonically increasing integer owned by the server.
- **Client payload older than the server's version:** the server migrates it through pure, ordered, forward-only functions (`LocalStore.Migrations.migrate/3`), then write-backs the migrated payload (step 5 above). Migrations are unit-tested against recorded fixtures of every prior version.
- **Client payload newer than the server's version** (a stale deployment, or a rolled-back release): the server **MUST NOT** write. It enters read-only mode, renders an explicit banner ("this browser holds data from a newer version of the app"), disables mutations, and offers export. Downgrading or dropping unknown fields is prohibited.
- IndexedDB's own version is bumped only for object-store/index changes, and its `onupgradeneeded` path never deletes stores holding data.

### Mutation round trip

Every mutation is a round trip; there is no server-side durability at any point.

1. User acts → `handle_event` on the LiveView.
2. Server computes the new state **in assigns**, assigns a `mutation_id` (UUID) and `seq = current_seq + 1`, records it in `assigns.pending_writes`, and renders optimistically with a "saving" affordance.
3. Server `push_event`s `local_store:put` with `{mutation_id, seq, upserts: [...], deletes: [...]}`.
4. Hook opens one `readwrite` transaction across the affected stores **plus `meta`**, performs a compare-and-set on `meta.seq` (see §"Multi-tab"), applies the changes, commits.
5. Hook `pushEvent`s `local_store:ack` `{mutation_id, seq, status: "ok"}`.
6. Server clears the pending write and renders the saved state.

**If no ack arrives within 2 000 ms, or the ack reports an error**, the server renders a persistent, non-dismissible "Not saved to this browser" state on the affected record, keeps the optimistic value visible but visibly marked as unsaved, and offers export. It does not retry silently and it does not roll back invisibly. The user is told the truth: the server holds this only until they close the tab.

### Quota and eviction

- IndexedDB storage is **best-effort by default**; browsers may evict it under storage pressure.
- After the user's first meaningful write (first vehicle saved), the hook calls `navigator.storage.persist()` once and records the boolean result in `meta.persist_granted`. The answer — granted, denied, or unavailable — is reflected honestly in the storage-status UI. Denial is not treated as an error, and a grant is **never** described to the user as a backup.
- `navigator.storage.estimate()` is read on hydration; if usage exceeds 80% of quota the UI surfaces it and suggests export/pruning.
- A write that fails with `QuotaExceededError` follows the failed-ack path above with a quota-specific message. Data is never silently dropped to make room.
- Target: the constitution §9 budget of ≤ 1 MiB per 1 000 text-only records carries over unchanged and is the design constraint that keeps quota a non-issue in practice.

### Private browsing and blocked storage

Behavior varies by browser: some throw on `indexedDB.open()`, some provide an ephemeral database discarded when the session ends, some silently allow a tiny quota.

The fallback ladder is explicit and has no silent step:

1. Try IndexedDB. If it opens and a probe write+read+delete round-trips, storage is **durable-capable** (subject to eviction).
2. If open or the probe fails → **session-only mode**. State lives in `socket.assigns` for the connection lifetime, backed by nothing. A persistent banner states that nothing is being saved and that closing the tab loses everything; export is offered prominently and repeatedly.
3. There is **no** silent fallback from IndexedDB to `localStorage` for records, and **no** fallback to server storage. Either the browser can hold the data or the user is told it isn't being held.

Session-only mode is fully functional for catalog browsing and one-off lookups. That is a legitimate use of the product; it just is not a garage.

### Multi-tab consistency

IndexedDB is shared across tabs of one origin; each tab has its own LiveView socket and its own independent assigns. Divergence is guaranteed without a protocol.

- A `BroadcastChannel("dos_local_store")` is opened per tab. After any successful commit, the writing tab broadcasts `{seq, mutation_id, tab_id}`.
- Receiving tabs compare the broadcast `seq` to their last-known `seq`. If it is ahead, the hook re-reads storage and pushes a fresh `local_store:hydrate` to its own socket. That tab's assigns are replaced wholesale; in-flight optimistic edits in that tab are re-applied on top if still pending, or surfaced as a conflict if the same record changed.
- Every write is a **compare-and-set on `meta.seq`** inside the same transaction. If stored `seq` is not the expected value, the transaction aborts and the hook pushes `local_store:conflict`. The server then discards its optimistic assign, triggers re-hydration, and shows a visible "reloaded from this browser's newer data" notice.
- Conflict resolution is **last-write-wins at record granularity, with the loss made visible**. This is a deliberate simplification justified by the single-user, single-person assumption; it is recorded as an open question below rather than presented as a general solution.
- `BroadcastChannel` is unavailable in some private-browsing contexts. Its absence degrades to per-mount hydration only, and the compare-and-set still prevents lost-update corruption — it just surfaces later.

### Export and import

- **Export** is produced entirely in the hook: read all stores, wrap in the envelope, append a SHA-256 content hash, serialize, and hand the user a `Blob` download named `digital-oil-sticker-export-YYYYMMDD.json`. It does not round-trip through the server.
- **Import** is read in the hook via a file input, parsed, hash-checked, then pushed as a normal `local_store:hydrate` (so it inherits all validation and migration). Import is explicitly **replace** or **merge**, chosen by the user, previewed with counts before it commits. It never silently merges.
- Export is the *only* recovery path and every surface that could imply otherwise is copy-reviewed against INV-5. Prohibited words in this UI: "backup", "synced", "safe", "we'll remember", "your account". Required: an always-reachable statement that data lives in this browser only and that clearing browser data deletes it permanently.

### Enforcement

These are release-gating checks, not conventions:

- A test asserting the deployed application's Ecto repo list is exactly `[CatalogRepo]` and that its connection is opened read-only.
- A static check that no module under the domain namespaces references `Phoenix.LiveView`, `Plug`, or the `LocalStore` protocol modules — protecting decision §6 (native reuse) mechanically.
- A test that drives a full scripted session (hydrate → several mutations → export → clear → import) with log capture, asserting that no VIN, odometer value, service date, note text, or custom vehicle name appears in any captured log line.
- A test that hydration is idempotent: hydrating the same payload twice produces identical assigns and emits no write-back.

---

## What this supersedes and amends

### ADR-0001 → Deferred

[ADR-0001](ADR-0001-mob-liveview-on-device.md) ("Mob LiveView runs the BEAM and Phoenix on-device") moves to:

> **Deferred — superseded for MVP by ADR-0004; retained for a future native client.**

Its analysis is *not* repudiated. The two-bridge architecture, the `Phoenix.LiveView.Socket` ≠ `Mob.Socket` distinction, the `DeviceCommandBroker` boundary, the no-background-process rule, and the loopback-binding hardening list remain the correct design **for a native Mob client** and are the starting point if the native track revives. What changed is sequencing and risk, not correctness.

The DOS-M00-003 gate in ADR-0001 §7 is **suspended, not passed and not failed** — it cannot resolve without a Mac. It is no longer a precondition for feature work, because feature work no longer depends on it. ADR-0001 §7's own escape clause ("or an explicit fallback ADR is approved") is exercised by this document.

### ADR-0002 → Amended

[ADR-0002](ADR-0002-netlify-static-boundary.md) ("Netlify is a static boundary, not a runtime") is **amended, not superseded**. Netlify is no longer the *only* edge, and three of its clauses change.

**What still stands, unchanged and emphatically:**

- **Netlify cannot host Phoenix.** Functions are TypeScript/JavaScript/Go; Edge Functions are Deno. There is no always-on BEAM. Nothing about this pivot changes that, and the Phoenix application is therefore **not** on Netlify.
- Builds happen in GitHub Actions, not in Netlify's build pipeline.
- Netlify never distributes application binaries.

**What each host now does:**

| Concern | Host |
| --- | --- |
| Phoenix LiveView application, WebSockets, all catalog queries, all rendering | **Fly.io** |
| Apex `digitaloilsticker.com` and `www` | **Fly.io** |
| Static marketing, support, privacy policy, and source-attribution pages | **Netlify** (team `cDiscourse`, already paid) |
| Deploy previews for that static content | **Netlify** |
| Later (post-MVP): immutable versioned catalog artifacts + signed manifest | **Netlify** |
| Elixir/Phoenix runtime of any kind | **Never Netlify** |

**Clauses amended:**

- ADR-0002 §5 ("the production domain is reserved for this boundary — nothing else") is **amended**: the apex and `www` now point at the Fly application. Static content moves to subdomains (`help.` / `legal.`, and later `catalog.`), or is served from `digitaloilsticker.net`. The privacy and attribution URLs must remain stable and reachable, and the application footer links them.
- ADR-0002 §6 ("no browser product is implied — a browser/PWA or hosted Phoenix product would require a separately approved architecture and deployment decision") is **satisfied**: this ADR *is* that separately approved decision. Note precisely what is approved — a **hosted Phoenix browser application**. A **PWA / service-worker offline mode is still not approved** and still requires its own decision.
- ADR-0002's consequence that "the installed application never depends on Netlify availability" is now trivially true for the app (the app doesn't touch Netlify) but its converse is new and worse: **the application depends entirely on Fly.io availability.** See §"Consequences".

### ADR-0003 → Unchanged

Every clause of [ADR-0003](ADR-0003-data-boundaries.md) survives intact: canonical entities, evidence requirements, the four confidence tiers, the source-gap matrix, fallbacks and the three-layer separation, testable coverage definitions, and the legal/redistribution gate. The user-override layer now physically lives in the browser instead of an on-device SQLite `UserRepo`; it is still a distinct layer that never mingles with curated claims.

**One new obligation ADR-0003 did not anticipate.** Its legal analysis assumed redistribution *inside an application bundle*. Serving catalog facts from a **public web endpoint** is a materially different distribution mode: broader reach, scrapable, no packaging boundary. Before any licensed (non-public-domain) source is served from the hosted app, `SOURCE_REGISTER.md` and `LICENSING_CHECKLIST.md` must be re-reviewed for web-serving rights specifically. vPIC and FuelEconomy.gov (17 U.S.C. §105 U.S. Government works) are unaffected. Sources in the "documented-facts" and "permission-needed" lanes are **gated** until this review completes. This is a hard gate, recorded here so it cannot be forgotten.

### Constitution invariants requiring re-ratification

Per [CHANGE_CONTROL.md](../governance/CHANGE_CONTROL.md) Rule 2a, an ADR is the required artifact for an architecture change — but the Constitution states that "amendments require a new ratified revision with fresh sign-off — never in-place edits." This ADR **does not amend the Constitution** and does not claim to. It records precisely which invariants it contradicts, so a Constitution revision 2.0.0 can be drafted and ratified as its own act:

| Invariant | Conflict | Required disposition |
| --- | --- | --- |
| **INV-1** (native iOS/Android only; browser is dev-only, not a production promise) | Directly contradicted | Rewrite: browser is the v1 platform; native is a future client |
| **INV-2** (endpoint binds `127.0.0.1` only) | Not applicable to a hosted app | Replace with the hosted security boundary (§ below) |
| **INV-6** (bundle includes a usable catalog; first launch works in airplane mode) | Cannot hold in a plain browser app | Rewrite honestly: connectivity is required (§"Consequences") |
| **INV-7** (connectivity MUST NOT be required to begin or keep using the app) | Directly contradicted | Rewrite; a future PWA decision could partially restore it |
| **INV-17** (OS-scheduled local notifications only) | No OS local notifications in a browser | Rewrite: in-app due/overdue state only; Web Push deferred |
| **INV-19** (prohibited scope includes "browser/PWA product") | Directly contradicted for the browser half | Rewrite: browser product permitted; PWA still requires a decision; every other prohibition (accounts, hidden server storage, cloud sync, remote push, telematics, commerce, ads, social, fleet) stands |
| **INV-3, INV-4, INV-5** | **Preserved and strengthened** | No change. No accounts, no server-side personal record, no telemetry, no implied backup |
| §9 latency budgets | Written for loopback; void over a network | Re-measure and re-ratify (§"Risks") |
| §9 packaged-app-size budgets | Not applicable | Replace with a first-paint payload budget |

Until that revision is ratified, this table is the authoritative record of the discrepancy. No implementation ticket may cite INV-1, INV-6, INV-7, INV-17, or INV-19 as binding in their current form.

---

## Hosting specifics

### Region

**Primary region: `ord` (Chicago). Single region.**

LiveView is latency-multiplying: every click, keystroke, and filter is a server round trip, so regional choice is a UX decision, not an ops preference. The market is the United States (INV-8, ADR-0003). A central-US region minimizes the *worst-case* coast-to-coast RTT, whereas an East-coast region (`iad`) optimizes the median at the expense of West-coast users, who would feel every interaction.

Single region because: there is no personal data to replicate (that is the whole point of the client-storage design); the catalog is read-only and identical everywhere; and multi-region read replicas would add consistency and deploy complexity for zero MVP benefit. Revisit only if measured p95 interaction latency by geography fails the (re-ratified) budget.

`min_machines_running = 1`. Scale-to-zero is **prohibited** for this app: a cold start on first paint is bad, but a cold start that drops live WebSockets is worse, and auto-stop machines would make hydration timeouts routine. A second machine for rolling deploys and HA is a cost decision, deferred (§"Cost shape").

### Custom domain and TLS

- `digitaloilsticker.com` (apex) and `www.digitaloilsticker.com` → the Fly application. Dedicated IPv4 + shared IPv6 as appropriate; `fly certs add` for both hostnames; ACME validation via the documented DNS records.
- `digitaloilsticker.net` → permanent redirect to `.com`. Owned, parked, not a second product surface.
- `help.` / `legal.` (and later `catalog.`) → Netlify.
- TLS is Fly-managed with automatic renewal. **HSTS is enabled only after certificates are verified and both hostnames serve correctly** — enabling it early on a misconfigured host is self-inflicted downtime. `preload` is not requested at MVP.
- `PHX_HOST` is set explicitly; `Endpoint` `:url` is configured for `https` on port 443 so generated URLs and the socket endpoint are correct behind the proxy.

### WebSocket and LiveView considerations

- Fly's proxy supports WebSockets natively; `/live/websocket` needs no special routing.
- `Plug.SSL` with `rewrite_on: [:x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]` so the app correctly sees TLS termination at the proxy. `force_ssl` on; plain HTTP redirects.
- `check_origin` is set to an **explicit host list**, never `true` and never `false`. Origin checking is the primary defense against cross-origin socket hijacking.
- The LiveView heartbeat (default 30 s) keeps sockets inside the proxy's idle window. Verify against Fly's current idle timeout during the deployment spike rather than assuming.
- **Deploys drop every WebSocket.** With one machine, a deploy is a brief disconnect; clients auto-reconnect with backoff and **remount, which re-runs hydration**. This is precisely why hydration must be idempotent, sub-second, and visually non-destructive (§"First-paint rules"). It also means a deploy during a user's unsaved mutation must not lose it — pending writes are re-driven after remount from client storage, which is the source of truth.
- `phx-disconnected` styling communicates reconnection honestly instead of freezing a stale-looking UI.

### Catalog database on Fly

**Recommendation: SQLite, shipped read-only *inside the deploy image*. No volume. No Postgres.**

The catalog is immutable within a `data_version` (CHANGE_CONTROL Rule 6), read-only at runtime, modest in size (constitution §9 targets ≤ 30 MiB compressed for the starter artifact), and produced by a deterministic build pipeline that ADR-0003 already proved rebuilds byte-identically (normalized SHA `25c737989c608b11…`). Under those conditions the database is not state — it is a build artifact.

Consequences of that choice, stated plainly:

| Property | Effect |
| --- | --- |
| **Single-writer problem** | Eliminated, not managed. Zero runtime writers. |
| **Catalog replacement** | Is a deploy. Atomic by construction; new image up, old image down. |
| **Rollback** | Redeploy the previous image. The old catalog comes back exactly. |
| **Backups** | The build inputs (git-tracked) plus the deterministic pipeline. Stronger than a DB dump: the artifact is *reproducible*, not merely *restorable*. |
| **Horizontal scaling** | Each machine carries its own identical read-only copy. No coordination. |
| **Latency** | In-process reads. No network hop per query — meaningful given LiveView's round-trip-per-interaction shape. |
| **Cost** | $0 beyond image storage. No managed database, no volume. |
| **Ad-hoc production edits** | Impossible. This is a feature: CHANGE_CONTROL Rule 6 forbids invisible data corrections, and this makes the rule structurally enforced. |
| **Image size** | Grows with the catalog. Acceptable now; a trigger to revisit if the catalog outgrows a comfortable image. |
| **Update cadence** | Requires a deploy. Acceptable — catalog releases are versioned events, not a stream. |

Rejected alternatives and why:

- **SQLite on a Fly persistent volume.** Pins the app to one machine and one zone, complicates deploys (volume must follow), and introduces a swap-and-flip ritual for catalog replacement — all to solve a problem (out-of-band updates) the MVP does not have. This is the documented fallback if the catalog outgrows the image or needs updating without a deploy. **LiteFS is explicitly not needed**: it solves write replication, and there are no writes.
- **Postgres (Fly Managed Postgres or another provider).** Adds an always-on cost, a network hop on every catalog query, an availability dependency, and backup/DR duty — for a read-only dataset. Not justified at MVP. It becomes the right answer only if provider operations, multi-writer catalog authoring, or genuinely large-scale relational querying appear post-MVP — and none of those would ever hold personal rows.

The catalog connection is opened read-only (SQLite read-only open mode; a `SELECT`-only role if Postgres ever arrives), so decision §4 is enforced by the connection itself, not only by code review.

### Secrets

- `SECRET_KEY_BASE`, `PHX_HOST`, and any future runtime configuration are set via `fly secrets set` and read in `runtime.exs`. Never committed; no `.env` in production.
- **There are no third-party API keys at runtime.** Catalog acquisition (vPIC, FuelEconomy.gov, licensed sources) runs at build time in GitHub Actions, not in the request path. This keeps the runtime secret surface to essentially one value.
- CI holds a **deploy-scoped** Fly token in GitHub Actions repository secrets — least privilege, not an org-admin token.
- `SECRET_KEY_BASE` rotation invalidates signed session cookies and LiveView socket tokens; clients reconnect and re-hydrate from browser storage. **No user data is lost by a secret rotation** — a genuinely nice property of the no-server-state design, and worth stating because it makes rotation cheap enough to actually do.
- Secrets are never logged, never echoed in error pages (`debug_errors: false` in prod), and never surfaced in a stack trace rendered to a user.

### Cost shape

The MVP shape is: **one always-on shared-CPU machine** (small RAM footprint — LiveView's per-connection cost is measured in tens of KB of process heap, not the megabytes a per-user database session would cost), **no managed database, no volume, no object storage, no third-party services**. Bandwidth is small: LiveView sends DOM diffs, not pages, and there is no media.

The cost curve is driven almost entirely by **machine count and size**, in this order: (1) adding a second always-on machine for HA and zero-downtime deploys, (2) increasing RAM as concurrent connections grow, (3) — only if it ever happens — a managed Postgres. Netlify is already paid for on the `cDiscourse` team and adds nothing marginal.

Concrete dollar figures are deliberately **not** asserted here: Fly's pricing changes, and this project does not record unverified facts. The provisioning ticket must read current pricing at the time of provisioning and record the measured monthly cost in the ledger.

---

## Security and privacy boundary for a hosted application

The old boundary was "the endpoint is on loopback and nothing can reach it" (INV-2). That defense is gone. It is replaced by the following, which is weaker in kind and therefore must be stronger in detail.

### Transport

- **HTTPS and WSS only.** `force_ssl` with redirect; HSTS enabled after certificate verification. No mixed content; the CSP forbids it anyway.
- `check_origin` restricted to the exact production hostnames.

### CSRF and session

- Phoenix `protect_from_forgery` on all HTTP routes; LiveView's `_csrf_token` passed through socket connect params and verified on connect.
- The session cookie is signed, `secure`, `http_only`, `same_site: "Lax"`, with a short `max_age`.
- **The session cookie contains no personal data and no stable user identifier.** Permitted contents: the CSRF token and `live_socket_id`. Prohibited: any vehicle, VIN, odometer, date, note, preference, anonymous user ID, or any value that could correlate one visit to another. If a stable identifier ever becomes necessary, it requires a new ADR and a privacy re-review — because "an anonymous ID we keep forever" is an account wearing a disguise, and INV-3 exists to prevent exactly that.

### Content Security Policy

Served on every response:

```
default-src 'self';
script-src 'self';
style-src 'self';
img-src 'self' data:;
font-src 'self';
connect-src 'self' wss://digitaloilsticker.com;
frame-ancestors 'none';
base-uri 'self';
form-action 'self';
object-src 'none'
```

Plus `Referrer-Policy: no-referrer`, `X-Content-Type-Options: nosniff`, and a `Permissions-Policy` denying geolocation, camera, microphone, and payment. (A post-MVP VIN-scan feature would need camera and is therefore a separate decision touching this header, not a quiet relaxation of it.)

All assets are first-party and bundled by esbuild. **No CDN, no Google Fonts, no external script of any kind** — fonts are self-hosted. `'unsafe-inline'` is not used; if a LiveView behavior turns out to require inline styles, the answer is a per-request nonce plug, verified in the deployment spike, not a blanket relaxation.

### No third-party anything

INV-4 is preserved without qualification: no analytics, no tag manager, no session recording, no A/B service, no third-party error reporting, no embedded widgets. The CSP enforces this structurally rather than relying on discipline. The Netlify static site inherits the same rule.

**Third-party error reporting is specifically prohibited**, because `socket.assigns` contains the user's garage: any crash reporter that serializes assigns would exfiltrate exactly the data this architecture exists to keep off servers. If error reporting is ever added it requires an ADR plus a proven assigns-scrubbing layer.

### Rate limiting and abuse

- Per-IP limits on socket connects and on HTTP requests, via a token-bucket plug.
- Per-socket limits on catalog search/filter events (they hit the database) and on hydrate/import events (they are the largest payloads).
- Server-side payload caps as specified in §"Validation" — rejected explicitly, never silently truncated.
- Client IP is taken from Fly's forwarded headers via a trusted-proxy-aware plug. It is used for rate limiting **in memory only** and is not persisted (see logging).

### LiveDashboard and operator access — stated honestly

- **LiveDashboard is disabled in production.** It exposes process state, and process state here means live users' vehicles and mileage. There is no "behind basic auth" compromise at MVP.
- `fly ssh console` / remote IEx grants an operator the technical ability to inspect a running process, including a live session's assigns. Therefore the accurate privacy claim is: **"we store no personal data on the server"** — not "no operator could ever observe a live session." Overclaiming here would be exactly the kind of dishonesty INV-5 and INV-15 exist to prevent, so the claim is scoped precisely and the privacy page says the same thing. Operational rule: no routine production console use, and never attaching to inspect a live socket. Console access is for incident diagnosis of the *application*, not of *users*.

### Logging

**Server logs MAY contain:** timestamp, HTTP method/path/status/duration for non-LiveView routes, LiveView event **name** (not params), error type and stacktrace, release version, machine ID, and coarse aggregate counters.

**Server logs MUST NOT contain:** VIN; odometer or mileage values; service dates; note text; custom vehicle names; the specific vehicle a session selected; any hydration, mutation, import, or export payload or fragment thereof; the `tab_id`; or the full client IP address (truncate, salt-hash with a rotating salt, or omit — omit is the default).

Enforcement: request-param logging disabled, `filter_parameters` configured, a Logger filter that drops `handle_event` params by default with an explicit allowlist for non-personal events, and the scripted-session log-scanning test from §"Enforcement" as a release gate. `debug_errors: false` in production so no assigns reach an error page.

---

## Consequences

### Gained

- The data product can be validated **now**, by real users, against real catalog data, from a URL — no store review, no signing identity, no Mac, no pre-1.0 native framework.
- Iteration is a deploy, measured in minutes, not a store review cycle.
- One codebase, one language, one deployment. The domain contexts are exactly the ones a future native client will reuse.
- INV-3/INV-4/INV-5 survive intact — arguably strengthened, since the server now provably holds nothing (one read-only repo, enforced by test), which is a cleaner claim than "we have a local database we promise not to sync."
- Secret rotation, deploys, and machine replacement are all data-loss-free by construction.

### Lost — honestly

- **No bundled offline catalog.** INV-6's promise cannot hold. What replaces it: the catalog is **queried from the server** at interaction time. There is no starter catalog on the client and none is implied. The user needs connectivity to select a vehicle or read a schedule.
- **The app does not work offline at all.** This is worse than "the catalog needs a network." LiveView renders on the server, so with no connection there is no UI beyond a disconnected shell — even for a garage already sitting in the user's own IndexedDB. This is the single largest honest loss of the pivot and no copy anywhere may soften it.
- **A PWA / service-worker offline mode is an explicitly deferred, separate decision.** It is not promised, not scheduled, and not implied by this ADR. It would require a service worker, an offline rendering strategy that does not depend on the server (a real architectural fork for a LiveView app), and its own ADR.
- **No OS local notifications.** `mob_notify` and OS-scheduled local notifications do not exist in a browser. The MVP ships **in-app due/overdue state only**, computed on hydration and after each mutation. The user learns their status by opening the app. The UI must say this plainly and must not imply it will alert them.
- **Web Push is explicitly deferred**, and flagged as architecturally uncomfortable: it requires a service worker, VAPID keys, and a browser-vendor push service — i.e. **remote infrastructure and a third-party delivery endpoint**, plus a push subscription that would have to live *somewhere*. Holding subscriptions server-side would create the first server-side per-user record this architecture exists to avoid. Web Push therefore conflicts with the no-remote-infrastructure and no-server-record stance and cannot be adopted incrementally; it needs its own ADR and a privacy re-review, not a ticket.
- **Browser storage is erasable, and by parties other than the user.** Clearing site data, "clear cookies on exit" settings, private-browsing sessions, storage eviction under pressure, browser-vendor eviction policies for infrequently-visited sites, a different browser, a different profile, or a different device — any of these means the garage is gone. INV-5 binds harder than ever: **no interface may imply backup or recoverability.** Export is the only recovery, and the UI says so unprompted.
- **No multi-device story.** Each browser profile is an independent garage. Moving between devices means export and import, manually.
- **A new availability dependency.** ADR-0002 correctly boasted that the installed app never depended on Netlify. The hosted app depends **entirely** on Fly.io: if Fly is down, the product is down. Single region and single machine at MVP make this sharper.
- **The loopback security posture is gone** (INV-2). It is replaced by the boundary above, which is a real boundary but a public one. The threat-model ticket (DOS-M07-001) must be rewritten from scratch against a hosted app; it currently reasons about a device-local endpoint.
- **Constitution §9's latency and size budgets are void.** The interaction-latency budget (local p95 ≤ 100 ms) was written for a loopback socket and is not achievable coast-to-coast over the public internet. New provisional budgets must be measured and re-ratified rather than quietly missed. Packaged-app-size budgets are replaced by a first-paint payload budget.

### Preserved for the native track

Nothing about the deferral discards native work. ADR-0001's design analysis, the pinned toolchain matrix, the five-defect record, the WSL2 containment recommendation, and the physical-device setup (Motorola Razr Ultra 2025 over wireless adb via Tailscale) are all retained. Decision §6 and its static-check enforcement mean the domain contexts written for the browser are the domain contexts a native client would mount — the client difference is one storage adapter (browser hydration protocol ↔ on-device SQLite) and one presentation shell.

---

## Alternatives considered

1. **Buy a Mac and finish the native gate.** Rejected for now: capital plus weeks of setup before a single line of data-product validation. The moat is the data, and the data can be validated without it. Not rejected forever — see revival triggers.
2. **Ship Android-only native.** Rejected: half the market, still pre-1.0 Mob, still a fragile build host, still store-review latency on every iteration, and it would leave the iOS question unanswered rather than answered.
3. **Browser app with accounts and server-side personal rows in Postgres.** Rejected outright: violates INV-3, discards the product's clearest differentiator, and imports auth, breach surface, and data-handling duty in exchange for convenience.
4. **Static SPA on Netlify with the catalog shipped as static JSON.** Rejected on two independent grounds. First, the catalog resolver — confidence tiers, conflict policy, unknown/unsupported states (ADR-0003) — *is* the product, belongs in Elixir, and is what a native client must reuse; reimplementing it in JavaScript doubles it. Second, and decisively: publishing the full normalized catalog as static JSON is **bulk redistribution to anyone who fetches it**, which ADR-0003's licensing lanes do not authorize for documented-facts or permission-needed sources.
5. **LiveView with server-side session state in ETS/Redis, keyed by an anonymous cookie.** Rejected: a durable server-side record keyed by a stable identifier is a personal record and an account without a password. It would breach INV-3 and INV-4 while *appearing* to satisfy them, which is worse than breaching them openly.
6. **Postgres for the catalog from day one.** Deferred, not rejected on principle: it buys nothing for a read-only, deploy-versioned dataset while adding cost, a network hop, and operational duty.

---

## Risks and open questions

| # | Risk / question | Disposition |
| --- | --- | --- |
| R1 | **Browser eviction of infrequently-used site storage.** Some browsers cap or evict script-writable storage for sites a user has not visited recently. A user who checks their oil once a quarter is exactly the profile most at risk — and quarterly is the natural usage cadence for this product. This is the single biggest product risk of the pivot. | Mitigations: `navigator.storage.persist()`, honest storage-status UI, export nudges after meaningful writes, and the `:data_missing` state so loss is never disguised as an empty garage. Actual per-browser eviction behavior must be **measured**, not assumed from documentation. A PWA-install path is the strongest known mitigation and is one of the arguments the future PWA decision must weigh. |
| R2 | Hydration round trip adds latency to first meaningful paint on every mount, including every reconnect. | Measure and budget explicitly; hydration must be sub-second on a cold connection or the skeleton state becomes the dominant impression of the product. |
| R3 | The strict CSP is unverified against LiveView's runtime behavior (transitions, JS commands, uploads). | Verify in the deployment spike. If a nonce is required, add a nonce plug — `'unsafe-inline'` is not an acceptable resolution. |
| R4 | Multi-tab conflict resolution is last-write-wins at record granularity. | Accepted for MVP under the single-user assumption, with losses made visible. Open question: whether any real workflow (two tabs, one logging a service while the other edits it) makes this materially wrong. Re-examine on evidence. |
| R5 | **Constitution invariants INV-1/2/6/7/17/19 are contradicted and not yet re-ratified.** | A Constitution revision 2.0.0 must be drafted and ratified as its own act. Until then the discrepancy table above governs, and no ticket may cite the superseded forms. |
| R6 | **Web-serving rights for licensed catalog sources are unreviewed.** ADR-0003's legal analysis assumed in-bundle redistribution. | Hard gate: no documented-facts or permission-needed source is served from the hosted app until `SOURCE_REGISTER.md` and `LICENSING_CHECKLIST.md` are re-reviewed for web serving. Public-domain U.S. Government sources are unaffected. |
| R7 | Catalog endpoints are publicly scrapable in a way an app bundle was not. | Rate limiting is a mitigation, not a solution. Open question: whether the licensing review (R6) imposes access constraints that change the product surface. |
| R8 | Single region, single always-on machine: Fly outage or zone failure = total product outage. Deploys drop all sockets. | Accepted at MVP. A second machine is a bounded cost decision revisited on real usage. Reconnect + re-hydration must be proven robust enough that a deploy is a non-event for users. |
| R9 | §9 latency budgets are void and no replacement is ratified. | Measure real-world p50/p95 interaction latency by geography, then propose provisional budgets for re-ratification. Do not ship against budgets known to be inapplicable. |
| R10 | Cost growth under traffic or abuse is unmeasured. | Record measured monthly cost in the ledger after provisioning; set an alert threshold rather than discovering it on a bill. |
| R11 | Whether users will accept a product that does nothing offline and never notifies them. | This is the core product bet of the pivot and it is honestly unknown. It is the primary thing the browser MVP exists to find out — which is itself the argument for shipping it fast. |

---

## Trigger conditions that revive the native track

Any one of these re-opens the native question. Revival means drafting **ADR-0005** with fresh evidence and re-running DOS-M00-003 as written — it does not mean silently resuming work.

1. **Mac/Xcode access is obtained** — purchased, borrowed, or rented. Note the spike's finding that GitHub Actions macOS runners can produce artifacts but **cannot** run the `mob.deploy` hot-push/IEx loop against a physical phone, so hosted CI alone does not satisfy the gate.
2. **Mob reaches 1.0** with documented Windows or WSL2 support **and** CI covering that host, or the five recorded defects (plus the triplicated host-tag hazard) land upstream and the `deps/` patch becomes unnecessary.
3. **A repeatable Linux build host is established** — the spike's own containment recommendation: WSL2 with the VHDX relocated to `F:` and `ADB_SERVER_SOCKET` pointed at the Windows adb server to preserve the physical-device loop over Tailscale. This alone revives the *Android* half and would let DOS-M00-003's Android criteria complete.
4. **Product evidence demands native capabilities** — measured storage-eviction loss (R1) proving the browser cannot hold a garage reliably, or user demand for OS notifications strong enough to outweigh the deferral.
5. **The browser MVP validates the data product**, making a native client a distribution decision on a proven foundation rather than a bet on an unproven one. This is the *good* trigger, and the one the pivot is designed to reach.

---

## Research anchors

Version- and vendor-specific behavior below (pricing, proxy timeouts, storage-eviction windows) **must be re-verified at implementation time** rather than treated as settled by this document.

- [Fly.io documentation](https://fly.io/docs/)
- [Fly.io Elixir/Phoenix getting started](https://fly.io/docs/elixir/getting-started/)
- [Fly.io regions](https://fly.io/docs/reference/regions/)
- [Fly.io volumes](https://fly.io/docs/volumes/)
- [Fly.io app secrets](https://fly.io/docs/apps/secrets/)
- [Phoenix deployment guide](https://hexdocs.pm/phoenix/deployment.html)
- [Phoenix LiveView JavaScript interoperability and client hooks](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- [Phoenix LiveView security model](https://hexdocs.pm/phoenix_live_view/security-model.html)
- [Ecto SQLite3 adapter](https://hexdocs.pm/ecto_sqlite3/)
- [MDN — IndexedDB API](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)
- [MDN — Storage quotas and eviction criteria](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)
- [MDN — `StorageManager.persist()`](https://developer.mozilla.org/en-US/docs/Web/API/StorageManager/persist)
- [MDN — BroadcastChannel API](https://developer.mozilla.org/en-US/docs/Web/API/BroadcastChannel)
- [MDN — Push API](https://developer.mozilla.org/en-US/docs/Web/API/Push_API)
- [MDN — Content-Security-Policy](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy)
- [DOS-M00-003 spike evidence — Mob 0.7.20 on physical devices](../../spikes/m00-003-mob-device/README.md)
- [ADR-0001](ADR-0001-mob-liveview-on-device.md) · [ADR-0002](ADR-0002-netlify-static-boundary.md) · [ADR-0003](ADR-0003-data-boundaries.md) · [CONSTITUTION.md](../product/CONSTITUTION.md) · [CHANGE_CONTROL.md](../governance/CHANGE_CONTROL.md)
