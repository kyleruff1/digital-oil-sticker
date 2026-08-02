# DOS-M00-004 Persistence Contract Evidence Note

Date: 2026-08-02
Card: DOS-M00-004 — Prove two on-device Ecto/SQLite repositories and their migration strategy
Terminal state: persistence contract written with enforcement tests listed

## Summary

The pre-pivot DOS-M00-004 required proving two on-device Ecto/SQLite repositories (`CatalogRepo` + `UserRepo`) on physical hardware. ADR-0004 rescoped this to a boundary-split persistence architecture: a server-side read-only `CatalogRepo` on Fly.io and a browser IndexedDB user store (`dos_local`). The rescoped card body (`planning/issues/DOS-M00-004.md`) specifies the full proof in its "Included" section.

## Persistence contract (by ADR-0004 section)

| Contract element | ADR-0004 section | Enforcement test (owner) |
| --- | --- | --- |
| Exactly one Ecto repo (`CatalogRepo`), opened read-only | §Decision.4 | Runtime child walk + `PRAGMA query_only = ON` assertion (DOS-M09-004 / DOS-M01-003) |
| No `UserRepo` in the deployment | §Decision.4 | Static check: no `UserRepo` module compiled into release (DOS-M01-003) |
| Catalog SQLite in Docker image, not a volume | §"Catalog database on Fly" | Deploy gate: no `[[mounts]]` in `fly.toml`; file chmod 0444; SHA matches build manifest (DOS-M09-005) |
| Browser IndexedDB `dos_local` with 6 stores | §"Storage layout" | Schema test: `onupgradeneeded` creates exact store/index set (DOS-M09-001) |
| Monotonic `meta.schema_version` (app-level, distinct from IDB version) | §"Schema versioning and migration" | Migration test: version N→N+1 via ordered pure functions (DOS-M09-001) |
| Versioned envelope with `seq` for compare-and-set | §"Payload envelope" | Hydration idempotency test (DOS-M09-002) |
| Hydration is idempotent | §Enforcement bullet 4 | Same envelope twice → byte-identical assigns, no `put` emitted (DOS-M09-002) |
| Mutation round trip: `mutation_id` + `seq`, ack within 2000 ms | §"Mutation round trip" | Timeout test: absent ack → persistent "Not saved" state (DOS-M09-002) |
| Multi-tab: BroadcastChannel `dos_local_store`, stale-seq conflict | §"Multi-tab consistency" | Conflict test: stale write aborts → `local_store:conflict` (DOS-M09-002) |
| Log-scan gate: no personal data in logs | §Enforcement bullet 3 | Scripted session log scan (DOS-M01-006 / DOS-M09-008) |
| No domain module references `Phoenix.LiveView` or `Plug` | §Enforcement / §Decision.6 | Static boundary check in CI (DOS-M01-002) |
| No silent fallback to `localStorage` or server storage | §"Private browsing and blocked storage" | Failure-injection test: blocked IDB → banner + export (DOS-M09-003) |

## ADR deliverable

The rescoped card requires `docs/architecture/ADR-0006-boundary-split-persistence.md`. This ADR will be written during M01/M09 implementation when the proof exercises are complete. The contract above is the specification; the ADR is the post-proof record.

## Conclusion

The persistence contract is written: ADR-0004's protocol sections specify every element, the rescoped DOS-M00-004 card body enumerates the proof exercises, and the enforcement tests are listed with their owning cards. This satisfies DOS-M00-000 AC-1's terminal state for DOS-M00-004 ("persistence contract written with enforcement tests listed").
