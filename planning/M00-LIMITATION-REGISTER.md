# M00 Limitation Register

Date: 2026-08-02
Epic: DOS-M00-000 — Freeze the feasible product architecture before feature development
Authority: FR-7 (exit — limitation register), AC-4

Every consciously accepted browser-first limitation is recorded below with an owner, a user-facing fallback, and a review date. These six entries are the minimum required by FR-7; additional entries may be added as implementation surfaces them.

## 1. No offline capability

| Field | Value |
| --- | --- |
| **Limitation** | The application requires an internet connection to function. The catalog is served from Fly.io; no service worker or local cache provides offline access to catalog data. |
| **ADR reference** | ADR-0004 §"Consequences → Lost — honestly" |
| **Owner** | kyleruff1 |
| **User-facing fallback** | Honest "unable to reach the server" state; personal data in IndexedDB remains accessible for export even when the server is unreachable. No copy implies offline capability. |
| **Review date** | 2027-02-01 (PWA/service-worker decision tracked as DOS-M09-010) |

## 2. No OS local notifications

| Field | Value |
| --- | --- |
| **Limitation** | The browser-first MVP cannot deliver OS-level notifications when the app is closed. `mob_notify` is a native binding with no browser equivalent. Web Push is explicitly deferred. |
| **ADR reference** | Constitution 2.0.0 §6 INV-17 (amended); ADR-0004 §"Consequences → Lost — honestly" |
| **Owner** | kyleruff1 |
| **User-facing fallback** | In-app due-state display ("Estimated due date", "Overdue") visible on the sticker view at every visit. No copy promises notification when the browser is closed. Rescoped M06 owns the in-app due-state fallback UX. |
| **Review date** | 2027-02-01 (Web Push decision tracked as DOS-M09-010) |

## 3. Storage eviction risk

| Field | Value |
| --- | --- |
| **Limitation** | Browser engines may evict IndexedDB data for infrequently visited sites. Quarterly oil-change cadence is exactly the at-risk usage profile. |
| **ADR reference** | ADR-0004 R1 |
| **Owner** | kyleruff1 |
| **User-facing fallback** | `navigator.storage.persist()` called after first write; honest storage-status UI; export nudges; `:data_missing` state (not `:empty`) when `dos_boot_state == "has_data"` but zero records hydrate (INV-24, INV-25). No copy implies data is backed up. |
| **Review date** | 2027-02-01 (measure actual eviction behavior per browser/engine after DOS-M09-008 conformance suite) |

## 4. Single-region, single-machine availability

| Field | Value |
| --- | --- |
| **Limitation** | The Fly.io deployment runs in a single region (ord) with `min_machines_running = 1` and `auto_stop_machines = "off"`. Total-outage risk exists that the loopback posture did not have. |
| **ADR reference** | ADR-0004 R8 |
| **Owner** | kyleruff1 |
| **User-facing fallback** | Personal data in IndexedDB survives server outages. Export is available at any time. No SLA is communicated to users. The sticker view renders cached values from the last hydration while the server is down; catalog queries fail honestly. |
| **Review date** | 2027-02-01 (evaluate multi-region or standby machine based on usage) |

## 5. Void pre-pivot latency and packaged-size budgets

| Field | Value |
| --- | --- |
| **Limitation** | Constitution 2.0.0 §0.3 records that the pre-pivot §9 latency budgets (loopback round-trip) and packaged-size budgets (iOS/Android app size) are void under the hosted model. Replacement browser-first budgets (time-to-hydrated, LiveView interaction p95 by geography, IndexedDB footprint per record, first-paint payload) are provisional and must be measured. |
| **ADR reference** | ADR-0004 R9; Constitution 2.0.0 §0.3 |
| **Owner** | kyleruff1 |
| **User-facing fallback** | N/A (internal quality metric). If measured latencies exceed provisional budgets, the budgets are revised with explicit approval rather than silently accepted. |
| **Review date** | M07 (DOS-M07-003, rescoped — performance measurement milestone) |

## 6. Operator-console honesty caveat

| Field | Value |
| --- | --- |
| **Limitation** | A Fly.io operator with `fly ssh console` access can read the CatalogRepo file and inspect BEAM process state including transient `socket.assigns`. Personal data exists transiently in server memory during a LiveView session. LiveDashboard is disabled in production, but operator console access is a stated honest risk. |
| **ADR reference** | ADR-0004 §"LiveDashboard and operator access — stated honestly" |
| **Owner** | kyleruff1 |
| **User-facing fallback** | Privacy documentation states honestly that operator console access exists; no copy claims "we never see your data" or "zero-knowledge." The operator is the sole owner (kyleruff1). Log redaction (no VIN/odometer/notes in logs) reduces the exposure surface but does not eliminate transient in-memory visibility. |
| **Review date** | 2027-02-01 (revisit if the operator pool expands beyond the sole owner) |
