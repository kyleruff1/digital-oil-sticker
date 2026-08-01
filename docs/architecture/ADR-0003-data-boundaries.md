# ADR-0003 — Vehicle and maintenance-data boundaries

**Status:** Proposed — pending DOS-M00-006 ratification · **Implements:** [DOS-M00-006](https://github.com/kyleruff1/digital-oil-sticker/issues/7) · **Cites:** INV-8, INV-9, INV-10, INV-11, INV-12, INV-15, INV-16 ([CONSTITUTION.md](../product/CONSTITUTION.md))

## Decision

Vehicle **identity** and maintenance/oil/filter **facts** are different datasets with different sources, rights, and confidence. NHTSA vPIC is the identity spine only. Maintenance intervals, oil specifications/capacities, oil-product claims, and filter fitments each require their own authoritative, licensed source with provenance and a conflict policy, or they are honestly shown as unknown/unsupported/user-entered. The measured proof slice (below) is the factual foundation M03 executes against.

## Measured evidence (spike `spikes/m00-006-data-boundary/`, retrieved 2026-07-31)

17 cached official responses; deterministic import (`import.mjs`, byte-identical rebuild, normalized SHA `25c737989c608b11…`); 435 normalized facts, all provenance-bearing; 10/10 automated checks pass (`checks.mjs`).

| Evidence | Measurement |
| --- | --- |
| vPIC variable surface | 144 VIN-decode variables; **zero** oil-interval, viscosity, capacity, oil-product, or filter-fitment fields |
| Identity coverage | year/make/model reliably populated across the window (Toyota 1997: 20 models; Toyota 2024; Ford 2010; Honda 2024; BMW 2015; Tesla 2024 — 64 makes, 363 model rows in slice) |
| Missing-field behavior | published 2013 F-150 sample decodes with `Trim`, `Series`, `EngineModel` unsubmitted → stored as `null`, displayed as unknown (never inferred) |
| Ambiguity | model-level rows do not enumerate retail trims/engines; FuelEconomy.gov menu shows Camry 2020 resolves to multiple engine/transmission options — enrichment candidate, not oil facts |
| EV handling | Tesla Model 3 decodes `Electric`/`BEV` → `engine_oil_service: not_applicable`; no oil plan invented |
| Discontinued make | Pontiac 2008 returns models; Pontiac 2024 returns 0 — an explicit empty result, not a default |
| Decode errors | check-digit warning surfaces as a recorded `decode_error`, not silently discarded |

## Canonical entities and evidence requirements (FR-1)

Every catalog fact requires: value, market, effective dates, source URL/document locator, source revision, license/rights reference, and retrieval time (the `data_sources` + `_provenance` model in [DATA_DICTIONARY.md](../data/DATA_DICTIONARY.md)). Entities: model year, make, model, vehicle/trim/series, engine/fuel/drivetrain attributes, manufacturer oil-change interval, severe-service interval, oil viscosity/specification, oil brand/product claim, filter brand/part fitment.

## Confidence tiers (FR-3 — never collapsed into one "compatible" boolean)

1. `verified_exact_configuration` — licensed source matches the exact configuration.
2. `verified_model_engine_family` — licensed source matches model/engine family; qualifier missing.
3. `general_model_guidance` — model-level guidance only; labeled as such.
4. `user_entered_unverified` — manual entry; isolated from curated claims; never relabeled as verified.

These map to the resolver states (`verified`, `partial`, `conflict`, `unsupported`, `not_applicable`) and support statuses (INV-11).

## Source-gap matrix (FR-4)

| Fact domain | vPIC? | Candidate sources (lane) | Rights/update/conflict policy required before shipping |
| --- | --- | --- | --- |
| Identity (year/make/model/VIN attrs) | **Yes** — proven | vPIC API (green) | §105 US-gov work; attribution + revision recorded; refresh per catalog release |
| Engine/fuel/drive/transmission enrichment | Partial (when submitted) | FuelEconomy.gov bulk + EPA cert files (green) | same; reconciliation only, never oil facts |
| OEM intervals + severe service | **No** | Public OEM manuals/maintenance guides (documented-facts); MOTOR schedules (procurement candidate) | per-document provenance, version, market; conflict → `conflict`, no auto recommendation |
| Oil viscosity/spec/capacity | **No** | OEM manuals (documented-facts); MOTOR fluids (candidate) | as above |
| Oil product claims | **No** | API EOLCS directory + brand TDS (documented-facts) | SKU-level claims + effective status; certification ≠ vehicle compatibility |
| Filter fitment | **No** | Supplier downloadable guides / written-permission exports (documented-facts / permission-needed) | part-to-configuration only; no text-similarity inference |

Unfilled cells stay open gaps that keep the corresponding M03 tickets gated (DOS-M03-001 rights matrix decides each lane).

## Fallbacks (FR-5) and layering (FR-8)

Custom vehicle creation and manual manual-derived intervals/specs are always available, labeled **"your setting"**, stored in the user layer, never mingled with curated claims. Three layers stay separate: raw source data → normalized catalog → user-entered overrides. UI language distinguishes "manufacturer guidance" / "product-maker claim" / "your setting" (INV-21).

## Testable coverage definitions (FR-6 — ratifies INV-8/9/10 operationally)

- **Market:** United States. **Window:** rolling 30 model years; 1997–2026 for the 2026 baseline; the window advances when a new catalog `data_version` is cut (refresh policy: re-run the M03 pipeline per release; the "major manufacturers" list re-measures then).
- **Major manufacturer (testable):** a make with ≥1 model listed in vPIC `GetModelsForMakeYear` for ≥15 of the 30 window years **or** present in the FuelEconomy.gov U.S. dataset for the same span; measured, not assumed. Discontinued/renamed makes (e.g., Pontiac, Dodge→Ram trucks) remain selectable for their production years via alias/crosswalk rows; empty years stay empty.
- Trim/build completeness depends on authoritative source coverage and cannot be inferred (measured per configuration in DOS-M03-005/006).

## Legal/redistribution assumptions (mandatory review gate)

vPIC and FuelEconomy.gov responses are official U.S. government structured data; under 17 U.S.C. §105 copyright protection is generally unavailable for U.S. Government works. We record source, access method, agency attribution, and revision; we assert no endorsement; trademarks (make/brand names) are used nominatively for identification only. **No full import ticket (DOS-M03-005+) unblocks until the owner reviews and accepts these assumptions** (recorded on issue #7). Cached fixtures here are a 17-response research slice, not a bulk redistribution.

## Consequences

- M03 acquisition tickets inherit this matrix; nothing ships from an ambiguous source (SOURCE_REGISTER.md dispositions govern).
- DOS-M00-004 uses the slice fixtures for persistence realism; M02 inherits the confidence tiers and unknown/conflict UX contracts.
- If a required entity ends up with no lawful candidate source, the coverage claim is unratifiable at this scope and returns to the M00 gate as a scope decision — it is never papered over with defaults.
