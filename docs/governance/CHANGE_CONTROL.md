# Change Control

This document operationalizes the seven enforced change-control rules from the master roadmap prompt. It applies to every epic, child issue, ADR, data artifact, and planning file in this repository. The companion workflow rules (Definition of Ready, Definition of Done, canonical body files) are in [CONTRIBUTING.md](../../CONTRIBUTING.md).

The baseline rule behind everything below: **work not stated in an issue's Included scope is excluded.** Scope grows only through the processes on this page, never silently.

## Rule 1 — How to propose a scope change

A proposed scope change is a written proposal, not a hallway agreement. It must:

1. **Link the affected epic** (and any affected child issues).
2. **State the user value** of the change in product terms.
3. **State the new Included/Excluded boundaries** — the exact text that would replace the current Included and Excluded sections.
4. **State the dependency impact** — which native blocked-by/parent relationships change, and whether the milestone DAG order is affected.
5. **State the data/license impact** — whether any automotive fact, source, or redistribution right is added, changed, or newly required.
6. **State the migration impact** — whether `UserRepo` migrations, catalog schema, or upgrade paths are affected.
7. **State the QA impact** — which acceptance criteria, test plans, golden vehicles, or release gates change.
8. **State what existing work would be displaced** — which planned issues move, shrink, or are deferred to absorb the change.

Process: raise the proposal as an issue (or an issue comment on the affected epic) labeled `needs:decision`. If approved, update the canonical body files and `planning/roadmap.yml` first, then reconcile GitHub (see Rule 5). If rejected, record the disposition on the proposal so the question does not recur unanswered.

## Rule 2 — Evidence-bearing changes require evidence artifacts

Three classes of change carry a mandatory artifact. Approval without the artifact is invalid.

### 2a. Architecture changes require an ADR

Any change to an architecture constraint (on-device Mob/Phoenix LiveView, dual SQLite repositories, the `DeviceCommandBroker` boundary, the Netlify static boundary, the local-only security posture, and similar) requires an Architecture Decision Record under `docs/architecture/`, numbered sequentially (`ADR-000N-short-title.md`). An ADR states context, decision, alternatives considered, and consequences. ADRs enter as **proposed** and become accepted only on real evidence — for example, ADR-0001 and ADR-0002 remain proposed/pending-spike until the M00 physical-device gate resolves. Existing constraints are treated as binding unless a milestone produces contrary evidence and an approved ADR.

### 2b. Automotive claim/source changes require a source-rights record

Any change to a displayed automotive fact, a data source, an acquisition method, or a redistribution claim requires an updated source-rights/provenance record before it ships in any artifact:

- Update `docs/data/SOURCE_REGISTER.md` with the source, canonical URL or document locator, license/terms, access method, provider version, retrieved/verified dates, attribution requirements, and review disposition.
- Update `docs/data/LICENSING_CHECKLIST.md` where the change affects reuse rights.
- Ambiguous or unreviewed sources stay out of a shipped catalog. "Visible without a login" is not permission for automated extraction and redistribution.

### 2c. Forecast behavior changes require algorithm versioning

Any change to forecast arithmetic, blending weights, confidence thresholds, quarantine rules, or due-date resolution requires:

- a **new algorithm version** recorded with the change (forecast snapshots persist the algorithm version and input hash, so old records remain explainable);
- an **old-versus-new comparison over the golden test set** (`docs/quality/GOLDEN_VEHICLES.md`), attached as evidence, showing exactly which outputs change and why;
- respect for the invariant that a prediction may warn earlier but may never extend the OEM interval.

## Rule 3 — Adjacent work gets its own issue

A developer who discovers adjacent work — a refactor, a data gap, a missing test, a neighboring bug — creates a **separate issue** and links it to the issue where it was discovered. They do not add the work to the active issue without product reapproval of that issue's scope. This holds even when the adjacent work looks small; "while I'm in here" is exactly the growth this rule prevents. The Definition of Done requires that follow-up discoveries have their own issues.

## Rule 4 — Unresolved questions block; they are never assumed

If an issue in progress surfaces an unresolved product, licensing, architecture, or QA question, the issue moves back to `Backlog` or `Blocked` (with a `needs:decision`, `needs:license`, or equivalent label) until the question is answered. An unresolved question never becomes an implementation assumption. Guessing an answer to keep an issue moving is a change-control violation even when the guess turns out to be right.

## Rule 5 — Managed issue-body edits go file-first

The committed files under `planning/issues/` are the canonical issue bodies. A managed body edit follows this order, always:

1. Edit the committed body file.
2. Change its specification hash.
3. Get the diff approved.
4. Reconcile GitHub through the synchronization tooling under `scripts/github/` (dry-run first; `--apply` is explicit).

Editing the GitHub issue body directly and back-porting it later is not permitted for managed bodies. `planning/state.json` records the server-returned numbers, URLs, IDs, and hashes; remote IDs are never hand-invented.

## Rule 6 — Data corrections are versioned, never invisible

Data corrections never edit historical source snapshots invisibly. A correction to shipped or staged catalog data is a **versioned catalog correction** that includes:

- the evidence for the correction (source document, version, locator);
- an affected-record report (which rows/configurations change);
- a user-impact analysis (what users of the previous version saw versus what they will see);
- a release note entry.

Catalog records are immutable within one `data_version`; a correction produces a new version. User-facing history keeps its recorded snapshots so old records remain understandable after the catalog changes.

## Rule 7 — No fictional calendar

Milestone dates, iteration assignments, and estimates are added only after team capacity and release constraints are known. Until then:

- milestones carry no due dates;
- Project `Start date` and `Target date` fields stay blank;
- estimates stay blank until refinement, and no issue may exceed 8 points — larger work is split;
- no assignees, iterations, or due dates are invented in any planning artifact.

This roadmap specifies **order and gates, not a calendar**. The dependency DAG determines what runs next; dates are a team decision made later, on evidence.
