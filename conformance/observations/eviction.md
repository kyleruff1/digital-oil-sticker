# Storage eviction observation — design and schedule

**Status: not started. Eviction behavior is UNMEASURED.** (DOS-M09-008 FR-21, AC-20; ADR-0004 R1)

## Why this document exists instead of a number

Every browser vendor publishes something about when origin storage is reclaimed — pressure thresholds, dwell periods, "best effort" versus "persistent" buckets. Those are documentation. They describe intent, they change without notice, and they do not bind the browser on a particular device with a particular amount of free disk.

Writing a vendor's number into our matrix would convert "the vendor says" into "we know", which is the exact substitution INV-15 exists to prevent. So this file records a **measurement design**, and the matrix says plainly that the answer is unknown until the measurement runs.

## What the product does about not knowing

Nothing, deliberately. The app never predicts eviction and never reassures anyone that their records are safe. It detects loss after the fact — `dos_boot_state == "has_data"` plus an empty store yields the `:data_missing` state — and says so in plain words. That behavior is already asserted per engine by `eviction.data-missing-distinct-from-first-visit`.

Knowing the eviction threshold would let us warn people earlier. It is not required for the app to be honest.

## The observation

**Question.** For a populated Digital Oil Sticker origin store on a real device, does the browser reclaim it, and after how long without a visit?

**Method.**

1. On each device below, visit the deployed app, set up one vehicle, and log three oil changes. Record the date, the browser build, the OS build, the device free-disk figure, and `navigator.storage.estimate()`.
2. Record whether `navigator.storage.persist()` was granted. Run **both** arms where the browser supports it: one profile that requested persistence and one that did not. They are different questions.
3. Do not visit the origin again.
4. At **7, 14, 30, 60, and 90 days**, open the app once and record: did the records survive, and what state did the app render.
5. Any visit is an intervention — it resets recency for that arm. Each checkpoint therefore needs its own device/profile arm, or the schedule collapses into "does it survive one week, repeatedly".

**Devices.** At least one arm per Tier 1 engine on real hardware, plus the two mobile targets the matrix currently calls unproven:

| Arm | Engine | Device | Persistence requested | Status |
| --- | --- | --- | --- | --- |
| A | Chromium | Windows desktop | no | not started |
| B | Chromium | Windows desktop | yes | not started |
| C | Gecko | Windows desktop | no | not started |
| D | WebKit | macOS Safari — **real Safari, not the Playwright build** | no | not started |
| E | WebKit | iPhone, iOS Safari | no | not started |
| F | Chromium | Android Chrome | no | not started |

**Confounds to record rather than control.** Device disk pressure during the dwell (the dominant real-world trigger), OS updates, browser updates mid-dwell, "clear browsing data" run by anything else on the machine, and iOS offloading the browser app. An arm with an unrecorded confound is discarded, not adjusted.

**What may be written down afterwards.** Only what was observed: "Arm E, iOS 18.x, records still present at day 30; absent at day 60; app rendered the data-missing state correctly." Never a threshold generalized from one arm, and never a vendor-documented figure presented as our result.

**Blocked on.** Physical hardware and calendar time. Arms A–C can start immediately on the development machine; D–F need devices this project does not currently have.

## Reporting

Results land in [`SUPPORT_MATRIX.md`](../../docs/quality/SUPPORT_MATRIX.md) under "Storage eviction", replacing the unmeasured note, and in the conformance report as an `observation` block distinct from the automated assertions — an observation is evidence, not a pass.
