# Digital Oil Sticker — Product Charter

## Mission

Build a local-first mobile application that replaces the disposable windshield oil-change sticker with an accurate, explainable digital record. A person selects a vehicle, records the date and odometer of an oil change, records the oil and filter used, sees the applicable sourced manufacturer interval and fluid requirements, periodically enters odometer readings, and receives an on-device reminder as the earlier of the time limit or estimated mileage limit approaches.

The application must remain useful with no account, no remote database, no vehicle connection, and no network after installation. Version 1 targets native iOS and Android packages using Elixir, Phoenix LiveView, and Mob. Netlify is the static web/distribution edge, not the runtime for Phoenix.

## Non-negotiable product rules

1. **No online accounts.** A "local profile" is a row on one device, not authentication. There is no email, password, password reset, cloud sync, remote recovery, or cross-device state in v1.
2. **Offline from first launch.** The native package contains a usable vehicle catalog and all core flows work in airplane mode. Runtime calls to NHTSA or a commercial source are not required for manual vehicle selection, service history, projections, or reminders.
3. **No telematics.** The app never claims to know the current odometer. Users enter service mileage and later readings manually.
4. **No fabricated automotive facts.** Every displayed manufacturer interval, viscosity/specification, capacity, oil-product claim, and filter fitment has provenance and a license permitting offline redistribution. Missing data is shown as unknown or unsupported.
5. **Requirements, not brand folklore.** Oil compatibility is determined by the intersection of vehicle requirements and a specific product/SKU's published claims. A brand name or viscosity alone never proves compatibility. Filter compatibility is part-number/configuration-specific.
6. **Earlier threshold wins.** A plan is due at the earlier of its sourced calendar threshold and projected mileage threshold. The prediction may warn earlier; it may never extend the OEM interval.
7. **Vehicle controls prevail.** For vehicles with an oil-life monitor or condition-based maintenance system, the app clearly labels its date as an estimate and tells the user to follow the vehicle indicator and owner documentation when they disagree.
8. **Local notifications only in v1.** Do not add APNs/FCM push infrastructure, device tokens, a notification server, or accounts. Use operating-system scheduled local notifications.
9. **One-vehicle MVP, multi-vehicle-safe internals.** The first releasable slice exposes one active vehicle, but IDs, tables, events, and notification identifiers must safely support many vehicles. Multi-vehicle tabs are an explicit post-MVP milestone, not hidden MVP scope.
10. **Change control.** Work not stated in an issue's Included scope is excluded. Discoveries become a new issue or ADR. Do not silently enlarge an active ticket.

## Primary user journey

1. First launch explains that data stays on the device, lets the user choose miles/kilometers and time zone, and does not ask for notification permission yet.
2. The user selects year → make → model → available configuration from the bundled catalog. Every selector works offline and preserves a clear no-result/manual path.
3. The app shows the source-backed schedule and oil requirements before saving the vehicle. If an exact configuration cannot be proven, it asks the user to confirm/manual-enter instead of guessing.
4. The user records the last oil change date, odometer, oil, filter, and optional notes.
5. The app computes the manufacturer calendar due date, mileage threshold, estimated mileage date, and effective earlier due date. It explains inputs and confidence.
6. Only after the value is clear does the app request notification permission. Denial never blocks the product.
7. The dashboard acts as the digital sticker. A later odometer check-in refines the estimate and reconciles local reminders.
8. Recording a new oil change closes the previous cycle, starts a new one, recomputes the forecast, and replaces obsolete notification requests atomically.

## One-vehicle MVP, multi-vehicle-safe internals

The first releasable slice exposes exactly one active vehicle in the UI. Underneath, every identifier, table, event, and notification identifier must safely support many vehicles from the first migration, so that enabling the multi-vehicle garage later is an additive change, not a schema rewrite. Multi-vehicle tabs, per-vehicle reminders, and garage management are an explicit post-MVP milestone (M08) and must never be treated as hidden MVP scope.

## Distribution and web presence

- The project owns the domains digitaloilsticker.com and digitaloilsticker.net. The Netlify static help/privacy/attribution site will eventually serve at those domains.
- Native applications ship through TestFlight and the App Store on iOS, and through Play internal testing and the Play Store on Android.
- Netlify is never the Phoenix runtime. It serves only static content: the product/support/privacy/attribution site, deploy previews for that site, and, post-MVP, immutable versioned catalog packages with their signed manifest.
