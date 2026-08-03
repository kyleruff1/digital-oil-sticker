# INV-27 — Content boundary: Fly.io app vs. Netlify static

**Status:** Adopted 2026-08-02 as evidence for [DOS-M01-005](../../planning/issues/DOS-M01-005.md) AC-11.
**Authority:** [CONSTITUTION.md](../product/CONSTITUTION.md) INV-27, [ADR-0002](ADR-0002-netlify-static-boundary.md) as amended by [ADR-0004](ADR-0004-browser-first-client-and-hosting.md), [INV-22](../product/CONSTITUTION.md) hosted transport, [INV-4](../product/CONSTITUTION.md) no telemetry.

This document is the single-page answer to: **which host serves what, and what is not allowed on either.** When a new page or endpoint is proposed, this rule decides where it lives.

## The two hosts

| Host | Origin (planned) | What it serves | What it must not do |
| --- | --- | --- | --- |
| **Fly.io — the app** | `digitaloilsticker.com` (and `www.digitaloilsticker.com` redirect) | The interactive Phoenix LiveView application: cascade pickers, oil-change logging, history, storage status, calendar export. The catalog is read from the baked SQLite artifact via `CatalogRepo`. | Never serves marketing, docs, or attribution pages. Never returns a page the user could reach without hydration having completed — pre-hydration renders skeletons, never empty-state prose. |
| **Netlify — the static site** | `digitaloilsticker.net` (and subdomains `help.`, `legal.`, `attribution.` on either primary domain) | Marketing, help, privacy policy, source attribution, contact — all as static HTML/CSS/asset files. | Never runs a Function or Edge Function on behalf of the app. Never carries a script that talks to the Fly app or any third party. Never sets a cookie. Never carries a tracker or analytics beacon. Never claims a user has an account. |

## The rules INV-27 imposes

1. **Personal data never crosses the boundary.** The static site collects no personal data; the app never proxies static content. There is no "share what you entered" widget on either host.
2. **Third-party scripts and styles are forbidden on the app.** The CSP defaults to first-party origins for every source (`script-src`, `style-src`, `img-src`, `font-src`, `connect-src`) with no `'unsafe-inline'`. Enforced by `production_posture_test.exs`.
3. **The static site carries no runtime.** Its Netlify configuration excludes Functions, Edge Functions, service workers, and PWA manifests. If a page needs behavior, that behavior lives on the app or does not ship.
4. **No cross-origin request from the app to the static site.** Rendered pages of the app never `fetch` from `digitaloilsticker.net` or its subdomains. Enforced by the conformance suite's request-log check.
5. **Attribution stays in sync.** Every source that requires attribution appears on `attribution.digitaloilsticker.net` and in [`docs/data/SOURCE_REGISTER.md`](../data/SOURCE_REGISTER.md). A discrepancy fails the attribution-sync check.
6. **Legal pages link forward, not back.** The privacy page on the static site describes what the app does with personal data (browser-only storage, no server-side records per INV-3/INV-23). It never asks the reader to sign in to see it.

## Consequences

- **A new interactive feature belongs on Fly.** Even a "just a form" belongs on Fly if it collects anything — the static site cannot receive input safely.
- **A new marketing page belongs on Netlify.** A landing page, a support article, a changelog written for a human — Netlify. Anything the app itself must decide to render — Fly.
- **A future PWA install prompt or service worker is out of scope for both** until [DOS-M09-010](../../planning/issues/DOS-M09-010.md) reopens the decision. Neither host may partially ship it.

## Where the boundary is enforced

| Rule | Test / gate |
| --- | --- |
| CSP forbids third-party origins and `'unsafe-inline'` | `test/digital_oil_sticker/production_posture_test.exs` |
| No third-party request from any app-rendered page | `conformance/` browser suite, request log check |
| No runtime path on the Netlify build | Netlify `netlify.toml` audit; documented in the static-site repo README |
| Attribution page ↔ `SOURCE_REGISTER.md` sync | `docs/data/SOURCE_REGISTER.md` change checklist (owner) |
| No `check_origin: true` and no `check_origin: false` — only the production allowlist | `test/digital_oil_sticker/deploy_config_test.exs` |

## Owner-gated close-out

- DNS: `digitaloilsticker.com` → Fly Anycast; `digitaloilsticker.net` → Netlify; `www.digitaloilsticker.com` → 301 to apex. TLS via Fly-managed cert on the app; Netlify-managed on the static site.
- Netlify team is `cDiscourse`; the static-site repo publishes to it. The Fly deploy publishes to app `digital-oil-sticker`.
- HSTS on the app is enabled **only after** the certificates are verified on both hostnames.
