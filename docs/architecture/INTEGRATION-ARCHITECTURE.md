# Integration Architecture

How the new REST API and MCP server fit into Digital Oil Sticker. Adopted 2026-11-08 alongside the DOS-M01-003+ integration surface work.

## One picture

```
                      EXTERNAL CALLERS
     POS/DMS systems  │  Browser POS screens  │  AI agents
          │                    │                    │
          ▼                    ▼                    ▼
        POST                 POST                  JSON-RPC
      /api/v1/*            /api/v1/*                /mcp
          └────────┬───────────┘                     │
                   │  (CORS *, no auth, rate-limited)│
                   ▼                                 ▼
          ┌─────────────────────┐          ┌──────────────────┐
          │  Phoenix router     │          │  McpController   │
          │  /api/v1 scope      │          │  JSON-RPC 2.0    │
          │                     │          │  streamable HTTP │
          └─────────┬───────────┘          └────────┬─────────┘
                    │                               │
                    ▼                               ▼
          ┌─────────────────────┐          ┌──────────────────┐
          │ Api.V1.Sticker-     │          │ Mcp.Server       │
          │  Controller         │          │ Mcp.Tools        │
          │ Api.V1.Format-      │          │  (5 tools)       │
          │  Controller         │          └────────┬─────────┘
          └─────────┬───────────┘                   │
                    │                               │
                    └────────────┬──────────────────┘
                                 │
                                 ▼
                 ┌───────────────────────────────┐
                 │       DOMAIN LAYER            │
                 │                               │
                 │  Sticker (param parsing)      │
                 │  StickerCode (bijection)      │
                 │  QR + QR.{Png,Svg,Zpl,…}      │
                 │  Grok.Client / ParseService   │
                 │  Mcp.Server / Mcp.Tools       │
                 │                               │
                 │  All framework-free.          │
                 │  Checked by M01-002's         │
                 │  namespace_boundary_test.     │
                 └───────────────────────────────┘
                                 │
                                 ▼
                 ┌───────────────────────────────┐
                 │  CONSUMER PWA (already live)  │
                 │  digitaloilsticker.com/s#code │
                 └───────────────────────────────┘
```

## Statelessness

Every endpoint is a pure function of its inputs. `StickerCode.encode/1` is a bijective encoding — the 25-byte code IS the sticker record. No database row is written, no shop account exists server-side, no state persists between calls.

A `GET /api/v1/stickers/<code>.<format>` is just: decode the code (validation), build the canonical URL, render the QR. CDN-cacheable with `max-age=31536000, immutable` because the output depends only on the URL.

This is the structural guarantee that INV-26 (no personal data server-side) stays intact as the integration surface grows: there is nothing to persist, so nothing can leak.

## Authentication model

**Reads:** no auth. The code is already a public token (see `StickerCode`'s moduledoc).

**Writes:** no auth at MVP. Per-IP rate limit via the existing `DigitalOilStickerWeb.Plugs.RateLimit` applied endpoint-wide. Can tighten later per-endpoint without changing the pattern.

**`/stickers/from-text`:** same no-auth posture, but a tighter rate limit will go here once we calibrate against real traffic (Grok calls cost real money per request).

**Partner keys:** deliberately not built. Adding them later as an opt-in path (for Motive MIX / Tekmetric / Shopmonkey partner-program certifications) is a bolt-on, not a rework.

## The Grok boundary

Grok is NEVER in the sticker-generation hot path. Three touchpoints only, all out-of-band:

1. `POST /api/v1/stickers/from-text` — explicitly opt-in for callers without structured data.
2. MCP tool `parse_service_record` — explicitly invoked by an agent.
3. Internal `mix dos.advise` CLI (not built yet) — BD tool only.

The REST `POST /api/v1/stickers` endpoint has zero Grok dependency. If `XAI_API_KEY` is missing at boot, the structured endpoint serves 100% of traffic normally; only the `/from-text` path degrades to 503.

## MCP in the same BEAM node

The MCP server is a module (`DigitalOilSticker.Mcp.Server`), not a separate OS process. The HTTP transport is a Phoenix controller (`DigitalOilStickerWeb.McpController`) that calls `Server.handle/1` with the decoded JSON-RPC request.

Benefits:
- One deploy. One release process. No sidecar, no cross-service contract.
- MCP tool handlers share the same BEAM functions the REST controllers call (`Sticker.from_params/1`, `StickerCode.encode/1`, `QR.render/3`). Both surfaces are guaranteed to agree because they call the same code.
- Testing: dispatch is pure, so most tests don't need a connection at all.

## Namespace boundary compliance

The new modules land under `DigitalOilSticker.Qr`, `DigitalOilSticker.Grok`, `DigitalOilSticker.Mcp`, and `DigitalOilSticker.Sticker` — all domain. Web shims under `DigitalOilStickerWeb.Api.V1.*` and `DigitalOilStickerWeb.McpController`.

`namespace_boundary_test` runs against every new module and catches any accidental `Phoenix.LiveView` / `Plug` / `DigitalOilStickerWeb` reference. The MCP tools module reads `PHX_HOST` directly rather than calling `DigitalOilStickerWeb.Hosts.canonical/0`, specifically to keep the domain-layer isolation.

## Where the `openapi.yaml` lives

Checked in at `docs/api/openapi.yaml`. Future work can serve it from the running app at `GET /api/v1/openapi.yaml` so SDK generators (`openapi-generator`, Stainless, etc.) can read it from the live deployment.

## Deployment

Same Fly.io machine, same Phoenix release, same `priv/catalog/*.sqlite3` artifact. No new Fly services, no new volumes, no new secrets required unless the owner wants Grok enabled (then `fly secrets set XAI_API_KEY=...`).
