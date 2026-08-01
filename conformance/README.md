# Browser conformance suite (DOS-M09-008)

Test tree only. Nothing here ships.

```bash
npm ci
npx playwright install chromium firefox webkit
npm test                                     # the suite's own tests
node bin/dos-conformance.mjs --base-url https://digital-oil-sticker.fly.dev
```

Exits non-zero when any Tier 1 engine produced a result that is not a pass —
including an assertion that never ran, and an engine that could not be
launched. There is no "skip".

- Engines, tiers, and the version policy live in
  [`docs/quality/SUPPORT_MATRIX.md`](../docs/quality/SUPPORT_MATRIX.md). The
  runner reads that file; it does not carry its own engine list.
- Reports land in `reports/` (gitignored) and are uploaded as CI artifacts.
- Simulation harnesses each state what they approximate **and what they do
  not** — see `src/harness/storage.mjs`.
- What automation cannot prove is reported `unproven`, never quietly skipped:
  screen-reader operability, real-device mobile, and storage eviction
  (designed and scheduled in `observations/eviction.md`).

Flags: `--engine <key>` to run one engine, `--release <id>` to label the
report, `--rehearse-red` to inject a failure and prove the gate still blocks.
