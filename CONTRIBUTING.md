# Contributing

This is a planning-first repository. All work flows through the GitHub planning system described in the master roadmap prompt and governed by [docs/governance/CHANGE_CONTROL.md](docs/governance/CHANGE_CONTROL.md).

## Issues are the unit of work

- Every change begins with a repository issue. Work not stated in an issue's **Included** scope is excluded.
- Each milestone has one epic parent issue and implementable children, related through native sub-issue and blocked-by relationships. The dependency DAG, not issue number, determines execution order.
- Discoveries made while implementing an issue become a **new issue or ADR**, linked to the original. Never silently enlarge an active ticket. See change control rule 3.

## Canonical issue bodies live in this repository

- `planning/issues/<roadmap-id>.md` is the canonical body for every epic and child issue. The GitHub issue body is a mirror of that file, tracked by a specification hash in `planning/state.json`.
- To edit a managed issue body: **edit the committed body file first**, update its specification hash, get the diff approved, and then reconcile GitHub with the synchronization tooling under `scripts/github/`. Dry-run is the default; `--apply` is explicit.
- Never treat a hand-edited GitHub body as the source of truth, and never hand-invent remote issue numbers or IDs.

## Definition of Ready

An issue may enter `Ready` only when:

- its outcome, Included, and Excluded sections are explicit;
- acceptance criteria are independently testable;
- required designs/data fixtures/source rights/ADRs exist;
- no blocking product, licensing, architecture, or QA question remains;
- native parent and blocked-by relationships are accurate;
- data/privacy/accessibility/offline sections are answered or marked `N/A — reason`;
- implementation can finish without silently broadening scope.

Do not mark a downstream issue Ready merely because work could be prototyped; its native blockers and source rights remain authoritative.

## Definition of Done

An implementation issue is Done only when:

- acceptance evidence is attached;
- automated and required physical-device tests pass;
- migrations/recovery are verified where applicable;
- documentation and source attribution are updated;
- logs/fixtures contain no private vehicle data;
- the linked PR uses `Closes #…`;
- follow-up discoveries have their own issues.

An epic closes only after every required child and its aggregate integration gate pass.

## Branches and pull requests

- Create a branch per issue; do not commit unrelated work to an issue's branch.
- Every PR links its issue with `Closes #…` in the description.
- Every PR attaches the acceptance evidence its issue requires (test output, device evidence, coverage or validation reports as applicable). Evidence and fixtures must contain no private vehicle data.
- A PR implements only its issue's Included scope. Adjacent work found during implementation gets its own issue and its own PR.
- An unresolved question discovered mid-implementation moves the issue back to `Backlog`/`Blocked`; it does not become an implementation assumption.

## Change-control summary

Full rules live in [docs/governance/CHANGE_CONTROL.md](docs/governance/CHANGE_CONTROL.md). In short:

- Scope changes are proposed against the affected epic with explicit new Included/Excluded boundaries and their dependency, data/license, migration, and QA impact.
- Architecture changes require an ADR. Automotive claim or source changes require an updated source-rights/provenance record. Forecast behavior changes require a new algorithm version and an old/new golden-test comparison.
- Data corrections are versioned catalog corrections with evidence; historical source snapshots are never edited invisibly.
- Milestone dates, iterations, and estimates are added only after team capacity and release constraints are known. Never invent start dates, target dates, assignees, or estimates in planning artifacts.

## Content rules

- No fabricated automotive facts anywhere: issues, docs, fixtures, or examples. Missing data is unknown or unsupported, never guessed.
- Use the required terminology from the product content contract (for example "Meets the recorded requirements", "Estimated due date", "Source unavailable", "Exact configuration not verified").
- American English throughout. Files are UTF-8 without BOM, LF line endings, with a final newline.
