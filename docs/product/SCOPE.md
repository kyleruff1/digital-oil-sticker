# Digital Oil Sticker — Scope

> **Status: frozen until M00 ratification (DOS-M00-001).** These boundaries are the planning baseline. Changing them requires the M00 ratification decision or a subsequent approved ADR; per the change-control rule, work not stated in an issue's Included scope is excluded.

## MVP release candidate

- Native iOS and Android app built with Mob LiveView.
- No-login local profile and unit/time-zone preferences.
- Bundled offline catalog for the approved U.S. light-duty coverage matrix.
- One active vehicle selected by year, make, model, and the best available licensed configuration; manual fallback when exact configuration is unavailable.
- Sourced normal/severe oil-service interval, oil requirement, capacity when licensed, source attribution, and explicit unknown/unsupported states.
- Record, correct, and review oil-change events with date, odometer, oil product/manual description, filter product/manual description, and notes.
- Manual odometer check-ins and transparent projected due date.
- One or more locally scheduled reminder thresholds for the active vehicle.
- In-app due/overdue states, notification deep link, permission-denied fallback.
- Fully offline startup, CRUD, search, projection, and reminder scheduling after install.
- Static Netlify help/privacy/attribution site.

## Launch hardening, still in v1

- Data-quality sign-off against a deliberately difficult golden vehicle set.
- Import/export or another approved local recovery mechanism.
- Accessibility, performance, privacy, migration, corruption-recovery, killed-app, reboot, time-zone, and DST validation.
- Store signing, beta, store listings, release/rollback runbooks.

## Explicit post-MVP

- Multiple vehicles enabled in the UI, vehicle tabs/list switching, and per-vehicle reminders.
- Signed catalog updates from Netlify with atomic activation and rollback.
- Optional VIN scan/decode with explicit network/privacy disclosure.
- Broader oil/filter product coverage and provider operations.
- A browser/PWA or hosted Phoenix product, only after a separate decision.
- Cloud sync, shared garages, remote push, telematics, shop booking, commerce, ads, social features, and predictive maintenance beyond oil changes.

## Coverage contract to freeze in M00

This is the planning default until M00 approves a different matrix:

- Market: United States.
- Rolling window: 30 model years; for the 2026 baseline, 1997–2026 inclusive.
- Vehicle classes: passenger cars, multipurpose passenger vehicles, and light pickups/vans that use engine oil.
- Include gasoline, diesel, and hybrid configurations when a licensed source supports them.
- Pure battery-electric vehicles may appear for honest identification but show "engine oil service not applicable"; never invent an oil plan.
- Heavy commercial vehicles, motorcycles, powersports, off-highway equipment, and non-U.S. schedules are excluded from v1.
- Catalog presence and recommendation support are separate statuses: `identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, and `unsupported`.
