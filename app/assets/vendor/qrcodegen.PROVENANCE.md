# qrcodegen.js — vendored

| | |
| --- | --- |
| Upstream | Project Nayuki, *QR Code generator library* |
| Via | npm `nayuki-qr-code-generator@1.8.0` (ESM build of the reference TypeScript) |
| License | MIT — see `qrcodegen.LICENSE`, and the header retained in the source |
| Vendored | 2026-08-02 |
| Modified | No. Byte-for-byte the published `index.js`. |

## Why vendored rather than a dependency

A CDN reference is forbidden by the enforced CSP and by DOS-M09-007 FR-16, and
an npm dependency in `assets/` would still have to be bundled into a
first-party asset to satisfy the same policy. Vendoring makes the exact bytes
that ship reviewable in the diff.

## Why a library rather than our own

QR encoding is Reed-Solomon over GF(256) plus format/version information and
eight mask patterns scored by four penalty rules. The failure mode of getting
it subtly wrong is not a crash — it is a code that scans on one reader and not
another, discovered on a sticker already stuck to a windshield or on a shop's
POS scanner. Nayuki's is the reference implementation most other libraries are
derived from.

## Updating

Replace the file, keep the header, update the version and date above, and run
the conformance suite: `conformance/test/qr-svg.test.mjs` asserts the rendered
symbol still decodes to the payload.
