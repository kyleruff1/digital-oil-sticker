# Digital Oil Sticker

A local-first mobile application that replaces the disposable windshield oil-change sticker with an accurate, explainable digital record. A person selects a vehicle, records the date and odometer of an oil change, records the oil and filter used, sees the applicable sourced manufacturer interval and fluid requirements, periodically enters odometer readings, and receives an on-device reminder as the earlier of the time limit or estimated mileage limit approaches.

The application must remain useful with no account, no remote database, no vehicle connection, and no network after installation. Version 1 targets native iOS and Android packages using Elixir, Phoenix LiveView, and Mob. Netlify is the static web/distribution edge, not the runtime for Phoenix.

## Current phase

**Planning bootstrap complete; execution begins at milestone M00 — no application code yet.**

This repository currently contains planning and governance documents only. The M01 scaffold issue owns creation of the application skeleton. Feature implementation must not begin until the M00 physical-device go/no-go spike passes or an explicit fallback ADR is approved.

## Non-negotiable product rules

1. **No online accounts.** A "local profile" is a row on one device, not authentication. There is no email, password, password reset, cloud sync, remote recovery, or cross-device state in v1.
2. **Offline from first launch.** The native package contains a usable vehicle catalog and all core flows work in airplane mode.
3. **No telematics.** The app never claims to know the current odometer. Users enter service mileage and later readings manually.
4. **No fabricated automotive facts.** Every displayed manufacturer interval, viscosity/specification, capacity, oil-product claim, and filter fitment has provenance and a license permitting offline redistribution. Missing data is shown as unknown or unsupported.
5. **Requirements, not brand folklore.** Oil compatibility is determined by the intersection of vehicle requirements and a specific product/SKU's published claims. A brand name or viscosity alone never proves compatibility. Filter compatibility is part-number/configuration-specific.
6. **Earlier threshold wins.** A plan is due at the earlier of its sourced calendar threshold and projected mileage threshold. The prediction may warn earlier; it may never extend the OEM interval.
7. **Vehicle controls prevail.** For vehicles with an oil-life monitor or condition-based maintenance system, the app labels its date as an estimate and defers to the vehicle indicator and owner documentation when they disagree.
8. **Local notifications only in v1.** No APNs/FCM push infrastructure, device tokens, notification server, or accounts.
9. **One-vehicle MVP, multi-vehicle-safe internals.** The first releasable slice exposes one active vehicle, but IDs, tables, events, and notification identifiers must safely support many vehicles.
10. **Change control.** Work not stated in an issue's Included scope is excluded. Discoveries become a new issue or ADR. No silent enlargement of an active ticket.

## Architecture summary

- **On-device Mob/Phoenix LiveView.** The BEAM and Phoenix are embedded in each Android/iOS app; the endpoint runs on device loopback (`http://127.0.0.1:4000`) and renders in a native WebView. This is not LiveView Native and not a remote Phoenix server. All device APIs that require a `Mob.Socket` are reached only through a typed `DeviceCommandBroker` and the root Mob screen.
- **Dual SQLite repositories.** `CatalogRepo` holds replaceable, read-mostly reference data bundled with the application. `UserRepo` holds the durable local profile, garage, plans, history, mileage, forecasts, and reminder metadata; it is never replaced by a catalog update. No cross-database foreign keys; user rows store a stable catalog key plus a readable snapshot.
- **Netlify static boundary.** Netlify hosts the static product, support, privacy, and attribution site, its deploy previews, and (post-MVP) immutable versioned catalog packages with a signed manifest. Netlify is not an always-on Elixir/Phoenix host. Native applications and catalogs are built and tested in GitHub Actions and distributed through the platform stores.
- **Production domain.** `digitaloilsticker.com` is owned but not yet deployed.
- **Local-only posture.** OS-scheduled local notifications, no telemetry or third-party analytics by default, and a loopback-only endpoint. See [SECURITY.md](SECURITY.md).

## Repository layout

```
README.md, CONTRIBUTING.md, SECURITY.md   Root governance files
docs/governance/                          Change control; roadmap ledger (after sync apply)
docs/product/                             Charter, scope, glossary, roadmap, content and claims
docs/architecture/                        ADRs (proposed/pending-spike until evidence exists)
docs/data/                                Source register, data dictionary, coverage matrix, licensing checklist
docs/quality/                             Test strategy, golden vehicles, release gates
.github/                                  Pull request template and issue forms (blank issues disabled)
assets/brand/                             Original logo and brand assets (see docs/product/BRAND.md)
planning/                                 roadmap.yml, canonical issue bodies (issues/*.md), state.json (after apply)
scripts/github/                           Idempotent roadmap validation/synchronization tooling (dry-run by default)
```

## Planning and governance documents

Root governance:

- [CONTRIBUTING.md](CONTRIBUTING.md) — workflow, Definition of Ready, Definition of Done, branch and PR expectations
- [SECURITY.md](SECURITY.md) — vulnerability reporting and the product's local-only security posture
- [docs/governance/CHANGE_CONTROL.md](docs/governance/CHANGE_CONTROL.md) — the enforced change-control rules
- [docs/governance/ROADMAP_LEDGER.md](docs/governance/ROADMAP_LEDGER.md) — written after the roadmap synchronization applies; records the roadmap IDs and server-returned issue numbers, URLs, and IDs

Product:

- [docs/product/PRODUCT_CHARTER.md](docs/product/PRODUCT_CHARTER.md)
- [docs/product/SCOPE.md](docs/product/SCOPE.md)
- [docs/product/GLOSSARY.md](docs/product/GLOSSARY.md)
- [docs/product/ROADMAP.md](docs/product/ROADMAP.md)
- [docs/product/CONTENT_AND_CLAIMS.md](docs/product/CONTENT_AND_CLAIMS.md)
- [docs/product/BRAND.md](docs/product/BRAND.md) — the adopted logo, palette, and usage rules

Architecture:

- [docs/architecture/ADR-0001-mob-liveview-on-device.md](docs/architecture/ADR-0001-mob-liveview-on-device.md) — proposed/pending-spike
- [docs/architecture/ADR-0002-netlify-static-boundary.md](docs/architecture/ADR-0002-netlify-static-boundary.md) — proposed/pending-spike

Data:

- [docs/data/SOURCE_REGISTER.md](docs/data/SOURCE_REGISTER.md)
- [docs/data/DATA_DICTIONARY.md](docs/data/DATA_DICTIONARY.md)
- [docs/data/COVERAGE_MATRIX.md](docs/data/COVERAGE_MATRIX.md)
- [docs/data/LICENSING_CHECKLIST.md](docs/data/LICENSING_CHECKLIST.md)

Quality:

- [docs/quality/TEST_STRATEGY.md](docs/quality/TEST_STRATEGY.md)
- [docs/quality/GOLDEN_VEHICLES.md](docs/quality/GOLDEN_VEHICLES.md)
- [docs/quality/RELEASE_GATES.md](docs/quality/RELEASE_GATES.md)

Planning:

- [planning/roadmap.yml](planning/roadmap.yml) — machine-readable catalog of labels, milestones, Project fields, issue metadata, parent IDs, blockers, body file paths, and field values
- `planning/issues/<roadmap-id>.md` — the canonical issue body for every epic and child issue
- `planning/state.json` — server-returned numbers, URLs, IDs, and specification hashes, written after apply; remote IDs are never hand-invented

## Execution order

The roadmap is dependency-driven across nine milestones, M00 through M08. The dependency DAG, not issue number, determines execution order. M01, M02, and permitted free-source investigation in M03 may run in parallel after their exact M00 blockers close. Milestones carry no due dates; the roadmap specifies order and gates, not a calendar.
