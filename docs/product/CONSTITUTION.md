# Digital Oil Sticker — Product Constitution

**Revision:** 1.0.0 · **Ratified:** 2026-07-31 · **Owner workstream:** Product · **Implements:** [DOS-M00-001](https://github.com/kyleruff1/digital-oil-sticker/issues/2)

This is the precedence document for the Digital Oil Sticker product. Every subsequent issue cites the invariant it implements or is bound by; when tickets conflict, this document prevails and the discovery becomes a new issue or ADR (change control, [CHANGE_CONTROL.md](../governance/CHANGE_CONTROL.md)). Amendments require a new ratified revision with fresh sign-off — never in-place edits that keep an old sign-off attached.

Key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY are used as in RFC 2119. MUST = release blocker. SHOULD = default requiring an explicit recorded exception. MAY = optional. Invariants are numbered `INV-*` and cited by later issues.

## 1. Platform promise

- **INV-1 (MUST):** Production v1 ships as native-packaged iOS and Android applications only, built with Elixir, Phoenix LiveView, and Mob. Browser execution is permitted solely as a local development convenience and is **not** a production promise. PWA/web distribution requires a separate future architecture decision (post-MVP list, SCOPE.md).
- **INV-2 (MUST):** The embedded Phoenix endpoint binds only to `127.0.0.1`. It MUST NOT listen on `0.0.0.0`, a LAN address, or any public interface. Another device on the same network MUST NOT be able to reach the endpoint.

## 2. No online accounts

- **INV-3 (MUST):** There is no registration, login, remote profile, identity provider, password reset, cloud synchronization, server-side personal record, or analytics identifier tied to a person. A **local profile** is a set of records on one installation, not an authenticated identity.
- **INV-4 (MUST):** No telemetry or third-party analytics by default. Any diagnostic export is opt-in, local, reviewable, and redacted. Personal data (VIN, mileage, notes, vehicle identifiers) never leaves the device and never appears in logs or fixtures.
- **INV-5 (MUST):** No interface may imply a local profile is backed up or recoverable unless an explicit export/import feature has shipped (DOS-M05-007 ships it for v1).

## 3. Offline-first

- **INV-6 (MUST):** The app bundle includes a usable baseline vehicle catalog. First launch, vehicle selection, status, oil-change logging, driving-usage editing, history, and due calculation all work in airplane mode with no provisioning download.
- **INV-7 (MUST NOT):** A catalog update may be offered when connectivity exists (post-MVP, M08), but connectivity MUST NOT be required to begin using, or to keep using, the installed app.

## 4. Coverage contract (ratifies the §5 planning default)

- **INV-8 (MUST):** Market: United States. Rolling window: last 30 model years — for the 2026 baseline, 1997–2026 inclusive; the window advances with each yearly catalog refresh decision.
- **INV-9 (MUST):** Vehicle classes: passenger cars, multipurpose passenger vehicles, and light pickups/vans that use engine oil. Gasoline, diesel, and hybrid configurations are included when a licensed source supports them. Battery-electric vehicles MAY appear for honest identification and show "engine oil service not applicable"; an oil plan is never invented. Heavy commercial, motorcycles, powersports, off-highway, and non-U.S. schedules are excluded from v1.
- **INV-10 (MUST):** "Major manufacturers" means: makes present in the NHTSA vPIC identity spine for the rolling window, ranked by U.S. light-duty registration presence, with the testable definition and measured coverage ratified by DOS-M00-006 and DOS-M03-001. The definition is re-examined at each catalog refresh (update cadence: with every catalog `data_version` release). Trim/build completeness depends on authoritative source coverage and cannot be inferred.
- **INV-11 (MUST):** Catalog presence and recommendation support are separate statuses: `identity_only`, `schedule_supported`, `full_product_supported`, `not_applicable`, `unsupported`. Missing data is shown as unknown or unsupported — never guessed.

## 5. Core user promise

- **INV-12 (MUST):** The app estimates when an oil change may be due from recorded mileage, elapsed time, manufacturer guidance when available, product guidance when licensed/verified, and user-entered driving samples. It does **not** read the odometer, connect to the vehicle, or diagnose anything (no telematics/OBD).
- **INV-13 (MUST):** Earlier threshold wins: a plan is due at the earlier of its sourced calendar threshold and projected mileage threshold. The prediction MAY warn earlier; it MUST NOT extend the OEM interval.
- **INV-14 (MUST):** Vehicle controls prevail: for vehicles with an oil-life monitor or condition-based maintenance, the app labels its date as an estimate and directs the user to follow the vehicle indicator and owner documentation when they disagree.
- **INV-15 (MUST):** No fabricated automotive facts. Every displayed interval, viscosity/specification, capacity, oil-product claim, and filter fitment has provenance and a license permitting offline redistribution.
- **INV-16 (MUST):** Requirements, not brand folklore: oil compatibility is the intersection of vehicle requirements and a specific product/SKU's published claims; a brand name or viscosity alone never proves compatibility. Filter compatibility is part-number/configuration-specific.

## 6. Notifications

- **INV-17 (MUST):** v1 uses operating-system scheduled **local** notifications only. No APNs/FCM infrastructure, device tokens, notification server, or accounts. Delivery is not guaranteed and the UI says so; in-app due/overdue states are the fallback.

## 7. Vehicles and scope shape

- **INV-18 (MUST):** One-vehicle MVP, multi-vehicle-safe internals: the first releasable slice exposes one active vehicle, but IDs, tables, events, and notification identifiers safely support many vehicles. Multi-vehicle UI is post-MVP (M08).
- **INV-19 (MUST):** Prohibited scope for v1 (post-MVP or never, per SCOPE.md): remote accounts and hidden server storage; cloud sync; shared garages; remote push; telematics; shop booking; commerce; ads; social features; predictive maintenance beyond oil changes; browser/PWA product; fleet administration; guaranteed notification delivery.

## 8. Safety-adjacent copy (ratifies §6 terminology)

- **INV-20 (MUST):** Results are called an "estimate" or "reminder", preserve source and effective model-year context, and direct the user to the owner's manual or a qualified service provider when data is missing or conflicting.
- **INV-21 (MUST):** Required terminology: "Meets the recorded requirements" (never "manufacturer approved" unless the source documents an OEM approval); "Estimated due date" with a confidence label; "Source unavailable" / "Exact configuration not verified" rather than a generic value. Oil-life monitor, calendar interval, mileage interval, normal service, and severe service stay distinct terms.

## 9. Measurable targets

Values marked *provisional* stand until the physical-device proofs (DOS-M00-002/003/004) supply measurements; revision then happens by explicit re-ratification, never a silent edit. A row without an owner fails review. Numbers align with the ratified DOS-M07-003 release budgets so the roadmap stays self-consistent.

| Target | Provisional value | Owner | Ratified | Verified by |
| --- | --- | --- | --- | --- |
| Cold tap-to-interactive | p95 ≤ 4.0 s, no run > 6.0 s | kyleruff1 (Product) | rc1 2026-07-31 | DOS-M00-003 → DOS-M07-003 |
| Warm start | p95 ≤ 1.5 s | kyleruff1 (Product) | rc1 2026-07-31 | DOS-M07-003 |
| On-device Phoenix readiness | included in cold-start budget; endpoint ready before first interaction | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M00-003 |
| WebView connect + LiveView socket | established within cold-start budget; auto-reconnect on resume | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M00-003 |
| LiveView interaction latency | local p95 ≤ 100 ms; first paged catalog result p95 ≤ 250 ms; subsequent filter p95 ≤ 150 ms; write+forecast recompute p95 ≤ 150 ms | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M07-003 |
| Packaged app size | per-arch compressed ≤ 50 MiB; installed app + starter catalog + empty DB ≤ 150 MiB | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M07-003 |
| Bundled catalog size | starter catalog artifact ≤ 30 MiB compressed | kyleruff1 (Data) | rc1 2026-07-31 | DOS-M03-010 → DOS-M07-003 |
| Memory | steady-state ≤ 200 MiB; growth ≤ 10% over 50 nav/add/edit cycles | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M07-003 |
| Offline readiness | all INV-6 flows pass in airplane mode on both physical platforms | kyleruff1 (QA) | rc1 2026-07-31 | DOS-M00-004 → DOS-M05-006 → DOS-M07-004 |
| Accessibility | WCAG 2.2 AA where applicable: text contrast ≥ 4.5:1 (UI components ≥ 3:1), 200% text scaling usable, touch targets ≥ 44×44 pt / 48×48 dp, full screen-reader operability | kyleruff1 (Design) | rc1 2026-07-31 | DOS-M02-002 → DOS-M07-002 |
| Minimum supported OS | iOS 16+; Android 10 (API 29)+ — provisional pending Mob 0.7.20 device proof | kyleruff1 (Eng) | rc1 2026-07-31 | DOS-M00-003 |
| User-data growth | ≤ 1 MiB per 1,000 text-only records | kyleruff1 (Data) | rc1 2026-07-31 | DOS-M07-003 |

## 10. Traceability table (invariant → verification milestone)

| Invariant | Verified by |
| --- | --- |
| INV-1 platforms | DOS-M00-002/003 (proof) · DOS-M07-007 (release) |
| INV-2 loopback-only | DOS-M00-002/003 · DOS-M07-001 (threat model) |
| INV-3 no accounts | DOS-M02-003 (UX) · DOS-M07-001 |
| INV-4 no telemetry / no data exfiltration | DOS-M07-001 (24 h idle traffic test in DOS-M07-003) |
| INV-5 no implied backup | DOS-M02-003 · DOS-M05-007 (export ships) |
| INV-6 offline first launch | DOS-M00-004 · DOS-M05-006 · DOS-M07-004 |
| INV-7 no required connectivity | DOS-M05-006 · DOS-M08-007 (updates stay optional) |
| INV-8/9 coverage window & classes | DOS-M00-006 · DOS-M03-001/005 · DOS-M03-010 |
| INV-10 major manufacturers | DOS-M00-006 · DOS-M03-001 |
| INV-11 support statuses | DOS-M03-002 · DOS-M04-004 · DOS-M05-002 |
| INV-12 estimate-only promise | DOS-M02-007 · DOS-M06-001/004 |
| INV-13 earlier threshold wins | DOS-M06-001/003 (property tests) |
| INV-14 vehicle controls prevail | DOS-M06-004 |
| INV-15 provenance or unknown | DOS-M03-001..010 · DOS-M05-003 |
| INV-16 requirements not folklore | DOS-M03-008/009 · DOS-M05-003 |
| INV-17 local notifications only | DOS-M00-005 · DOS-M06-005/006/007 |
| INV-18 multi-vehicle-safe internals | DOS-M04-003 · DOS-M08-001 |
| INV-19 prohibited scope | every milestone exit gate · DOS-M07-001 |
| INV-20/21 safety copy & terminology | DOS-M02-001..008 · DOS-M07-002 |

## 11. Tabletop review record (three required scenarios)

1. **First launch without connectivity.** Expected: onboarding explains data stays on the device; unit/time-zone choice; year→make→model selection from the bundled catalog; schedule and oil requirements shown with source attribution or an explicit `unsupported`/`identity_only` state; oil change recordable; due date computed — all in airplane mode with no permission prompt until value is clear (INV-3, INV-6, INV-11, INV-20). No network error states appear because no network is required.
2. **Loss or replacement of a phone.** Expected: records are device-local (INV-3); with no export taken, history is not recoverable and the app never implied it would be (INV-5). With a v1 export file (DOS-M05-007), import on the new device restores vehicles, history, and reminder intent; notifications are re-scheduled locally, not restored from any server (INV-17).
3. **Missing maintenance data for an otherwise selectable vehicle.** Expected: the vehicle is selectable as `identity_only`; the schedule area states "Source unavailable" (INV-21); the user may enter their owner's-manual interval manually, clearly labeled as user-entered, and reminders work from it (INV-12, INV-20); no generic default interval is fabricated (INV-15).

## 12. Sign-off

One unchanged revision is reviewed by the representatives below; ratification is recorded on issue [#2](https://github.com/kyleruff1/digital-oil-sticker/issues/2). This is a solo-founder project: one person may hold multiple roles, but each role's review is recorded explicitly.

| Role | Representative | Status |
| --- | --- | --- |
| Product | kyleruff1 | ratified 2026-07-31 (revision 1.0.0) |
| Engineering | kyleruff1 | ratified 2026-07-31 (revision 1.0.0) |
| Design | kyleruff1 | ratified 2026-07-31 (revision 1.0.0) |
| Data | kyleruff1 | ratified 2026-07-31 (revision 1.0.0) |
| QA | kyleruff1 | ratified 2026-07-31 (revision 1.0.0) |

Ratification was recorded by the owner in the working session of 2026-07-31; provisional targets in §9 carry their own ratification dates and re-ratify on measurement (DOS-M00-002/003/004).
