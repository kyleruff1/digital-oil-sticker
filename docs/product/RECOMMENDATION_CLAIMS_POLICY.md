# Recommendation and claims policy

Adopted by the owner 2026-08-01 (planning review rev 2). Defines permitted terminology and the evidence thresholds behind every compatibility or maintenance statement the product makes. Complements [CONTENT_AND_CLAIMS.md](CONTENT_AND_CLAIMS.md) and [FACTUAL_USE_AND_MARKS_POLICY.md](../data/FACTUAL_USE_AND_MARKS_POLICY.md); where they overlap, this document is the stricter, controlling text for claim language.

## The three-record model

The product distinguishes three record kinds and never blurs them:

1. **Vehicle requirement** — a fact tied to an exact configuration: `required_viscosity, acceptable_viscosities, api_service_category, oem_specification, capacity_with_filter, capacity_without_filter, normal_service_interval, severe_service_interval, applicability_conditions, source_locator, source_page, source_effective_date`.
2. **Product claim** — what the product manufacturer or a certification source says about a product: `product_id, claimed_viscosity, claimed_service_categories, claimed_oem_specifications, claim_type, claim_source, observed_at, verification_status`.
3. **Match result** — an app-generated comparison, never stored as fact: `vehicle_requirement_id, product_claim_id, algorithm_version, matched_fields, unresolved_fields, conflicts, result_status, generated_at`.

Permitted match statuses: `verified_match` · `partial_match` · `insufficient_data` · `conflict` · `not_applicable`.

**Hard rules:** missing information is never converted into compatibility (tests must prove absent requirements cannot yield `verified_match`). Every derived result carries `algorithm_version`. **Recording what oil went in is separate from vehicle compatibility** — a user may record any oil without the app claiming it fits the selected vehicle.

### A fourth record kind: our own model (amended 2026-08-01, [ADR-0005](../architecture/ADR-0005-own-oil-model.md))

Our oil model is none of the three above. It is not a manufacturer requirement, not a product claim, and not a match between them — it is an interval **we** estimate from standard viscosity grades, published base-stock ranges, and an engine class we derive ourselves.

It therefore gets its own result status, `our_model`, which sits **outside** the INV-11 support ladder. An estimate we produced must never read as a vehicle whose data we hold: `our_model` never appears as `schedule_supported` or `full_product_supported` and never upgrades a vehicle's support status.

**Oil brand and family were dropped.** Products from different brands share the chemistry that determines interval, so a brand list added redundancy without adding a fact the app could stand behind — and it was the one part of the catalog needing the heaviest acquisition and redistribution review. What the user records now is a base stock and a viscosity grade. Brand may still be typed into notes; it is never a structured field and never enters a recommendation.

## Claim language

| Avoid | Use instead |
| --- | --- |
| "Recommended oil" | "Matches the recorded requirements" |
| "Best oil for your car" | "Products matching the selected specifications" |
| "Manufacturer approved" | "Manufacturer specification recorded as …" |
| "API approved" | "Listed as API service category SP as of [date]" |
| "Works with your vehicle" | "Matches viscosity and service-category fields; capacity/filter not verified" |
| "Change your oil on [date]" | "Estimated due date based on Your interval" |
| "Your car needs 5W-30" | "Commonly used on [engine class] engines" |
| "Recommended interval" (unattributed) | "Estimated due date — Our estimate, not manufacturer guidance" |
| "Synthetic lasts 10,000 miles" (as a due date) | "Full synthetic: published 7,500–10,000 mi" (as model reasoning) |
| "Guaranteed compatible" | "Exact configuration verified against [source]" |
| "Safe for your warranty" | Do not make this claim |
| "Factory recommended" (as a sentence, unattributed) | The **"Factory recommendation"** badge next to the specific value it certifies (see below) |

"Meets the recorded requirements" is permitted **only** when every mandatory requirement has a source-backed match. If only viscosity matches, say exactly that.

**Copy-lint prohibited terms** (build-failing, in addition to the storage-framing list): `best oil`, `guaranteed`, `warranty safe`, `manufacturer approved`, `API approved`, `recommended by`, `works with every`.

## Factory recommendation label

The **"Factory recommendation"** badge is the visual promise that a specific rendered value carries OEM-sourced provenance in our internal source register. It is bounded by three non-negotiable rules, each traceable to an existing invariant:

1. **Provenance required.** The label appears **only** when the specific value being displayed came from OEM-sourced data with per-row provenance recorded in our internal source register — the `source_locator, source_page, source_effective_date, source_id, verification_state` fields that ADR-0007 §"What every lane must preserve" mandates on every published `maintenance_schedules` / `oil_requirements` row. In practice this is DOS-M03-007 lane **(b)** (commercial license) or the hybrid lane **(d)** ([ADR-0007](../architecture/ADR-0007-manufacturer-oil-schedule-sourcing.md)); other origins are excluded — no our-model estimate ([ADR-0005](../architecture/ADR-0005-own-oil-model.md), `result_status: our_model`), no user-entered value, and no nearest-match imputation (the "Never infer a manufacturer interval from a generic model family; never use a nearest engine/configuration match" rule in this document's Interval rules section is the on-point prohibition).
2. **Source is not shown to the client.** No publisher name, no URL, no revision date, no source ID appears on-screen. Attribution stays inside our source register (`data_sources`, per ADR-0007). This is the promise the label makes: we hold OEM-backed provenance, we do not expose whose data it came from. The requirement is enforced by a negative render test.
3. **Badge, not sentence text.** The label is a badge that renders **next to the specific value it certifies** (a viscosity grade, an interval number, a capacity), not as a standalone sentence. This distinguishes it from a vehicle-level endorsement — the badge scopes the OEM claim to one field, matching the field-level provenance in the source register.

The label does not upgrade a vehicle's INV-11 support status (`identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, `unsupported`): a vehicle whose viscosity carries the badge but whose interval schedule does not remains `identity_only` for scheduling purposes. Coverage is per row, not per vehicle.

Implemented by `DigitalOilStickerWeb.Components.Badges.factory_recommendation_badge/1` with mandated text from `DigitalOilStickerWeb.Copy.factory_recommendation_label/0` ("Factory recommendation"); consumed today by `DigitalOilStickerWeb.VehicleProfileLive` gated on `maintenance_plan.manufacturer_viscosity` being non-nil (the field DOS-M03-007 activation populates). The display is READY but INERT until that ingest lands — no data path exists yet.

## Substantiation

Objective product claims imply the publisher possesses substantiation (FTC Advertising Substantiation Policy). Every compatibility or interval statement must trace to a requirement row and claim row with source locators and observation dates. A disclaimer cannot repair an unsupported claim.

**Affiliate/sponsorship fields exist now and are always false.** If commercial relationships are ever introduced, disclosure must be clear, conspicuous, and adjacent to the recommendation (FTC Endorsement Guides).

## Interval rules

Two intervals can exist today: the user's own, labeled **"Your interval"**, and our own model's, labeled **"Our estimate"**. Neither is ever presented as manufacturer guidance, and every surface that shows one names which it is.

### Rules specific to our own model

- Every rendered interval carries the basis sentence: this is our model, not the vehicle maker's, and a maker's schedule would replace it.
- No modelled interval may exceed the published high of its base stock's range. Asserted by test across the full cross product.
- A combination we hold no rule for resolves to the **lowest** published interval for that base stock, never an extrapolation, and the UI says a specific rule was unavailable.
- Severe service only ever shortens.
- The engine class is derived by us and labeled as such ("We classify this vehicle as: …"), never as a manufacturer statement about the engine.
- A factor we cannot observe across the corpus is omitted rather than applied to the minority of rows that happen to record it (see ADR-0005 on forced induction).
- The class code and model version are snapshotted onto the vehicle record at setup, so revising the model never silently changes an interval a user has already been shown.

When manufacturer schedules are added:

- Store normal and severe-service intervals separately; preserve every applicability condition.
- Record whether the interval is time-based, distance-based, oil-life-monitor-based, or a combination; never collapse "12 months or 10,000 miles, whichever occurs first" into one field.
- An oil manufacturer's "up to 20,000 miles" marketing statement never overrides the vehicle schedule, and a product's claimed life never becomes the due date automatically (it may be shown as product information).
- Never infer a manufacturer interval from a generic model family; never use a nearest engine/configuration match.
- Display exact source, manual edition, page, market, and observation date.
- If configuration resolution is incomplete, continue using "Your interval."
- Treat an oil-life monitor as a separate scheduling mode.

**Interval precedence (amended 2026-08-01):** mileage and time resolve independently and **the shortest wins**, with the basis always named — 1. exact manufacturer schedule → 2. the user's own interval → 3. our own model → 4. no estimate. Ties credit the manufacturer, because that is the source we could cite. Nothing ever lengthens an interval: if our model would allow more miles than the user asked for, the user's number stands. A vehicle with no engine oil service yields no interval at all rather than falling back to the user's number.

Implemented by `DigitalOilSticker.IntervalPolicy`; asserted by `test/digital_oil_sticker/interval_policy_test.exs`.
