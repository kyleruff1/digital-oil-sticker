# Recommendation and claims policy

Adopted by the owner 2026-08-01 (planning review rev 2). Defines permitted terminology and the evidence thresholds behind every compatibility or maintenance statement the product makes. Complements [CONTENT_AND_CLAIMS.md](CONTENT_AND_CLAIMS.md) and [FACTUAL_USE_AND_MARKS_POLICY.md](../data/FACTUAL_USE_AND_MARKS_POLICY.md); where they overlap, this document is the stricter, controlling text for claim language.

## The three-record model

The product distinguishes three record kinds and never blurs them:

1. **Vehicle requirement** — a fact tied to an exact configuration: `required_viscosity, acceptable_viscosities, api_service_category, oem_specification, capacity_with_filter, capacity_without_filter, normal_service_interval, severe_service_interval, applicability_conditions, source_locator, source_page, source_effective_date`.
2. **Product claim** — what the product manufacturer or a certification source says about a product: `product_id, claimed_viscosity, claimed_service_categories, claimed_oem_specifications, claim_type, claim_source, observed_at, verification_status`.
3. **Match result** — an app-generated comparison, never stored as fact: `vehicle_requirement_id, product_claim_id, algorithm_version, matched_fields, unresolved_fields, conflicts, result_status, generated_at`.

Permitted match statuses: `verified_match` · `partial_match` · `insufficient_data` · `conflict` · `not_applicable`.

**Hard rules:** missing information is never converted into compatibility (tests must prove absent requirements cannot yield `verified_match`). Every derived result carries `algorithm_version`. **Oil browsing is separate from vehicle compatibility** — a user may browse or record any brand without the app claiming it fits the selected vehicle.

## Claim language

| Avoid | Use instead |
| --- | --- |
| "Recommended oil" | "Matches the recorded requirements" |
| "Best oil for your car" | "Products matching the selected specifications" |
| "Manufacturer approved" | "Manufacturer specification recorded as …" |
| "API approved" | "Listed as API service category SP as of [date]" |
| "Works with your vehicle" | "Matches viscosity and service-category fields; capacity/filter not verified" |
| "Change your oil on [date]" | "Estimated due date based on Your interval" |
| "Guaranteed compatible" | "Exact configuration verified against [source]" |
| "Safe for your warranty" | Do not make this claim |

"Meets the recorded requirements" is permitted **only** when every mandatory requirement has a source-backed match. If only viscosity matches, say exactly that.

**Copy-lint prohibited terms** (build-failing, in addition to the storage-framing list): `best oil`, `guaranteed`, `warranty safe`, `manufacturer approved`, `API approved`, `recommended by`, `works with every`.

## Substantiation

Objective product claims imply the publisher possesses substantiation (FTC Advertising Substantiation Policy). Every compatibility or interval statement must trace to a requirement row and claim row with source locators and observation dates. A disclaimer cannot repair an unsupported claim.

**Affiliate/sponsorship fields exist now and are always false.** If commercial relationships are ever introduced, disclosure must be clear, conspicuous, and adjacent to the recommendation (FTC Endorsement Guides).

## Interval rules

While licensed schedule data is absent, the only interval is the user's own — labeled **"Your interval"**, never presented as manufacturer guidance. When manufacturer schedules are added:

- Store normal and severe-service intervals separately; preserve every applicability condition.
- Record whether the interval is time-based, distance-based, oil-life-monitor-based, or a combination; never collapse "12 months or 10,000 miles, whichever occurs first" into one field.
- An oil manufacturer's "up to 20,000 miles" marketing statement never overrides the vehicle schedule, and a product's claimed life never becomes the due date automatically (it may be shown as product information).
- Never infer a manufacturer interval from a generic model family; never use a nearest engine/configuration match.
- Display exact source, manual edition, page, market, and observation date.
- If configuration resolution is incomplete, continue using "Your interval."
- Treat an oil-life monitor as a separate scheduling mode.

**Interval precedence:** 1. user-selected stricter interval → 2. exact manufacturer schedule → 3. user-entered interval → 4. no estimate.
