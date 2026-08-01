# §9 re-ratification proposal — measured browser support and multi-tab consistency

**Proposed 2026-08-01 by DOS-M09-008. NOT yet ratified. §9 of the constitution is deliberately left unedited until the owner ratifies this** (FR-23, AC-21).

Evidence: `conformance/reports/conformance-live-all-*.json`, run against the deployed application at https://digital-oil-sticker.fly.dev.

---

## Row: `Browser support matrix`

**Current text (provisional):**

> *provisional* current and prior stable release of Chrome, Edge, Firefox, and Safari (desktop), plus iOS Safari 16+ and Android Chrome; IndexedDB availability probed at runtime (INV-24.6)

**Proposed text (measured):**

> **Measured** on three engines — Chromium 141, Gecko 142, WebKit 26 — each passing all 17 runnable storage, privacy, and accessibility assertions. Support is a property of the **engine**; shells sharing an engine are not counted separately, and the version policy is a rule in `docs/quality/SUPPORT_MATRIX.md` rather than a list. IndexedDB availability is probed at runtime and never inferred from a user-agent string (asserted by `bundle.no-user-agent-branching`). **iOS Safari and Android Chrome remain unproven:** they are exercised only through desktop engine builds, which share the engine but not the platform's storage behavior, and no physical-device run has been performed.

**What changed and why.** The provisional row named browsers; the measured row names engines, because that is what the assertions actually exercise and what the fallback behavior actually depends on. It also removes the implication that iOS Safari 16+ and Android Chrome are covered — they are named as targets in the matrix, and reported unproven, until real hardware runs them.

## Row: `Multi-tab consistency`

**Current text:**

> two-tab mutation test passes with no silent stale overwrite (INV-24.7)

**Proposed text (measured):**

> **Measured** on all three Tier 1 engines: a commit in one tab is reflected in the other, and the compare-and-set on `meta.seq` prevents lost updates **with and without `BroadcastChannel`**. The degraded path — `BroadcastChannel` deleted before any application script runs — was asserted separately and passes; without it the other tab converges on its next hydration rather than immediately, and no duplicate or lost record was observed.

**What changed and why.** The original row did not distinguish the two mechanisms. `BroadcastChannel` provides promptness; the compare-and-set provides correctness. Only the second is a safety property, and it is now asserted independently of the first.

## Row: `Accessibility` — evidence, no text change proposed

No wording change is proposed, but the row's claims are now partially measured and partially not, and the difference should be on the record:

| Claim in §9 | Status |
| --- | --- |
| Text contrast ≥ 4.5:1 | **Measured** — axe-core WCAG 2.1 AA, zero violations on all five routes, all three engines. Two real violations were found and fixed (`text-zinc-400` body copy on the sticker and storage pages). |
| 320 CSS px reflow | **Measured** — asserted per engine. A real violation was found and fixed (the header navbar overflowed to 510px). |
| Full keyboard operability, visible focus, no keyboard traps | **Not measured.** No automated assertion exists yet. |
| Target size ≥ 24×24 (≥ 44×44 where touch is primary) | **Not measured.** |
| Full screen-reader operability, live-region announcements | **Not measured** — reported `unproven` every run; requires a human with NVDA/JAWS/VoiceOver. |
| 200% zoom | **Not measured.** |

Three of six claims in a ratified row are currently unmeasured. That is worth the owner's attention independently of this proposal.

## Row: `Client storage footprint` — one measured correction offered

§9 says quota-exceeded is "handled visibly (INV-24.5)". As of this card that is true; **before this card it was not.** The copy existed (`Copy.unsaved_record/0`, `Copy.not_saved_body/0`, `Copy.quota_full/0`) and was never rendered on any surface, and the app navigated away from a failed write before the browser could report it. A refused write was completely silent — the precise release blocker INV-24.5 names. Both defects were found by this suite and fixed; `quota.exhaustion-is-honest` now asserts the behavior per engine.

No text change is proposed. The row was aspirational when ratified and is now accurate.

## What is deliberately not proposed

- **Storage eviction.** Unmeasured, by design, until the observation in `conformance/observations/eviction.md` runs. No vendor-documented threshold may enter §9.
- **Mobile.** Unproven until physical devices run the manual matrix.
- **Latency budgets.** Per-engine timings are recorded in the reports but the sample is one machine on one network; that is not a measurement worth ratifying.
