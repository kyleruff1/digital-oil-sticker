# ADR-0002: Netlify is a static boundary, not a runtime

Status: **Amended — 2026-08-01 by [ADR-0004](ADR-0004-browser-first-client-and-hosting.md)**

> **What still stands:** Netlify cannot host Phoenix. That constraint is unchanged and is the reason the pivot required a separate hosting decision.
>
> **What changed:** Netlify is no longer the product's only edge. Under ADR-0004 the Phoenix LiveView application runs on **Fly.io** at `digitaloilsticker.com`, and Netlify keeps static marketing, support, privacy, and attribution content (and, later, catalog artifacts). The "bundled offline catalog shipped in a native package" premise below no longer applies to the MVP.
>
> **See also:** [INV-27-CONTENT-BOUNDARY.md](INV-27-CONTENT-BOUNDARY.md) — the single-page rule for which host serves what and what is not allowed on either.

## Context

Digital Oil Sticker is a local-first mobile product: the Phoenix runtime lives on-device (see ADR-0001), and the application must remain useful with no network after installation. The project still needs a public web presence — product, support, privacy, and attribution pages — and, post-MVP, a distribution point for versioned catalog packages.

[Netlify Functions](https://docs.netlify.com/build/functions/get-started/) support TypeScript, JavaScript, and Go request handlers, while [Edge Functions](https://docs.netlify.com/build/edge-functions/api/) run in Deno. Netlify is not an always-on Elixir/Phoenix host and must not be represented as one. No part of the product runtime may assume a hosted BEAM.

The production domains **digitaloilsticker.com** and **digitaloilsticker.net** are owned and reserved for this static boundary.

## Decision

1. **Netlify serves only static and edge concerns:**
   - the static product, support, privacy, and attribution site;
   - deploy previews for that static site;
   - later (post-MVP, M08), immutable versioned catalog packages and their signed manifest.
2. **If serverless logic is ever needed at this boundary**, it uses Netlify's documented runtimes — TypeScript/JavaScript/Go for Functions, Deno for Edge Functions — and never an Elixir/Phoenix process. Netlify is **not** an always-on Elixir host.
3. **Builds happen in GitHub Actions.** Native applications and catalog artifacts are built and tested in GitHub Actions, not in Netlify's build pipeline.
4. **Distribution is through the app stores.** iOS ships through TestFlight/App Store; Android ships through internal testing/Play Store. Netlify never distributes application binaries.
5. **The production domain is reserved for this boundary.** digitaloilsticker.com/.net point at the static site and, later, the catalog package host — nothing else.
6. **No browser product is implied.** A browser/PWA or hosted Phoenix product would require a separately approved architecture and deployment decision; it is not promised by this roadmap.

## Consequences

- The installed application never depends on Netlify availability: startup, CRUD, search, projection, and reminder scheduling are fully offline. Netlify outages affect only the marketing/support site and, post-MVP, optional catalog updates.
- Catalog updates, when introduced in M08, ship as immutable versioned packages with a signed manifest (hash, size, schema/min-app compatibility), staged integrity check, atomic activation, and rollback. They never overwrite `UserRepo`.
- The privacy story stays simple: a valid privacy URL exists for store review even though the app is local-only, and the static site carries the required source attribution.
- Any future ambition to run Phoenix on a server (browser product, sync, provider operations) requires a new ADR and deployment plan; this ADR forbids sneaking it in through the Netlify boundary.
- DOS-M00-002 must ratify this boundary alongside the on-device architecture before feature work begins; until then the status remains Proposed.

## Research anchors

- [Netlify Functions runtimes](https://docs.netlify.com/build/functions/get-started/)
- [Netlify Edge Functions runtime](https://docs.netlify.com/build/edge-functions/api/)
