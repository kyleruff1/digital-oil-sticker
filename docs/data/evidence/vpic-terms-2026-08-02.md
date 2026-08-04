# vPIC API terms of service snapshot

- Date recorded: 2026-08-02
- Source URL: https://vpic.nhtsa.dot.gov/api/Home/Index/faq
- Companion page: https://vpic.nhtsa.dot.gov/api/
- Snapshot captured by: owner
- Why we consider this source approved: The vPIC API is offered by NHTSA
  as a public, no-cost API with no license, registration, contract, or
  API key required. Access terms below expressly authorize public use and
  redistribution of the returned factual data, which is the basis
  `docs/data/FACTUAL_USE_AND_MARKS_POLICY.md` §"Source-level authorization"
  cites and that `docs/architecture/ADR-0004-browser-first-client-and-hosting.md`
  §R6 leaves out of the licensed-source hard gate ("Public-domain U.S.
  Government sources are unaffected"). vPIC content is populated partly
  from manufacturer submissions, so approval rests on the express
  open-data authorization plus the factual nature of the extracted
  fields — not on a blanket 17 U.S.C. §105 federal-work claim.

## Verbatim snapshot of the vPIC API FAQ (relevant items)

Source: https://vpic.nhtsa.dot.gov/api/Home/Index/faq — retrieved
2026-08-02.

> **What is the vPIC API?**
>
> The vPIC API provides different services that can be used to gather
> information on Vehicles and their specifications. NHTSA's Product
> Information Catalog and Vehicle Listing (vPIC) is an online catalog of
> vehicle manufacturers, their products, and their specifications.

> **How much does it cost to use the vPIC API?**
>
> The vPIC API is free to use.

> **Do I need an API key or to register to use the vPIC API?**
>
> No, you do not need to register or obtain an API key to use the vPIC
> API. It is available for public use.

> **May I redistribute the data?**
>
> The information provided by the vPIC API is publicly available
> information collected by NHTSA. You may use and redistribute the data
> subject to attributing the source to NHTSA vPIC.

> **Are there rate limits?**
>
> The vPIC API is subject to reasonable-use rate control. Clients that
> generate excessive traffic may receive HTTP 429 responses with a
> `Retry-After` header; clients are expected to honor it.

## Companion vPIC API landing page (https://vpic.nhtsa.dot.gov/api/) — relevant excerpts

> vPIC provides different services and different filters that can be
> used to gather information on Vehicles and their specifications. The
> API is free and does not require registration.

> Data returned by the vPIC API is publicly available information.
> Attribution to NHTSA vPIC is requested when the data is used or
> redistributed.

## Operational controls we impose in addition to the terms above

These are internal operating rules; they are not conditions imposed by
NHTSA. They are captured here so the evidence hash covers both what the
source authorizes and how we exercise that authorization.

- ID-based endpoints only; no VIN or user-entered data is sent to vPIC.
- Rate control with `Retry-After` honored; cache and resume between
  runs.
- Provenance timestamps preserved per retrieval; source URL and
  retrieval date stored on every `data_sources` row.
- NHTSA/vPIC attribution rendered on the attribution page; no implied
  endorsement copy.
- Release-notes and FAQ monitored; any change to the terms above
  triggers a re-hash of this file and a compiler rebuild so the new
  `terms_sha256` propagates through the manifest.

## Cross-references

- `docs/data/FACTUAL_USE_AND_MARKS_POLICY.md` §"Source-level
  authorization" — the policy row this evidence backs.
- `docs/data/SOURCE_REGISTER.md` — the "NHTSA vPIC API" register entry.
- `docs/architecture/ADR-0004-browser-first-client-and-hosting.md` §R6 —
  licensed-source web-serving gate, which explicitly exempts
  public-domain U.S. Government sources such as this one.
- `tools/catalog/src/compile/production.mjs`,
  `tools/catalog/src/compile/bootstrap.mjs`,
  `tools/catalog/src/compile/fixture.mjs` — the three compile paths
  whose `data_sources.terms_sha256` column carries this file's
  SHA-256.
