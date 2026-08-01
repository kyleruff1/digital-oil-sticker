# Test Strategy

This document sets the testing intent for Digital Oil Sticker before any application code exists. Implementation issues inherit these rules; they do not restate or weaken them.

## Test pyramid intent

1. **Unit and property tests on the pure domain.** `DigitalOilSticker.Forecasting` and the recommendation resolver are deterministic pure functions (mileage rate, confidence, due thresholds, reason codes; `verified`/`partial`/`conflict`/`unsupported`/`not_applicable` resolution). They get the densest coverage: example-based units plus property tests for invariants such as "the prediction may warn earlier; it may never extend the OEM interval," "unknown never collapses to compatible," and "earlier threshold wins."
2. **Integration tests on the repos and the broker.** `CatalogRepo` and `UserRepo` (SQLite, `pool_size: 1`, no cross-database foreign keys), forward migrations, catalog verification/bootstrap, and the `DeviceCommandBroker` dispatch/correlation/timeout/redaction seam. Broker tests run against a fake root screen in CI; the real plugin path is a device concern.
3. **Physical-device gates.** Behavior that only real hardware can prove: the M00 loopback LiveView spike (DOS-M00-003), local notification delivery, killed-app and reboot behavior, and the M07 cross-platform QA matrix (DOS-M07-004). No emulator result substitutes for a required physical-device gate.

## No wall-clock dependence

All date/time logic goes through the injected `DigitalOilSticker.Clock` UTC/local date and time-zone behaviour so tests do not depend on wall-clock time. No test may sleep to reach a deadline, read the system clock directly in domain assertions, or fail depending on the day it runs. Time-zone and DST cases are explicit fixtures, not accidents of the CI host.

## Offline-first testing

The app must work in airplane mode from first launch. The test plan therefore includes, on physical devices in airplane mode: startup, vehicle selection (catalog CRUD and search), service-event recording, projection, and reminder scheduling — with no network from install onward. Runtime calls to NHTSA or a commercial source are never required for manual vehicle selection, service history, projections, or reminders.

## Physical-device matrix requirement

Required device tests run on a documented matrix of physical iOS and Android devices (recorded per issue in its Manual/device matrix section). The matrix must exercise: offline operation, migration and corruption recovery, killed-app and reboot behavior, time-zone changes, DST transitions, notification permission denial, and [Mob background-execution constraints](https://mob.hexdocs.pm/background_execution.html). Local notifications follow the OS-held request model in [Mob device capabilities](https://mob.hexdocs.pm/device_capabilities.html); tests verify reconciliation, not background polling.

## Golden vehicles

Data-quality sign-off runs against a deliberately difficult golden vehicle set (see `docs/quality/GOLDEN_VEHICLES.md`): EVs that must resolve `not_applicable`, oil-life-monitor vehicles, severe-service variants, unknown-configuration fallbacks, and unit-conversion edge cases. Golden vehicles are fixtures for resolver, forecast, and UI-state tests; a catalog release that regresses a golden vehicle fails its gate.

## Definition of Ready

An issue may enter `Ready` only when:

- its outcome, Included, and Excluded sections are explicit;
- acceptance criteria are independently testable;
- required designs/data fixtures/source rights/ADRs exist;
- no blocking product, licensing, architecture, or QA question remains;
- native parent and blocked-by relationships are accurate;
- data/privacy/accessibility/offline sections are answered or marked `N/A — reason`;
- implementation can finish without silently broadening scope.

## Definition of Done

An implementation issue is Done only when acceptance evidence is attached, automated and required physical-device tests pass, migrations/recovery are verified where applicable, documentation and source attribution are updated, logs/fixtures contain no private vehicle data, the linked PR uses `Closes #…`, and follow-up discoveries have their own issues. An epic closes only after every required child and its aggregate integration gate pass.

## Evidence requirements

- Every acceptance criterion is satisfied by attached evidence (test output, device recording, migration log, coverage report), not by assertion.
- Physical-device evidence names the device, OS version, and build under test.
- Logs and fixtures are redacted: no VIN, mileage, notes, or vehicle identifiers that belong to a real person.
- Do not report success for a behavior that was not read back and verified; read-back over claims.
