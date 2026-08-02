# Browser support matrix

**Status:** Authored 2026-08-01 (DOS-M09-008). Tier 1 rows are measured by the conformance suite in [`conformance/`](../../conformance); every value here that is *not* measured says so.

This file is the single authority for which browsers Digital Oil Sticker supports and what that support promises. **No test file, CI job, or product surface may name a supported browser this matrix does not list.** The conformance suite asserts that correspondence in both directions (AC-1).

---

## What a tier promises

| Tier | Promise | Gate |
| --- | --- | --- |
| **Tier 1** | Every conformance assertion passes on this engine before a release ships. A regression here blocks the release. | Release-blocking. A `fail` **or** an `unproven` on a Tier 1 engine fails the run (FR-20). |
| **Tier 2** | The app is expected to work. Assertions are run when convenient and reported, but a failure raises an issue rather than blocking a release. | Reported, not blocking. |
| **Untested** | Not run, and not blocked either. The app decides by capability probe, so an untested browser whose probes pass runs normally. | None. Never a "browser not supported" wall (FR-5). |

**Untested is not unsupported.** There is no user-agent gate anywhere in the shipped client, and there is no browser blocklist. A browser we have never run is simply a browser we have not measured; if its probes pass it behaves like any other, and if a required probe fails it enters the same honest `:storage_unavailable` state a Tier 1 browser would (INV-24.6, INV-25).

## Engines, not brands

Support is a property of the **engine**, not the badge on the browser. Shells that share an engine are not counted twice, and a row records which engine it actually exercises.

| Engine | Ships in | Tier | Host OS measured | How it is exercised |
| --- | --- | --- | --- | --- |
| **Chromium** | Chrome, Edge, Brave, Opera, Android Chrome | 1 | Windows 11 | Playwright `chromium` |
| **Gecko** | Firefox | 1 | Windows 11 | Playwright `firefox` |
| **WebKit** | Safari (macOS), all iOS browsers | 1 | Windows 11 — **proxy, see below** | Playwright `webkit` |
| **Chromium (Android)** | Android Chrome | 1 | Android 13 (SDK 33) — **real hardware** | CDP over adb, `conformance/bin/dos-conformance-device.mjs` |

### The WebKit caveat, stated plainly

Playwright's `webkit` is a build of the WebKit engine driven on the host OS. It is **not** Safari, and it is **not** iOS. It shares the engine, which makes it a good proxy for engine-level storage behavior, and a poor proxy for the things that differ by platform: iOS storage eviction policy, Safari's private-browsing storage behavior, Home Screen web-app storage, and the real quota a device offers.

Every WebKit result in the conformance report is therefore labeled with `proxy: true` and the real target it stands in for. **Anything that depends on the platform rather than the engine is reported `unproven` until it is run on real Safari and real iOS hardware.** Recording a Playwright-WebKit pass as a Safari pass would be exactly the kind of convenient-but-false claim INV-15 exists to prevent.

### Platform engine constraints

Historically, iOS required all browsers to use the system WebKit engine. This has been subject to regulatory change (EU DMA). **We have not verified the current state.** Per FR-2 a platform engine constraint may only be recorded here with a verification date, so this row is deliberately blank rather than filled from memory:

| Constraint | Status | Verified on |
| --- | --- | --- |
| iOS third-party engine availability | **Unverified** — must be checked before any iOS row is promoted past proxy | — |

## Version policy

A rule, not a list, so this file does not rot (FR-3):

- **Channels in scope:** stable only. Beta, dev, canary, and ESR are out of scope; a defect found there is a valid bug report but does not block a release.
- **Entering the matrix:** the current stable release of a Tier 1 engine is in scope automatically, from the day the automation toolchain ships a build for it. No edit to this file is required for a routine version bump — the report records the exact version that ran.
- **Ageing out:** the current stable release and the one before it are supported. A third-newest release leaves scope when its successor reaches stable.
- **Staleness:** a Tier 1 engine that has not been run in **30 days** is marked `stale` in the report and is treated as `unproven` — which, at Tier 1, fails the run. An engine cannot drift into being silently assumed to work.
- **Toolchain versions** are pinned by `DOS-M01-001` and recorded in [`conformance/package.json`](../../conformance/package.json). This matrix names engines; it does not name tool versions.

## Mobile

| Target | Tier | Status |
| --- | --- | --- |
| iOS Safari 16+ | 1 (intended) | **Unproven.** Exercised only through the WebKit engine proxy above. No physical-device run has been performed. |
| Android Chrome | 1 | **Measured 2026-08-02** on a Lenovo TB125FU (Tab M10 Plus 3rd Gen), Android 13 / SDK 33, Chrome 150.0.7871.186, 1200×2000 @ 240dpi. 17 pass, 0 fail, 4 unproven — the same four structural gaps every engine reports, and identical to the desktop result. |

**What the Android run is and is not.** It is the platform, not a stand-in for it: real Chrome on real hardware, driven over CDP through adb, running the same assertions as the desktop sweep. It is a single device, so it measures Android 13 on this tablet and nothing wider — not a phone form factor, not another OEM's Chrome build, not an older Android.

iOS Safari remains unproven and may not be reported as passing until the manual matrix runs on real Apple hardware. Playwright's WebKit shares the engine and not the platform.

### Running the device suite

```
adb pair <host>:<pairing-port>          # code from the tablet's wireless-debugging dialog
adb connect <host>:<connect-port>
ADB_PATH=<path-to-adb> node conformance/bin/dos-conformance-device.mjs   --serial <host>:<connect-port> --release <label>
```

Two constraints make this a separate runner rather than another engine in the main one. `browser.newContext()` is unavailable on an attached Android Chrome, so cases cannot each get a clean context; and `context.addInitScript()` works but cannot be removed, so a harness installed by one case would silently change every case after it. The runner obtains isolation by force-stopping and relaunching Chrome on the device, which is slow, so it does that only for the three cases that install an init script.

## Storage eviction

**Unmeasured.** Browsers evict origin storage under conditions vendors describe but do not guarantee, and those descriptions are documentation, not measurement.

Per ADR-0004 R1 and AC-20, no vendor-published eviction threshold or dwell period is recorded here as fact. The observation is designed and scheduled in [`conformance/observations/eviction.md`](../../conformance/observations/eviction.md); until it completes and reports a measured result, the honest statement is: **we do not know how long a populated store survives un-visited in any browser.** The product does not depend on knowing — it detects loss and says so (`:data_missing`) rather than predicting it.

## What the app requires

Capability, probed at runtime — never a version check:

| Capability | Required? | If absent |
| --- | --- | --- |
| IndexedDB (open + write + read + delete round trip) | Yes | Session-only mode, persistent banner, export offered |
| WebSocket | Yes | Explicit connection state; the app is a LiveView |
| `BroadcastChannel` | No | Multi-tab still safe via compare-and-set on `meta.seq`; divergence surfaces on next hydration |
| `navigator.storage.estimate()` | No | Quota warnings simply do not appear; nothing is guessed |
| `navigator.storage.persist()` | No | Storage is best-effort; the UI never claims durability it was not granted |

## Deliberately absent

Asserted by the suite on every run (FR-22), because these are deferred by INV-6/INV-17/INV-19 and their accidental appearance would change what the app promises:

- No service worker registration
- No web app manifest link
- No push subscription
- No background sync registration

## Revision

| Date | Change |
| --- | --- |
| 2026-08-01 | Authored. Tier 1 engines named; WebKit recorded as a proxy; mobile and eviction recorded as unmeasured. |
| 2026-08-02 | Android Chrome promoted from unproven to **measured** on a physical Lenovo TB125FU (Android 13, Chrome 150): 17 pass, 0 fail. iOS Safari and storage eviction remain unmeasured. |
