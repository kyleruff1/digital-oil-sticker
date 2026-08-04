# CSP report-only phase — review artifact (AC-2)

**Status:** Adopted 2026-08-04 as evidence for [DOS-M09-007](../../planning/issues/DOS-M09-007.md) AC-2 / FR-3.
**Authority:** [ADR-0004](../architecture/ADR-0004-browser-first-client-and-hosting.md) §"Security and privacy boundary for a hosted application", `DOS-M09-007` FR-3 (report-only precedes enforcement; stored reports asserted free of personal data).

FR-3 requires that the CSP ship first in report-only mode, that its reports be reviewed, and that only after review may the policy be enforced. AC-2 asks for the artifact that says which of those three things happened, when, and how the "no personal data in stored reports" claim was proven. This document is that artifact.

## When the report-only phase ran

The policy was deployed report-only to `digital-oil-sticker.fly.dev` on **2026-08-01**. A full session — hydrate, mutation, export, clear, import — plus every route in the `:garage` live_session was driven with the browser console open across four engines:

| Engine | Version | Host |
| --- | --- | --- |
| Chromium | 141.0.7390.37 | Windows 11 (desktop) |
| Gecko (Firefox) | 142 | Windows 11 (desktop) |
| WebKit (via Playwright) | 26 | Windows 11 (desktop) |
| Android Chrome | 150 | Lenovo TB125FU (real device) |

The report-only header served is `content-security-policy-report-only`; the switch from report-only to enforced is a single `enforce: true` config value (`app/config/prod.exs`, line 49) that flips the header name in `DigitalOilStickerWeb.Plugs.SecurityHeaders`. Same policy string either way, which is what makes "what was reviewed is what gets enforced" a real property rather than a hope.

Enforcement was enabled at commit `426c09d` ("Enforce the content security policy, with a scrubbed report sink", 2026-08-01), after the remediation described below reduced the sweep to zero violations. The narrative of the phase is preserved as a comment above the config line (`app/config/prod.exs`, lines 36–48) and again in the CSS file where the fix landed (`app/assets/css/app.css`, lines 154–165), so the reason the enforce flip was safe is not a claim the deployment carries but a claim the code carries.

## Sample of reports captured

The sink is `POST /csp-report` → `DigitalOilStickerWeb.CSPReportController.create/2`. It does not persist reports to disk or database: each report is scrubbed to an allowlist and emitted as a single `Logger.warning "csp_violation ..."` line. That is deliberate — the server holds nothing (INV-23), and adding a store for violation reports would be the first server-side record of anything. The log is the whole of the sink.

The report-only sweep on 2026-08-01 produced **56 violations on the first run**, every one of them a `style-src 'self'` violation for an inline `style=""` attribute on the sticker component. Every viewport, on every render, one violation per attribute. The count is recorded in the enforce-flip commit message (`git log 426c09d`) and in the surrounding source comments named above. No JSON dump of the raw reports was retained: the *count and category* of the violations were the actionable output, and the remediation (moving those styles into a CSS rule) is the thing that reduced the count to zero rather than any change to the reports themselves.

The re-verification sweep after the CSS change reported **zero CSP violations** across all four engines. The evidence for the post-fix sweep is the conformance report at `conformance/reports/conformance-csp-enforced-2026-08-02T03-20-40-255Z.json`, which was captured against the same four-engine matrix after enforcement was enabled.

## No personal data in captured reports

A CSP report is browser-authored and can carry page content back at us — `script-sample` is a literal fragment of whatever the blocked script contained, `referrer` is wherever the user came from, and `source-file` is a URL whose query string can carry anything a caller put on it. FR-3 requires that a field which *could* carry personal data is dropped before storage. `DigitalOilStickerWeb.CSPReportController` implements this as an allowlist (keep only fields that name our own policy and our own assets), not a denylist (drop the ones we thought of).

Kept fields (`@keep`): `violated-directive`, `effective-directive`, `disposition`, `line-number`, `column-number`, `status-code`.
Kept URI fields (`@uri_fields`, reduced to scheme + host + path with query and fragment dropped): `document-uri`, `blocked-uri`, `source-file`.
Everything else — including `script-sample`, `referrer`, `original-policy`, and any field a future browser adds — is dropped by default, because it was not on the allowlist.

The behaviour is asserted by `app/test/digital_oil_sticker_web/csp_report_test.exs`. Each of the following assertions runs against a "hostile report" fixture built to carry the worst case (a VIN inside `script-sample`, an odometer reading in a `document-uri` query string, a private referrer, and an unknown-key `future-field` also carrying the VIN):

- `"drops the script sample, which is page content by definition"` — asserts the log does not contain the VIN embedded in `script-sample`.
- `"drops the referrer"` — asserts the log does not contain the private referrer host.
- `"reduces URIs so a query string cannot ride along"` — asserts the odometer value, the query-string note, and the `?vsn=d` asset hash never appear in the log.
- `"drops a field it has never heard of, rather than logging it"` — asserts a field the allowlist does not know about is dropped rather than logged, so a future browser adding `future-field` cannot introduce a leak.
- `"an oversized body is refused unread"` — asserts a body larger than `@max_body_bytes` (8 KiB) is refused with 413 rather than buffered, so an unauthenticated endpoint cannot be turned into a scratchpad.
- `"a body that is not a report is refused without crashing"` — asserts a non-report JSON body is silently discarded and answered 204.
- `"keeps what makes a violation actionable"` — asserts that after all the removals, the log still contains what a reviewer needs (directive, path fragment, line number).

Because scrubbing happens before the `Logger.warning` call, the log line — which is the "storage" for these reports — cannot contain the dropped fields. The test suite fails the build if that stops being true.

## Current state

- **Sink**: in place at `POST /csp-report` (`app/lib/digital_oil_sticker_web/controllers/csp_report_controller.ex`), wired in the `:api` scope of the router.
- **Report-only mode**: the report-only phase completed on 2026-08-01 and enforcement was enabled at commit `426c09d` the same day. In development and test environments the policy remains report-only (`enforcing?/0` returns `false` because no config sets `enforce: true` outside prod), so a local developer's browser console continues to surface new violations during ordinary work without breaking pages.
- **Enforcement flip**: production runs enforced (`config/prod.exs` line 49). Rolling back to report-only in production is a one-line config revert plus a redeploy; the sink stays operational either way because the same `report-uri` and `report-to` directives are emitted in both modes.
- **No stored reports**: by design. There is no database of past reports to prove personal-data-free; the test above proves the shape of *any future* report the sink accepts is personal-data-free before it reaches the log.

## Cross-references

- [`DOS-M09-007.md`](../../planning/issues/DOS-M09-007.md) AC-2, FR-3 — the criterion this artifact closes.
- [`ADR-0004`](../architecture/ADR-0004-browser-first-client-and-hosting.md) §"Security and privacy boundary for a hosted application" — the CSP the report-only phase reviewed.
- `app/lib/digital_oil_sticker_web/controllers/csp_report_controller.ex` — the scrubbing allowlist, in code.
- `app/test/digital_oil_sticker_web/csp_report_test.exs` — the eight assertions above.
- `app/lib/digital_oil_sticker_web/plugs/security_headers.ex` — the header set, and the report-only ↔ enforced flip (`enforcing?/0`).
- `app/config/prod.exs` lines 36–49 — the narrative of the report-only phase, in situ.
- `app/assets/css/app.css` lines 154–165 — the fix the report-only phase drove.
- `conformance/reports/conformance-csp-enforced-2026-08-02T03-20-40-255Z.json` — the four-engine post-fix sweep.
- Git commit `426c09d` — the enforce flip, with the 56-violations count in its message.
