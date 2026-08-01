# Security Policy

## Reporting a vulnerability

This is a private repository. If you find a suspected vulnerability in the planning artifacts, tooling, or (once it exists) the application:

1. Use GitHub's **private vulnerability reporting** on this repository if it is enabled.
2. Otherwise, open a repository issue labeled `quality:security`. Because the repository is private, the report is visible only to repository collaborators.

Do not disclose suspected vulnerabilities outside the repository. There is **no bounty program**; no monetary rewards are offered.

## Product security posture: local-only by design

The product ships as native iOS and Android packages with an embedded BEAM/Phoenix runtime. There is no server-side attack surface in v1: no online accounts, no credentials, no remote user database, and no push infrastructure. The following posture is a build-time contract for all implementation work (no application code exists yet; these rules govern implementation starting at the M01 scaffold):

- **Loopback-only endpoint.** Cowboy/Phoenix binds strictly to `127.0.0.1`, never `0.0.0.0`. The LiveView WebSocket uses device loopback. Release verification must confirm that another LAN device cannot reach the endpoint.
- **Hardened release builds.** Native releases are built with `MIX_ENV=prod`; code reload, LiveDashboard, development routes, the remote inspector, and Erlang distribution are disabled in release builds.
- **WebView containment.** CSRF protections are retained. WebView navigation is restricted to loopback application routes; approved external links are handed to the system browser. On Android, any cleartext exception is limited to device loopback.
- **Local integrity material, not remote secrets.** Packaged session keys are treated as local integrity material, not as remotely secret credentials.
- **Data at rest.** SQLite databases are protected by the OS app sandbox but are not automatically encrypted. Full VIN storage is avoided by default; VIN, mileage, notes, and vehicle identifiers are redacted from logs and fixtures.
- **No telemetry.** No telemetry or third-party analytics by default. An opt-in diagnostic export is local, reviewable, and redacted.

## Scope notes

- User data never leaves the device in v1. There is no cloud sync, remote recovery, or cross-device state.
- Notifications are OS-scheduled local notifications only; there are no device tokens or notification servers.
- The Netlify property is a static site (product, support, privacy, attribution); it hosts no runtime, no user data, and no authentication. The production domain `digitaloilsticker.com` is owned but not yet deployed.
- Security-relevant changes to this posture require an ADR under change control; see [docs/governance/CHANGE_CONTROL.md](docs/governance/CHANGE_CONTROL.md).
