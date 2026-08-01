# Digital Oil Sticker — Glossary

Terminology in this file is binding for UI copy, issue bodies, and documentation. American English throughout.

## Required display terminology

- **"Meets the recorded requirements"** — the only permitted compatibility phrasing for an oil or filter product that satisfies the vehicle's recorded requirement claims. It may not be phrased as "manufacturer approved" unless the source explicitly documents an OEM approval.
- **"Estimated due date"** — the required label for the mileage-projection date. It must always be shown with a confidence label, and may not be presented as an exact or guaranteed date.
- **"Source unavailable"** and **"Exact configuration not verified"** — the required phrasings when data is missing or the configuration cannot be proven. The app may never supply a generic value in their place.
- **Oil-life monitor**, **calendar interval**, **mileage interval**, **normal service**, and **severe service** — these five terms are kept distinct. They may not be merged, aliased, or used interchangeably in copy or data.
- **Provenance display** — every recommendation detail view identifies provider/document, source version/revision, retrieved/verified date, applicable market and condition, plus a route for reporting a data error.

## Recommendation resolver states

Given a vehicle configuration and operating condition, the resolver returns exactly one typed result:

- `verified` — exact licensed match with thresholds, requirements, and provenance.
- `partial` — identity is known but a required engine/configuration qualifier is missing.
- `conflict` — sources disagree; show no automatic product recommendation and retain both facts for review.
- `unsupported` — no licensed schedule for the selection.
- `not_applicable` — verified non-engine-oil vehicle such as a battery EV.

## Confidence levels

Confidence is a categorical, explainable result based on observation count, observation span, recency, and disagreement with the baseline. It is not a probability. The suggested levels are `baseline_only`, `low`, `medium`, and `high`; M06 freezes exact thresholds with tests.

## Catalog support statuses

Catalog presence and recommendation support are separate statuses. The five values are `identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, and `unsupported`. `not_applicable` marks a verified non-engine-oil vehicle (such as a battery EV), which may appear for honest identification but shows "engine oil service not applicable" and never receives an invented oil plan. Exact field-level definitions for the remaining statuses are frozen by the M00 coverage-contract ratification and the M03 vocabulary contract; no status may be used to imply data the catalog does not carry.

## Core nouns

- **Catalog** — the read-only, versioned reference dataset bundled with the application and served through `CatalogRepo`: vehicle identity (makes, models, vehicle configurations), maintenance schedules, oil requirements, oil and filter products and their claims/fitments, aliases, data sources, and catalog metadata. Catalog records are immutable within one `data_version`, and the catalog is never patched by user migrations.
- **Plan (maintenance plan)** — a per-vehicle user record holding the operating condition, sourced miles/months/oil-life-monitor rule snapshots, requirement/source/version snapshots, an optional explicit user override with reason, and the active cycle.
- **Service cycle** — the active span between one recorded oil change and the next for a vehicle. Recording a new oil change closes the previous cycle, starts a new one, recomputes the forecast, and replaces obsolete notification requests atomically.
- **Service event** — one recorded oil change: performed local date, normalized odometer plus unit, oil brand/product/viscosity snapshots, filter brand/product snapshots, notes, provenance mode (`catalog` or `manual`), timestamps, and correction lineage.
- **Odometer reading** — one manually observed odometer value: observed instant/local date, normalized odometer, input unit, source (`service_event` or `manual`), and validity/supersession fields.
- **Usage profile** — the user's declared driving baseline for a vehicle: baseline distance/week, unit, severe-use answers and the selected condition, and effective timestamps. The answers that selected the condition are preserved.
- **Forecast snapshot** — an explainability/audit record of one forecast computation: algorithm version, input hash, computation time, effective rate, due odometer, projected/calendar/effective dates, confidence code, and reason code. Snapshots are audit records, not the only source of truth.
- **Reminder rule** — a per-vehicle reminder preference: reminder kind, lead value/unit, preferred local time, and enabled flag. Reminder rules are multi-vehicle-safe from the first migration.
- **Scheduled notification** — the tracked state of one operating-system local notification request: stable notification ID, vehicle/cycle/rule IDs, desired and scheduled instants, due-date snapshot, payload version, platform state, and last error/reconciliation time.
