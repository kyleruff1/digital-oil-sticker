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

## The baseline

Four assertions cannot be run at all right now — export/import round trip and
post-import re-resolution (no import path exists yet), forward migration (only
one schema version has ever shipped), and screen-reader operability (needs a
human). `baseline.json` accepts them so the gate is not permanently red, which
is the state in which people stop reading it.

It is not an ignore-list:

- every baselined assertion is still reported as unproven, in the report and in
  the terminal;
- a **failing** assertion is never excused — the baseline is for assertions
  that cannot RUN, not for ones that run and come out wrong;
- a baselined assertion that starts **passing** blocks, so the entry is removed
  as part of the work that fixed it;
- an entry naming an assertion the suite no longer produces blocks too.

`--no-baseline` reports the raw truth, which is what a release review should
look at.

Flags: `--engine <key>` to run one engine, `--release <id>` to label the
report, `--rehearse-red` to inject a failure and prove the gate still blocks,
`--no-baseline` to ignore the accepted-unproven list.
