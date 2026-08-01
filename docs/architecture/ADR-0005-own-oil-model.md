# ADR-0005 — Our own oil model replaces the oil-brand catalog

**Status:** Accepted — 2026-08-01 (owner decision) · **Amends:** [ADR-0003](ADR-0003-data-boundaries.md) (oil/product domain only; identity boundaries unchanged) · **Amends:** [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) (the "core functionality" scope it defined) · **Cites:** INV-11, INV-15, INV-16, INV-20, INV-21, INV-26 ([CONSTITUTION.md](../product/CONSTITUTION.md)) · **Governed by:** [RECOMMENDATION_CLAIMS_POLICY.md](../product/RECOMMENDATION_CLAIMS_POLICY.md), [FACTUAL_USE_AND_MARKS_POLICY.md](../data/FACTUAL_USE_AND_MARKS_POLICY.md)

---

## Context

### Brand was the wrong question to ask the user

The build-1 plan asked the user for an oil **brand**, then an oil **family**, from a curated list. Two problems, and they compound.

The first is redundancy. Brands do not differentiate the thing that determines when oil needs changing. A full synthetic 5W-30 from one manufacturer and a full synthetic 5W-30 from another are, for interval purposes, the same answer arriving under two names. A brand list of any useful size therefore produces dozens of entries that all collapse to one recommendation, and the user is made to pick among distinctions the app then ignores.

The second is sourcing cost. A brand-and-family list is a *compilation* — someone's selection and arrangement of products — which is exactly the category the rev-2 factual-use review flagged as needing an acquisition and redistribution basis before it can be served. The API EOLCS licensee directory is a private trade-association directory, and the policy already commits us to zero production rows from it until that review clears. So build 1 was going to ship brand fields that were user-entered anyway, at the cost of carrying the entire gated pipeline.

We were paying for a list that added no signal and needed the most legal review of anything in the catalog.

### What actually moves the interval

Three things, none of which are brand:

1. **Base stock** — conventional, synthetic blend, full synthetic, or high mileage. Published interval ranges cluster by base stock, and the spread between conventional and full synthetic is roughly 3,000–5,000 versus 7,500–10,000 miles. This is the dominant term.
2. **Viscosity grade** — the SAE J300 classification (`0W-20`, `5W-30`, …). Grades are a *standard*, not a product list, and the standard's grade names are short factual identifiers.
3. **What kind of engine it is** — direct injection shortens useful oil life through fuel dilution; a hybrid's engine runs less but cold-starts more; a diesel needs a different service category entirely; a battery-electric vehicle has no engine oil service at all.

The first two are answers the user can give from the bottle in their hand. The third we can derive ourselves from fields we already hold.

### We can classify engines from data we already have

The catalog holds 33,273 configurations with EPA/DOE fuel type, electrification level, engine descriptor, displacement, and cylinder count. That is enough to sort every configuration into one of nine classes without any per-vehicle lookup and without asserting anything a manufacturer said.

## Decision

**Drop oil brand and oil family entirely. Build and ship our own oil model as catalog data, and ask the user for base stock and grade instead.**

The model is authored in [`tools/catalog/data/curated/oil_science.json`](../../tools/catalog/data/curated/oil_science.json), compiled into the catalog artifact by [`tools/catalog/src/compile/oil_model.mjs`](../../tools/catalog/src/compile/oil_model.mjs), and read at boot by `DigitalOilSticker.Catalog.OilModel`. It has five parts:

| Part | Rows | What it is |
| --- | --- | --- |
| `oil_grades` | 14 | SAE J300 viscosity grades, with a `common` flag and a note on where each is typically specified |
| `oil_base_stocks` | 4 | Base stocks with their published mileage range, time cap, and our reasoning for each |
| `engine_classes` | 9 | Classes we derive, each with an interval factor, typical grades, and reasoning |
| `service_conditions` | 2 | Normal and severe, with the published severe-service questions |
| `interval_rules` | 56 | The cross product of the above, generated — one row per (class × base stock × condition) |

Classification is done **at compile time**, and each configuration's `engine_class_code` is stored in the artifact. A vehicle record snapshots that code plus the model version at setup, so revising the model never silently changes an interval a user has already been shown.

### The classes

`bev` and `fcv` have no engine oil service. `diesel_light` carries a distinct service-category requirement. `hybrid_gas` holds the base interval and leans on the time cap. `gas_direct_injection` takes a 0.8 factor. `gas_small`, `gas_mid`, and `gas_large` split port-injected gasoline by displacement and cylinder count. `gas_other` is the fallback for engines we cannot classify, and it takes the same 0.8 factor — an unknown engine is treated as a demanding one.

Measured distribution over the production catalog: direct injection 9,815, mid 6,698, small 5,370, other 3,915, large 3,697, hybrid 2,033, BEV 1,216, diesel 487, fuel cell 42.

### What we deliberately do not classify

**Forced induction.** The EPA/DOE engine descriptor records it on roughly 39 of 33,000 rows. A "turbocharged" class would be almost entirely false negatives, and a factor applied to 0.1% of the vehicles that should get it is worse than no factor — it would imply the other 99.9% had been checked. We omit the term rather than assert one we cannot see.

### The safety rule

> For any combination we do not have an explicit rule for, use the LOWEST interval of the applicable published range. Never extrapolate upward.

This is recorded in the artifact (`oil_model_metadata.safety_rule`), not only in code, and `OilModel.interval/3` implements it: an unmodelled combination returns the base stock's published low with `basis: :fallback_lowest_published`, and the UI says so. No generated rule may exceed its base stock's published high — asserted by test across the full cross product.

### Precedence

`DigitalOilSticker.IntervalPolicy` resolves mileage and time independently and **the shortest wins**, with the basis always named:

1. A manufacturer schedule sourced for this exact configuration (we hold none; the clause exists so adding one changes data, not logic).
2. An interval the user set themselves.
3. Our model.

Ties credit the manufacturer, because that is the one we could cite. Nothing in the policy ever lengthens an interval: if our model would allow more miles than the user asked for, the user's number stands. A vehicle with no engine oil service yields no interval at all rather than falling back to the user's number.

## Consequences

### What this buys

**No gated source in the critical path.** The oil model is ours. It needs no acquisition basis, no redistribution review, and no trademark posture, because it reproduces no one's compilation and names no one's product. The EOLCS review (#88) stops blocking build 1 and becomes what it should be — a later verification input.

**Honest coverage everywhere.** Previously a vehicle with no licensed schedule resolved to `identity_only` and the app could offer nothing but "Your interval". Now every vehicle we can classify gets an estimate, clearly labelled as ours. That is a large increase in usefulness with no increase in claim risk, because the claim being made is "this is our estimate", which is true.

**A model we can improve.** Interval factors, class boundaries, and base-stock ranges are data in one reviewable JSON file with reasoning attached to every entry. Changing our mind about direct injection is a data edit and a catalog rebuild.

### What this costs

**`:our_model` is a new result status**, deliberately outside the INV-11 support ladder. An interval we estimated must never read as a vehicle whose data we hold, so `:our_model` cannot appear as `schedule_supported` or `full_product_supported` and does not upgrade a vehicle's support status. Asserted by test.

**We are now making a substantive claim in our own name.** Every surface that renders an interval must carry the basis sentence — that this comes from our model rather than the vehicle's maker, and that a maker's schedule would replace it. The copy catalog holds those strings and the copy lint scans for the prohibited alternatives. This is a real obligation and it is the price of being useful.

**Legacy fields stay readable.** `oil_brand` and `oil_family` remain in the client-storage key list so records written before this change keep rendering rather than sliding into `__unknown__`. They are never written again.

## Alternatives considered

**Keep brand, add base stock alongside it.** Rejected: it preserves the redundancy and the sourcing cost to gain a field the model does not use. If a user wants to record the brand, the notes field takes free text.

**Ask the user for base stock but derive nothing about the engine.** Rejected: it throws away the one input we can supply without asking, and it means a direct-injection engine and a port-injected one get the same answer when we can see they should not.

**Per-vehicle interval lookups from a licensed schedule source.** Not rejected — deferred. This is what M03 is for, and the precedence rule already has the slot. It is simply not available now, and the model is what makes the app useful in the meantime.

## Verification

- `test/digital_oil_sticker/catalog/oil_model_test.exs` — the safety rule (fallback to published low, severe never lengthens, unknown base stock errors rather than guesses), the range invariant across the full cross product, direct injection shorter than port injection, no-engine-oil classes yielding no interval, suggested grades partitioning the model, and the basis/safety-rule text present in the artifact.
- `test/digital_oil_sticker/interval_policy_test.exs` — shortest-wins in both directions, manufacturer wins ties, mixed-basis reporting, not-applicable overriding a user plan, non-positive intervals ignored.
- `test/digital_oil_sticker/catalog/status_test.exs` — `:our_model` never reports a sourced support status.
- Compile-time: `foreign_key_check` on `vehicle_configurations.engine_class_code`, and the emitted coverage report carries the class distribution and the model version.
