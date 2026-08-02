# ADR-0007 — Manufacturer oil-schedule sourcing lane

**Status:** Accepted in part — 2026-08-02 (lane and spike authorization decided; four questions remain open) · **Cites:** INV-11, INV-15, INV-16, INV-20, INV-21 ([CONSTITUTION.md](../product/CONSTITUTION.md)) · **Governed by:** [FACTUAL_USE_AND_MARKS_POLICY.md](../data/FACTUAL_USE_AND_MARKS_POLICY.md), [RECOMMENDATION_CLAIMS_POLICY.md](../product/RECOMMENDATION_CLAIMS_POLICY.md), [DOS-M03-001](../../planning/issues/DOS-M03-001.md) rights matrix

> **Owner decision, 2026-08-02.** Lane **(b)** — commercial license — is the chosen sourcing lane. The DOS-M03-007 §FR-2 sample/contract spike with MOTOR (or approved equivalent) is authorized to begin: capture delivery format, authentication, rate limits, change semantics, measured coverage over the shipped 33,273-configuration corpus, provider vehicle IDs, one-time and update pricing, and every embedding/retention/hosted-serving/termination right; write everything back into [DOS-M03-001](../../planning/issues/DOS-M03-001.md).
>
> The remaining Decision-required questions (coverage floor, behavior for uncovered vehicles, budget ceiling, rights-revocation) are held open until the spike returns. This ADR moves to Accepted (full) when they are answered; when it does, [ADR-0005](ADR-0005-own-oil-model.md) is amended to note the `:manufacturer` clause is now sourced.
>
> DOS-M03-007 is moved off its gated state for lane (b) only. Lanes (a), (c), (d), (e) remain not selected.

---

## Context

### The problem, plainly

The shipped oil-interval model varies over exactly three axes: engine class × base stock × service condition. Two vehicles that resolve to the same `engine_class_code` receive the same interval for the same oil. There is no per-model-year, per-trim, per-drivetrain, or per-engine-VIN variation.

The lookup is enforced by `UNIQUE(engine_class_code, base_stock_code, service_condition)` in `tools/catalog/src/compile/schema.sql:138` and by the three-arg `OilModel.interval/3` defined at `app/lib/digital_oil_sticker/catalog/oil_model.ex:105`. Per-vehicle differences exist only because different configurations may carry different `engine_class_code` values (`schema.sql:172-173`); once two vehicles share a class, they share an interval.

Users have observed this behavior and asked why the calculation is not per-vehicle. The honest answer is that no manufacturer schedule data has been sourced yet. The catalog's `maintenance_schedules` and `oil_requirements` tables ship on purpose empty:

- `app/priv/catalog/catalog-manifest.json` records `"maintenance_schedules": 0, "oil_requirements": 0` (`app/priv/catalog/catalog-manifest.json:27-28`).
- `tools/catalog/src/compile/production.mjs:230` stamps the flat metadata keys `feature_schedules: 'own_model'` and `feature_oil_requirements: 'absent'`; the sibling `production.mjs:267` stamps a nested `features: { schedules: 'own_model', oil_requirements: 'absent', … }` object under differently-named keys. The two stamps are separate fields, both currently agreeing that no source is shipping, and either would have to be updated when a lane goes live.
- `app/test/digital_oil_sticker/catalog/repo_readonly_test.exs:87-95` asserts a hard zero for both tables in the shipped catalog.
- `app/lib/digital_oil_sticker/catalog/source_gate.ex:12-13` gates the tables on a `catalog_metadata` feature flag: a table is cleared unless its feature is explicitly `"withheld"`. Under the current metadata (`feature_schedules: "own_model"`, `feature_oil_requirements: "absent"`) both `cleared?/1` calls return `true`; the empty tables are the honest posture, not a gate closed against a source that exists.

They are empty because INV-15 (no fabricated automotive facts; the required right for 2.0.0 is a license permitting hosted network serving), INV-16 (requirements not brand folklore; compatibility is an intersection of vehicle requirement and SKU-level product claim), INV-20 (source and effective model-year context preserved to display), and INV-21 (no "manufacturer approved" absent OEM approval evidence) forbid quoting a manufacturer specification we cannot source. INV-11 also forbids guessing missing data into presence: a schedule we cannot cite must show as unknown, not filled in.

### What a sourcing decision unlocks

`DigitalOilSticker.IntervalPolicy` already carries a `:manufacturer` basis. In `@precedence` at `app/lib/digital_oil_sticker/interval_policy.ex:85` it sits first, so it wins ties, and the docstring at `interval_policy.ex:82-84` states it "outranks nothing by itself — it wins only by being shorter". The module docstring at `interval_policy.ex:6-10` states outright: *"a manufacturer schedule sourced for this exact configuration (we hold none yet — the clause is here so adding one changes data, not logic)"*.

`IntervalPolicy.for_vehicle/2` (`interval_policy.ex:61-80`) currently assembles only `user:` and `our_model:` candidates. `Due.oil_rule/2` (`app/lib/digital_oil_sticker/due.ex:125-161`) only walks three `OilModel` stages. The `:manufacturer` branch is unreachable until something upstream fetches an OEM row and passes `manufacturer:` into `IntervalPolicy.resolve/1`.

An approved sourcing lane, therefore, activates [DOS-M03-007](../../planning/issues/DOS-M03-007.md) (currently a "when the source matrix permits" card) to import per-vehicle rows into `maintenance_schedules` and `oil_requirements` and to feed the manufacturer basis. This ADR does not write import code; it selects the lane the DOS-M03-007 adapter is written against.

### The shape mismatch the ingest must resolve

OEM rows are keyed to `configuration_key` in the catalog (`schema.sql:202-218`, `220-236`) — effectively per model-year × make × model × trim × engine/drivetrain (`schema.sql:144-178`). Our internal model is keyed to `engine_class_code` alone. The `:manufacturer` slot in `IntervalPolicy` is the only bridge, and it takes just `{miles, months}` (`interval_policy.ex:24-30`), stamped with `miles_basis: :manufacturer` and `months_basis: :manufacturer`. Anything richer — the OEM row's `oil_life_monitor`, `recommendation_text`, `condition`, and provenance — must be surfaced by whatever fetches the row, not by `IntervalPolicy`. This constrains lane design: whatever lane is chosen, its adapter is responsible for translating a per-configuration OEM row into the exact `{miles, months}` fed to the resolver, while separately holding the row's OLM flag, condition, and provenance for display.

## Decision

This ADR does not decide. The remaining sections specify the lanes on offer, what any lane must preserve, the consequences of each, and the questions the owner must answer to move this ADR to Accepted.

## Lanes under consideration

The real design space here is two orthogonal axes, not a menu of peer lanes:

1. **Licensed corpus?** Yes (buy MOTOR-class aggregation) or no.
2. **Independent manual verification of the shipped rows against OEM manuals?** Yes (documented-facts extraction workflow with second-review evidence) or no.

The four cells of that 2×2 are enumerated below as lanes (a), (b), (d), plus the "neither" cell, which is the current shipping posture and not a candidate for the manufacturer basis. Two further lanes appear for completeness: lane (c) (crowd-sourced) and lane (e) (OEM owner-account websites). Both are ruled out and the reasons are given.

The live candidates are lane (a) (no license, verified), lane (b) (license, unverified), and lane (d) (license, verified). "No license, no verification" cannot supply a manufacturer-basis row at all — the app already ships that cell as our-model plus user-entered.

### Lane (a) — Manual documented-facts extraction from owner's manuals

**What it is.** Human review of publicly available OEM owner's manuals, maintenance booklets, and warranty/maintenance guides. A reviewer opens the manual for a specific model-year × make × model × trim × engine, reads the oil-service section, and enters discrete factual values — required viscosity grade, capacity, normal-service interval in miles and months, severe-service alternative, OLM presence, applicability conditions — into our own schema fields, with document locator, page/section, source effective date, and second-reviewer identity recorded per row. The pattern is described in DOS-M03-007 §Context (relaying the upstream Master-prompt §4.4 finding that "the documented-facts lane permits normalizing discrete facts from public OEM owner manuals, maintenance booklets, warranty/maintenance guides") and its adapter/second-review requirements are set out in DOS-M03-007 §Included and §FR-9. `FACTUAL_USE_AND_MARKS_POLICY.md` line 22 ("Oil-manufacturer publications") authorizes the analogous pattern for *lubricant* manufacturer publications; it does not itself authorize extraction from *vehicle* owner's manuals. If lane (a) is chosen, that policy must be amended with an explicit vehicle-owner's-manual section that mirrors the "Oil-manufacturer publications" row (per-row provenance fields, factual-extraction basis, "never copy" list carried through), so the copyright and trademark posture for the vehicle-manual path lives in the same document as the other approved sources.

**What CAN be extracted.** The enumerated factual field list in `FACTUAL_USE_AND_MARKS_POLICY.md`: model year, make, model, trim/configuration name, engine displacement, cylinder count, fuel type, transmission, drivetrain, electrification type, oil viscosity grade, oil capacity, oil-filter part number, maintenance interval, oil brand and product-family names, API service category and other specification identifiers. Rendered in the app's own words and schema, per row.

**What CANNOT be extracted.** The "Never copy" list in the same policy: source descriptions verbatim, manual prose, source-specific table layouts, photographs or product-label artwork, manufacturer or certification logos (including the API donut, starburst, and shield), a private directory's entire selection and arrangement, substantial portions of a copyrighted manual or standard. The output is a field-valued row, not a re-typed manual page.

**Coverage math to price.** The production catalog holds **33,273 configurations** (measured, ADR-0005 §"We can classify engines from data we already have"). Per-configuration reviewer time — locating the correct manual, opening the maintenance section, reading through severe-service qualifiers, entering the fields, and answering a second reviewer's questions, then a second-review pass — has not been measured for this project. No timed pilot has been run and no comparable extraction study is cited. Any minutes-per-configuration figure quoted before a spike is an unmeasured planning estimate and cannot carry sign-off weight; before this ADR moves to Accepted on lane (a), a small (roughly ten-configuration) timed pilot must produce a defensible per-configuration reviewer-minute figure, which is then multiplied against the coverage floor chosen in Q3. The qualitative point that survives without measurement is that this lane's cost is denominated in staff-days rather than licensing dollars.

**Legal posture.** Green under `FACTUAL_USE_AND_MARKS_POLICY.md` for factual extraction with per-row provenance. Source dispositions: `copyright_basis: factual_extraction`, `acquisition_basis: manufacturer_publication`, `redistribution_basis: factual_republication`, `claim_posture: manufacturer_claim` (when the manual is authoritative), `trademark_posture: plain_text_reference`. No offline-only license is being converted to a hosted-serving one — INV-15's amended requirement is satisfied by the extraction method itself. `review_status` must still be moved from `pending` to `approved` on the per-source row in `config/data_sources.yml` before ingest turns on (DOS-M03-001 status enum).

**Second-reviewer burden.** DOS-M03-007 §FR-9 requires "document/page/section provenance and second-review evidence for every extracted value". This lane commits us to a reviewing workflow, not only an entering workflow — closer to a bench-scientist protocol than to data entry. The infrastructure to hold the second-review evidence must exist before the first row lands, per DOS-M03-007's publication gate: "No record reaches publication without an exact/reviewed vehicle crosswalk (DOS-M03-006) and allowed provenance."

### Lane (b) — Commercial license (MOTOR Maintenance Schedules + Fluids or approved equivalent)

**What it is.** A written license from a commercial data provider whose product is per-configuration OEM maintenance schedule and lubricant requirement data. DOS-M03-007 §FR-2 and its research anchors name MOTOR's Maintenance Schedules and Fluids products by URL as the procurement candidate. The preferred procurement shape, stated verbatim in DOS-M03-007 §FR-2, is "a one-time rolling-30-year snapshot with perpetual derived/offline redistribution."

**Rights the contract must cover.** DOS-M03-001 AC-6 enumerates them: written rights to "normalize/derive, vendor in the app, store offline on end-user devices, retain access-controlled build/backups, retain historical user snapshots, and continue distributing the acquired version after the agreement ends, plus explicit attribution/trademark and optional update terms. API/portal access or payment by itself does not pass." Under INV-15's 2.0.0 amendment, the license must additionally cover **hosted network serving**, not merely offline bundle redistribution. `FACTUAL_USE_AND_MARKS_POLICY.md` states this explicitly: "the required right is now a license permitting serving the data over a network from a hosted service, which is not automatically implied by a right to redistribute inside an installed application bundle. Any source cleared under 1.0.0 for offline bundle redistribution MUST be re-reviewed against the hosted-serving use before it ships." A sample license that omits hosted-serving rights fails INV-15 at the contract stage.

**Coverage and shape.** MOTOR's marketing of 1985+ domestic and import light-duty coverage is relayed in DOS-M03-007 §Context and source of truth (which cites an external Master-prompt §11.2 "Research-backed source policy" research anchor, verified 2026-07-31); the claim is not itself normative text of a tracked planning document. A rolling-30-year window at the 2026 baseline is 1997–2026, which aligns with ADR-0003 §FR-6's declared window. Provider vehicle IDs must be captured at ingest so DOS-M03-006 crosswalks can resolve them to our `configuration_key` — the shape mismatch identified above is real work regardless of source.

**Cost to price.** Pricing is not published. DOS-M03-007 §FR-2 requires a "provider sample/contract/data dictionary spike" that captures "delivery format, authentication, rate limits, change semantics, measured coverage, provider vehicle IDs, one-time/update pricing, and every embedding/retention/termination right." Until that spike returns, this lane's cost is not knowable in dollars and this ADR does not volunteer a range. The qualitative reading the owner should carry into the spike is that the contract will likely include seat, deployment, or user-count clauses that scale with adoption, and that the ongoing update-refresh price is a separate line item from the one-time acquisition. The spike is a precondition, not a formality.

**Legal posture.** Green in principle: `copyright_basis: licensed`, `acquisition_basis: licensed_feed`, `redistribution_basis: license` (bounded by the contract's exact language), `claim_posture: manufacturer_claim`. Trademark posture depends on the contract's attribution/trademark clause. Row-level provenance still traces to the OEM manual the licensor extracted from, not to the licensor itself — MOTOR is not the source of the fact, they are the source of the aggregation.

**Rights-revocation behavior.** DOS-M03-007 states it: "Rights revocation flips the source's flag off; already-released catalogs follow contractual continued-distribution terms; the UI fallback is user-entered data." This lane requires the contract to specify what happens after termination, and the app must remain shippable in a state where the license is dead.

### Lane (c) — Crowd-sourced / user-contributed schedules (ruled out for this ADR)

**What it would be.** Aggregating values users enter for their own vehicles, then publishing the aggregate as though it were manufacturer guidance for other users' vehicles of the same configuration.

**Why it is ruled out as a manufacturer-basis source.** Intervals are not an oil-vs-vehicle compatibility question, so INV-16 (which governs the intersection of vehicle requirements and product claims) and the RECOMMENDATION_CLAIMS_POLICY.md "missing information is never converted into compatibility" clause (bounded by the match-status enum `verified_match`/`partial_match`/`insufficient_data`/`conflict`/`not_applicable`) are not the on-point rules here. The on-point rules are: **INV-11** ("Missing data is shown as unknown or unsupported — never guessed"); **`RECOMMENDATION_CLAIMS_POLICY.md` line 31**, which forbids the claim-language transformation the lane would perform — "Manufacturer approved" is only ever recorded as "Manufacturer specification recorded as …", which requires an actual manufacturer specification; and the Interval Rules section of the same document, which states that "Nothing ever lengthens an interval" and "Never infer a manufacturer interval from a generic model family; never use a nearest engine/configuration match." A crowd-sourced aggregate is not a manufacturer specification, so it cannot be labeled as one; and averaging across users would necessarily infer intervals across configurations, which the interval rules explicitly reject. INV-15 also bites, though not for OEM-provenance reasons: it requires "provenance and a license permitting the distribution the product actually performs," and user-aggregate provenance is not a manufacturer-source provenance that could support a manufacturer-basis claim.

**What it already is.** A user entering their own interval for their own vehicle is the "your setting" fallback that ADR-0003 §Fallbacks and DOS-M03-007's "Mandatory fallback" already provide, labeled `User entered`. `IntervalPolicy` already places this ahead of our model in precedence. That is not a sourcing lane; it is the floor the product already ships. This ADR does not disturb it and does not consider it a candidate for the `:manufacturer` basis.

### Lane (d) — Hybrid: license plus independent manual verification of shipped rows

**What it is.** The "yes / yes" cell of the 2×2: a license supplies the corpus, coverage, and provider vehicle IDs, and reviewers additionally perform manual documented-facts extraction on a stratified sample of the licensed corpus — sampling across model-year, make, drivetrain, and severe-service presence — reading the OEM manual directly and verifying that the licensor's row matches the manual. Discrepancies are logged; the pass produces the second-reviewer evidence DOS-M03-007 §FR-9 requires and validates that the licensor's aggregation is faithful. It is not an independent lane in its own right — it is the composition of the axes chosen in (a) and (b) — so any consequence true of (a) or (b) is also true here.

**What it buys over (b) alone.** Direct evidence for the compliance file that shipped rows match OEM sources, not just that they arrived under license. Independence of the claim from the licensor's copy: the source we cite is the manual, not the aggregator. A measured caught-error rate that tells us how much trust the licensor's rows warrant.

**What it costs over (b) alone.** All of (b)'s license fee plus a reviewer program sized to the sample rate. A 5% stratified sample of the catalog is over 1,600 configurations reviewed; a 1% sample is over 330. The sample must be stratified enough that its results generalize — a purely random small sample may miss whole categories (severe-service-only diesel light-duty, hybrid CVT, etc.).

**When to pick this over (b).** When the license itself is inexpensive enough that the reviewer program dominates the cost; or when the compliance posture requires independent OEM-source verification for shipped rows regardless of license quality; or when the licensor's coverage of severe-service alternatives and OLM disclosures is uneven and needs a second look.

### Lane (e) — OEM owner-account websites (ruled out absent written OEM authorization)

**What it would be.** Several manufacturers operate authenticated owner-facing websites (MyFord/FordPass, Toyota Owners, MyChevrolet, MyBMW, etc.) that publish structured per-VIN maintenance schedules — already parsed into fields, sometimes filterable by service condition. Unlike PDF owner's manuals, the data is machine-shaped at the source. An "acquisition" here is either interactive session-by-session copy by a reviewer, or automated retrieval against the owner account.

**Why it is ruled out.** DOS-M03-001 AC-10 is explicit: "No issue in M03 uses `scrape` as an acquisition method unless a publisher has explicitly authorized it in writing." No such written authorization exists for any of these owner-account sites, so automated retrieval is prohibited on the same footing that ADR-0003's "scrape publicly displayed OEM material" branch is ruled out. `FACTUAL_USE_AND_MARKS_POLICY.md` states the same principle for the `robots.txt` case: public visibility is an automation instruction, not a copyright license. The manual-session-by-session variant additionally runs into the site's terms-of-service acceptance (which the reviewer accepts on behalf of the project each session) and the fact that these sites are the manufacturer's own presentation of the data — a private-directory's "selection and arrangement" the "Never copy" list already forbids reproducing.

**When this lane could open.** Only when a specific manufacturer grants written authorization for the acquisition method — at which point it collapses back into lane (a) or lane (b) depending on whether the authorization is a licensed feed or a factual-extraction permission, and the per-source row in `config/data_sources.yml` records the written evidence. Until that happens, this lane contributes zero rows and is out of scope for the DOS-M03-007 adapter.

## What every lane must preserve

Regardless of which lane is chosen, the shipped row must carry, per the `maintenance_schedules` and `oil_requirements` schema at `tools/catalog/src/compile/schema.sql:202-236` and DOS-M03-007 §FR-5/§FR-6:

- **`source_locator`, `source_page`, `source_effective_date`, `source_id` (FK to `data_sources`), and `verification_state`** — all present at row level. `source_locator`, `source_id`, and `verification_state` are `NOT NULL` in the DDL.
- **Effective-date and source-revision preservation** (DOS-M03-007 §FR-8): "conflicting or overlapping schedules are never collapsed without a recorded precedence/review decision."
- **Second-review evidence** for manual paths (DOS-M03-007 §FR-9): "document/page/section provenance and second-review evidence for every extracted value."
- **Normal-vs-severe kept distinct** (INV-21, DDL `condition` CHECK ∈ `normal`/`severe`/`flexible`): never collapsed to a single "recommended" interval.
- **OLM as a separate policy, never converted to invented miles/months** (DOS-M03-007 §Excluded, INV-21): `oil_life_monitor` column, 0/1, with the row-level CHECK allowing a row that carries only the OLM flag and no numeric interval.
- **Applicability conditions preserved** — `applicability_conditions` on the `oil_requirements` row (`schema.sql:230`) and `qualifier_text` on the schedule row per DOS-M03-007 §FR-5. Trim, drivetrain, market, and severe-service qualifiers stay attached.
- **The ability to say "no data for your vehicle" honestly.** `RECOMMENDATION_CLAIMS_POLICY.md` explicitly forbids nearest-match inference: "Never infer a manufacturer interval from a generic model family; never use a nearest engine/configuration match. If configuration resolution is incomplete, continue using 'Your interval.'" A lane that pads coverage by generalizing across trims fails this even if every row is provenance-bearing.
- **US-territory scope.** `FACTUAL_USE_AND_MARKS_POLICY.md`: "Initial release territory: **United States.** Another review is required before targeted UK/EU distribution."
- **Ingest gate.** DOS-M03-007's publication rule: "If no license is approved, the normalized adapter interface ships with synthetic fixtures only; the production feature flag remains off and the UI path uses user-entered intervals/specifications labeled `User entered`." The chosen lane must have `review_status: approved` or `approved_with_conditions` on its row in `config/data_sources.yml` before ingest turns on.

## Consequences by lane

### Lane (a) — manual extraction

- **Coverage the user sees.** Whatever the reviewer program actually processes. A realistic first-year coverage floor is a curated shortlist (highest-volume US makes and model-years) — hundreds to low thousands of configurations out of 33,273. Everything else keeps falling to our model (ADR-0005), and the `Our estimate, not manufacturer guidance` basis line stays load-bearing for the majority of vehicles.
- **Integrity preserved.** Provenance is naturally per-row and per-page. Second-review evidence is a direct byproduct of the workflow, not a compensating control. `claim_posture: manufacturer_claim` is honest — the source we cite is the manual.
- **Compensating controls required.** A reviewer-training and dispute-resolution process; a mechanism to re-review a row when the OEM issues a manual revision; a measured and published defect rate.
- **Cost class.** Staff-days. No licensing dollars. Ongoing per year to keep new model-years current.
- **Copy change.** For covered vehicles the interval renders with a manufacturer basis and a manual citation. For uncovered vehicles, the model's basis line stays; there is no promise that coverage will grow.

### Lane (b) — commercial license

- **Coverage the user sees.** Broad — potentially the full 1997–2026 rolling window across US-market makes at license go-live, subject to what the sample spike measures. `Our estimate` becomes the exception rather than the rule for covered makes.
- **Integrity preserved.** Configuration-qualified rows arrive with provider IDs and (typically) source manual references. Normal/severe and OLM stay distinct **if** the license preserves them; the ingest must not collapse them.
- **Compensating controls required.** The contract itself must satisfy INV-15's hosted-serving amendment and DOS-M03-001 AC-6's seven-way rights list. Rights-revocation planning must be real: the UI must degrade to our model or to user-entered without silently changing an interval a user has already been shown (see ADR-0005's snapshot rule).
- **Cost class.** Licensing dollars, unquantified until the spike returns; plus modest staff-days for the ingest adapter and the crosswalk.
- **Copy change.** The `Our estimate, not manufacturer guidance` basis line becomes conditional — replaced by the manufacturer citation when a licensed row exists. This is the strongest change to the app's voice of any lane.

### Lane (d) — hybrid

- **Coverage the user sees.** As (b) — the license drives the ceiling.
- **Integrity preserved.** As (b), plus a directly measurable defect rate against OEM manuals, plus the second-review evidence file (a) produces natively.
- **Compensating controls required.** As (b), plus a stratified-sampling protocol that a reviewer can execute reproducibly; a discrepancy log; a decision rule for what a discrepancy triggers (row-level correction, licensor query, or a broader sampling widen-out).
- **Cost class.** Licensing dollars **and** staff-days. The most expensive lane on both axes.
- **Copy change.** As (b).

## Alternatives already considered

**Keep only the current user-entered fallback and ship no manufacturer data.** Rejected as a permanent posture. The current model is what makes the app useful today (ADR-0005) but it is deliberately outside the INV-11 support ladder, and users are already asking why the calculation is not per-vehicle. This ADR exists because that question deserves a real answer eventually. Not rejected as an interim posture — it is what the app does now.

**Import vPIC schedule fields.** Rejected outright. Per ADR-0003 §"Measured evidence": "vPIC variable surface — 144 VIN-decode variables; **zero** oil-interval, viscosity, capacity, oil-product, or filter-fitment fields." DOS-M03-001 carries the same finding verbatim: "the vPIC standalone database is unsuitable for make/model enumeration (VIN-decode-only)." vPIC cannot supply an interval at any coverage.

**Scrape publicly displayed OEM material.** Rejected outright. DOS-M03-001 AC-10: "No issue in M03 uses `scrape` as an acquisition method unless a publisher has explicitly authorized it in writing." DOS-M03-007 §Excluded: "Extracting from a source/method rejected by M03-001." `FACTUAL_USE_AND_MARKS_POLICY.md` on `robots.txt`: "an automation instruction, not a copyright license." Public web visibility is not permission to redistribute.

**Publish crowd-sourced user-entered values as manufacturer guidance.** Rejected. See Lane (c) above.

**Use API EOLCS product certifications as a schedule source.** Rejected as out of scope for this ADR. Per `FACTUAL_USE_AND_MARKS_POLICY.md`: EOLCS "contributes **zero production rows** until its acquisition and redistribution method is approved; it is reserved as a separately-reviewed certification-verification source." EOLCS answers what oil is certified; it does not answer what the vehicle's OEM says the interval is.

## Decision required

Two of the six answered on 2026-08-02; four remain open until the spike returns. Owner Q4 is a policy question that can be answered independently and is being requested with the spike.

1. **The two axes.** ✓ Answered 2026-08-02. **Licensed corpus: yes. Independent manual verification of shipped rows: no** — lane **(b)**. Lane (d)'s hybrid is not selected; a subsequent ADR may revisit adding verification if the spike's coverage or extraction-quality evidence is thin.
2. **If (b) or (d), authorization to run the DOS-M03-007 §FR-2 sample/contract spike.** ✓ Authorized 2026-08-02. The spike is the precondition for answering Q3, Q5, and Q6, and must land its measurements in the DOS-M03-001 matrix before this ADR moves to Accepted (full).
3. **OPEN — Coverage floor.** Held until the spike returns. Owner will name a threshold (percentage of the 33,273-configuration corpus, or an explicit make × year subset) within a stated window after the spike results land; the DOS-M03-007 publication gate remains off until then.
4. **OPEN — Behavior for uncovered vehicles.** Options: (i) fall back to our model with the existing `Our estimate, not manufacturer guidance` copy; (ii) refuse to show a due date for uncovered vehicles until the user enters one. Answerable now in principle; the spike's coverage measurement will inform whether (ii) is livable in practice.
5. **OPEN — Budget class and ceiling.** Lane (b) is a licensing-dollars line item; the ceiling is decidable when the spike returns pricing.
6. **OPEN — Rights-revocation behavior.** Whether covered vehicles retain their manufacturer-basis row (per contractual continued-distribution terms) or revert to our model after license termination. Answerable when contract terms are proposed in the spike.

When Q3–Q6 land, this ADR is amended to Accepted (full).

## Research anchors

- `docs/product/CONSTITUTION.md` — INV-11, INV-15, INV-16, INV-20, INV-21.
- `docs/data/FACTUAL_USE_AND_MARKS_POLICY.md` — factual-extraction lane, "Never copy" list, six-dimension source dispositions, hosted-serving amendment, US-territory scope.
- `docs/product/RECOMMENDATION_CLAIMS_POLICY.md` — three-record model, prohibited claim language, no nearest-match inference, interval-precedence amendment.
- `planning/issues/DOS-M03-001.md` — three-lane approval model, AC-6 seven-way rights, AC-10 scrape prohibition, ambiguous-terms rule, status enum.
- `planning/issues/DOS-M03-007.md` — schedule ingest scope, FR-2 procurement shape, FR-5 and FR-6 field lists, FR-9 second-review requirement, publication gate, rights-revocation behavior.
- [ADR-0003](ADR-0003-data-boundaries.md) — source-gap matrix, confidence tiers, coverage window.
- [ADR-0005](ADR-0005-own-oil-model.md) — the model this ADR is designed to extend; the `:manufacturer` clause in `IntervalPolicy` reserved for this lane; the interval-snapshot rule.
- [MOTOR Maintenance Schedules](https://www.motor.com/products-services/data-products/maintenance-schedules/), [MOTOR Fluids](https://www.motor.com/products-services/data-products/fluids/) — procurement candidate named in DOS-M03-007 §11.2.
