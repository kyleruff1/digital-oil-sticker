# API-surface test sprint — catalog

Working artifact from the test sprint staged against commit `5a60f43`
("Open the integration surface: REST API + MCP server for QR stickers"),
run on 2026-11-08 against `main`. Not an integrator-facing document;
lives beside `openapi.yaml` only because `docs/api/` is the natural home.

Command template, run from `app/`:

```bash
export PATH="/c/Users/kyler/.elixir-install/installs/otp/28.4/bin:/c/Users/kyler/.elixir-install/installs/elixir/1.20.2-otp-28/bin:$PATH"
mix test <path> --seed 0
```

## Summary

| # | file                                                                               | tests | pass | fail | skip | wall ms | judgment |
|---|------------------------------------------------------------------------------------|------:|-----:|-----:|-----:|--------:|----------|
| 1 | test/digital_oil_sticker/sticker_test.exs                                          |    10 |   10 |    0 |    0 |      40 | OK       |
| 2 | test/digital_oil_sticker/grok/parse_service_test.exs                               |     5 |    5 |    0 |    0 |      70 | OK       |
| 3 | test/digital_oil_sticker/mcp/server_test.exs                                       |    10 |   10 |    0 |    0 |     100 | OK       |
| 4 | test/digital_oil_sticker_web/plugs/rate_limit_test.exs                             |     7 |    7 |    0 |    0 |     100 | OK       |
| 5 | test/digital_oil_sticker_web/controllers/api/v1/sticker_controller_test.exs        |    14 |   14 |    0 |    0 |     300 | OK       |
| 6 | grouped: api/ + mcp/ + grok/ + sticker_test + rate_limit_test                      |    46 |   46 |    0 |    0 |     400 | OK       |

Totals (per-file 1–5, no double-count of the group run): **46 tests, 46
pass, 0 fail, 0 skip.** Group run matches, so no cross-file interference.

## Per-file notes

### 1. sticker_test.exs — OK

Domain unit test for `Sticker.from_params/1` and `Sticker.canonical_url/2`.
Async, no Phoenix, no HTTP. 10 passed in 40 ms. Nothing to flag.

### 2. grok/parse_service_test.exs — OK

Covers the full Grok parse surface with `Req.Test.stub/2`: tool-call
extraction, prose fallback (`:no_tool_call`), no-API-key early return
(no network trip), `{:http_error, 500}`, `:transport_error`. 5 passed in
70 ms. `XAI_API_KEY` is set to `"test-key"` in `setup` and restored on
exit, so the test file is self-contained.

### 3. mcp/server_test.exs — OK

Dispatch-only, no HTTP. Covers: `initialize` (protocolVersion / server
info / capabilities), notifications (no response), `tools/list` (all 5
tools with inputSchema), `tools/call generate_sticker` (text + resource
content, `isError` on bad UUID), `tools/call list_formats`,
`tools/call get_integration_examples` (default curl + python language
arg), unknown method (`-32601`), malformed request (`-32600`). 10 passed
in 100 ms.

### 4. plugs/rate_limit_test.exs — OK

Token-bucket unit test with an injected `now_fun` — no sleeps. 7 passed
in 100 ms. Isolated from the API suite, so this doesn't prove the plug
is wired into the endpoint — that gap is **F4**.

### 5. api/v1/sticker_controller_test.exs — OK

End-to-end through the Phoenix endpoint: `GET /formats`, `POST /stickers`
(PNG default / ZPL / ESC_POS / JSON envelope / missing-key 422 /
invalid-date 422 / unknown-format 400), `GET /stickers/:code.:format`
(PNG / ZPL / cache headers / unknown format 400 / bogus code 400), CORS
preflight. 14 passed in 300 ms. **Does not cover `POST /stickers/from-text`**
— that gap is **F1**.

### 6. Grouped run — OK

`test/digital_oil_sticker_web/controllers/api test/digital_oil_sticker/mcp
test/digital_oil_sticker/grok test/digital_oil_sticker/sticker_test.exs
test/digital_oil_sticker_web/plugs/rate_limit_test.exs` as one invocation.
46 passed in 400 ms, which matches the per-file sum — no cross-file
interference from shared ETS tables, env-var mutation in
`parse_service_test.exs`, or the suite-wide rate-limit override.

## Observations outside the test results

- `mix deps.get` was needed before the first run: `mix.lock` had
  `heroicons` locked to a newer rev than the cache. Not a sprint
  finding, just an environment note — captured here so the next person
  to clone-and-test doesn't take it for a regression.
- A benign colocated-assets symlink warning prints on every compile
  under Windows without admin. The `phoenix_live_view` docs suggest
  `config :phoenix_live_view, :colocated_assets, disable_symlink_warning:
  true`. Does not affect results; separate cleanup if we care.

## Follow-up stubs

Priority order (highest first): **F1 → F3 → F2 → F4 → F5**.
All green from the sprint, so the stop-the-sprint clause did not fire —
the full set is below.

### F1. `from_text` controller test

**Gap.** `POST /api/v1/stickers/from-text` has no controller-level test.
The Grok parse pipeline is tested at the domain layer in
`parse_service_test.exs`, but the controller's error-mapping (503 for
`:no_api_key`, 502 for `:transport_error`/`{:http_error, _}`, 422 for
`:no_tool_call`) is unexercised end-to-end.

**Where.** New `describe "POST /api/v1/stickers/from-text"` block inside
the existing `test/digital_oil_sticker_web/controllers/api/v1/sticker_controller_test.exs`.

**How.** Reuse the `Req.Test.stub(DigitalOilSticker.Grok.Client, fn conn -> … end)`
pattern from `parse_service_test.exs`. Manage `XAI_API_KEY` with a
`setup` block that puts a dummy key and restores on exit, same shape
as `parse_service_test.exs`'s setup.

**Cases.**
1. Happy path: valid key + text → stub returns a tool_call → 200 with PNG bytes, `x-sticker-code` header set.
2. `:no_api_key` (env var deleted) → 503 `{"error":"grok_not_configured"}`.
3. `:no_tool_call` (stub returns prose) → 422 `{"error":"could_not_parse_text"}`.
4. `:transport_error` (`Req.Test.transport_error(conn, :econnrefused)`) → 502 `{"error":"grok_unreachable"}`.
5. `{:http_error, 500}` (stub returns 500) → 502 `{"error":"grok_error"}`.
6. Missing `text` → 400 `{"error":"missing_text"}`.
7. Missing `configuration_key` → 422 `{"error":"invalid_configuration_key"}` (what the pipeline currently emits — matches sticker_controller.ex:197–198).

**Size.** ~90 lines.

### F2. QR renderer unit tests

**Gap.** The six format modules under `lib/digital_oil_sticker/qr/`
(png, svg, zpl, esc_pos, epl, tspl) have no direct unit tests. They're
exercised through the controller tests for three formats (PNG, ZPL,
ESC/POS); SVG, EPL, and TSPL have zero coverage, and even the three
covered formats don't have byte-level assertions beyond the PNG
signature / `^XA` prefix / `0x1D 0x28 0x6B` header.

**Where.** New `test/digital_oil_sticker/qr/` directory with one file
per format: `png_test.exs`, `svg_test.exs`, `zpl_test.exs`,
`esc_pos_test.exs`, `epl_test.exs`, `tspl_test.exs`. Plus a
`qr_test.exs` for the top-level dispatcher: `parse_format/1` (string
and atom inputs, unknown returns `:unknown_format`), `formats/0`, and
`render/3` dispatch on an unknown format returning `{:error, :unknown_format}`
rather than crashing.

**Cases per file.**
- `png_test`: 8-byte PNG signature (`\x89PNG\r\n\x1a\n`), IHDR + IDAT +
  IEND chunk framing present, `width:` option honored.
- `svg_test`: root `<svg>` with `viewBox` attribute, contains at least
  one QR-cell `<rect>` (or `<path>`, depending on `EQRCode`'s SVG
  output), has namespace declaration.
- `zpl_test`: starts with `^XA`, contains `^BQN,2,` (model-2 QR, normal
  orientation), ends with `^XZ`, URL appears verbatim in the
  `MM,A<url>` field data.
- `esc_pos_test`: `GS ( k` (`0x1D 0x28 0x6B`) command header present,
  store-the-data command (`fn=80`) carries the URL bytes, print
  command (`fn=81`) follows.
- `epl_test`: `b` command with Q-type selector present, URL in the data
  field.
- `tspl_test`: `QRCODE` keyword present, URL quoted in the args.
- `url_too_long` exercised in at least one file with a crafted >2KB URL,
  asserting `{:error, :url_too_long}`.

**Size.** ~50 lines per file × 7 files ≈ 350 lines.

### F3. MCP HTTP transport test

**Gap.** `DigitalOilStickerWeb.McpController` has no test. Pure dispatch
is covered by `mcp/server_test.exs`, but the controller's
single-vs-batch body routing, notification handling (returns `nil` →
204), empty-batch handling, and parse-error path (`-32700`) are
unexercised.

**Where.** New `test/digital_oil_sticker_web/controllers/mcp_controller_test.exs`.

**Cases.**
1. Single JSON-RPC request (map body) → 200 with a single response object, `content-type: application/json`.
2. Batch request (list body → parsed as `_json`) → 200 with array of responses, notifications filtered out.
3. `notifications/initialized` alone → 204 no content.
4. Empty batch `[]` → 204 no content.
5. Malformed body (e.g. a bare string, or empty object) → 400 with `-32700 parse error`.
6. All 200 responses have `content-type: application/json`.

**Size.** ~80 lines.

### F4. API-level rate-limit integration test

**Gap.** The `RateLimit` plug has a unit test (file 4 above), but the
endpoint-level wiring — that a 61st request to `/api/v1/stickers`
actually returns 429 with a `Retry-After` header — is not proven.

**Where.** New `test/digital_oil_sticker_web/controllers/api/v1/rate_limit_test.exs`.

**How.** `config/test.exs` sets `capacity: 1_000_000` for the whole
suite so other tests don't drain the bucket. This file needs to override
that in `setup` with `Application.put_env(:digital_oil_sticker,
DigitalOilStickerWeb.Plugs.RateLimit, capacity: 3, refill_per_second: 1)`
and restore the prior value on `on_exit`. Not `async: true` — it mutates
shared Application env.

**Cases.**
1. First 3 POSTs to `/api/v1/stickers` from the same IP return 200.
2. The 4th POST returns 429 with a `retry-after` header whose value is an integer ≥ 1.
3. A request with a different `x-forwarded-for` succeeds — buckets are per-IP.
4. After `refill_per_second: 1`-worth of simulated time (either real-sleep ~1.1s, or by injecting a `now_fun` through app env — current plug only reads `now_fun` from init opts, so this may require a design pass; see F4-sub below), the bucket allows a request again.

**F4-sub.** The `RateLimit` plug today reads `now_fun` only from init
opts, not from app env. If F4 needs deterministic time (no sleep), the
plug needs a small change: fall back to a configured `now_fun` from app
env when init didn't set one. One-line addition to `resolve/1`. Decide
during F4 whether to take the sleep hit or make the plug change.

**Size.** ~70 lines of test, plus maybe 3 lines of plug if we do F4-sub.

### F5. Tighter rate limit for `/from-text`

**Gap (wiring, not test).** The README and the integration plan both
say `/from-text` is "tighter (expensive Grok calls)" and target 10
req/min there vs 60 req/min elsewhere. In practice `/from-text` shares
the same `:public_api` pipeline and the same bucket as `/stickers`, so
a client can drain the whole 60/min on Grok-backed calls.

**Where.** `router.ex:73-90` (the `/api/v1` scope).

**Shape of the fix (design pass needed).**

Option A — a second pipeline:
```elixir
pipeline :public_api_strict do
  plug CORSPlug, origin: "*"
  plug DigitalOilStickerWeb.Plugs.RateLimit, capacity: 10, refill_per_second: 0.17
  plug :accepts, ["json"]
end

scope "/api/v1", DigitalOilStickerWeb.Api.V1 do
  pipe_through :public_api_strict
  post "/stickers/from-text", StickerController, :from_text
end
```

But this hits `rate_limit.ex` reading one named ETS table — a second,
differently-configured bucket on the same key would stomp on the first.
Options:

1. **Two ETS tables.** `RateLimitStore` grows a `start_strict/0` + a
   second table name; the plug takes `:table` as init opt (it already
   does). Clean; only new infra is a second store child.
2. **Per-plug keying.** The plug prefixes the ETS key with a tag from
   init opts (`:bucket_name` → `"from-text:<ip-hash>"` vs
   `"api:<ip-hash>"`). Cheaper, one table; but a surprise if the two
   buckets interact under ETS contention.
3. **Keep one bucket, charge extra on `/from-text`.** The plug takes
   `:cost` as init opt (default 1); `/from-text` sets `cost: 6`. The
   two endpoints share a bucket but the Grok endpoint drains it 6×
   faster. Simplest, but changes the mental model from "60/min per
   endpoint tier" to "60 token/min shared".

Recommend **Option 1** (two tables) — it's what the README already
describes. Decide at implementation time; leave open for the owner's
read.

**Size.** ~20 lines of plug/store change + ~10 lines of router + ~40
lines of test (an F4 analog for the strict bucket).

## Sprint done when

- [x] Steps 1–5 run and recorded.
- [x] Step 6 grouped run matches the per-file sum.
- [x] Catalog has summary table + per-file sections + stubs.
- [x] Every row labeled OK / REGRESSION / FLAKY / NEEDS INVESTIGATION.
- [x] No regressions → full stub set below.

## Follow-ups landed

- [x] F1 — commit `208e69c` — 7 new tests on `POST /from-text` (14 → 21 in the file).
- [x] F3 — commit `7c71a76` — 6 new tests on `POST /mcp` (new file).
- [x] F2 — commit `1a83d24` — 33 new tests across six renderer files + a dispatcher file (new dir).
  During grouped verification, the pre-existing `test/digital_oil_sticker/qr_test.exs`
  collided on the `DigitalOilSticker.QRTest` module name; the per-format split subsumed
  it with stricter assertions, so it was dropped in the F5 commit.
- [x] F4 — commit `6a7e8c0` — 3 new tests prove the per-IP bucket is wired into
  `/api/v1/stickers` end-to-end (drain, per-IP isolation, recovery after refill).
- [x] F5 — (this commit) — new `:public_api_strict` pipeline, `GrokBucket` ETS
  table, `:config_key` init opt on the `RateLimit` plug, prod config in
  `config/config.exs`, test override in `config/test.exs`, and
  `from_text_rate_limit_test.exs` with 2 cases: the strict bucket drains
  independently, and draining it does not block `/stickers`.

Sprint closed; API surface coverage complete. **786 tests passing on main.**
