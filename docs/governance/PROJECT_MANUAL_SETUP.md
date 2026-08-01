# Project manual setup checklist

The roadmap synchronizer created the Project, the built-in `Status` options (Backlog, Ready, In Progress, In Review, In QA, Blocked, Done — configured via API and read back), all eight custom fields, and the six named views with their layouts. Current GitHub APIs do **not** expose view filters, grouping, sorting, visible fields, or built-in workflows, so the following must be applied by hand in the Project UI ("Digital Oil Sticker — Product Roadmap"). Attach a screenshot of each configured view to the epic DOS-M00-000 as evidence when done.

## Per-view configuration

| View | Layout (already set) | Filter | Group by | Sort | Visible fields |
| --- | --- | --- | --- | --- | --- |
| Delivery board | Board | `-label:kind:epic` | Status (columns) | Sequence asc | Title, Priority, Workstream, Milestone, Parent issue |
| Ready queue | Table | `status:Ready -label:kind:epic` | — | Priority asc, then Sequence asc | Title, Priority, Workstream, Risk, Milestone, Blocked by |
| Roadmap | Roadmap | (none) | Milestone | Sequence asc | Title, Status, Target; dates remain blank until a schedule is approved |
| QA queue | Table | `status:"In QA" OR label:needs:qa` | Status | Sequence asc | Title, Priority, Workstream, Milestone |
| Blocked | Table | `status:Blocked` (native "blocked by" open items also surface here) | Milestone | Sequence asc | Title, Priority, Blocked by, Risk |
| Post-MVP | Table | `target:Post-MVP` | Milestone | Sequence asc | Title, Status, Priority, Workstream |

Also enable **Sub-issue progress** as a visible field on Delivery board and Roadmap (Field menu → Sub-issue progress).

## Built-in workflows (Project → ⋯ → Workflows)

- `Item closed` → set Status: **Done**.
- `Pull request merged` → set Status: **Done**.
- `Item added to project` → set Status: **Backlog** (the synchronizer already set Backlog explicitly on all 77 items; this covers future items).
- Leave auto-archive off.

## Not configured anywhere (deliberate)

- No iterations, no Start/Target dates, no assignees, no Estimate values — these are added only after the team approves capacity and schedule (see docs/governance/CHANGE_CONTROL.md rule 7).
