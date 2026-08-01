# ADR-0001: Mob LiveView runs the BEAM and Phoenix on-device

Status: **Proposed — pending the M00 physical-device spike (DOS-M00-003)**

## Context

Digital Oil Sticker must remain fully useful with no account, no remote database, and no network after installation. Version 1 targets native iOS and Android packages built with Elixir, Phoenix LiveView, and Mob.

As of this ADR, [Mob 0.7.20](https://hex.pm/packages/mob) is a pre-1.0 BEAM-on-device framework. Its [LiveView mode](https://mob.hexdocs.pm/liveview.html) embeds the BEAM and Phoenix inside each Android/iOS application package, runs the Phoenix endpoint on `http://127.0.0.1:4000`, and displays it in a native WebView. The LiveView WebSocket therefore travels over device loopback and can function without the internet. Mob's [getting-started guide](https://mob.hexdocs.pm/getting_started.html) documents `mix mob.new ... --liveview`, Elixir 1.19+, and the native build flow.

Two facts about Mob's runtime shape constrain every downstream design decision:

1. **Navigation.** Mixed native and Phoenix navigation stacks do not synchronize automatically. Product navigation must live in one place or the two stacks drift.
2. **Bridging.** Mob's LiveView documentation describes [two mutually exclusive JavaScript bridges](https://hexdocs.pm/mob/0.7.20/liveview.html#the-two-bridge-architecture): the native WebView bridge and the `MobHook` LiveView bridge, which replaces `window.mob` after the LiveView socket connects. A `Phoenix.LiveView.Socket` is not a `Mob.Socket`. First-party plugins such as `MobNotify` are invoked from callbacks on the root [`Mob.Screen`](https://hexdocs.pm/mob/0.7.20/Mob.Screen.html), whose state is a `Mob.Socket`. Code that passes a Phoenix socket to a Mob plugin, or that assumes a LiveView JS event invokes native functionality, is wrong by construction.

Because Mob is young and pre-1.0, this decision cannot be ratified from documentation alone. M00 contains a physical-device go/no-go spike (DOS-M00-003) that must prove the architecture on real iOS and Android hardware.

## Decision

1. **Embed the BEAM and Phoenix on-device with Mob 0.7.20 LiveView mode.** The Phoenix endpoint binds to loopback `127.0.0.1:4000` and is rendered in a native WebView. This is explicitly **not LiveView Native** and **not a remote Phoenix server**; there is no hosted runtime in the product path.
2. **One root WebView, one Phoenix route stack.** Prefer a single Mob root WebView and a single Phoenix route stack for all product navigation. Native screens are added only for device functions that the LiveView bridge cannot safely expose.
3. **Respect the two-bridge architecture.** Treat the native WebView bridge and the `MobHook` LiveView bridge as mutually exclusive, as documented. Never conflate `Phoenix.LiveView.Socket` with `Mob.Socket`.
4. **All device commands cross one typed boundary: `DigitalOilSticker.DeviceCommandBroker`.** Ordinary Phoenix/OTP code computes a command and dispatches it to the registered root screen process (for example through the documented `Mob.Screen.dispatch/3` path). The root screen (`DigitalOilSticker.MobScreen`) calls the pinned plugin with its `Mob.Socket`, and a correlated acknowledgement/result is returned to the domain/UI. The broker owns command validation, correlation IDs, timeout/restart behavior, and redacted acknowledgements. Plugin-specific values never leak into domain modules. No implementation ticket may simply pass a Phoenix socket to `MobNotify` or assume a LiveView JS event reaches native code.
5. **Single application, not an umbrella.** Keep the first implementation as one Mob/Phoenix application unless the M00 spike proves a concrete need for an umbrella.
6. **No perpetual background processes for deadlines.** Do not add Oban or a long-lived deadline GenServer; mobile operating systems suspend normal processes (see [Mob background-execution constraints](https://mob.hexdocs.pm/background_execution.html)). Recompute synchronously or on a supervised foreground task after relevant mutations and at app foreground, then let the OS hold local notification requests (see [Mob device capabilities and local notifications](https://mob.hexdocs.pm/device_capabilities.html)).
7. **Go/no-go gate before feature work.** Feature implementation must not begin until DOS-M00-003 proves, end-to-end on physical iOS and Android devices, the loopback LiveView shell, the `DeviceCommandBroker` round trip to a native plugin, and on-device SQLite persistence — or an explicit fallback ADR is approved.

## Consequences

- The application works in airplane mode from first launch: UI, domain logic, persistence, and reminder scheduling all run on-device.
- Production shells must bind Cowboy/Phoenix strictly to `127.0.0.1` (never `0.0.0.0`), build with `MIX_ENV=prod`, disable code reload, LiveDashboard, development routes, remote inspector, and Erlang distribution, retain CSRF protections, restrict WebView navigation to loopback application routes, and hand approved external links to the system browser. On Android, any cleartext exception is limited to device loopback. Verification that another LAN device cannot reach the endpoint is a release requirement.
- Every native capability (notifications first) is funneled through `DeviceCommandBroker`, which concentrates risk in one testable seam but adds a dispatch/correlation layer that M00 must prove and M01+ must maintain.
- Pre-1.0 dependency risk is explicit: this ADR stays **Proposed** until the DOS-M00-003 gate passes on physical hardware. If the gate fails, a fallback ADR (different framework or architecture) must be approved before any feature work.
- On-device persistence follows [Mob's Ecto/SQLite guidance](https://mob.hexdocs.pm/data.html) (two SQLite repos, startup migrations); the details are owned by the data-contract documents, not this ADR.

## Research anchors

- [Mob package and current release](https://hex.pm/packages/mob)
- [Mob getting started and LiveView project generation](https://mob.hexdocs.pm/getting_started.html)
- [Mob LiveView loopback architecture](https://mob.hexdocs.pm/liveview.html)
- [Mob LiveView two-bridge architecture and message API](https://hexdocs.pm/mob/0.7.20/liveview.html#the-two-bridge-architecture)
- [Mob.Screen process, callbacks, and dispatch API](https://hexdocs.pm/mob/0.7.20/Mob.Screen.html)
- [Mob Ecto/SQLite persistence and on-device migrations](https://mob.hexdocs.pm/data.html)
- [Mob device capabilities and local notifications](https://mob.hexdocs.pm/device_capabilities.html)
- [Mob background-execution constraints](https://mob.hexdocs.pm/background_execution.html)
