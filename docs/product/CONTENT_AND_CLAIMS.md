# Digital Oil Sticker — Content and Claims Contract

This contract governs every automotive fact, compatibility statement, due date, and piece of recommendation copy the product displays. It binds UI copy, catalog data, issue specifications, and store/support materials.

## No fabricated automotive facts

Every displayed manufacturer interval, viscosity/specification, capacity, oil-product claim, and filter fitment has provenance and a license permitting offline redistribution. Missing data is shown as unknown or unsupported — never filled with a plausible-sounding value.

## Requirements, not brand folklore

Oil compatibility is determined by the intersection of vehicle requirements and a specific product/SKU's published claims. A brand name or viscosity alone never proves compatibility. Filter compatibility is part-number/configuration-specific.

## Earlier threshold wins

A plan is due at the earlier of its sourced calendar threshold and projected mileage threshold. The prediction may warn earlier; it may never extend the OEM interval.

## Vehicle controls prevail

For vehicles with an oil-life monitor or condition-based maintenance system, the app clearly labels its date as an estimate and tells the user to follow the vehicle indicator and owner documentation when they disagree.

## Required terminology

- Say **"Meets the recorded requirements"**, not "manufacturer approved," unless the source explicitly documents an OEM approval.
- Say **"Estimated due date"** for mileage projection and show a confidence label.
- Say **"Source unavailable"** or **"Exact configuration not verified"** rather than supplying a generic value.
- Keep **oil-life monitor**, **calendar interval**, **mileage interval**, **normal service**, and **severe service** distinct.

## Provenance display requirements

Every recommendation detail view identifies provider/document, source version/revision, retrieved/verified date, applicable market and condition, plus a route for reporting a data error.

## Recommendation resolver and match_basis rules

Given a vehicle configuration and operating condition, the resolver returns a typed result:

- `verified`: exact licensed match with thresholds, requirements, and provenance;
- `partial`: identity is known but a required engine/configuration qualifier is missing;
- `conflict`: sources disagree; show no automatic product recommendation and retain both facts for review;
- `unsupported`: no licensed schedule for the selection;
- `not_applicable`: verified non-engine-oil vehicle such as a battery EV.

Filter oil products by all mandatory normalized requirement claims and market/effective date. Record `match_basis` values; never collapse unknown to compatible. Filter filters only through licensed configuration-specific application records and qualifiers. Users may manually record any oil/filter they used, but manual history must not be relabeled as verified compatibility.
