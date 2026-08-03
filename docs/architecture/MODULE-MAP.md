# Browser-first module map

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-002](../../planning/issues/DOS-M01-002.md) AC-1.
**Authority:** [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) (browser-first client and hosting), [ADR-0003](ADR-0003-data-boundaries.md) (data boundaries), [CONSTITUTION.md](../product/CONSTITUTION.md) revision 2.0.0 (INV-1, INV-3, INV-17, INV-22, INV-23, INV-24, INV-25, INV-26, INV-27).

This document names every module in the browser-MVP tree, what it owns, and the dependency directions it is allowed to have. It is the ground truth the automated boundary tests enforce. When it and the code disagree, the code is wrong or this document is stale — one of the two must change in the same PR.

## Layered view

```
+---------------------------------------------------------------------------+
|  Presentation (server-rendered, LiveView)                                 |
|  DigitalOilStickerWeb.*.Live / *.Components / Copy / Router / Endpoint    |
|         ↑ speaks to → domain public APIs, LocalStore.Session              |
+---------------------------------------------------------------------------+
|  Web adapters (hosted-endpoint hardening + protocol edges)                |
|  DigitalOilStickerWeb.LocalStore.Session / LocalStoreHook                 |
|  DigitalOilStickerWeb.CatalogEvents / Plugs / Hosts / Telemetry           |
|         ↑ speaks to → domain ports; owns Phoenix/Plug wiring              |
+---------------------------------------------------------------------------+
|  Domain (deterministic, framework-free)                                   |
|  DigitalOilSticker.Catalog / Due / IntervalPolicy / Units / Clock         |
|  DigitalOilSticker.LocalStore (pure modules) / CalendarExport             |
|  DigitalOilSticker.StickerCode                                            |
|         ↑ speaks to → CatalogRepo (read-only), Clock                      |
+---------------------------------------------------------------------------+
|  Infrastructure (single-purpose adapters)                                 |
|  DigitalOilSticker.CatalogRepo (Ecto, read-only SQLite)                   |
|  DigitalOilSticker.Application / .Release                                 |
+---------------------------------------------------------------------------+
```

## Domain modules — `DigitalOilSticker.*`

Deterministic, no Phoenix, no Plug, no LiveView, no framework acquisition of an Ecto repo other than `CatalogRepo`. Enforced by `test/digital_oil_sticker/namespace_boundary_test.exs`.

| Module | Owns | Depends on |
| --- | --- | --- |
| `Catalog` (facade) + `Catalog.{Vocabulary, Selector, Result, Status, Metadata, Cursor, Cache, RateLimit, SourceGate, OilModel, Telemetry}` and `Catalog.Queries.*` | The read-only impersonal catalog query surface. Closed vocabulary, structural rejection of personal keys (INV-26). | `CatalogRepo`, `Clock` |
| `LocalStore.{Envelope, Caps, Validation, Migrations, Quarantine, Schema.V1}` | Pure protocol modules for the hydration envelope, quarantine, forward-only schema migration, per-store caps. Server-side implementation of ADR-0004 §"Payload envelope". | — |
| `Due` | The single answer to "when is the next oil change." Basis is the odometer AT the change, not now. | `Catalog.OilModel`, `IntervalPolicy`, `Units` |
| `IntervalPolicy` | Resolves an interval for a vehicle from its maintenance plan and oil model. | `Catalog.OilModel` |
| `Units` | Canonical integer metres; mi/km round-trip. | — |
| `Clock` | Time-source port; injected in tests via `Application.put_env/3` for determinism (AC-9). | — |
| `CalendarExport` | ICS reminder file generation. Zero side effects; no OS notification path exists (AC-4, INV-17). | `Clock` |
| `StickerCode` | Sticker deep-link encoding. Impersonal identifiers only. | — |
| `CatalogRepo` | Sole server-side Ecto repo. Opened `read_only: true`, `journal_mode: nil`, PRAGMA `query_only = ON`. Baked SQLite artifact, chmod 0444 in the image. | Ecto |

## Web layer — `DigitalOilStickerWeb.*`

Speaks to the domain through public APIs; owns Phoenix/Plug/LiveView wiring. Personal state lives only in `socket.assigns` for one connection's lifetime (INV-23).

| Module | Owns |
| --- | --- |
| `Endpoint`, `Router` | HTTP/WSS entry. `check_origin` allowlist from `Hosts`. |
| `Hosts` | Origin allowlist consumed by `check_origin`. |
| `Plugs.*` | CSP header composer (no third-party origins, no `'unsafe-inline'`), session-cookie invariants (`_csrf_token` + `live_socket_id` only). |
| `Telemetry` | Query-shape metrics only; never values (INV-4). |
| `Copy` | Every user-facing string. Copy-lint enforces INV-25 wording; forbidden words (`saved to your account`, `synced`, `backed up`, `restore`) fail the build. |
| `Components.*` | Presentation-only HEEx components. |
| `Live.LocalStoreHook` (`on_mount :default` for `:garage` live_session) | Attaches protocol event/info hooks so every LiveView in `:garage` shares the LocalStore protocol with zero duplication. |
| `LocalStore.Session` | **The sole mutator of LocalStore assigns.** Holds the hydration state machine (`local_state ∈ :hydrating \| :loaded \| :empty \| :storage_unavailable \| :data_missing \| :hydration_refused`), pending-write ledger, deadline/ack timers, mutation staging, unsaved-write ledger. Documented deviation from the domain namespace because it composes Phoenix-specific push_event calls; enforced by the domain-boundary test that excludes it from the domain scan. |
| `CatalogEvents` | Compiled allowlist mapping the 8 `catalog:*` event names to `Selector` calls. |
| `Live.{Sticker, VehiclePicker, VehicleProfile, OilChange, History, StorageStatus}Live` | The garage's LiveViews. Presentation only; use `Session` for mutation and read domain APIs directly. |

## Ports and their production/test implementations

| Port | Production implementation | Test double |
| --- | --- | --- |
| Catalog query | `DigitalOilSticker.Catalog` facade → `CatalogRepo` (read-only SQLite artifact). Closed vocabulary `%Selector{}` inputs. | Ecto `CatalogRepo` opened against `catalog-fixture-a.sqlite3`. |
| LocalStore (browser storage) | Owned by `DOS-M09-002`: JS `phx-hook="LocalStore"` + IndexedDB adapter. Server-side, `LocalStore.Session` handles hydrate/put/ack/conflict over `push_event`. | In-process: `render_hook/3` in LiveView tests drives the four protocol events against a real `Session`. `LocalStore.Envelope`/`Validation`/`Caps` are pure and unit-tested in isolation. |
| Clock / timezone | `DigitalOilSticker.Clock.System` (UTC). | Any module implementing `@behaviour DigitalOilSticker.Clock`; injected via `Application.put_env(:digital_oil_sticker, :clock, MyFixedClock)`. Proven deterministic by `clock_determinism_test.exs`. |
| ID generation | Client-side UUIDv4 (per ADR-0004 §"Storage layout"). Server ids: `LocalStore.Session.generate_id/0` from `:crypto.strong_rand_bytes/1` for mutation ids only. | Fixed ids in test fixtures. |
| In-app due state | `DigitalOilSticker.Due.compute/2`, deterministic in `(vehicle, event)`. | Same code path; fixtures drive it. |
| Export/import file pipeline | `CalendarExport` (ICS); JSON export/import owned by StorageStatusLive. | Round-trip tested in `storage_recovery_test.exs`. |
| LiveView socket lifecycle | `Live.LocalStoreHook` on_mount + `Session.init/1`. Reconnect drives re-hydration; `terminate/2` relies on Phoenix's built-in cleanup (open-question per DOS-M01-002 resolved by DOS-M09-003). | LiveViewTest `live/2` + `render_hook/3`. |
| Rate limit | Tier 1: pure token bucket in `Catalog.RateLimit`, held in socket assigns. Tier 2: web-layer per-IP HMAC (DOS-M09-007). | Direct `RateLimit.new/take` in tests. |
| CSP / cookies / origin allowlist | `Plugs.*`, `Hosts`. | `production_posture_test.exs`. |

## LocalStore protocol message set

Server ↔ browser, over `push_event` / `pushEvent`. Envelope shape per ADR-0004 §"Payload envelope".

- `local_store:hydrate` — hook → server; full envelope on mount and reconnect. Idempotent (AC-5, `idempotence_test.exs`).
- `local_store:put` — server → hook; `{mutation_id, seq, upserts, deletes}`. Never emitted during passive re-hydrate.
- `local_store:ack` — hook → server; `{mutation_id, seq, status}`. Timeout → `:unsaved`.
- `local_store:conflict` — hook → server; stale-`seq` compare-and-set failure. Re-arms hydration deadline, sets `:hydrating`, pushes `local_store:rehydrate`.
- `local_store:rehydrate` — server → hook; ask for a fresh envelope.
- `local_store:persist_result` — hook → server; result of the `persist()` permission call.
- `local_store:erase` — server → hook; user confirmed erase from `StorageStatusLive`.

## Error taxonomy → assigns states

Every error the LocalStore protocol can produce maps to exactly one `local_state`. Raw exceptions do not cross into presentation. Enforced by `error_mapping_test.exs`.

| Origin | `local_state` | UX copy source |
| --- | --- | --- |
| Successful hydrate, non-empty | `:loaded` | domain UI |
| Successful hydrate, empty + intentional emptying | `:empty` | `Copy.empty_*` |
| Successful hydrate, empty + `boot_hint == "has_data"` | `:data_missing` | `Copy.data_missing_*` |
| `session_only` storage mode | `:storage_unavailable` | `Copy.storage_unavailable_*` |
| Generic envelope validation failure | `:storage_unavailable` | same |
| Hydration deadline expired | `:storage_unavailable` | same |
| Cap exceeded (payload_bytes / vehicles / events / readings) | `:hydration_refused` | `Copy.hydration_refused_*` (INV-25: never masquerade as data loss) |
| Newer schema than server understands | `:loaded` + `read_only: true` | `Copy.read_only_banner` |
| Stale-seq conflict | back to `:hydrating` + `conflict_notice: true` + rehydrate | — |

## Retired: pre-pivot on-device-bridge modules

Per ADR-0004's supersession of ADR-0001, the following pre-pivot module namespaces are **absent** from the tree and no longer part of the design:

- `DigitalOilSticker.MobScreen` and any `Mob.*` type
- `DigitalOilSticker.DeviceCommandBroker` and its command envelope
- Any `Mob.Socket` binding, `mob_notify` call site, or native root-screen adapter
- Any OS-notification scheduling module or in-process background scheduler for reminders

Their absence is a passing test: `test/digital_oil_sticker/namespace_boundary_test.exs` scans domain sources and the `no_os_notifications_test.exs` scanner rejects the API surface. Adding any of these back would fail CI at the module boundary rather than at manual audit.

## Enforcement gates (release-blocking)

| Rule | Test |
| --- | --- |
| Domain isolated from `Phoenix.LiveView`, `Plug`, `DigitalOilStickerWeb`, `use Ecto.Repo` | `test/digital_oil_sticker/namespace_boundary_test.exs` |
| Catalog port accepts no personal identifier | `test/digital_oil_sticker/catalog/impersonal_selector_test.exs` |
| `CatalogRepo` opened read-only, `journal_mode` prevents `-wal`/`-shm`, PRAGMA `query_only` on | `test/digital_oil_sticker/catalog/repo_readonly_test.exs` |
| Only one Ecto repo in the tree, and it is `CatalogRepo` | same |
| No personal data on the server (no schemas/migrations/backups; no third-party origins) | `test/digital_oil_sticker/no_personal_persistence_test.exs` |
| No OS-notification code path | `test/digital_oil_sticker/no_os_notifications_test.exs` |
| Log-scrub scaffold and hardening-port surface | `test/digital_oil_sticker/production_posture_test.exs` |
| Error → `local_state` mapping is one-to-one | `test/digital_oil_sticker_web/live/error_mapping_test.exs` |
| Re-hydrating the same envelope is idempotent, emits no write-back | `test/digital_oil_sticker_web/local_store/idempotence_test.exs` |
| Domain output deterministic under a fixed `Clock` | `test/digital_oil_sticker/clock_determinism_test.exs` |
| Every route in the `:garage` live_session mounts the LocalStore hook element | `test/digital_oil_sticker_web/hydration_wiring_test.exs` |

## Cross-references

- ADR-0004 §"Enforcement" — the four enforcement bullets are implemented by the tests in the table above.
- ADR-0003 — data boundaries; catalog vs. personal data.
- Constitution 2.0.0 INV-23/INV-24/INV-25/INV-26 — the privacy and hydration invariants this map protects.
