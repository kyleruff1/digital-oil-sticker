# Browser storage schema

**Status:** Adopted 2026-08-02 as evidence for [DOS-M09-001](../../planning/issues/DOS-M09-001.md).
**Authority:** [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) §"The client-storage + LiveView hydration protocol"; [CONSTITUTION.md](../product/CONSTITUTION.md) 2.0.0 INV-3, INV-4, INV-5, INV-11, INV-15, INV-18, INV-21, INV-23, INV-24, INV-25, §9.

This is the single specification document for the anonymous client storage subsystem. The IndexedDB adapter (`app/assets/js/local_store/idb.js`) and the server-side validation (`app/lib/digital_oil_sticker/local_store/`) are both written against it. When the code and this document disagree, one of them is wrong and the same PR must fix both — silent drift is the failure mode this document exists to prevent.

Every field in every store is either the user's own record or a non-personal preference. There is no credential, no email, no password, no account identifier, no device identifier, no push subscription, no server-assigned identifier of any kind, and no full VIN by default (INV-3, INV-4, INV-17). Nothing here is ever synchronized to a server; the user's records leave the browser only through a user-initiated export file (INV-5, INV-23).

## The database

**Name:** `dos_local` — origin-scoped (`digitaloilsticker.com`).
**Structural IndexedDB version:** `1` (`IDB_VERSION` in [`schema.js`](../../app/assets/js/local_store/schema.js)).
**Logical schema version:** `1` (`SCHEMA_VERSION`; also `Envelope.current_schema_version/0` in [`envelope.ex`](../../app/lib/digital_oil_sticker/local_store/envelope.ex)).

The two version lines are documented in §"Version lines" below. The `dos_local` origin scope means a different origin (e.g., `staging.digitaloilsticker.com`) reaches a different database — records do not leak across origins.

**`localStorage` scope:** exactly one non-personal key, `dos_boot_state`, values `"never"` or `"has_data"` (see [`boot_hint.js`](../../app/assets/js/local_store/boot_hint.js)). Plus `phx:theme` from Phoenix's theme picker. Nothing else — no personal record, no session token, no identifier.

## Object stores

| Store | Key path | Key type | Indexes | Contents |
| --- | --- | --- | --- | --- |
| `meta` | out-of-line singleton at literal key `"meta"` | fixed string | none | logical `schema_version`, monotonic `seq`, `created_at`, `last_write_at`, `write_count`, `persist_granted`, bounded non-personal `log` |
| `vehicles` | `vehicle_id` | UUIDv4 string | `by_archived` (`archived`) | garage vehicles: nickname, stable catalog `configuration_key` + `catalog_data_version`, immutable `display_snapshot`, `support_status`, `engine_class_code`, `oil_model_version`, nullable `vin_last6`, `archived`, embedded `maintenance_plan`, timestamps |
| `events` | `event_id` | UUIDv4 string | `by_vehicle` (`vehicle_id`); `by_vehicle_performed` (`[vehicle_id, performed_at]`) | service events: `performed_at`, `odometer_m` + `odometer_input_value` + `input_unit`, oil snapshots (`oil_base_stock`, `oil_viscosity`, legacy `oil_brand`/`oil_family`), `filter_text`, `notes`, `provenance_mode` (`catalog`/`manual`), `correction_of`, timestamps |
| `readings` | `reading_id` | UUIDv4 string | `by_vehicle` (`vehicle_id`); `by_vehicle_observed` (`[vehicle_id, observed_at]`) | odometer check-ins: `observed_at`, `odometer_m`, `input_unit`, `source`, `source_ref`, `valid`, `superseded_by`, timestamps |
| `usage` | `usage_id` | UUIDv4 string | `by_vehicle` (`vehicle_id`); `by_vehicle_effective` (`[vehicle_id, effective_from]`) | usage profile rows: `baseline_distance_per_week`, `unit`, `severe_answers`, `condition`, `effective_from`, `effective_to`, timestamps |
| `reminders` | `reminder_id` | UUIDv4 string | `by_vehicle` (`vehicle_id`) | reminder intent: `kind`, `lead_value`, `lead_unit`, `preferred_time`, `enabled`, timestamps |
| `prefs` | out-of-line singleton at literal key `"prefs"` | fixed string | none | `unit_system`, `time_zone` (IANA), `onboarding_version`, `display`, `dismissed_notices`, `active_vehicle_id` |

**Key strategy** (FR-3, AC-3, AC-13):
- Every record primary key is a **client-generated UUIDv4**. No key is derived from a value the server transmits, assigns, or could correlate across visits.
- `meta` and `prefs` are the only singleton stores; both use out-of-line fixed string keys.
- No "current vehicle" singleton field exists at the top of any store — the currently active vehicle is `prefs.active_vehicle_id`, a soft pointer that a caller resolves through `LocalStore.Session.active_vehicle/1` with a live-vehicle fallback if the pointer names an archived or deleted vehicle.

**Ordering contracts** (FR-5) are index-backed. History rendered by [`HistoryLive`](../../app/lib/digital_oil_sticker_web/live/history_live.ex) sorts events by `(performed_at desc, event_id desc)`; `readings` sorts by `(observed_at desc, reading_id desc)`. Both come off `by_vehicle_performed` / `by_vehicle_observed` without a full-store scan.

## Record shapes

Server-side validation and canonicalization live in [`Schema.V1`](../../app/lib/digital_oil_sticker/local_store/schema/v1.ex); the allowlists below are that module's `@vehicle_keys`, `@event_keys`, etc. Unknown keys are **preserved verbatim** under a `"__unknown__"` submap so an older deployment never destroys fields a newer one wrote (FR-10, AC-7).

### `vehicles`

Required: `vehicle_id` (UUIDv4).
Allowlisted keys: `vehicle_id`, `nickname`, `configuration_key`, `catalog_data_version`, `model_year`, `display_snapshot`, `support_status`, `engine_class_code`, `oil_model_version`, `vin_last6`, `archived` (boolean or nil), `maintenance_plan`, `created_at`, `updated_at`.

`maintenance_plan` is a **top-level allowlisted key whose inner map is opaque** — inner keys survive round-trip without a schema bump. New inner keys (e.g., `manufacturer_viscosity` populated by [DOS-M03-007](../../planning/issues/DOS-M03-007.md)) need no allowlist change. `engine_class_code` is our derived classification snapshotted at setup so the interval a user sees does not silently change when the model is revised.

`display_snapshot` is the immutable human-readable identity carried forward alongside the stable `configuration_key`, so history stays intelligible after a catalog release changes, a product is withdrawn, or a configuration is superseded (INV-11).

### `events`

Required: `event_id`, `vehicle_id`, `performed_at` (ISO 8601 date or instant), `odometer_m` (non-negative integer, base unit **metres**), `input_unit` (`"mi"` or `"km"`), `provenance_mode` (`"catalog"` or `"manual"`).
Allowlisted keys: `event_id`, `vehicle_id`, `performed_at`, `odometer_m`, `odometer_input_value`, `input_unit`, `oil_base_stock`, `oil_viscosity`, `oil_brand`, `oil_family`, `filter_text`, `notes`, `provenance_mode`, `correction_of`, `created_at`, `updated_at`.

`oil_brand`/`oil_family` are legacy: brand was dropped in favour of `oil_base_stock` + `oil_viscosity`, but records written before that keep rendering rather than sliding into `__unknown__`. `correction_of` records the lineage when a user corrects a prior event.

### `readings`

Required: `reading_id`, `vehicle_id`, `observed_at`, `odometer_m` (non-negative integer metres), `input_unit`.
Allowlisted keys: `reading_id`, `vehicle_id`, `observed_at`, `odometer_m`, `input_unit`, `source` (e.g., `"service_event"` or `"manual"`), `source_ref`, `valid`, `superseded_by`, `created_at`, `updated_at`.

### `usage`

Required: `usage_id`, `vehicle_id`, `effective_from`.
Allowlisted keys: `usage_id`, `vehicle_id`, `baseline_distance_per_week`, `unit` (`"mi"`/`"km"` or nil), `severe_answers`, `condition`, `effective_from`, `effective_to`, `created_at`, `updated_at`.

`severe_answers` retains the answers that selected the operating condition, so a later re-review can see how the condition was chosen and whether the answers still hold.

### `reminders`

Required: `reminder_id`, `vehicle_id`.
Allowlisted keys: `reminder_id`, `vehicle_id`, `kind`, `lead_value`, `lead_unit`, `preferred_time`, `enabled` (boolean or nil), `created_at`, `updated_at`.

Reminder **intent** only. There is no `scheduled_notifications` store because nothing is scheduled in this platform (INV-17); reminders are rendered as in-app due state.

### `prefs`

Singleton at fixed key `"prefs"`.
Allowlisted keys: `unit_system` (`"mi"`/`"km"` or nil), `time_zone` (IANA identifier), `onboarding_version`, `display`, `dismissed_notices`, `active_vehicle_id`.

`active_vehicle_id` was added after v1 shipped as a soft pointer. It is additive — an older payload without it validates unchanged, and an older deployment reading a newer payload carries it through `__unknown__`. No version bump was required.

### `meta`

Singleton at fixed key `"meta"`.
Allowlisted keys: `schema_version` (positive integer or nil), `seq` (non-negative integer or nil), `created_at`, `last_write_at`, `write_count`, `persist_granted` (result of the `navigator.storage.persist()` call), `log` (bounded non-personal ring of migration and repair outcomes — versions, outcomes, counts only; never automotive content, never record contents, never field values).

`meta.seq` is the **compare-and-set field** for multi-tab safety (FR-16, INV-24.7). Every write reads it, compares it against expected, and aborts on mismatch so a stale tab cannot silently overwrite newer records.

## `UserRepo` → browser mapping

Every legacy `DATA_DICTIONARY.md` `UserRepo` table is accounted for. Tables with no browser home have a reason recorded (FR-4, AC-2). The pre-pivot data-dictionary now points at this document for the browser storage layout.

| `UserRepo` table | Browser home | Reason |
| --- | --- | --- |
| `local_profiles` | `prefs` singleton + `meta` | Anonymous store — no profile identity to model. Unit system, time zone, onboarding version are preferences; the rest was identity scaffolding INV-3 forbids. |
| `vehicles` | `vehicles` store | Direct equivalent, keyed by client-generated UUID. |
| `maintenance_plans` | versioned sub-document embedded inside each `vehicles` record (`maintenance_plan` opaque submap) | IndexedDB has no cross-store FKs and the plan is never read without its vehicle. Embedding removes an unenforceable join. One active plan per vehicle at MVP. |
| `service_events` | `events` store | Direct equivalent (store name follows ADR-0004). |
| `odometer_readings` | `readings` store | Direct equivalent. |
| `usage_profiles` | `usage` store | Direct equivalent. **Addendum obligation** under FR-20: the `usage` store is not in ADR-0004's original storage-layout table; recorded in §"ADR-0004 addendum obligations" below. |
| `forecast_snapshots` | **no store at MVP** | Derived from stored inputs and recomputed on load. Whether to persist an audit trail is [open question resolved](#open-questions) — the default is not to persist; adding a store later is a forward-only version bump. |
| `reminder_rules` | `reminders` store | Direct equivalent, narrowed to **intent** only. |
| `scheduled_notifications` | **no store** | Nothing is scheduled in this platform (INV-17). Nothing to record or reconcile. |
| `schema_events` | bounded ring inside `meta.log` | Migration and repair outcomes must survive but must contain no automotive or user content. A bounded ring keeps the footprint fixed. |

## Version lines

Two version lines, each with its own bump rule. This is the ratified decision from FR-6 / AC-4 / §"Decision" in the M09-001 issue.

### Logical schema version — `schema_version`

- **Where:** `meta.schema_version` in the store, `schema_version` in every hydration and export envelope.
- **Owned by:** the server. The server writes the current value into every envelope it produces and only accepts a payload whose value it understands.
- **Bumps when:** the shape or semantics of a record change — a field is renamed, a required field is added that older records must be given a value for, an enumeration narrows.
- **Current value:** `1` (`Envelope.current_schema_version/0`).
- **Never bumps for:** additive optional keys that older code can carry through `__unknown__` (e.g., `prefs.active_vehicle_id` shipped after v1 without a bump).

### Structural database version — `IDB_VERSION`

- **Where:** IndexedDB's built-in database version; opened via `factory.open(DB_NAME, IDB_VERSION)`.
- **Owned by:** the client adapter ([`idb.js`](../../app/assets/js/local_store/idb.js)).
- **Bumps when:** an object store or index is added or changed. Every structural bump MUST state which logical versions it is compatible with.
- **Current value:** `1`.
- **Never bumps for:** logical-only record-shape changes. A pure record-shape change that adds no store or index must NOT force a structural upgrade on every browser.

### Worked examples

- **Logical-only bump** (`schema_version` 1 → 2): a required `events.provenance_mode` value adds a third enum member `"imported"`. `Schema.V1` is superseded by `Schema.V2`; `Migrations` gets a new step `1 -> 2`; the fixture set gains a v1 fixture whose upgrade output matches the v2 fixture. `IDB_VERSION` stays at `1` — no store or index changed.
- **Structural bump** (`IDB_VERSION` 1 → 2): a new store `usage_answers` is added to record usage-question responses independently of `usage` rows. `IDB_VERSION` bumps to `2`; `STORES` in `schema.js` gains the new store; the `runUpgrade` path in `idb.js` creates it inside the `onupgradeneeded` transaction. The logical schema version bump is decided separately: if no existing record's shape changes, `schema_version` stays where it is and the addendum records "structural version 2 is compatible with logical versions 1 and any future logical version that does not remove `usage_answers`."

## Forward-only upgrade contract

Rules from FR-7 / FR-8 / AC-5 / AC-6, implemented by [`Migrations`](../../app/lib/digital_oil_sticker/local_store/migrations.ex) and by the `onupgradeneeded` path in [`idb.js`](../../app/assets/js/local_store/idb.js).

1. **Ordered.** Steps are pure functions `from_version → to_version`, applied in sequence. Every version transition has a step; no step is skipped.
2. **Pure and idempotent.** Re-running a step on an already-upgraded payload produces an identical payload and no write. `Migrations.migrate/3` short-circuits with `:unchanged` when `from == to`.
3. **All-or-nothing.** The IndexedDB version-change transaction is atomic: if any step raises, the transaction aborts, the database remains at its prior structural version with records **byte-identical**, and the adapter surfaces `upgrade_failed` (see `classifyError` in `idb.js` — `NotFoundError` / `ConstraintError` → `"upgrade_failed"`).
4. **No destructive upgrade.** An upgrade step never deletes an object store that holds data. `runUpgrade` in `idb.js` only calls `createObjectStore` / `createIndex`.
5. **No downgrade.** A payload at a logical version **newer** than the deployment triggers read-only mode (FR-9). `Migrations.migrate/3` returns `{:error, {:newer_than_server, from_version}}`; the LiveView session sets `read_only: true` and shows the "This browser holds data from a newer version" banner (see `Copy.read_only_banner`). Downgrading, dropping unknown fields, or writing at the older version is prohibited.
6. **Unknown fields survive.** `Schema.V1.canonicalize/2` moves any top-level key not in the allowlist into a `"__unknown__"` submap; `restore_unknown/1` merges them back flat for write-back. Round-trip byte equality on unknown fields is asserted by `test/digital_oil_sticker/local_store/validation_test.exs`.

## Read-time integrity pass

Rules from FR-11 / FR-12, implemented by [`Validation.validate/2`](../../app/lib/digital_oil_sticker/local_store/validation.ex) invoking [`Schema.V1`](../../app/lib/digital_oil_sticker/local_store/schema/v1.ex). Failing records **quarantine**, never repair-on-read, never silently drop.

| Rule (atom) | Meaning |
| --- | --- |
| `:not_a_map` | Record is not a JSON object. |
| `:invalid_uuid` | A required id (`vehicle_id`, `event_id`, `reading_id`, `usage_id`, `reminder_id`) is missing or does not match the UUIDv4 shape `[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}`. |
| `:unparseable_instant` | A required or present instant/date does not parse as ISO 8601. |
| `:invalid_odometer` | `odometer_m` missing, non-integer, or negative. (Mileage is a non-negative integer in the documented base unit **metres**.) |
| `:invalid_unit` | A unit field is not `"mi"` or `"km"`. |
| `:invalid_provenance_mode` | `provenance_mode` is not `"catalog"` or `"manual"`. |
| `:invalid_archived` | `archived` is present but not a boolean. |
| `:invalid_enabled` | `enabled` is present but not a boolean. |
| `:invalid_seq` | `meta.seq` is present but not a non-negative integer. |
| `:bad_version` | `meta.schema_version` is present but not a positive integer. |
| `:orphan_vehicle_id` | A vehicle-scoped record's `vehicle_id` is not among the validated `vehicles`. Quarantined, never re-linked by inference, offered to the repair path. |

**Quarantine entry contents** ([`Quarantine`](../../app/lib/digital_oil_sticker/local_store/quarantine.ex)): `{store, id, rule}` and nothing else. `Inspect` is derived to render only those three fields. Record contents are never carried through quarantine so nothing personal can leak through inspection, logging, or error reports (INV-4).

Valid records hydrate as canonical data; failing records return in a quarantine list. The count and nature are surfaced (`StorageStatusLive`); the raw payload stays exportable for recovery.

## Hard caps

Rules from FR-14 / AC-10, implemented by [`Caps.check/2`](../../app/lib/digital_oil_sticker/local_store/caps.ex). A payload exceeding a cap is **rejected explicitly** with the specific cap named; silent truncation is prohibited. The rejected payload maps to `local_state: :hydration_refused` (never `:storage_unavailable` — that would be a lie about what happened, per `Copy.hydration_refused_body/1`).

| Cap | Value | Symbol |
| --- | --- | --- |
| Decoded payload size | 1 MiB (1,048,576 bytes) | `:payload_bytes` |
| Vehicles | 200 | `:vehicles` |
| Service events | 5,000 | `:events` |
| Odometer readings | 20,000 | `:readings` |

## The envelope

Envelope shape ratified in ADR-0004 §"Payload envelope"; implemented by [`Envelope`](../../app/lib/digital_oil_sticker/local_store/envelope.ex) (server) and [`envelope.js`](../../app/assets/js/local_store/envelope.js) (client). One shape carries hydrate, write-back, and export.

**Top-level keys** (`@allowed_top_level_keys` — any other key is `{:error, {:unknown_top_level_key, key}}`):

| Key | Type | Required | Notes |
| --- | --- | --- | --- |
| `envelope` | string, literal `"dos_local"` | yes | Envelope marker. |
| `schema_version` | positive integer | yes | Logical version. |
| `seq` | non-negative integer | yes | Monotonic write counter; drives compare-and-set. |
| `tab_id` | string | yes (hydrate) | **Ephemeral per-tab identifier.** Never persisted to a store. Never included in an export file. Never written to a cookie. |
| `generated_at` | ISO 8601 instant | yes | When this envelope was assembled. |
| `data` | map keyed by collection name | yes | The record payload. |
| `storage` | map (session context) | no | Transient sibling — mode, quota, persistence grant, availability probes. Held on the decoded struct for the session; never part of any write-back or export. |

**Data collections** (`@collections`; any unknown collection name inside `data` is `{:error, {:unknown_top_level_key, name}}`):

| Collection | Shape |
| --- | --- |
| `meta` | singleton object or `null` |
| `prefs` | singleton object or `null` |
| `vehicles` | list of records |
| `events` | list of records |
| `readings` | list of records |
| `usage` | list of records |
| `reminders` | list of records |

Missing list collections default to `[]`; missing singletons default to `null`. Record contents pass through decode untouched — per-record validation belongs to `Validation` / `Schema.V1`, never to decode.

**Write-back payload** ([`Envelope.build_put/4`](../../app/lib/digital_oil_sticker/local_store/envelope.ex)) is the server → client `local_store:put` instruction:

```json
{
  "mutation_id": "…",
  "seq": N,
  "upserts": [{"store": "events", "record": {…}}, …],
  "deletes": [{"store": "events", "key": "event_id-…"}, …]
}
```

`storage` is deliberately not representable here — write-back carries records and keys only.

## Export and import

Rules from FR-17 / AC-11, implemented by [`export.js`](../../app/assets/js/local_store/export.js). Export is the sole portability path (INV-5, ADR-0004 Decision §5); import is the sole recovery path when a store has been evicted or cleared.

**Export file shape** (produced client-side, no server round trip):

```json
{
  "envelope": "dos_local",
  "schema_version": 1,
  "seq": N,
  "generated_at": "…",
  "data": {…},
  "exported_at": "…",
  "sha256": "…hex-of-payload-with-hash-and-tab_id-and-storage-excluded…"
}
```

Rules:

1. **`tab_id` and `storage` are stripped.** Both are ephemeral; a file the user keeps or shares must carry nothing that was not their own record or preference. See `export.js` — `const {tab_id: _tabId, storage: _storage, ...exportable} = envelopeData`.
2. **Canonical serialization for the hash.** `sha256` is computed over `JSON.stringify(exportable)` — the payload *excluding* the `sha256` field, `exported_at`, `tab_id`, and `storage`. This is the canonical serialization; a file that re-hashes to a different value is corrupt or tampered with.
3. **No server transmission.** Export is a client-side download; the file's contents are never transmitted to any server by the product.
4. **File name:** `dos-export-YYYY-MM-DD.json` (date from `generated_at`).

**Import** (owned by `StorageStatusLive` and the client adapter; contract for `DOS-M09-002`):

1. Validate the envelope, `schema_version`, caps, and hash **before writing anything**.
2. Preview counts per store to the user.
3. Require an explicit **replace-or-merge** choice — never merge silently.
4. Reject on: mismatched hash, unknown or ahead-of-server `schema_version`, cap exceeded, or duplicate primary key in a merge that the user did not resolve.

## Distinguishing storage states

Rule from FR-15 / AC-9: a **first visit** and a **cleared/evicted store** must be distinguishable. The combination of `dos_boot_state` in `localStorage` plus the presence-or-absence of a `meta` record makes them separable in code (and therefore separable in copy in [DOS-M09-004](../../planning/issues/DOS-M09-004.md)).

| State | `dos_boot_state` | `dos_local` open | `meta` record | Data | Assigns `local_state` |
| --- | --- | --- | --- | --- | --- |
| First visit | `"never"` | opens empty | absent | empty | `:empty` |
| Populated | `"has_data"` | opens | present | non-empty | `:loaded` |
| **Data missing** (eviction, cleared site data) | `"has_data"` | opens empty | absent | empty | `:data_missing` |
| Storage blocked (private browsing, blocked storage) | either | `unavailable` / `blocked` | — | — | `:storage_unavailable` |
| Session-only storage (no persistence) | either | opens but writes rejected | — | — | `:storage_unavailable` |
| Newer than deployment | either | opens | schema_version > server | — | `:loaded` + `read_only: true` |
| Cap exceeded | either | opens | present | over a cap | `:hydration_refused` |
| Upgrade failed | either | opens at prior structural version | prior | prior (byte-identical) | `:storage_unavailable` |

The `:data_missing` case is the one that used to be indistinguishable from a first visit and was the whole reason for `dos_boot_state`. The rule (INV-25): an empty-or-evicted store must never render "your first visit" prose — that would invite the user to start over on top of records they may still have somewhere.

## ADR-0004 addendum obligations

Every extension this schema makes to ADR-0004's original storage-layout table or envelope is recorded here (FR-20 / AC-14). ADR-0004 amendments are additions to this list, not silent edits to the ADR body (CHANGE_CONTROL Rule 2a).

1. **`usage` object store.** Not in ADR-0004's original layout table. Added to hold usage-profile rows (baseline distance, severe-answers, condition, effective-from/to). Rationale: the pre-pivot `UserRepo` had `usage_profiles` and forecast quality depends on capturing them; embedding inside `vehicles` would inflate the vehicle record and lose the effective-dated history shape. Envelope collection: `usage`.
2. **`prefs.active_vehicle_id` field.** Added after v1 shipped as a soft pointer to the currently active vehicle. Additive: no `schema_version` bump. Older payloads validate unchanged; older deployments carry the field verbatim through `__unknown__`. Rationale: the switcher on the sticker page needs a persistent "current garage" pointer that survives reload; a hardcoded singleton field would be unenforceable and encoding it as `archived` state was ambiguous.
3. **`vin_last6` field on `vehicles`.** Nullable and off by default. Full VIN storage is prohibited by default (INV-3); enabling `vin_last6` beyond opt-in requires its own privacy issue covering consent, export, and deletion.
4. **`meta.log` bounded ring.** For migration and repair outcomes. Non-personal: versions, outcomes, and counts only — never automotive content, never field values. Safe to display in `StorageStatusLive` and safe to include in an export (INV-4).

## Fixtures (owed to close AC-5, AC-8, AC-12)

The full fixture set the M09-001 acceptance criteria enumerate is **not yet delivered as a single fixture directory**. The pieces that exist today:

- **Per-version canonical payload:** `test/digital_oil_sticker/local_store/envelope_test.exs` builds a valid v1 envelope. When v2 lands, a `test/support/fixtures/local_store/v1.json` + `v2.json` pair is the migration-chain input; the migration test asserts `migrate(v1_payload) == v2_payload` and `migrate(v2_payload) == v2_payload` (idempotence).
- **Corrupt-record set:** `envelope_test.exs` + `validation_test.exs` exercise every integrity rule listed above; the assertion pattern is that the valid subset hydrates and the offending records return in the quarantine list naming the rule.
- **Stress fixture for §9 footprint:** owed by [DOS-M09-002](../../planning/issues/DOS-M09-002.md) — a payload sized against the 5 MiB working ceiling / 1 MiB per 1,000 records budget, with the measured figure attached to that issue's evidence. This document names the budget; measuring it belongs to the adapter card.

## Open questions

The M09-001 issue calls out three open questions this document is obligated to close before the adapter ships:

1. **Persisting derived forecast records at MVP.** **Decision:** no. Forecasts are recomputed on load from stored inputs (`Due.compute/2` in [`due.ex`](../../app/lib/digital_oil_sticker/due.ex)). Adding a `forecasts` store later is a forward-only version bump. Rationale: a derived store adds footprint, an invalidation rule, and a migration surface for data that is reproducible; the audit-trail argument is weaker than the footprint argument for MVP.
2. **Usage-profile history depth.** **Decision:** the `usage` store shape supports full effective-dated history (`effective_from` / `effective_to` + `by_vehicle_effective` index). Whether the adapter writes a new row on every change vs. mutating the current row is deferred to [DOS-M09-002](../../planning/issues/DOS-M09-002.md); the schema is not the blocker.
3. **`usage` store's addendum path.** **Decision:** recorded here in §"ADR-0004 addendum obligations" §1. This document is the addendum; ADR-0004's storage-layout table is not edited in place. If a future revision of ADR-0004 supersedes this addendum, it does so by referencing this file and the ADR-0004 Amendment mechanism (CHANGE_CONTROL Rule 2a).

## What this schema is NOT

- **Not a place for anything the server transmits.** No server-derivable key, no session token, no anonymous-ID cookie value, no push subscription, no device fingerprint. INV-3 makes this a build failure via the enforcement gates in [MODULE-MAP.md](../architecture/MODULE-MAP.md#enforcement-gates-release-blocking).
- **Not a place for automotive facts.** Every interval, viscosity, capacity, product claim, and fitment in a record is a **snapshot** of a provenance-carrying catalog value or an explicitly user-entered value labeled as such (INV-15). No field asserts a manufacturer specification.
- **Not a place for scheduled notifications.** OS-scheduled notifications do not exist in this platform (INV-17). Reminder rows are **intent**; rendering is in-app due state.
- **Not a place for full VIN.** At most `vin_last6`, nullable, off by default; enabling more requires its own privacy issue.
- **Not a place for anything a browser cannot hold.** Service workers, `localStorage` records, OPFS, WASM SQLite are all out of scope (INV-19, INV-23).

## Cross-references

- [MODULE-MAP.md](../architecture/MODULE-MAP.md) — where `LocalStore.*` sits in the domain/web split.
- [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) §"The client-storage + LiveView hydration protocol" — the ratified protocol this schema implements.
- [DATA_DICTIONARY.md](DATA_DICTIONARY.md) — the `CatalogRepo` field-level dictionary; redirects browser-storage questions here.
- [DOS-M09-002](../../planning/issues/DOS-M09-002.md) — the adapter written against this contract.
- [DOS-M09-003](../../planning/issues/DOS-M09-003.md) — the hydration protocol carrying this envelope.
- [DOS-M09-004](../../planning/issues/DOS-M09-004.md) — the copy for the states this schema makes distinguishable.
