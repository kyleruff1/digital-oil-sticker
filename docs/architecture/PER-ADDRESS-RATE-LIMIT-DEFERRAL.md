# Per-address catalog rate limit — deferral memo

**Status:** Deferred 2026-08-03 as part of [DOS-M09-004](../../planning/issues/DOS-M09-004.md) AC-10 close-out.
**Authority:** DOS-M09-004 §"Included" (rate limiting: "a per-socket token bucket on catalog events, and a per-address bucket for any HTTP-exposed catalog route"), [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) §"Rate limiting and abuse", [MODULE-MAP.md](MODULE-MAP.md) §"Ports and their production/test implementations" (Rate limit row).

## Scope

This memo records why the *catalog* per-address rate limit called for in DOS-M09-004 §"Included" is not built today, what is built in its place, and the exact condition under which it must be built. It concerns **catalog** query traffic only; the internet-facing per-IP HTTP posture (HTTPS connect limits, socket-connect limits, request-header filtering, trusted-proxy resolution of the client IP) is owned by [DOS-M09-007](../../planning/issues/DOS-M09-007.md) and is out of scope here.

## Current state

Every catalog read reaches the domain through exactly one path:

1. A LiveView in the `:garage` live_session pushes a `catalog:*` event over the WSS socket.
2. `DigitalOilStickerWeb.CatalogEvents.handle/4` validates the event name against the compiled allowlist, validates the payload against the closed vocabulary, and spends one token from `socket.assigns.catalog_budget`.
3. The token bucket is `DigitalOilSticker.Catalog.RateLimit` — a pure struct (`capacity: 30`, `refill_per_second: 5`, no ETS, no GenServer, no keyspace), initialized in `DigitalOilStickerWeb.LocalStore.Session.init/1` and stored in `socket.assigns` for the lifetime of that one socket.

There is no per-address bucket, and there is nowhere for one to sit. `DigitalOilStickerWeb.Router` exposes exactly six live routes under the `:garage` live_session, plus `/csp-report`, `/health`, `/ready`, and `/version`. **None of the four HTTP routes read the catalog**; the three health endpoints touch `CatalogRepo` for readiness diagnostics only (`HealthController.catalog_read_only/0`, `catalog_queryable/0`) and answer with a fixed-shape probe result, not a queryable surface. `/csp-report` performs no catalog work at all. The catalog is unreachable off-socket.

The tier-1 (per-socket) bucket therefore covers 100% of the traffic that can reach the catalog today. A caller who wants to exceed the tier-1 threshold must first pay the WSS-connect and socket-authentication costs governed by DOS-M09-007's per-IP HTTP and socket-connect limits, then repeat that per socket. A per-address catalog bucket layered on top would clamp nothing that the two existing tiers do not already clamp.

## Why deferred

The per-address bucket in DOS-M09-004 §"Included" is written as a conditional: *"for any HTTP-exposed catalog route."* Today, no such route exists. Building the bucket now would mean:

- Choosing an in-memory keyspace (an ETS table or `:persistent_term` map) and an eviction discipline for entries that no route consults.
- Instantiating a client-address extraction plug — the same trusted-proxy-aware resolver DOS-M09-007 mandates, but attached to no request path, so its correctness could not be exercised end-to-end.
- Committing an untested threshold value (bursts, refill rate) with no request pattern to measure it against.

Each of those choices is easier to make correctly at the same commit that introduces the endpoint the bucket protects, because the endpoint's expected request shape drives the threshold and the endpoint's controller drives where the bucket is spent. Building the mechanism first and finding a use for it later inverts that order and produces exactly the kind of "load-bearing but unused" surface that DOS-M09-004 §"Excluded" ("no per-user or per-session cache, any query log that retains parameters, and any durable identifier that could correlate one socket to another") is written to prevent.

The tier-1 (per-socket) bucket, by contrast, is load-bearing right now: it is the sole guard on catalog event flooding from a connected LiveView, and its behaviour is exercised by `facade_test.exs` "an event is rate limited past the socket bucket" and by property-style drain tests. Shipping only tier-1 keeps every rate-limit line in the codebase covered by a live request path.

## Re-open trigger

This deferral holds **only** as long as every catalog read is socket-mediated. The moment any of the following is introduced — in this repo, in this deployment, or in a companion service that speaks to `CatalogRepo` — the per-address bucket becomes required at that commit, and this memo must be updated or superseded in the same PR:

- A machine-facing catalog API introduced by DOS-M10 (or its successor) — e.g. a `GET /api/v1/catalog/...` route for third-party sticker readers, a JSON dump for offline mirrors, or any endpoint that answers a `Selector`-shaped query over HTTP rather than WSS.
- A public schema or attribution endpoint (e.g. `GET /catalog/schema.json`, `GET /catalog/attributions.json`, or an INV-15 provenance browsing route) that reads any part of the baked SQLite artifact and returns catalog-derived content.
- Any controller in `DigitalOilStickerWeb.*` that calls `DigitalOilSticker.Catalog` functions from HTTP request context rather than from LiveView socket context.
- Any deployment topology change that admits catalog reads from a caller that does not first establish a LiveView socket (for example, a companion CLI, a preview generator, or an SSR route rendered outside the `:garage` live_session).

At that point the per-address bucket must be introduced concurrently with the endpoint, with its threshold justified against the endpoint's expected request pattern and its address source resolved through the DOS-M09-007 trusted-proxy plug (address held in memory only, never persisted or logged in full, per FR-13 and INV-4).

## Cross-references

- [MODULE-MAP.md](MODULE-MAP.md) — Rate limit port row, updated to reference this memo.
- [DOS-M09-004.md](../../planning/issues/DOS-M09-004.md) AC-10 — the acceptance criterion this memo closes as `deferred-with-trigger`.
- [DOS-M09-007.md](../../planning/issues/DOS-M09-007.md) — per-IP HTTP and socket-connect limits (the tier that DOES exist at the web edge today, and the one whose trusted-proxy plug the future per-address catalog bucket must reuse rather than re-derive).
- [ADR-0004](ADR-0004-browser-first-client-and-hosting.md) §"Rate limiting and abuse" — the standing design constraint (in-memory only, never persisted, typed `:rate_limited` result over silent empty page).
