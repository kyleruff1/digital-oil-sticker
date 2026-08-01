# DOS-M00-003 spike — Mob 0.7.20 on physical devices (Android half)

Working area for the [issue #4](https://github.com/kyleruff1/digital-oil-sticker/issues/4) physical-device proof. The generated `digital_oil_sticker/` shell here is **disposable** and gitignored; the committed deliverables are this log, the pinned-version matrix, and the compatibility evidence. The iOS half is blocked on Mac/Xcode access (recorded constraint).

## Pinned toolchain (Windows host `slams-api`)

| Component | Version / source |
| --- | --- |
| Host Elixir / OTP | Elixir 1.20.2, Erlang/OTP 28.4 (`~/.elixir-install`, official install.sh) |
| Mob framework | **0.7.20** (hex; current latest, pinned in generated mix.exs) |
| mob_new generator | 0.4.20 (mix archive) |
| JDK | Microsoft OpenJDK 17 (winget; Gradle 8.2.1 wrapper caps Java at 20) |
| Android cmdline-tools | build 15859902 (dl.google.com, 155.7 MB) |
| Gradle / AGP | 8.2.1 wrapper (auto-download) / AGP 8.2.0 |
| SDK packages | platform-tools, platforms;android-35 (compile/target 35, min 28), build-tools;34.0.0, ndk;27.2.12479018, cmake;3.22.1 |
| Device | Motorola Razr Ultra 2025 (foldable), Android — wireless adb over Tailscale (100.123.251.104) |

## Planned proof sequence (from the issue + mob docs)

1. `mix mob.new digital_oil_sticker --liveview --android` → pin `{:mob, "0.7.20"}` → `mix deps.get`
2. `mix mob.install` (prebuilt OTP runtime download; writes `mob.exs`, `android/local.properties`)
3. `mix mob.doctor` → resolve findings
4. Wireless adb pair + connect over tailnet → `adb devices` authorized
5. `mix mob.deploy --native --android` (debug) → launch, loopback LiveView renders, input works
6. Lifecycle: background/resume, force-quit/relaunch, fold/unfold (hinge safe-area), keyboard, rotation
7. Release-like build; capture size, logs (redacted), boot timings vs constitution §9 provisional budgets
8. API-surface matrix rows: BEAM lifecycle, WebView/loopback, app-support paths, lifecycle, `mob_notify` presence check (full notify proof = DOS-M00-005)

## Known risks being watched (from docs research)

- EPMD port 4369 can clash with adb (alt port 4380 via `mob.exs`).
- Interrupted `mob.install` leaves a stale OTP-runtime cache → delete and re-fetch.
- `android/local.properties` `sdk.dir` may need a hand-fixed Windows path.
- Windows docs are thin; deploy is Android-only from this host (expected).

## Evidence log

(appended as the spike runs)
