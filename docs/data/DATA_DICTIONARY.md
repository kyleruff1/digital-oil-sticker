# Data Dictionary

**Status:** Browser-first baseline, aligned with [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) and [CONSTITUTION.md](../product/CONSTITUTION.md) revision 2.0.0. Delivered as evidence for [DOS-M01-003](../../planning/issues/DOS-M01-003.md) AC-1, AC-3, AC-9.

## Two stores, one server, one browser

| Store | Location | Owner | Lifecycle | Personal data |
| --- | --- | --- | --- | --- |
| `CatalogRepo` | Server (Fly image), read-only SQLite artifact chmod 0444 | This document | Replaced by rolling a new Fly image with a new `data_version` | Never |
| `dos_local` (IndexedDB) | Browser (`digitaloilsticker.com` origin only) | [DOS-M09-001](../../planning/issues/DOS-M09-001.md) | Forward-only per-store version line; erased with site data | Only |

There is **no server-side `UserRepo`** and no personal-data Ecto schema anywhere in `DigitalOilSticker.*`. Personal state exists on the server only as transient socket assigns for one LiveView connection's lifetime and is never written to disk, database, cache, ETS, external store, or log (INV-3, INV-23, INV-4). Enforcement lives in `test/digital_oil_sticker/catalog/repo_readonly_test.exs` (repo list == `[CatalogRepo]`, opened read-only), `test/digital_oil_sticker/no_personal_persistence_test.exs`, and `test/digital_oil_sticker/no_personal_ecto_schema_test.exs`.

For browser-storage schema, keys, indexes, quarantine rules, and the forward-only IndexedDB version line, see **[BROWSER_STORAGE_SCHEMA.md](BROWSER_STORAGE_SCHEMA.md)** (the DOS-M09-001 committed specification) — this dictionary does not restate it.

## `CatalogRepo` field-level dictionary

Every table is `STRICT`. Unknown values are `NULL` — never `''`, `0`, or `false`. Stable IDs are UUIDv5 strings so a rebuild from the same inputs produces the same rows. Every row that could contradict itself across sources carries `source_id` referencing `data_sources`.

The schema of record lives at `tools/catalog/src/compile/schema.sql`. This document describes every column with the intent to be read alongside the schema, not to replace it. A field's semantics take precedence over its column name; if the two disagree, this document is wrong and must be updated in the same PR that changes the semantics.

### `catalog_metadata` — versioning and feature flags

| Column | Type | Semantics |
| --- | --- | --- |
| `key` | TEXT PK | Metadata key. Required keys: `schema_version`, `data_version`, `generated_at` (ISO 8601 UTC), `min_app_version`, `content_hash`, plus feature flags `feature_schedules`, `feature_oil_products`, `feature_filter_fitments` with values `present`/`absent`/`withheld`. |
| `value` | TEXT | The value. Always a string; numeric keys are decoded at read time. |

`feature_*` values distinguish "we queried and there is nothing" (`absent`) from "we have data but chose not to serve it" (`withheld` — rights-gated per [DOS-M09-010](../../planning/issues/DOS-M09-010.md)) from "we have it and serve it" (`present`). Only `absent` yields the honest `identity_only` UI state.

### `data_sources` — six-axis factual-use disposition

The rev-2 dispositions treat each source's legal posture as six independent axes rather than one aggregate flag. A row is served in the artifact only when its axes are collectively approved by the source-gate.

| Column | Semantics |
| --- | --- |
| `id` | UUIDv5 PK. |
| `source_key`, `provider`, `source_type`, `dataset_name`, `canonical_url` | Source identity and where it came from. |
| `source_version`, `raw_sha256`, `retrieved_at`, `effective_at`, `verified_at` | Reproducibility: same inputs re-run must produce the same version + hash. |
| `attribution_text`, `web_attribution_text` | Public-facing attribution string. `web_attribution_text` is what the /attribution page renders; `attribution_text` is the canonical text. |
| `copyright_basis` | `government_public_domain \| factual_extraction \| licensed \| limited_fair_use \| unknown` — the copyright question, standalone. |
| `acquisition_basis` | `public_api \| official_bulk_download \| manufacturer_publication \| direct_observation \| licensed_feed \| user_entry \| prohibited \| unknown` — how we obtained it. |
| `redistribution_basis` | `factual_republication \| express_permission \| license \| internal_verification_only \| prohibited \| unknown` — what we may re-publish. |
| `trademark_posture` | `plain_text_reference \| authorized_mark \| no_mark_used \| review_required` — how names/marks are used. |
| `claim_posture` | `identity_only \| unverified_product_fact \| manufacturer_claim \| independently_verified \| derived_match \| prohibited` — the strength of any product claim derived from this source. |
| `review_status` | `approved \| approved_with_conditions \| pending \| rejected` — the joint reviewer disposition. |
| `terms_sha256`, `evidence_ref`, `reviewed_at`, `reviewer` | Evidence: which terms text we reviewed, where the memo lives, who signed, when. |

A row served in the artifact must satisfy `redistribution_basis != 'prohibited'` **and** `review_status IN ('approved', 'approved_with_conditions')` **and** its `claim_posture` must be compatible with the surface it lands on (e.g. `identity_only` sources never populate `oil_requirements`).

### `makes` — vehicle manufacturer identity

| Column | Semantics |
| --- | --- |
| `id` | UUIDv5 PK. |
| `vpic_make_id` | Nullable INTEGER, UNIQUE. NULL when the make has no vPIC record. |
| `display_name` | The name we render. |
| `normalized_name` | Uppercased/collapsed name for lookup, UNIQUE + indexed. |
| `support_status` | `identity_only \| schedule_supported \| full_product_supported \| not_applicable \| unsupported`. `not_applicable` is BEV-only makes; `unsupported` is the heavy-commercial denylist (PETERBILT, KENWORTH). |
| `first_window_year`, `last_window_year`, `window_year_count` | Enumeration coverage window, for the UI's honest year picker. NULL until enumeration completes for that make. |
| `source_id` | REFERENCES `data_sources(id)`. |

### `models` — model identity per make

| Column | Semantics |
| --- | --- |
| `id` | UUIDv5 PK, unique across the catalog (not per-make). |
| `make_id` | REFERENCES `makes(id)`. |
| `vpic_model_id` | Nullable INTEGER; UNIQUE within `(make_id, vpic_model_id)`. |
| `display_name`, `normalized_name` | Display and lookup. UNIQUE + indexed within `(make_id, normalized_name)`. |
| `source_id` | REFERENCES `data_sources(id)`. |

### `vehicle_configurations` — the year-make-model-configuration row

The row a `Selector` for `list_configurations/4` resolves to.

| Column | Semantics |
| --- | --- |
| `configuration_key` | UUIDv5 PK. |
| `model_year` | INTEGER, CHECK 1900..2100. Enumeration window is 1997–current+1. |
| `make_id`, `model_id` | FKs into `CatalogRepo` only. |
| `vpic_vehicle_type_id`, `vehicle_type_name` | vPIC vehicle-type classification. |
| `trim`, `series`, `body_class`, `drive_type`, `fuel_primary`, `fuel_secondary`, `electrification_level`, `engine_cylinders`, `displacement_l`, `engine_descriptor`, `transmission`, `transmission_descriptor`, `epa_size_class`, `start_stop` | Configuration attributes. NULL when the source did not provide the field — never a placeholder. |
| `provider_namespace`, `provider_key` | External key (e.g. FuelEconomy.gov `id`). UNIQUE partial index where `provider_key IS NOT NULL`. |
| `completeness_code` | `identity_only \| configuration_enriched \| configuration_verified`. |
| `support_status` | Mirrors the make's status or narrows further. |
| `engine_oil_service` | `applicable \| not_applicable`. NULL means "we do not know," never "yes." A BEV configuration is `not_applicable` **only** when the source's electrification column says so — a NULL electrification level is never inferred as BEV. |
| `engine_class_code` | Nullable FK to our derived `engine_classes` classification. |
| `crosswalk_status` | `exact \| qualified \| ambiguous \| rejected \| manual_review`. The Selector suppresses `ambiguous` / `rejected` from the browsing surface. |
| `search_text` | Concatenated tokens for the cascading picker's non-FTS lookup path. |
| `source_id` | REFERENCES `data_sources(id)`. |

Indexes: `(model_year, make_id, model_id, configuration_key)` for the cascading picker; `(provider_namespace, provider_key)` unique-when-present.

### Our oil model — replaces the brand/product catalog

Six tables (`oil_model_metadata`, `oil_grades`, `oil_base_stocks`, `engine_classes`, `engine_class_grades`, `service_conditions`, `interval_rules`) define an **independently-authored** derivation from SAE J300 grades, published industry guidance on base-stock characteristics, and our own engine classification derived from EPA/DOE fields. No vendor brand/product catalog is licensed for this MVP; oil brands and families ship user-entered per [DOS-M09-010](../../planning/issues/DOS-M09-010.md) build 1.

| Table | Semantics |
| --- | --- |
| `oil_model_metadata` | Model version, source guidance references. |
| `oil_grades` | SAE J300 rows: `code` (e.g. `5W-30`), `winter`, `operating`, `common` boolean, notes. |
| `oil_base_stocks` | Conventional / synthetic blend / full synthetic / high mileage. Each carries a published miles low/high range and a months cap. |
| `engine_classes` | Our derived classification (gas port injection, gas direct injection, turbocharged, diesel, BEV, etc.). Each carries `engine_oil` applicability, an `interval_factor`, an optional `requires_service_category`, and a reasoning note. |
| `engine_class_grades` | Which grades an engine class accepts, ranked. |
| `service_conditions` | `normal` / `severe`. Each has a factor multiplier and a set of user-facing qualifying questions. |
| `interval_rules` | One row per (engine class × base stock × service condition). `miles_low` is the safety fallback; `miles_recommended` never exceeds the base stock's published range. UNIQUE and indexed. |

**Interval precedence** (the rule the UI must obey): a sourced manufacturer schedule always overrides the derived model; user-entered stricter overrides both; "the shorter always wins." This is asserted by [`Due`](../architecture/MODULE-MAP.md#domain-modules--digitaloilsticker) and its tests, not by data.

### `aliases` — cross-source rename / badge / spelling

| Column | Semantics |
| --- | --- |
| `id` | UUIDv5 PK. |
| `entity_type` | `make \| model \| oil_brand`. |
| `entity_id` | The canonical entity's UUIDv5. |
| `normalized_alias` | Uppercased alias. UNIQUE within `(entity_type, normalized_alias)`, indexed. |
| `display_alias` | The alias as originally written. |
| `alias_kind` | `rename \| badge \| marketing \| spelling \| crosswalk`. |
| `source_id` | REFERENCES `data_sources(id)`. |

### Present-but-empty in build 1: `maintenance_schedules`, `oil_requirements`, `filter_*`

These tables ship with full DDL and **zero rows** in build 1. Their absence is the honest `identity_only` state, signaled through `catalog_metadata.feature_schedules='absent'`, `feature_oil_products='withheld'` (rights-gated), `feature_filter_fitments='absent'`. Row-adding in M03 is not a schema-version bump.

- `maintenance_schedules`: per-configuration interval by service condition, oil-life-monitor flag, source locator. A row must satisfy `interval_miles IS NOT NULL OR interval_months IS NOT NULL OR oil_life_monitor = 1` — a missing interval is never zero.
- `oil_requirements`: viscosity / API service / OEM spec / capacity per configuration, with source locator.
- `filter_brands` / `filter_products` / `filter_fitments`: brand, part number, application-key fitment.

## Example rows for every provenance case

`CatalogRepo` fixtures live at `app/priv/catalog/catalog-fixture-{a,b}.sqlite3`. Real personal data never appears; every value is synthetic or public-catalog.

| Case | Where it appears | Shape |
| --- | --- | --- |
| **Exact match** | `vehicle_configurations` with `crosswalk_status='exact'` and every attribute non-NULL. | Fixture-a has 235 configurations. |
| **Ambiguous** | `vehicle_configurations` with `crosswalk_status='ambiguous'`. The Selector suppresses these from the picker. | Add to fixture-b in M03 backfill. |
| **Missing** | Any column NULL: `trim`, `engine_descriptor`, `transmission`, etc. — the browsing surface renders "Not specified" (INV-20). | Fixture-a rows with sparse configuration data. |
| **Custom (user-entered)** | Never in `CatalogRepo` — lives in browser IndexedDB per [DOS-M09-001](../../planning/issues/DOS-M09-001.md) with a per-record `provenance: user_entered` flag. | Out of scope for this repo. |
| **Retired** | A `make` or `model` row whose `support_status` transitions to `unsupported` in a new `data_version` — the row is retained (never deleted) so history renders. | Add a rename via `aliases` when the entity ID changes. |
| **Conflicting sources** | Two `data_sources` rows differ in a field the UI must choose between; the reconciler prefers `redistribution_basis='factual_republication'` from a `government_public_domain` source over a `limited_fair_use` source. | Documented in `tools/catalog/src/compile/` reconciler notes. |

## Boundary rules

1. **Foreign keys stay inside `CatalogRepo`.** No `CatalogRepo` FK ever names a personal-data table — none exist server-side.
2. **The reader is read-only at the driver level.** `journal_mode: nil` (defeats ecto_sqlite3's `put_new(:wal)`), `mode: :readonly`, `after_connect: PRAGMA query_only = ON`. Enforcement in `repo_readonly_test.exs`.
3. **A missing interval is never zero.** Enforced by the `maintenance_schedules` CHECK constraint.
4. **No personal identifier is representable as a query parameter.** The Selector's closed vocabulary (year/make/model/configuration/…) rejects every personal key; asserted by `impersonal_selector_test.exs` (INV-26).
5. **Rebuild determinism.** Same inputs + `SOURCE_DATE_EPOCH` + PK-sorted inserts produce byte-identical artifacts. Asserted by the CI double-build + SHA compare in `catalog_determinism_test.exs`.
6. **Schema versions are additive.** M03 adds rows to `maintenance_schedules` / `oil_requirements` / `filter_*` without a schema-version bump. Schema-shape changes require a new forward-only migration (never edits to shipped ones).

## What a `CatalogRepo` row is NOT

- Not a place to record any personal identifier: no VIN column, no vehicle_id column, no odometer column, no notes column, no user_id column, no client identifier column, no timestamp of a personal event, no free-text field a user filled in. If a future field would let a request-time query correlate a person across visits, that field belongs in browser IndexedDB or nowhere at all (INV-26).
- Not a place to reproduce restricted source prose. Only factual fields are stored; copyrighted schedule text, manufacturer service-manual language, and licensed data-sheet paragraphs are never re-published — extracts are limited to factual entries the copyright basis actually covers.

## Browser storage — see BROWSER_STORAGE_SCHEMA.md

For the IndexedDB object-store layout (`meta`, `vehicles`, `events`, `readings`, `usage`, `reminders`, `prefs`), the payload envelope, the schema-version line, the forward-only upgrade contract, the quarantine rules, and the storage caps — see [BROWSER_STORAGE_SCHEMA.md](BROWSER_STORAGE_SCHEMA.md) (DOS-M09-001). That specification and this document share nothing except the promise that catalog IDs are stable enough to snapshot from.
