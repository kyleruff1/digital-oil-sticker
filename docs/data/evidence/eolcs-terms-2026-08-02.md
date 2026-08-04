# EOLCS Terms of Use snapshot

- **Recorded:** 2026-08-02
- **Recorded by:** kyleruff1
- **Source:** American Petroleum Institute (API) — Engine Oil Licensing and
  Certification System (EOLCS) product directory and associated API terms.

## Observed terms

Recorded 2026-08-02: the API T&C prohibit reproduction/derivatives without
written authorization. In particular, the EOLCS product directory and any
associated data feeds may not be copied, redistributed, or used to create
derivative works (including a compiled catalog of licensed products, brand
names, or SAE grade / performance-category claims) without prior written
authorization from the American Petroleum Institute.

## Consequence for Digital Oil Sticker

Combined with the `Disallow: /` robots directive recorded in
`eolcs-robots-txt-2026-08-02.txt`, the six-axis disposition for EOLCS is:

- `copyright_basis = licensed`
- `acquisition_basis = prohibited`
- `redistribution_basis = prohibited`
- `trademark_posture = review_required`
- `claim_posture = prohibited`
- `review_status = rejected`

No EOLCS-derived rows are emitted into any Digital Oil Sticker catalog build
(production, bootstrap, or fixture). This file exists so the six-axis policy
has a positive `data_sources` record of the gate rather than an implicit
absence. See `docs/data/FACTUAL_USE_AND_MARKS_POLICY.md` for the surrounding
policy.
