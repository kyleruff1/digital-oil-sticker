# Digital Oil Sticker — Roadmap

The roadmap is dependency-driven: nine milestones, each led by an epic issue with child issues. The machine-readable plan lives in [`planning/roadmap.yml`](../../planning/roadmap.yml). After the GitHub sync, GitHub Issues and the GitHub Project are the live tracker; this document is orientation, not status.

Issue totals: 9 epics plus 68 children = 77 issues. Per-milestone child counts: M00 = 6, M01 = 6, M02 = 8, M03 = 10, M04 = 10, M05 = 7, M06 = 7, M07 = 7, M08 = 7.

## Milestones

### M00 — Decisions & Proof (DOS-M00-000, 6 children)

Convert the product idea into tested constraints and written decisions, then prove the binding runtime architecture: a Mob `0.7.20` application generated with `mix mob.new digital_oil_sticker --liveview`, with BEAM/Phoenix running entirely on the device, a native WebView loading LiveView over IPv4 loopback, two on-device Ecto/SQLite repositories, and `mob_notify` local notifications. Netlify is a separate static publishing surface and is never the application runtime.

### M01 — Engineering Foundation (DOS-M01-000, 6 children)

Implement only the platform skeleton selected by M00: the Mob `0.7.20` on-device LiveView runtime, strict loopback hardening, two Ecto/SQLite repositories, a tiny bundled fixture catalog, `mob_notify` adapter boundary, a separate static Netlify support site, and automated quality gates. The foundation must make privacy, offline, and runtime-boundary constraints hard to violate accidentally.

### M02 — UX & Content Contract (DOS-M02-000, 8 children)

Produce implementation-ready flows, component/state specifications, content rules, accessibility expectations, and testable native-mobile prototypes for local onboarding, one active MVP vehicle, oil-change records, forecasts, and reminders. Preserve a clearly separated post-MVP design direction for multi-vehicle tabs/search without adding it to MVP implementation acceptance. Designs must show offline, missing-data, denied-permission, native-runtime failure, and destructive states—not only the happy path.

### M03 — Data Acquisition & Offline Catalog (DOS-M03-000, 10 children)

Produce a reproducible, legally distributable, versioned, read-only offline catalog artifact for a rolling 30-model-year scope. The artifact supports deterministic vehicle lookup and, only where licensed evidence exists, oil-service schedules, vehicle lubricant requirements, API-licensed oil products, and oil-filter fitment.

### M04 — Local Domain & Persistence (DOS-M04-000, 10 children)

Implement separate read-only catalog and mutable user-data persistence boundaries that work offline, survive upgrades/crashes, support multiple vehicles from day one, and require no online account or server-side personal-data store.

### M05 — Single-Vehicle, Local-Only, Offline MVP (DOS-M05-000, 7 children)

A first-time user can install the native Digital Oil Sticker app, select one exact vehicle from the bundled catalog without a network connection, save one local vehicle profile, record an oil change and odometer readings, and understand the vehicle's current time/mileage service position. No sign-in, cloud database, remote profile, or network dependency is allowed in the core journey.

### M06 — Usage Forecasting and On-Device Local Notifications (DOS-M06-000, 7 children)

Digital Oil Sticker converts the selected interval, service history, manually sampled odometer history, and an optional declared typical-driving baseline into a deterministic, explainable estimate. It identifies the earlier of the time and projected-mileage thresholds and schedules private, on-device reminders through `mob_notify`; it never requires a user account, remote job, APNs/FCM push service, or a running/backgrounded BEAM process.

### M07 — Hardening, Closed Beta, and Store Release (DOS-M07-000, 7 children)

The single-vehicle app is accessible, private, secure, supportable, performant, migration-safe, and demonstrably reliable on the declared iOS/Android matrix. Signed release builds and truthful store/Netlify materials can move through closed beta to staged production without introducing accounts or behavioral telemetry.

### M08 — Post-MVP Multi-Vehicle Garage and Signed Catalog Operations (DOS-M08-000, 7 children)

A user can maintain many fully isolated vehicles, switch among them through an accessible tabbed garage, and receive correctly budgeted reminders for each. The data team can build, sign, publish, audit, roll back, and retire public catalog packs on Netlify; clients can verify and atomically activate them without risking private vehicle/history data or losing offline operation.

## Epic-level dependency DAG

```mermaid
flowchart TD
    M00["M00: Decisions and proof"] --> M01["M01: Engineering foundation"]
    M00 --> M02["M02: UX and content contract"]
    M00 --> M03["M03: Data acquisition and catalog"]
    M01 --> M04["M04: Local domain and persistence"]
    M03 --> M04
    M02 --> M05["M05: Single-vehicle MVP"]
    M04 --> M05
    M05 --> M06["M06: Forecasting and reminders"]
    M03 --> M07["M07: Hardening and release"]
    M06 --> M07
    M07 --> M08["M08: Post-MVP expansion"]
```

## Parallelism

M01, M02, and permitted free-source investigation in M03 may run in parallel after their exact M00 blockers close. Do not mark a downstream issue Ready merely because work could be prototyped; its native blockers and source rights remain authoritative.
