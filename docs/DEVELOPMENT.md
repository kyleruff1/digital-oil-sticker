# Development Setup

Browser-first toolchain for the Digital Oil Sticker Phoenix/LiveView application on Fly.io.

## Prerequisites

| Tool | Version | Pin source |
|------|---------|------------|
| Erlang/OTP | 28.4 | `.tool-versions`, `Dockerfile` |
| Elixir | 1.20.2 (OTP 28) | `.tool-versions`, `app/mix.exs` |
| Node.js | 24.x | `.tool-versions` (asset tooling only) |
| Docker | latest stable | Release build |
| flyctl | 0.4.77 | `.github/workflows/deploy.yml` |

Install Erlang and Elixir via your preferred version manager (`asdf`, `mise`, `rtx`, or manual install). The `.tool-versions` file at the repo root pins the exact versions.

**Not required:** Xcode, Android SDK, Gradle, or any Mob-family tool. These belong to the deferred native track — see [ADR-0004 §"Trigger conditions"](architecture/ADR-0004-browser-first-client-and-hosting.md).

## Quick start

```bash
cd app
mix setup        # deps.get + assets.setup + assets.build
mix precommit    # compile --warnings-as-errors, deps.unlock --unused, format, test
```

## Commands

| Command | What it does |
|---------|-------------|
| `mix setup` | Install deps, download esbuild/tailwind binaries, build assets |
| `mix precommit` | Compile (warnings=errors), check unused deps, format, test |
| `mix test` | Run the test suite |
| `mix assets.build` | Compile + build CSS/JS |
| `mix assets.deploy` | Minified CSS/JS + phx.digest (release only) |
| `mix phx.server` | Start the dev server at http://localhost:4000 |

## Environment variables

Copy `app/.env.example` to `app/.env` for local development. Production secrets are set via `fly secrets set` — `.env` files are never committed and never used in production.

| Variable | Required | Description |
|----------|----------|-------------|
| `PHX_HOST` | prod | Hostname for URL generation and `check_origin` |
| `PORT` | prod | Port the app binds to (Fly expects 8080) |
| `SECRET_KEY_BASE` | prod | Generate with `mix phx.gen.secret`; set via `fly secrets set` |
| `CATALOG_DATABASE_PATH` | no | Defaults to `priv/catalog/catalog.sqlite3` |

## Deploy

Deploy requires a Fly.io account with `FLY_API_TOKEN` set as a GitHub Actions secret. Without the token, the deploy workflow is inert.

```bash
cd app
flyctl deploy --build-arg GIT_SHA=$(git rev-parse HEAD) --build-arg BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
```

The deploy workflow (`.github/workflows/deploy.yml`) is triggered manually via `workflow_dispatch`. It builds, deploys, polls `/ready`, verifies `/version`, and records a release ledger entry.

## Repository layout

```
app/                          Phoenix application
  lib/digital_oil_sticker/    Domain code
  lib/digital_oil_sticker_web/ LiveView surface
  assets/                     CSS, JS, static assets
  test/                       ExUnit tests
  config/                     Compile-time and runtime config
  rel/                        Release configuration
  Dockerfile                  Digest-pinned multi-stage build
  fly.toml                    Fly.io deployment config
  priv/catalog/               Read-only catalog artifact (build output)
tools/catalog/                Catalog build pipeline (Node ESM)
docs/                         Architecture, product, governance docs
planning/issues/              Roadmap card bodies
conformance/                  Browser conformance harness
```

Generated build output (`app/_build/`, `app/deps/`, `app/priv/static/assets/`) is gitignored.

## Secret hygiene

The repository gitignore rejects `.env` files, Fly API tokens, `*.pem`/`*.key` files, raw restricted catalog datasets, and personal test exports. No real secret value is ever committed — `app/.env.example` contains placeholders only.
