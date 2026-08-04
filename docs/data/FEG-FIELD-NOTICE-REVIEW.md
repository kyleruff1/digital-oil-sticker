# FuelEconomy.gov field-level notice review

Adopted by the owner 2026-08-04, DOS-M09-010 AC-4-notice. This document enumerates every field the Digital Oil Sticker catalog ingests from FuelEconomy.gov (FEG) and confirms, per field, whether a per-field attribution or notice is required beyond the umbrella source-level authorization already recorded in [FACTUAL_USE_AND_MARKS_POLICY.md §"FuelEconomy.gov (DOE/EPA) — approved"](FACTUAL_USE_AND_MARKS_POLICY.md#source-level-authorization). It is a planning/engineering review, not a legal opinion.

## Umbrella authorization

FEG is a U.S. Department of Energy site jointly operated by DOE and EPA. The DOE public web policy states that government information published on DOE sites is public domain with attribution requested, and separately calls out that third-party-marked material inside such datasets is excepted. FEG offers documented bulk downloads (`vehicles.csv`) for all model years, which is the acquisition channel the catalog uses. That combination is the umbrella basis under which every field below is ingested; a field is either covered by that umbrella or it is explicitly flagged in the "Notice mechanism" column as requiring separate handling.

Attribution obligations under the umbrella are discharged by three surfaces the app already ships (see `app/lib/digital_oil_sticker_web/copy.ex` §`no_affiliation`, `app/lib/digital_oil_sticker/catalog/queries/provenance.ex` §`all_sources/0`, and `data_sources.attribution_text` / `data_sources.web_attribution_text` for the FEG row):

- **Attribution page** (planned `/attribution`, DOS-M09-010 AC-5). Renders the FEG row's `web_attribution_text` — currently `Configurations: FuelEconomy.gov (DOE/EPA)` — alongside the full `attribution_text` — currently `Vehicle configuration data from FuelEconomy.gov (U.S. DOE/EPA). DOE and EPA do not endorse this application.`
- **No-affiliation statement** (`Copy.no_affiliation/0`, rendered verbatim on the attribution page and today on `/settings/storage`). This is the single, joint no-endorsement clause referenced from every field in the table below that carries a trademark or endorsement concern.
- **Per-source `data_sources` row** (`source_key: 'fueleconomy_gov_bulk'`) — carries `provider`, `dataset_name`, `canonical_url`, `retrieved_at`, `raw_sha256`, `attribution_text`, `web_attribution_text`, and the six disposition axes. Same row for every field ingested from `vehicles.csv`; no field is served without it.

**Umbrella source (all fields below):** `https://www.fueleconomy.gov/feg/epadata/vehicles.csv` (bulk download, one request per catalog rebuild). Documentation for the field semantics lives at `https://www.fueleconomy.gov/feg/ws/index.shtml` (web-services data dictionary; the bulk CSV uses the same column names as the JSON web services).

## Field-by-field review

Every field below is ingested from a single row of `vehicles.csv` and mapped into `vehicle_configurations` (or into the identity spine at the join step). "Umbrella" in the notice column means the field is a plain factual observation whose only attribution obligation is the source-level `attribution_text` rendered on the attribution page; no per-vehicle badge or per-field callout is required. "Flagged" means the field crosses into third-party-marked material and requires the additional mechanism named on the same line.

| Field name (`vehicles.csv` column) | Ingested into (`vehicle_configurations` unless noted) | FEG source | Notice / attribution required? | If yes: how the notice appears in the app |
| --- | --- | --- | --- | --- |
| `id` | `provider_key` (namespaced `fueleconomy.gov`) and part of `configuration_key` | `https://www.fueleconomy.gov/feg/epadata/vehicles.csv`, `id` column | No (umbrella) | Attribution page only, via the `fueleconomy_gov_bulk` source row. Not user-visible as a value. |
| `year` | `model_year` | Same CSV, `year` column | No (umbrella) | Attribution page only. |
| `make` | Join key to `makes.display_name` / `.normalized_name` (identity spine) | Same CSV, `make` column | **Flagged — third-party mark.** DOE web policy excepts third-party-marked material. | `Copy.no_affiliation/0` rendered verbatim on the attribution page and on `/settings/storage` covers the joint no-endorsement clause for every vehicle mark. No per-vehicle badge is added; the plain-text-reference posture recorded on the `data_sources` row (`trademark_posture = 'plain_text_reference'`) plus the app-wide no-affiliation clause is the discharge mechanism. Build test at `app/test/digital_oil_sticker_web/copy_lint_test.exs` enforces that no third-party logo asset ships. |
| `model` | Join key to `models.display_name` / `.normalized_name`; if it differs from `models.display_name`, ingested as `trim` on the configuration | Same CSV, `model` column | **Flagged — third-party mark.** Same rationale as `make`. | Same mechanism as `make` — the app-wide no-affiliation clause plus the plain-text-reference posture on the `data_sources` row. |
| `baseModel` | Join key to `models.display_name` / `.normalized_name` (preferred over `model` when both match a known model) | Same CSV, `baseModel` column | **Flagged — third-party mark.** Same rationale as `make`. | Same mechanism as `make`. |
| `cylinders` | `engine_cylinders` | Same CSV, `cylinders` column | No (umbrella) | Attribution page only. |
| `displ` | `displacement_l` | Same CSV, `displ` column | No (umbrella) | Attribution page only. |
| `drive` | `drive_type` | Same CSV, `drive` column | No (umbrella) | Attribution page only. |
| `fuelType1` | `fuel_primary`, and drives derived `electrification_level = 'BEV'` when `Electricity` and no `fuelType2` | Same CSV, `fuelType1` column | No (umbrella) | Attribution page only. |
| `fuelType2` | `fuel_secondary` | Same CSV, `fuelType2` column | No (umbrella) | Attribution page only. |
| `eng_dscr` | `engine_descriptor` | Same CSV, `eng_dscr` column | No (umbrella) | Attribution page only. Values are FEG's own free-text notes about the engine and do not contain third-party mark material beyond the make/model already recorded above. |
| `trany` | `transmission` | Same CSV, `trany` column | No (umbrella) | Attribution page only. |
| `trans_dscr` | `transmission_descriptor` | Same CSV, `trans_dscr` column | No (umbrella) | Attribution page only. |
| `VClass` | `body_class` and `epa_size_class` (same value copied into both columns) | Same CSV, `VClass` column | No (umbrella) | Attribution page only. EPA size-class labels are the government's own taxonomy — not a third-party mark. |
| `atvType` | Derived into `electrification_level` (`EV` → `BEV`, `Hybrid` → `HEV`); not stored raw | Same CSV, `atvType` column | No (umbrella) | Attribution page only. |
| `startStop` | `start_stop` | Same CSV, `startStop` column | No (umbrella) | Attribution page only. |

## File-level provenance (not per-field, but recorded on the same source row)

The following metadata is recorded once for every FEG catalog rebuild on the `data_sources` row (`source_key = 'fueleconomy_gov_bulk'`) and covers all rows ingested in that rebuild:

| Metadatum | Column on `data_sources` | Discharged via |
| --- | --- | --- |
| Canonical download URL | `canonical_url` | Attribution page renders it under the provider name. |
| Retrieval timestamp | `retrieved_at` / `verified_at` | Attribution page can render `Copy.as_of(date)` next to the provider (planned, DOS-M09-010 AC-5). |
| Bulk-file SHA-256 | `raw_sha256` | Not user-visible; recorded for reproducibility of the rebuild (`tools/catalog/data/raw/feg-vehicles-csv.meta.json`). |
| Six disposition axes | `copyright_basis = 'government_public_domain'`, `acquisition_basis = 'official_bulk_download'`, `redistribution_basis = 'factual_republication'`, `trademark_posture = 'plain_text_reference'`, `claim_posture = 'identity_only'`, `review_status = 'approved'` | Enforced at the source-gate; a field is served only when its source row passes. |

## Fields FEG offers but we deliberately do not ingest

FEG's `vehicles.csv` publishes fuel-economy test results (`comb08`, `city08`, `highway08`, `fuelCost08`, `co2TailpipeGpm`, etc.). The catalog ingests none of them — the app's job is identity + oil, not fuel economy or emissions — so this review does not extend to them. If a future card ever ingests any of those columns, that card must extend this document with a row for each new column and confirm the same umbrella/flagged disposition or arrange a separate notice.

## Follow-up review triggers

Extend this document (do not silently add columns to the ingestion list) whenever any of the following happens:

1. A new column from `vehicles.csv` is added to the `need` list in `tools/catalog/src/sources/fueleconomy.mjs`.
2. FEG updates its data-dictionary URL, its bulk-download URL, or its documented terms in a way that changes the umbrella authorization recorded above.
3. The DOE public web policy changes materially with respect to attribution or third-party-marked material.
4. Any FEG field starts driving a user-facing claim stronger than identity (e.g. an oil interval, a warranty statement, or a manufacturer recommendation) — that would push the `claim_posture` off `identity_only` and require the notice mechanism to be re-reviewed.
