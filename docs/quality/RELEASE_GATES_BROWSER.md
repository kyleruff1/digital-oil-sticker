# Release gates — browser MVP

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-006](../../planning/issues/DOS-M01-006.md) AC-3.
**Supersedes for the browser MVP:** the M07 mobile-store gates in [RELEASE_GATES.md](RELEASE_GATES.md) do not apply here; that file is retained as historical for the deferred native track (ADR-0001).
**Authority:** [CONSTITUTION.md](../product/CONSTITUTION.md) §9 (measurable targets, all owner-ratified 2026-08-01), [QUALITY_POLICY.md](QUALITY_POLICY.md) (severity, blockers, exceptions), [MODULE-MAP.md](../architecture/MODULE-MAP.md) §"Enforcement gates" (test list).

Every gate below has: a **threshold** (blocking numeric or boolean), a **provenance label** (`ratified` vs `provisional` — see Constitution §9), a **verifier** (the test or workflow that proves it), and an **owner**. A release cannot pass to production without every ratified gate green; provisional gates fail-open (fail warns, not blocks) until owner-ratified.

## Blocking gates — must be green

### 1. Privacy and personal-data boundary (INV-3, INV-4, INV-23, INV-26)

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| Server repo list == `[CatalogRepo]` opened read-only | Boolean | ratified | `test/digital_oil_sticker/catalog/repo_readonly_test.exs` |
| No personal-data Ecto schema anywhere in domain | Boolean | ratified | `test/digital_oil_sticker/no_personal_ecto_schema_test.exs` |
| No personal-data persistence path on the server | Boolean | ratified | `test/digital_oil_sticker/no_personal_persistence_test.exs` |
| Catalog query surface is impersonal | Boolean | ratified | `test/digital_oil_sticker/catalog/impersonal_selector_test.exs` |
| Scripted session log-scan contains no personal value | Boolean | ratified | `test/digital_oil_sticker/production_posture_test.exs` |
| No third-party origin reachable from the app | Boolean | ratified | `conformance/` request-log check + `production_posture_test.exs` |
| No OS-notification code path (INV-17) | Boolean | ratified | `test/digital_oil_sticker/no_os_notifications_test.exs` |

### 2. Domain and static-content boundary (INV-27)

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| App CSP forbids `'unsafe-inline'` and third-party origins | Boolean | ratified | `production_posture_test.exs` |
| Netlify static site carries no runtime path (no Functions, no service worker, no PWA manifest) | Boolean | ratified | Owner audit + `INV-27-CONTENT-BOUNDARY.md` checklist |
| App makes zero requests to Netlify origin | Boolean | ratified | Conformance suite request log |
| Attribution page and `SOURCE_REGISTER.md` in sync | Boolean | ratified | Owner sweep pre-release |

### 3. Hydration protocol correctness (INV-24)

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| Idempotent re-hydrate produces identical assigns and emits no write-back | Boolean | ratified | `test/digital_oil_sticker_web/local_store/idempotence_test.exs` |
| Every route in `:garage` live_session mounts the LocalStore hook | Boolean | ratified | `test/digital_oil_sticker_web/hydration_wiring_test.exs` |
| Four hydration states (`:hydrating`, `:empty`, `:storage_unavailable`, `:data_missing`) render distinctly | Boolean | ratified | `test/digital_oil_sticker_web/live/error_mapping_test.exs` + `storage_recovery_test.exs` |
| `:hydration_refused` never masquerades as data loss | Boolean | ratified | `test/digital_oil_sticker_web/live/hydration_refused_test.exs` |
| Domain output deterministic under a fixed Clock | Boolean | ratified | `test/digital_oil_sticker/clock_determinism_test.exs` |

### 4. Catalog artifact integrity

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| Committed catalog matches its manifest SHA + row counts | Boolean | ratified | `test/digital_oil_sticker/catalog/fixture_manifest_test.exs` |
| Catalog build is deterministic across two runs | Boolean | ratified | `.github/workflows/ci.yml` `catalog-tools` job |
| No runtime call to a third-party catalog data provider | Boolean | ratified | `test/digital_oil_sticker/no_runtime_catalog_sources_test.exs` |

### 5. Transport security (INV-22)

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| `check_origin` set to the production allowlist (not `true`, not `false`) | Boolean | ratified | `test/digital_oil_sticker/deploy_config_test.exs` |
| `force_ssl` on; HTTP → HTTPS redirect fires | Boolean | ratified | Deploy-time probe against `digitaloilsticker.com` |
| HSTS served only after both hostnames' certs verified | Boolean | ratified | Owner one-time flip after cert issuance |
| Session cookie contents restricted to `_csrf_token` + `live_socket_id`; `Secure` + `HttpOnly` + `SameSite=Lax`; short `max_age` | Boolean | ratified | `production_posture_test.exs` |
| CSRF-absent socket connect rejected | Boolean | ratified | `conformance/` negative-connect test |

### 6. Multi-tab and privacy on the wire

| Gate | Threshold | Provenance | Verifier |
| --- | --- | --- | --- |
| Two-tab mutation test passes with no silent stale overwrite (INV-24.7) | Boolean | ratified 2026-08-01 | `conformance/` two-tab suite |
| 24 h idle capture shows zero outbound requests beyond the app origin; no request carries a personal field | Boolean | ratified rc1 2026-07-31 (re-ratified 2026-08-01) | Owner pre-release capture |

## Blocking numeric gates (ratified)

Per Constitution §9 these have owners and ratification dates. Provisional labels are the constitution's — do not remove without a re-ratification.

| Metric | Threshold | Provenance | Measurement |
| --- | --- | --- | --- |
| Client storage footprint | ≤ 1 MiB per 1,000 text-only records; total origin footprint held under 5 MiB working ceiling; quota-exceeded handled visibly | **ratified rc1 2026-07-31, re-ratified 2026-08-01** | Storage-status page + `Caps` unit tests |
| Privacy on the wire | Zero outbound requests to non-app origins over 24 h idle; no personal field in any request | **ratified rc1 2026-07-31, re-ratified 2026-08-01** | Owner pre-release capture |
| Accessibility — WCAG 2.2 AA | Text contrast ≥ 4.5:1 (UI + graphical ≥ 3:1); usable at 200 % zoom and 320 CSS px reflow; full keyboard operability with visible focus and no traps; target size ≥ 24×24 CSS px (≥ 44×44 SHOULD where touch is primary); screen-reader operability including live-region announcement of due-state and hydration changes | **ratified rc1 2026-07-31, re-ratified 2026-08-01** | Owner audit (VoiceOver on iOS Safari, TalkBack on Android Chrome, NVDA on Windows Firefox+Chrome) + axe automated pass |
| Honest-degradation coverage | Every INV-7 / INV-24.3–24.8 / INV-25 state has a specified screen and an automated or scripted test | **ratified 2026-08-01** | Test-suite coverage of `local_state` and `hydration_refused` |
| Multi-tab consistency | Two-tab mutation test passes with no silent stale overwrite | **ratified 2026-08-01** | `conformance/` two-tab suite |

## Provisional numeric gates — warn, do not block

All rows below are Constitution §9 provisional. They report but do not block until the owner ratifies against real measurement on the deployed `digitaloilsticker.com` target. Numbers are the constitution's; the release-gate job flags any threshold breach as `warn`, and the release row records the actual number for the ratification conversation.

| Metric | Provisional threshold | Provenance | Measurement |
| --- | --- | --- | --- |
| Page load — LCP | p75 ≤ 2.5 s on 4G-class connection, mid-tier mobile; no run > 4.0 s | provisional 2026-08-01 | Conformance Lighthouse job |
| Page load — TTI / first interaction ready | p75 ≤ 3.5 s; interactive controls MUST NOT accept input before hydration state is known | provisional 2026-08-01 | Conformance suite |
| LiveView socket connect | Static-to-live p95 ≤ 1.0 s after HTML paint; automatic reconnect p95 ≤ 2.0 s re-running hydration | provisional 2026-08-01 | Conformance suite |
| Hydration completion | IndexedDB read → `pushEvent` → assigns populated, p95 ≤ 300 ms after socket join | provisional 2026-08-01 | Conformance instrumented run |
| Server response — HTTP TTFB | p95 ≤ 400 ms | provisional 2026-08-01 | Fly metrics + release probe |
| Server response — LiveView event round trip | p95 ≤ 150 ms measured from the client | provisional 2026-08-01 | Conformance suite |
| Catalog query p95 | First paged result p95 ≤ 250 ms server-side; subsequent filter p95 ≤ 150 ms | provisional 2026-08-01 | `Catalog.Telemetry` + release probe |
| First-visit payload | Initial HTML+CSS+JS ≤ 250 KiB compressed; total first-visit transfer ≤ 500 KiB; zero third-party origins | provisional 2026-08-01 | Conformance suite (network capture) |
| Repeat-visit payload | ≤ 60 KiB compressed on warm HTTP cache, excluding catalog query results | provisional 2026-08-01 | Conformance suite |
| Browser support matrix | Current + prior stable Chrome, Edge, Firefox, Safari desktop; iOS Safari 16+; Android Chrome | provisional 2026-08-01 | `docs/quality/SUPPORT_MATRIX.md` + conformance runner |

## Release-evidence bundle

Every production release records a row in [RELEASE_LEDGER.md](../governance/RELEASE_LEDGER.md) carrying all 13 fields (date, reason, commit, app version, catalog `data_version`, catalog SHA256, LocalStore schema version, Fly release number, image ref + digest, rollback target, ready-probe status, conformance report reference, evidence links). The deploy workflow captures the ledger row automatically; the human writes only the `reason` field.

## Exceptions

A ratified gate can be skipped only via a QUALITY_POLICY.md §4 exception record — check name, reason, owner, expiration, mitigation — filed in `docs/quality/EXCEPTIONS.md` (create when first exception is filed). A missing exception with a skipped required check is itself a release blocker.

## Owner ratification checklist for provisional rows

To move a row from provisional to ratified:
1. Run the measurement on the deployed `digitaloilsticker.com` target (post custom-domain flip).
2. Record the measured value in the corresponding Constitution §9 row.
3. Set an owner and ratification date on that row (edit CONSTITUTION.md; commit references this file).
4. Remove the provisional label here (edit RELEASE_GATES_BROWSER.md in the same PR).
5. Add the metric to the deploy workflow's blocking-gate list.
