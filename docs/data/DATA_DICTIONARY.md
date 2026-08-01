# Data Dictionary

Status: **baseline — M03/M04 may refine names but not semantics.** The boundaries and semantics below are fixed; renames require the refining issue to preserve them explicitly.

Two local SQLite databases run on-device (see ADR-0001 and [Mob Ecto/SQLite persistence and on-device migrations](https://mob.hexdocs.pm/data.html)):

- **`CatalogRepo`** — replaceable, read-mostly reference data bundled with the application.
- **`UserRepo`** — durable local profile, garage, plan, history, mileage, forecasts, and reminder metadata. It is never replaced by a catalog update.

Use `pool_size: 1` for each SQLite Repo. Do not create cross-database foreign keys. User rows store a stable catalog key plus a readable snapshot so old history remains understandable when a catalog changes.

## `CatalogRepo` tables

| Table | Required fields and constraints |
| --- | --- |
| `catalog_metadata` | `key` primary key, `value`; includes `schema_version`, `data_version`, `generated_at`, `min_app_version`, and content hash. |
| `data_sources` | Stable `id`; provider/type/name; canonical URL or document locator; license reference; provider version; retrieved/effective/verified timestamps; SHA-256; attribution; authority and review status. |
| `makes` | Stable `id`, nullable unique `vpic_make_id`, display/normalized names, support status. Index normalized name. |
| `models` | Stable `id`, `make_id`, nullable `vpic_model_id`, display/normalized names. Unique provider identity and index `(make_id, normalized_name)`. |
| `vehicle_configurations` | Stable `configuration_key`; year, make/model IDs, trim/series/body/drive/fuel/electrification/engine fields when known; vehicle type; provider namespace/key; completeness code; search text. Index `(model_year, make_id, model_id)` and provider key. Unknown is nullable, not false. |
| `maintenance_schedules` | Configuration/rule key, `service_type = engine_oil`, normal/severe/flexible condition, nullable miles/months, oil-life-monitor flag, recommendation text, source ID/locator, effective dates and verification state. At least one threshold or a documented indicator rule is required. |
| `oil_requirements` | Schedule/configuration link; SAE viscosity, API/ILSAC/ACEA/OEM codes as separately normalized facts, capacity value/unit and with/without-filter qualifier, notes and source. Do not copy restricted standard text. |
| `oil_brands`, `oil_products`, `oil_product_claims` | Stable brand/product/SKU, market/status/effective dates, viscosity and certification/approval claims, claim source and last verification. A brand row alone is never compatible. |
| `filter_brands`, `filter_products`, `filter_fitments` | Stable brand/part number, configuration/provider application key, position/service type, qualifiers, source and effective status. |
| `aliases` | Entity type/key, normalized alias, source; unique alias within entity type and indexed for lookup. |
| optional FTS tables | Add only after the Mob/exqlite build proves FTS5 support. Cascading indexed selectors must work without FTS. |

The catalog builder emits rejected-row reports, coverage counts, collisions, source diffs, a manifest, and a deterministic SQLite artifact. Catalog records are immutable within one `data_version`.

## `UserRepo` tables

| Table | Required fields and constraints |
| --- | --- |
| `local_profiles` | UUID, optional display name, unit system, IANA time zone, onboarding version, timestamps. One active profile in MVP; no credentials. |
| `vehicles` | UUID, profile ID, nullable stable `configuration_key`, catalog version, nickname, year/make/model/configuration snapshots, support status, optional local-only VIN with explicit consent, timestamps/archival state. |
| `maintenance_plans` | Vehicle ID, operating condition, sourced miles/months/OLM rule snapshots, requirement/source/version snapshots, optional explicit user override with reason, active cycle and timestamps. |
| `service_events` | UUID, vehicle ID, performed local date, normalized odometer plus unit, oil brand/product/viscosity snapshots, filter brand/product snapshots, notes, provenance mode (`catalog` or `manual`), timestamps and correction lineage. |
| `odometer_readings` | UUID, vehicle ID, observed instant/local date, normalized odometer, input unit, source (`service_event` or `manual`), validity/supersession fields. Index `(vehicle_id, observed_at)`. |
| `usage_profiles` | Vehicle ID, user baseline distance/week, unit, severe-use answers and selected condition, effective timestamps. Preserve answers that selected the condition. |
| `forecast_snapshots` | Vehicle/cycle ID, algorithm version, input hash, computation time, effective rate, due odometer, projected/calendar/effective dates, confidence code, reason code. Snapshots are explainability/audit records, not the only source of truth. |
| `reminder_rules` | UUID, vehicle ID, reminder kind, lead value/unit, preferred local time, enabled flag. Multi-vehicle-safe from the first migration. |
| `scheduled_notifications` | Stable notification ID primary key, vehicle/cycle/rule IDs, desired and scheduled instants, due-date snapshot, payload version, platform state, last error/reconciliation time. |
| `schema_events` | Migration/catalog compatibility/recovery events with version and non-sensitive result; no automotive/user content. |

## Unit and time rules

- **Integer base units for mileage.** Use integer base units for persisted mileage (for example metres or a documented fixed unit) and convert at the boundary so switching miles/kilometres never loses precision.
- **UTC instants plus IANA time zone.** Store UTC instants for events plus the IANA time zone used to derive a local notification time; store service dates as dates when time-of-day is not meaningful.

## Migration and catalog rules

- `UserRepo` uses forward Ecto migrations run explicitly before the UI becomes writable. Test fresh install and every supported upgrade path. Before a risky migration, create a local atomic backup and document recovery; never silently reset user history.
- `CatalogRepo` is not patched by user migrations. On first launch, verify and copy the bundled artifact into application support. When a newer compatible bundled catalog exists after an app upgrade, stage, integrity-check, atomically rename, and retain the previous catalog for rollback.
- An optional network update follows the same protocol in M08: signed manifest, hash, size, schema/min-app compatibility, staged integrity check, atomic activation, rollback. It never overwrites `UserRepo`.
