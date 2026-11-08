# Digital Oil Sticker — Integration API

A free, open, read-only REST API that returns a QR oil-change sticker in the format your printer already speaks. One POST at work-order close. No shop account. No new hardware. No per-shop subscription.

> **Base URL:** `https://digitaloilsticker.com/api/v1`
> **Auth:** none on reads; the write endpoints are rate-limited per IP.
> **CORS:** `*` — call us directly from your browser-based work-order screen.

## The 30-second integration

A shop finishes an oil change. Your POS/DMS/CRM already knows the vehicle (as a catalog `configuration_key`) and the service details. One request:

```bash
curl -X POST https://digitaloilsticker.com/api/v1/stickers \
  -H 'Content-Type: application/json' \
  --output sticker.png \
  -d '{
    "configuration_key": "11111111-2222-4333-8444-555555555555",
    "changed_on": "2026-11-08",
    "odometer": 45000,
    "odometer_unit": "mi",
    "grade": "5W-30",
    "base_stock": "full_synthetic",
    "format": "png"
  }'
```

`sticker.png` is a QR code the driver scans to see their next-service record at `digitaloilsticker.com/s#<code>`. The `X-Sticker-Code` response header carries the code itself if you want to store it alongside the work order.

## Endpoints

### `POST /api/v1/stickers`

Generate a sticker. Request body:

| Field               | Type    | Required | Notes                                                    |
|---------------------|---------|----------|----------------------------------------------------------|
| `configuration_key` | string  | yes      | Catalog UUID for this vehicle configuration              |
| `changed_on`        | string  | no       | ISO 8601 date (YYYY-MM-DD)                               |
| `odometer_m`        | integer | no*      | Odometer in whole metres (canonical)                     |
| `odometer`          | number  | no*      | Odometer value; pair with `odometer_unit`                |
| `odometer_unit`     | string  | no*      | `"mi"` or `"km"`                                         |
| `grade`             | string  | no       | One of `0W-8`, `0W-16`, `0W-20`, …, `20W-50`             |
| `base_stock`        | string  | no       | `conventional`, `synthetic_blend`, `full_synthetic`, `high_mileage` |
| `format`            | string  | no       | `png` (default), `svg`, `zpl`, `esc_pos`, `epl`, `tspl`  |
| `output`            | string  | no       | `"json"` to receive a JSON envelope with base64 data     |
| `width`             | integer | no       | Pixel width for raster formats (default 320)             |

*At most one of `odometer_m` / (`odometer` + `odometer_unit`).

Response: the raw rendered bytes with `Content-Type` set for the format. Response headers:

- `X-Sticker-Code` — the compact code
- `X-Sticker-URL` — the URL the QR encodes
- `Content-Type` — set per format

### `GET /api/v1/stickers/{code}.{format}`

Re-render an existing sticker. Idempotent, `Cache-Control: public, max-age=31536000, immutable` — the code IS the content, so this is CDN-friendly.

```bash
curl https://digitaloilsticker.com/api/v1/stickers/ABCDEFGH23456789.png -o sticker.png
curl https://digitaloilsticker.com/api/v1/stickers/ABCDEFGH23456789.zpl
```

### `POST /api/v1/stickers/from-text`

Natural-language fallback for free-text service notes. Requires `XAI_API_KEY` configured on the server; returns 503 otherwise.

```bash
curl -X POST https://digitaloilsticker.com/api/v1/stickers/from-text \
  -H 'Content-Type: application/json' \
  --output sticker.zpl \
  -d '{
    "configuration_key": "11111111-2222-4333-8444-555555555555",
    "text": "5W-30 full synthetic, 45,000 miles, changed today",
    "format": "zpl"
  }'
```

### `GET /api/v1/formats`

List supported formats and their MIME types:

```bash
curl https://digitaloilsticker.com/api/v1/formats
```

### `POST /mcp`

Model Context Protocol endpoint. Any MCP-compatible agent (Claude, Grok, a shop's own assistant) can list and call the sticker tools over JSON-RPC 2.0.

```bash
curl -X POST https://digitaloilsticker.com/mcp \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

Tools exposed: `generate_sticker`, `get_sticker`, `list_formats`, `parse_service_record`, `get_integration_examples`.

## Formats — what each printer needs

| Format     | Content-Type                | What it is                                                               |
|------------|-----------------------------|--------------------------------------------------------------------------|
| `png`      | `image/png`                 | Universal raster image. Inline via data URI or save to disk.             |
| `svg`      | `image/svg+xml`             | Vector image. Scale losslessly, inline into HTML.                        |
| `zpl`      | `application/vnd.zebra.zpl` | Zebra Programming Language. Pipe directly to a Zebra label printer.      |
| `esc_pos`  | `application/octet-stream`  | Epson/Star thermal-receipt-printer bytes. GS ( k native QR command.      |
| `epl`      | `application/vnd.zebra.epl` | Eltron Programming Language. Legacy Zebra-branded units.                 |
| `tspl`     | `application/vnd.tsc.tspl`  | TSC Printer Language. TSC, Argox, Godex, and compatibles.                |

The printer encodes the QR itself for the four thermal formats — we emit the command, the printer draws the matrix. No client-side rendering, no PNG-to-print conversion step.

## Rate limits

Per-IP token bucket. Default: 60 req/min with burst of 60. `from-text` endpoint is tighter (expensive Grok calls). When exceeded: `429` with a `Retry-After` header. The response body is empty — we never echo your IP back.

## What this API does not do

- No shop accounts.
- No persistence: we never store your customer's data server-side. The sticker code IS the record.
- No analytics on your stickers. No webhooks back to us.
- No auth tokens. If you want to swap to key-based auth later as a Tier-1 integration partner, say so.

## Examples by language

### Node.js

```javascript
const res = await fetch("https://digitaloilsticker.com/api/v1/stickers", {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({
    configuration_key: "11111111-2222-4333-8444-555555555555",
    changed_on: "2026-11-08",
    odometer: 45000,
    odometer_unit: "mi",
    grade: "5W-30",
    base_stock: "full_synthetic",
    format: "zpl"
  })
});
const zpl = await res.text();
// Send zpl straight to the shop's Zebra printer.
```

### Python

```python
import requests

r = requests.post("https://digitaloilsticker.com/api/v1/stickers", json={
    "configuration_key": "11111111-2222-4333-8444-555555555555",
    "changed_on": "2026-11-08",
    "odometer": 45000, "odometer_unit": "mi",
    "grade": "5W-30", "base_stock": "full_synthetic",
    "format": "esc_pos"
})
# r.content is the ESC/POS byte stream — send to the receipt printer.
```

### Elixir

```elixir
{:ok, resp} = Req.post("https://digitaloilsticker.com/api/v1/stickers",
  json: %{
    configuration_key: "11111111-2222-4333-8444-555555555555",
    changed_on: "2026-11-08",
    odometer: 45_000, odometer_unit: "mi",
    grade: "5W-30", base_stock: "full_synthetic",
    format: "svg"
  })
# resp.body is the SVG string.
```

## Error responses

JSON `{"error": "<atom>"}` with one of:

| Status | Error                          | Meaning                                              |
|--------|--------------------------------|------------------------------------------------------|
| 400    | `unknown_format`               | `format` isn't one of the supported names            |
| 400    | `invalid_request`              | Body isn't the expected shape                        |
| 422    | `invalid_configuration_key`    | Not a valid UUID                                     |
| 422    | `invalid_date`                 | `changed_on` isn't ISO 8601                          |
| 422    | `date_out_of_range`            | Before 2000-01-01 or far future                      |
| 422    | `odometer_out_of_range`        | Negative or implausibly high                         |
| 422    | `invalid_grade`                | Not in the frozen viscosity list                     |
| 422    | `invalid_base_stock`           | Not in the frozen base-stock list                    |
| 429    | (empty body)                   | Rate-limited; see `Retry-After` header               |
| 503    | `grok_not_configured`          | `/from-text` endpoint only; server has no XAI_API_KEY|

## Support

Open an issue at <https://github.com/kyleruff1/digital-oil-sticker/issues>, or email the maintainer.
