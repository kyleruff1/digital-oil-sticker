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

### 2026-08-01 — Windows host build chain: WORKS, with four documented defects

`BUILD SUCCESSFUL in 2m 14s` — `mix mob.deploy --native --android` produced
`android/app/build/outputs/apk/debug/app-debug.apk` (77,264,396 bytes = **73.7 MiB**, debug, universal/all-ABI).
The zig-compiled JNI layer, Kotlin/Compose `MobBridge.kt`, dex merge, and `assembleDebug` all completed on
Windows 11 with the pinned toolchain.

**Device run completed (Motorola Razr Ultra 2025, wireless adb over Tailscale, no cable):**

- Streamed install succeeded in **5.7 s**; package `com.example.digital_oil_sticker`.
- Native layer healthy: `MobNIF: mob_ui_cache_class: …/MobBridge cached OK`, then
  `DigitalOilSticker: onCreate — handing off to BEAM`.
- Full deploy loop verified: APK install + **OTP release push** + **1,115 BEAM files** pushed + app restart.
- **Embedded BEAM booted and Phoenix served on device loopback** — Bandit 1.12.4 handled HTTP/1 requests in-process
  (`Bandit.HTTP1.Handler.handle_data/3` in the on-device stack trace).
- Device runtime is **erts-17.0**, independent of the host's OTP 28.4 — confirms Mob's decoupled-runtime claim.
- Graceful degradation: with no EPMD reachable, `Mob.Dist` logged
  `no EPMD on port 4369 after 10s -- skipping dist` and continued instead of crashing.

**Not completed:** on-device LiveView render (blocked by defect 5 below), the lifecycle/fold/safe-area matrix,
a release-signed build, and the entire iOS half (no Mac/Xcode).

#### Defect 5 — generator omits `live_reload:`, crashing every on-device request
`mob_new` 0.4.20 emits `code_reloader: true` in `config/dev.exs` but no `live_reload:` block. The endpoint plugs
`Phoenix.LiveReloader` whenever `code_reloading?` is true, and the plug then calls `Access.get(false, :patterns, nil)`
→ `FunctionClauseError` on every request. Adding `live_reload: [patterns: []]` fixes it, but the config is baked into
the release at **native build time**, so a BEAM-only push cannot apply the fix — a full `--native` rebuild is required.

**Size note vs constitution §9:** 73.7 MiB debug/universal against a ≤50 MiB per-arch *compressed release* target.
Not yet comparable — a release build with per-ABI splits is required before judging the budget (DOS-M07-003 owns enforcement).

#### Defect 1 — `System.user_home!()` backslashes break the OTP cache (blocking)
`MobDev.OtpDownloader` builds `C:\Users\kyler/.mob/cache/...` by joining a backslash home with forward-slash
segments. `Path.wildcard/1` treats `\` as a **glob escape**, so the pattern collapses to `C:Userskyler/...` and
`verify_erts/1` reports "OTP extraction produced no erts-* directory" *even when extraction succeeded*. The same
mixed path made Git-Bash `tar` read `C:` as a remote host (`Cannot connect to C: resolve failed`).
**Workaround (supported):** `export MOB_CACHE_DIR='C:/Users/kyler/.mob/cache'` — an escape hatch already present
in `cache_dir/1`. Confirmed: `Cached at C:/Users/kyler/.mob/cache/otp-android-5c9c69fc`.

#### Defect 2 — undocumented zig requirement
Mob 0.7+ compiles the Android JNI layer with `build.zig`; the CMake fallback is dead (`mob_nif.c` no longer ships).
`zig 0.15.x` is required but appears in no prerequisite list we found. Installed zig **0.15.2** manually.

#### Defect 3 — NDK host tag omits Windows (blocking, one-line upstream fix)
`MobDev.NdkVersion.host/0` maps only `{:unix,:darwin}` and `{:unix,:linux}` and raises
`unsupported host for NDK: {:win32, :nt}` — yet NDK 27.2.12479018 **ships a `windows-x86_64` prebuilt toolchain**.
**Local probe patch** (`deps/mob_dev/lib/mob_dev/ndk_version.ex`, disposable): add `{:win32, :nt} -> "windows-x86_64"`.
With that single clause the zig/NDK compile succeeded for every ABI — Windows support is genuinely one clause away
at this layer. Upstream report warranted.

#### Defect 4 — `local.properties` written with unescaped backslashes (blocking)
`mix mob.install` writes `sdk.dir=C:\Users\kyler\android-sdk`, but Java `.properties` treats `\` as an escape
character, so Gradle fails with *"The filename, directory name, or volume label syntax is incorrect"* (surfaced
confusingly through a Kotlin `BuildFlowService` isolation error).
**Workaround:** rewrite `android/local.properties` with forward slashes (and set `ANDROID_HOME` with forward slashes
so regeneration stays clean).

#### Environment/tooling notes
- Elixir toolchain resolves via `~/.elixir-install`; `mob_new` 0.4.20 requires `phx_new` (1.8.9) to be installed first — `mix mob.new` fails with "task phx.new could not be found" otherwise.
- Device OTP runtime is **erts-17.0** (prebuilt, downloaded), independent of the host's OTP 28.4 — confirms the docs' decoupling claim.
- Wireless adb over Tailscale requires `ADB_MDNS_OPENSCREEN=0`; otherwise `adb pair`/`connect` fail with
  `protocol fault (couldn't read status message)`. After pairing, the TLS connection auto-establishes via mDNS
  (`adb-<serial>._adb-tls-connect._tcp`); pairing and connect ports rotate on every toggle.
- Persisted toolchain env lives in `~/.bashrc` (JAVA_HOME, ANDROID_HOME, MOB_CACHE_DIR, ADB_MDNS_OPENSCREEN, PATH with zig).

### Why the Windows build worked, and why it is not a supported path

The APK built **only because the build runs from a Git-Bash/MSYS shell**. Static review of `mob_dev` 0.6.23 shows
the Android path assumes POSIX utilities are ambient — `gradle_assemble/0` invokes `System.cmd("bash", [gradlew, …])`
(and the generated project ships **no `gradlew.bat`**), and `ensure_jni_libs/2` plus `push_otp_runas/5` shell out to
`cp`. Git Bash supplies `bash`, `cp`, `tar`, and `chmod` on PATH, so those calls resolve; from a native
PowerShell/cmd host they raise `:enoent`. Additional latent Windows hazards found by review:

- The host tag is **triplicated** — `ndk_version.ex` (the one we patched, which raises) plus `native_build.ex:941`
  and `tflite_nif.ex:294`, both of which silently fall back to `darwin-x86_64` on Windows rather than failing loudly.
- `OtpDownloader.cache_dir/1` joins `System.get_env("HOME")`, which is unset on native Windows → `Path.join([nil,…])`
  raises; `MOB_CACHE_DIR` is the only safe route (and must use forward slashes, or every `erts-*` glob silently
  returns `[]` and the cache re-downloads on every build).
- `clear_stale_gradle_locks/0` globs a backslash path, silently matches nothing, so the Gradle-daemon lock cleanup
  it exists to perform never runs on Windows.
- NDK tools resolve inconsistently: `llvm-ar`/`llvm-nm` exist only as `.exe` (so `File.regular?` guards give false
  negatives), while the extensionless `aarch64-linux-android28-clang++` exists as a shell script (false positive).

**Upstream status:** the hexdocs claim *"On macOS it includes both platforms; on Linux/Windows it deploys Android only"*
is not backed by code — Windows support was never implemented and never built in CI (both repos test ubuntu-latest +
macos-15 only), and no Windows/WSL issue exists in either repo. This is an upstream documentation defect worth filing,
citing `ndk_version.ex` host/0 against the getting-started guide.

**Containment rule for the compatibility matrix:** Windows-host Android builds are *possible but unsupported and
fragile* — they require Git Bash, four workarounds, and a `deps/` patch that any `mix deps.get` erases (making the
setup non-repeatable by construction). The repeatable build host must be Linux: **WSL2** (VHDX relocated to `F:`,
which has 528.7 GB free versus 6.4 GB on `C:`) with `ADB_SERVER_SOCKET` pointed at the Windows adb server so the
physical-device loop over Tailscale is preserved; a tailnet-joined Linux VM is the fallback. GitHub Actions can
produce artifacts later but cannot run the `mob.deploy` hot-push/IEx loop against the phone, so it is not the
spike host.

**Version matrix addendum:** record `mob_dev` **0.6.23** — it is the component that actually broke and was previously unpinned in this table.
