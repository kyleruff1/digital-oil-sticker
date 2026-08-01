# Deploy runbook

**Status:** Authored 2026-08-01 (DOS-M09-005, issue #83). **No procedure in this document has been executed end to end.** §7 lists exactly what is unrehearsed and what that means for your confidence at 3am.

This runbook covers the Phoenix LiveView application deployed as the Fly.io app `digital-oil-sticker`. It assumes the ADR-0004 posture: one region (`ord`), no volume, no release command, a read-only catalog baked into the image, and **no server-side record of any user's data**.

Commands are written for **Git Bash** on the owner's Windows workstation, because the repository's own CI is bash and the workstation has no `jq` (verified 2026-08-01) — JSON is parsed with `node`, which is present. `flyctl` lives at `C:\Users\kyler\.fly\bin\flyctl.exe`; put it on `PATH` first:

```bash
export PATH="$PATH:/c/Users/kyler/.fly/bin"
```

File-and-line references are accurate as of 2026-08-01 and will drift. If a line number does not point where this document says it does, trust the named file and symbol, not the number.

---

## 0. Read this first — the repository and the running app disagree

If you skip this section you will misread every command below.

Measured 2026-08-01 with the commands shown:

| Fact | How it was measured | Value |
| --- | --- | --- |
| Releases | `flyctl releases --app digital-oil-sticker` | v1 (failed) through v12 (complete). v12 is live. All 12 pushed by `kyleruff@gmail.com` from a workstation. |
| Machines | `flyctl status --app digital-oil-sticker` | Two, both `started`, both in `ord`: `2862e40c6e0758` and `48ee567fd20ee8`. Each reports **`1 total, 1 passing`**. |
| Live image | `flyctl releases --json` | `registry.fly.io/digital-oil-sticker:deployment-01KYZK2J6KVEVD9PT6Y31SN50D` |
| Live health config | `flyctl config show -a digital-oil-sticker` | **One** check: `GET /health`, 30 s. |
| Repo health config | `app/fly.toml` | **Two** checks: `GET /ready` (15 s) and `GET /health` (30 s). |
| `/health` on the live app | `curl -o /dev/null -w "%{http_code}"` | `200` |
| `/ready` on the live app | same | **`404`** |
| `/version` on the live app | same | **`404`** |
| Deploy credential | `flyctl tokens list -a digital-oil-sticker` | Zero rows. |
| GitHub secret | `gh secret list` | Empty. |
| Orphan volume | `flyctl volumes list --app digital-oil-sticker` | `vol_4y8d01doz7gmz21r`, 1 GB, region `iad`, `created`, **no attached VM**. |
| Local Docker | `which docker` | Absent. `flyctl deploy` therefore builds on a Fly remote builder, not locally. |
| flyctl | `flyctl version` | v0.4.77 |

Three consequences you must hold in your head:

1. **The health-endpoint work in this repository is not deployed.** `/ready` and `/version` return 404 on the live app. Every verification step in §3 will fail against the *current* release and will only start working after the first deploy that carries `HealthController` and the two-check `fly.toml`. That first deploy is therefore not a routine deploy; treat it as the rehearsal §7 says has never happened.

2. **`min_machines_running = 1` but two machines are running.** That is an unrecorded posture, not a setting. It is probably better than one machine (a rolling deploy has somewhere to send traffic), but nobody decided it and nothing in `fly.toml` asks for it. **The owner must settle this**: either raise `min_machines_running` to 2 and accept the second machine's cost deliberately, or scale down to 1 and accept that a deploy takes the whole app out of rotation for the length of one machine replacement. Leaving it as is means the next `flyctl scale` or a machine-destroying incident silently changes the deploy's blast radius.

3. **An unattached 1 GB volume exists in `iad`.** A volume is precisely what ADR-0004 forbids (`app/fly.toml` has no `[[mounts]]`, and the catalog is a build artifact, not state). It predates ADR-0004 and is attached to nothing, so it is not affecting deploys — but it costs money and it contradicts the recorded architecture. **Deleting it is a destructive owner action and is out of scope for this runbook.** Do not delete it mid-incident.

---

## 1. Preflight

Everything here is cheap. Run all of it. A ten-second local check is better than a ten-minute remote build that fails on the same condition.

### 1.1 The working tree must be clean

```bash
cd /c/Users/kyler/digitalOilSticker
git status --porcelain          # must print nothing
git rev-parse HEAD              # write this down — you will assert it in §3.2
```

Why: a workstation deploy builds from the tree on disk, not from a commit. If the tree is dirty you ship something that exists nowhere in git, and the git SHA you stamp into the image is then a **lie** — the image claims a commit whose contents it does not have. That is worse than an unlabelled image, because it defeats the one check (§3.2) designed to catch a wrong deploy.

> As of 2026-08-01 the working tree is **not** clean. The deploy that carries this runbook's own subject matter must commit first.

### 1.2 CI must be green for the exact commit you are deploying

```bash
gh run list --workflow=ci.yml          --branch main --limit 5
gh run list --workflow=conformance.yml --branch main --limit 5
```

Match the SHA column against §1.1's `HEAD`. "Green on main yesterday" is not green on this commit.

If a run is still in flight: `gh run watch`.

What CI proves (`.github/workflows/ci.yml`): the fixture catalog rebuilds byte-identically from the pipeline, formatting, `mix compile --warnings-as-errors`, `mix test`, no unused deps, catalog determinism across two builds, the committed production catalog matches its manifest, and the conformance suite's own self-tests.

What the conformance workflow proves (`.github/workflows/conformance.yml`): the Tier 1 browser assertions in `conformance/` against a deployed target, plus a red-run rehearsal that proves the gate still blocks. Note the ordering problem this creates and do not pretend otherwise: **conformance runs against whatever is currently deployed, not against the image you are about to ship.** Its pre-deploy run tells you the *previous* release was conformant. The post-deploy run (`deploy.yml`'s `conformance` job) is the one that speaks about the new release.

### 1.3 The catalog artifact must match its manifest

Run the **same script the image build runs** — not a re-implementation of it, which is how a preflight check drifts from the gate it is supposed to predict:

```bash
cd /c/Users/kyler/digitalOilSticker/app
sh scripts/verify_catalog.sh priv/catalog/catalog.sqlite3 priv/catalog/catalog-manifest.json
```

Success prints `catalog verified: sha256 <hash>, <n> bytes, schema 1`. Any failure prints a distinct `FAIL:` line and exits non-zero — see §6.4 for what each one means.

Do **not** pass `--expect-no-fixtures` here. That flag asserts no test fixture sits beside the production catalog, which is correct inside the image (`.dockerignore` keeps fixtures out of the build context) and wrong in a working tree, where the fixtures are supposed to be there.

Running this locally turns a failed ten-minute remote build into a five-second answer.

### 1.4 If you cannot see a green CI run for this commit, run the gate locally

```bash
cd /c/Users/kyler/digitalOilSticker/app
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```

This is a substitute for CI, not an addition to it. It does not run the catalog-determinism job or the browser suite.

### 1.5 Record the rollback target before you change anything

```bash
export PATH="$PATH:/c/Users/kyler/.fly/bin"
flyctl releases --app digital-oil-sticker | head -4
flyctl releases --app digital-oil-sticker --json \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const r=JSON.parse(s)[0];console.log(r.Version, r.ImageRef)})"
```

Write down both the version number and the full `ImageRef`. Do it **now**, while you are calm. §5 needs it, and §5 is where you will be least able to look things up.

---

## 2. The deploy

Two paths. Path A is the intended one and does not work yet. Path B is what has actually shipped all 12 releases.

### Path A — the GitHub Actions workflow

**Prerequisite: `FLY_API_TOKEN` does not exist.** Verified 2026-08-01: `flyctl tokens list -a digital-oil-sticker` returns zero rows and `gh secret list` is empty. Until the owner provisions it, `.github/workflows/deploy.yml` is inert by design — its `preflight` job emits a warning, sets `armed=false`, and the `deploy` job is skipped.

**Read that consequence carefully: an inert run reports SUCCESS.** A green check mark on the Deploy workflow currently means "the workflow correctly declined to deploy", not "the deploy worked". Open the run and read the preflight warning before you believe anything.

Arming it is an **owner action**. It creates a credential, so it is done by the owner, in the owner's own terminal, and never by an agent:

```bash
# Owner only. Creates a deploy-scoped token (least privilege, per ADR-0004 "Secrets").
flyctl tokens create deploy -a digital-oil-sticker

# Paste it at the prompt rather than passing --body, so it does not land in shell history.
gh secret set FLY_API_TOKEN --app actions
```

Once armed, trigger a deploy:

```bash
gh workflow run deploy.yml -f reason="<why this deploy is happening>"
gh run watch
```

The trigger is `workflow_dispatch` only, deliberately. Deploy-on-merge is not a CI preference here — every deploy drops every live LiveView socket (§4), so "on merge" is a product decision about interrupting people mid-task. That decision is not recorded, so a human asks.

`-f skip_conformance=true` exists for emergency rollback only. Using it on a forward deploy means shipping without the browser gate.

**Two things about this workflow that have never run and that you should expect to break on the first armed attempt:**

- **Working directory.** The deploy steps run `flyctl deploy --app "$FLY_APP"` from the checkout root. The repository's only `fly.toml` is at `app/fly.toml` and the only `Dockerfile` is at `app/Dockerfile`. Measured 2026-08-01: running `flyctl` from the repository root fails with `the config for your app is missing an app name, add an app field to the fly.toml file or specify with the -a flag` — flyctl does **not** find `app/fly.toml` from there. The fix is `working-directory: app` on the deploy step (or `--config app/fly.toml --dockerfile app/Dockerfile`). This is unverified as a deploy failure only because the workflow cannot run at all yet.
- **Release identity.** See the warning in Path B. It applies identically to Path A, because both paths build the same `Dockerfile`.

### Path B — the workstation fallback

Run this **from `app/`**, not from the repository root (see the measurement above).

```bash
export PATH="$PATH:/c/Users/kyler/.fly/bin"
cd /c/Users/kyler/digitalOilSticker/app

GIT_SHA=$(git rev-parse HEAD)
BUILD_TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

flyctl deploy \
  --app digital-oil-sticker \
  --build-arg GIT_SHA="$GIT_SHA" \
  --build-arg BUILD_TIMESTAMP="$BUILD_TIMESTAMP" \
  --image-label "sha-$GIT_SHA" \
  --wait-timeout 600
```

With no local Docker (verified), this builds on a Fly remote builder. Build time is unmeasured; `--wait-timeout 600` is copied from the workflow and is likewise unmeasured — if a deploy times out at ten minutes, that is a number nobody has justified, not evidence of a hung deploy.

`--image-label "sha-$GIT_SHA"` is not cosmetic. Every existing release is tagged `deployment-<ULID>` (see §0), which names *when* it was pushed and nothing about *what* it contains. A `sha-` label lets §5 pick a rollback target by reading the tag instead of correlating timestamps.

#### Why the build args are not optional

The chain, traced through the actual files:

1. `app/Dockerfile:94-97` declares `ARG GIT_SHA=unknown` / `ENV GIT_SHA=${GIT_SHA}` in the builder stage, and `:125-128` repeats it in the runner stage (ARGs do not cross a `FROM`).
2. `app/lib/digital_oil_sticker/release.ex:30-31` reads `GIT_SHA` and `BUILD_TIMESTAMP`, defaulting each to the string `"unknown"`.
3. `app/lib/digital_oil_sticker_web/controllers/health_controller.ex:176-177`: the `release_identified` readiness check fails when `FLY_MACHINE_ID` is set **and** `git_sha` is `"unknown"` — "deployed image carries no git sha".
4. A failing check means `/ready` returns **503** (`:service_unavailable`), and `app/fly.toml:40-45` wires `/ready` to a 15-second health check.

So on a laptop, `unknown` is deliberate and harmless — `mix phx.server` has no build arg and refusing to boot over that would be theatre. On a Fly machine it is fatal to readiness: the machine never goes green, and `/version` reports a build that cannot say which commit it is. **A workstation deploy without those two flags produces an image that cannot identify itself.**

#### The part that is worse than that, and that you must verify on the first deploy

`@git_sha` in `release.ex:30` is a **module attribute** — it is evaluated at compile time. In `app/Dockerfile`, `RUN mix compile` is line 81 and `ENV GIT_SHA` is line 96. The environment variable is set *after* the code that reads it has already been compiled, and `mix release` at line 100 will not recompile an unchanged `lib/`.

Measured 2026-08-01 on Elixir 1.20.2/OTP 28 (the workstation toolchain; the image builds on Elixir 1.18, which was not measured), with a minimal project containing exactly `@v System.get_env("GIT_SHA") || "unknown"`:

| Step | Result |
| --- | --- |
| `mix compile` with `GIT_SHA` unset | attribute is `"unknown"` |
| `GIT_SHA=deadbeef mix compile` (no source change) | **still `"unknown"`** — nothing recompiled |
| `GIT_SHA=deadbeef mix compile --force` | `"deadbeef"` |

Elixir does not treat a compile-time `System.get_env/1` as a recompilation trigger. If that holds in the image, then **the build args are necessary but not sufficient**, and every image this Dockerfile produces reports `git_sha: "unknown"` regardless of what you pass — which means `/ready` never goes green once the two-check `fly.toml` ships.

This is unverified in the real image only because `/version` does not exist on the live app yet (§0). **§3.2 is the step that finds out.** Do not skip it, and do not treat a 503 on the first deploy as a mystery — check `/version` first. If it reports `unknown`, the fix is in the Dockerfile, not in your command: move the `ARG`/`ENV GIT_SHA` block above `RUN mix compile`, so the value exists before the module is compiled.

---

## 3. Verification

Never trust "deploy succeeded". Fly accepting a deploy means Fly accepted a deploy. It does not mean the machine can serve.

### 3.1 Poll readiness until it says `ready`

```bash
APP=digital-oil-sticker
for attempt in $(seq 1 30); do
  body=$(curl -fsS "https://$APP.fly.dev/ready" || true)
  if echo "$body" | grep -q '"status":"ready"'; then
    echo "ready after $attempt attempt(s)"; echo "$body"; break
  fi
  sleep 5
done
```

Thirty attempts at five seconds is 150 seconds. That budget is **copied from `deploy.yml` and is unmeasured** — nobody has recorded how long this application actually takes to become ready after a machine replacement. Treat an expiry as "I do not know whether this is slow or broken" and go read the body, not as a diagnosis.

If it is not ready, read which check failed — that is the whole point of naming them:

```bash
curl -sS "https://$APP.fly.dev/ready" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const r=JSON.parse(s);console.log(r.status);for(const [k,v] of Object.entries(r.checks))console.log((v.ok?'ok  ':'FAIL'),k,v.detail??'')})"
```

The six checks, and what each one failing actually means:

| Check | Fails when |
| --- | --- |
| `catalog_present` | The artifact is not on this machine — the image was built without it, or the path did not resolve. |
| `catalog_payload_matches_boot` | The artifact's SHA-256 differs from what it was at boot. Something replaced a file that is `0444` and root-owned. |
| `catalog_read_only` | A `CREATE TABLE` against the catalog **succeeded**. Four write-prevention layers failed at once. |
| `catalog_schema_supported` | The artifact's `schema_version` is outside the window this code supports. |
| `catalog_queryable` | `SELECT count(*) FROM vehicle_configurations` returned zero or did not run. The file opens but holds nothing usable. |
| `release_identified` | `catalog_data_version` is unknown, or a deployed machine (`FLY_MACHINE_ID` set) reports `git_sha` unknown. See §2 Path B. |

The check runs **fail closed**: an exception is reported as not-ready, never as ready.

### 3.2 Assert the live machine is the commit you deployed

This is the single most important step in the runbook. It is the only thing that distinguishes "I deployed" from "I believe I deployed".

```bash
APP=digital-oil-sticker
EXPECTED=$(git -C /c/Users/kyler/digitalOilSticker rev-parse HEAD)
REPORTED=$(curl -fsS "https://$APP.fly.dev/version" \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).git_sha))")
echo "expected=$EXPECTED"
echo "reported=$REPORTED"
[ "$EXPECTED" = "$REPORTED" ] && echo MATCH || echo "MISMATCH — the live machine is not what you built"
```

Then read the whole identity, because four things move on four schedules and you want all four recorded:

```bash
curl -fsS "https://$APP.fly.dev/version"
```

Expected fields (`release.ex:39-53`): `app_version`, `git_sha`, `built_at`, `catalog_data_version`, `catalog_schema_version`, `catalog_payload_sha256`, `local_store_schema_version`, `fly_release_version`, `fly_image_ref`, `fly_machine_id`, `fly_region`.

Check `catalog_payload_sha256` against `payload_sha256` in `app/priv/catalog/catalog-manifest.json` (`c978c2cd2825144181c42d836a98986c17c1d064d6ccb1f63f7130747029cec6` as of 2026-08-01). This is the artifact hashed **on disk right now on the running machine**, not a manifest's claim about it.

> **`/version` is per-machine.** Two machines are running (§0) and Fly's proxy picks one per request. A single passing `/version` proves one machine is on the new release. Repeat the call a few times, or check each machine individually, before concluding both are.

### 3.3 Smoke walk

```bash
APP=digital-oil-sticker
curl -fsS "https://$APP.fly.dev/health"  > /dev/null && echo "health ok"
curl -fsS "https://$APP.fly.dev/"               | grep -q "Digital Oil Sticker" && echo "root ok"
curl -fsS "https://$APP.fly.dev/vehicle/select" | grep -q "Choose a vehicle"   && echo "picker ok"
```

The strings are verified present in source: `Digital Oil Sticker` in `app/lib/digital_oil_sticker_web/components/layouts/root.html.heex:7`, `Choose a vehicle` in `app/lib/digital_oil_sticker_web/live/vehicle_picker_live.ex:111`.

This is a **static-render** smoke walk. `curl` gets the dead HTML; it never opens a WebSocket, never runs the hook, never touches IndexedDB. It proves the app boots and the catalog answers. It proves nothing about hydration. For that, run the browser suite:

```bash
cd /c/Users/kyler/digitalOilSticker/conformance
npm ci --no-audit --no-fund
npx playwright install chromium firefox webkit
node bin/dos-conformance.mjs --base-url https://digital-oil-sticker.fly.dev --release "$(git rev-parse HEAD)"
```

It exits non-zero on any Tier 1 result that is not a pass — including an assertion that never ran and an engine that could not launch. There is no "skip".

---

## 4. What a deploy does to the people using the app

### Every deploy drops every live LiveView socket

Not "may". LiveView holds UI state in a server process; replacing the machine kills the process. ADR-0004 states this outright ("Deploys drop every WebSocket") and accepts it as an MVP cost (R8).

### What a user actually experiences

1. **The socket drops.** The DOM they are looking at stays on screen. LiveView does not tear the view down on disconnect; `phx-disconnected` styling communicates the reconnection rather than reverting to a skeleton (ADR-0004, "First-paint and empty-state rules").
2. **The client reconnects with backoff** and **remounts**. A remount is a fresh `mount/3` on a fresh process with **empty** assigns — the server begins knowing nothing about them, because the server never knew anything durable about them.
3. **Hydration re-runs.** The `LocalStore` hook reads IndexedDB and pushes `local_store:hydrate`; the server validates it, migrates it if needed, and populates assigns (INV-24.1). This is a **per-mount** operation by design, which is why it must be idempotent and visually non-destructive.
4. **A hydration deadline is armed at 5 000 ms** (`local_store/session.ex:11-14`). If no hydrate event arrives, the user gets the explicit `:storage_unavailable` state — a distinct state from "empty garage", saying so in words.
5. **The provisional §9 budget for reconnect is p95 ≤ 2.0 s, and for hydration completion p95 ≤ 300 ms after socket join.** Both are marked *provisional* in `CONSTITUTION.md` §9 and neither has been measured against the deployed app. Do not quote them to anyone as an observed reconnect time.

### What happens to a write that was in flight

Be precise here, because the comfortable version is wrong.

A mutation is staged in `pending_writes` in socket assigns, pushed to the browser as `local_store:put`, and rendered as **SAVING** — never as committed — until the hook acks (`local_store/session.ex:101-136`, INV-24.2). The ack timeout is 2 000 ms; a missed or failed ack surfaces as a persistent "Not saved to this browser" state, not a silent rollback.

If the socket drops between the push and the ack:

- The `pending_writes` ledger dies with the process, and a remount initialises it to `%{}` (`session.ex:33`). **Nothing on the server retries it.**
- What the user ends up with is whatever their **browser** actually committed. If the hook's IndexedDB transaction completed before the drop, re-hydration finds the record and it is simply there. If it did not, the record does not exist — and it never did, because it was never rendered as committed.

ADR-0004's phrase "pending writes are re-driven after remount from client storage" is accurate only in that sense: re-hydration reads whatever the browser holds. It does **not** mean an un-acked mutation is replayed.

### Why no user data is at risk

The browser is the system of record. INV-23 puts the garage, service history, odometer readings, and reminder intent in IndexedDB and forbids any personal row on the server. INV-24.1 says it explicitly: *"A server restart or a Fly.io machine replacement MUST NOT lose user data, because the server was never the system of record."*

Concretely: there is no server-side database of user data to corrupt, no migration to fail, no backup to restore — and no backup **exists**, which is the same fact stated honestly. The catalog is read-only and baked into the image. A deploy replaces code and catalog; it cannot touch a user's records because it cannot reach them.

The converse is the risk that actually exists, and it is not a deploy risk: if a user's browser storage is cleared or evicted, the data is gone and there is no recovery but their own export (INV-24.8, INV-25). A deploy neither causes nor mitigates that.

### The conformance assertions that back the reconnect claim

In `conformance/src/cases/storage.mjs`:

| Assertion | Requirement | What it proves |
| --- | --- | --- |
| `hydration.reconnect-no-skeleton-teardown` | FR-8 | Sets up a vehicle, logs an oil change, then drops and restores the socket **the way a deploy does** (`liveSocket.disconnect()` / `connect()`), and asserts the view does not fall back to an empty-garage state and that the sticker's own values come back. |
| `hydration.idempotent` | FR-8 | Hydrating the same payload twice leaves the store byte-identical — hydration is not writing back, so repeated remounts cannot drift the data. |
| `hydration.no-empty-claim-before-resolution` | FR-7 | Captures every frame from first paint and asserts no frame before resolution claims an empty garage. A returning user is never told, even for one frame, that their garage is empty. |
| `eviction.data-missing-distinct-from-first-visit` | FR-10 | An evicted store renders the `:data_missing` state and a genuine first visit does not. Loss is never disguised as a fresh install. |
| `multitab.propagation-and-compare-and-set` | FR-13 | Two tabs converge on the same events rather than clobbering each other. |

**What these do not prove, stated plainly.** The reconnect case simulates a socket drop *inside the page*. It does not deploy a new release underneath a live session, and no test anywhere exercises a real deploy against live users. The end-to-end claim "a deploy is a non-event for users" (ADR-0004 R8) is **unproven**. What would prove it: open a session with a populated garage, run a real deploy against it, and record what the session did. That rehearsal has not been run (§7).

---

## 5. Rollback

Rollback here is a redeploy of a previous image. There is no volume, no release command, and no database migration to reverse, so the operation is genuinely just "run the old bytes again".

### 5.1 Pick the target

```bash
export PATH="$PATH:/c/Users/kyler/.fly/bin"
flyctl releases --app digital-oil-sticker
flyctl releases --app digital-oil-sticker --json \
  | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{for(const r of JSON.parse(s).slice(0,6))console.log(r.Version,r.Status,r.CreatedAt,r.ImageRef)})"
```

Pick the **most recent release you have positive evidence was good** — a recorded `/version` response, a green conformance report, or your own memory of using it. Do not pick "the one before this" reflexively; if the bad change shipped three releases ago, v-1 is also bad.

Every current release is tagged `deployment-<ULID>`, which tells you nothing about contents (§0). Correlate by `CreatedAt` and by whatever you wrote down in §1.5. This is exactly the pain `--image-label "sha-$GIT_SHA"` exists to remove for future releases.

### 5.2 Deploy that image

```bash
cd /c/Users/kyler/digitalOilSticker/app
flyctl deploy \
  --app digital-oil-sticker \
  --image registry.fly.io/digital-oil-sticker:deployment-<ULID-of-the-good-release> \
  --wait-timeout 600
```

Use the **full** `ImageRef` from §5.1, registry host included. `--image` skips the build entirely: no rebuild, no remote builder, no chance of a different result from the same source. That is the point — you are re-running a known artifact, not re-deriving one.

Do not pass `--build-arg` here. There is no build.

### 5.3 Verify the rollback took

The same three steps as §3, in the same order, with one difference: the SHA you assert is the **old** one.

```bash
APP=digital-oil-sticker
curl -sS "https://$APP.fly.dev/ready"   | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>console.log(JSON.parse(s).status))"
curl -fsS "https://$APP.fly.dev/version"
```

Confirm `git_sha` is the rolled-back commit and `fly_release_version` has advanced (a rollback is a **new, higher** release number carrying older bytes — `flyctl releases` will show v13 running v10's image, not a return to v10). Confirm `catalog_payload_sha256` matches the catalog that shipped in that image, which may not be the one in your working tree.

Then re-run the smoke walk (§3.3). Call the incident closed only after that.

### 5.4 What rollback does and does not undo

**It does roll the catalog back, necessarily and inseparably.** `app/Dockerfile:67` copies `priv` — including `priv/catalog/catalog.sqlite3` — into the builder, `:78` verifies it against `catalog-manifest.json`, `:131` copies the compiled release into the runner image, and `:146` re-verifies it *in the final image* before setting it `root:root` and `0444`. There is no volume and no `release_command` (`app/fly.toml`). The catalog is therefore *inside* the image, and redeploying an old image restores that image's catalog byte-for-byte.

State the corollary precisely, because it cuts both ways: **you cannot roll back code without rolling back catalog data, and you cannot roll back catalog data without rolling back code.** They are one artifact. If you deployed a code fix and a `catalog_data_version` bump in the same image, rolling back the code reverts the data too — every vehicle, interval, and oil-model row goes back to the previous `data_version`, and `/version` will report that older `catalog_data_version`. If you need to keep the new catalog and drop the new code, that is not a rollback; it is a new build from the old code with the new `priv/catalog`, and it needs its own commit.

**What rollback cannot undo is anything the newer release already wrote into a user's browser.** The server has nothing to reverse, but the browser does:

- If the newer release bumped `local_store_schema_version` (currently `1`, `local_store/envelope.ex:31`) and migrated a user's payload, that user's IndexedDB now holds a **newer** schema than the rolled-back server understands. Per ADR-0004 ("Schema versioning and migration"), the server then **MUST NOT write**: it enters read-only mode, shows a "this browser holds data from a newer version of the app" banner, disables mutations, and offers export. Downgrading or dropping unknown fields is prohibited.
- That is correct behaviour, not a bug — but it means a rollback after a schema bump leaves affected users unable to record anything until you roll forward. **A `local_store_schema_version` bump is effectively a one-way door.** Treat any release that changes it as one you cannot cheaply reverse, and say so in the deploy reason.
- Records the user created under the newer release stay in their browser. Nothing on the server deletes or touches them.

---

## 6. Failure modes

### 6.1 Readiness never goes green

**Looks like:** `flyctl deploy` either hangs to `--wait-timeout` or reports failure; `/ready` returns 503 with `"status":"not_ready"`; `flyctl status` shows a machine with a failing check.

**Do this, in order:**

```bash
curl -sS https://digital-oil-sticker.fly.dev/ready       # read WHICH check failed — it is named
flyctl status --app digital-oil-sticker
flyctl logs --app digital-oil-sticker
flyctl checks list --app digital-oil-sticker
```

The named check tells you which branch to take. Map it with the table in §3.1. The most likely one on a first deploy is `release_identified` — go to §2's build-args warning before anything else, because that failure has a known cause and a known fix, and chasing the catalog checks first will waste the twenty minutes you do not have.

If the deploy is failing and the previous release is still serving, **you are not in an outage** — the old machines are still up. Stop, read, and fix forward rather than rolling back something that never took.

Note the liveness/readiness split and do not confuse them: `/health` checks *nothing* on purpose (`health_controller.ex:29-33`). A liveness probe that consults dependencies turns one bad artifact into a restart storm across every machine. So `/health` returning 200 while `/ready` returns 503 is the system working as designed, not a contradiction.

### 6.2 `/version` reports the wrong commit

**Looks like:** §3.2 prints `MISMATCH`, or `git_sha` is `unknown`.

| Reported | Means | Do |
| --- | --- | --- |
| `unknown` | The image carries no git SHA. Either you omitted `--build-arg GIT_SHA`, or the Dockerfile's compile-ordering problem (§2) bit. | Check your command first. If the flags were present, it is the Dockerfile — fix the `ARG`/`ENV` ordering and rebuild. Do not paper over it by relaxing the readiness check; `release_identified` exists precisely so a machine that cannot name itself is not trusted. |
| An older SHA | A cached or reused image shipped, or the proxy answered from a machine still on the old release. | Repeat the call several times (two machines are running, §0). If it is consistently old, redeploy with `--no-cache` and re-check. |
| A SHA that is not in `git log` | The build came from a dirty tree or a different checkout. | Stop. The image claims a commit it does not contain. Roll back (§5) and redeploy from a clean tree. |

A mismatch is never cosmetic. It means the artifact you are reasoning about is not the artifact that is serving, and every other conclusion you draw is unsound.

### 6.3 Machine restart loop

**Looks like:** `flyctl status` shows a machine cycling through `started` / `stopping` / `starting`, or a restart count climbing; `flyctl logs` shows the same boot sequence repeating.

```bash
flyctl status --app digital-oil-sticker
flyctl machine status <machine-id> --app digital-oil-sticker
flyctl logs --app digital-oil-sticker
```

Where to look first: the application's supervision tree fails closed at boot on a bad catalog. `application.ex:15-22` starts `CatalogRepo`, then `Catalog.Metadata` ("fails closed on missing/incompatible catalog"), then `Catalog.OilModel` ("read at boot so a catalog without it fails loudly instead of showing no intervals"). A crash in any of those is a supervisor crash, which is a process exit, which is a restart. So a restart loop most likely means the catalog in the image is unusable — which the build's own verification (§6.4) should have caught, and which is worth understanding rather than restarting past.

A liveness check cannot cause this loop by design (§6.1), so do not suspect `/health`.

If the loop is on the new release only and the old release was healthy, roll back (§5) and diagnose from the artifact rather than from production.

### 6.4 Catalog verification fails at build time

`app/scripts/verify_catalog.sh` runs **twice**, and which run failed tells you something:

- `app/Dockerfile:78`, in the builder stage, against the build context — before any Elixir compiles. A failure here means the artifact you committed is wrong.
- `app/Dockerfile:146`, in the **final image**, against the release that actually shipped, with `--expect-no-fixtures`. A failure here means the build context was sound but what came out the other end is not — a genuinely different and more alarming case.

**Looks like:** the build stops with one of these `FAIL:` messages on stderr.

| Message | Means |
| --- | --- |
| `<manifest> is absent — the catalog build did not run` | The manifest is missing. Run the catalog pipeline. |
| `<catalog> is absent — there is no catalog to serve` | The artifact is missing. Same. |
| `the manifest carries no payload_sha256 — it was not written by the catalog compiler` | The manifest is malformed, truncated, or hand-made. |
| `the manifest carries no size` | Same. |
| `catalog is N bytes, manifest says M — truncated or replaced` | Size mismatch. Most often a partial write or a line-ending accident. |
| `catalog sha256 X does not match manifest Y — this is not the artifact that was built` | Same size, different bytes. The artifact was edited, or the manifest is stale. |
| `catalog schema_version 'N' is outside the window this app supports (1)` | The artifact's schema is outside `@supported_schema_versions` in `catalog/metadata.ex`. The script's `supported_schemas` must track that list; if they drift, the image builds and then fails to boot. |
| `test fixture <name> reached the image beside the production catalog` | **Final-stage only.** A synthetic fixture rode into the image. `.dockerignore` is supposed to prevent this. Serving a fixture as real data is a correctness failure, not housekeeping. |

Each failure mode gets its own message on purpose — "catalog check failed" is not actionable at 3am. The check lives in a script rather than inline in the Dockerfile for the same reason: inlined, a `sed` backreference passing through the Dockerfile parser, the shell, and BuildKit arrived as a literal `0x01` byte, and the check failed on its own quoting rather than on the artifact. A verification step that can fail for reasons unrelated to what it verifies trains you to ignore it.

**This failing is the system working.** The catalog artifact is the product; a truncated, swapped, or stale one would ship and stay invisible until a user got a wrong answer. Do not disable the check to get a deploy out.

**Fix by rebuilding, not by editing:**

```bash
cd /c/Users/kyler/digitalOilSticker
node tools/catalog/bin/dos-catalog.mjs --help   # prints: discover | enumerate | fixture | compile
```

Then re-run §1.3 locally until it matches before you touch `flyctl` again. Hand-editing either file to make them agree defeats the entire mechanism and CI will catch it anyway (`ci.yml` rebuilds the fixture and diffs it, and re-verifies the production artifact against its manifest).

---

## 7. Not rehearsed

Everything in this section is a claim this runbook makes that **nobody has tested**. It is here so you know the difference between a procedure that has worked and a procedure that is merely written down.

**None of the rehearsals have been run.** Not one.

| Claim | Status | What would settle it |
| --- | --- | --- |
| The GitHub Actions deploy workflow works | **Never run.** No `FLY_API_TOKEN` exists (measured 2026-08-01). The workflow has never executed its deploy job once. | Provision the token, deploy a no-op commit, read the run. |
| The workflow's `flyctl` invocations find `app/fly.toml` | **Expected to fail.** Measured: `flyctl` run from the repository root cannot resolve the app. The workflow has no `working-directory`. | The first armed run. |
| `--build-arg GIT_SHA` actually reaches `Release.identifier/0` | **Contradicted by local measurement** (§2). Elixir did not re-read a compile-time `System.get_env/1` without a forced recompile, on Elixir 1.20.2; the image builds on 1.18 and was not measured. | One deploy, then `curl /version`. This is the highest-value single test in this document. |
| `/ready` and `/version` serve at all | **Never served.** Both return 404 on the live app right now. | The first deploy carrying `HealthController`. |
| The two-check `fly.toml` behaves as intended | **Never deployed.** Live config has one check. | The first deploy carrying it. |
| Readiness comes green within 150 seconds | **Unmeasured.** The 30 × 5 s budget is copied from `deploy.yml` and rests on nothing. | Time it on the first successful deploy and record the number. |
| `--wait-timeout 600` is the right timeout | **Unmeasured.** No build has been timed. | Same. |
| A rollback via `flyctl deploy --image` works | **Never performed.** Twelve forward deploys, zero rollbacks. | Deliberately roll back to v11 in a quiet window and roll forward again. |
| A deploy is a non-event for a user mid-session | **Unproven.** The conformance suite simulates a socket drop inside the page; no test deploys a release under a live session. | Open a session with a populated garage, deploy, record what the session did. |
| The 5 000 ms hydration deadline and 2 000 ms ack timeout are right | **Unmeasured against the deployed app.** Both are configured defaults, not observations. | Instrument a real session over a real network. |
| §9 latency budgets (LCP, TTI, reconnect p95, hydration p95) | **Provisional and unmeasured**, and marked so in `CONSTITUTION.md` §9. | The re-ratification work in `docs/quality/SECTION9_RERATIFICATION_PROPOSAL.md`. |
| Browser conformance against a deployed target | Suite exists and its self-tests run in CI. Whether the full three-engine sweep has ever completed against `digital-oil-sticker.fly.dev` is **not recorded here** — check `gh run list --workflow=conformance.yml`. | Read the run list. |
| Two machines vs `min_machines_running = 1` | **Unrecorded posture** (§0). Nobody decided this, so nobody knows what a deploy's blast radius is. | An owner decision, then a `fly.toml` that says it. |
| iOS Safari and Android Chrome behaviour | **Unproven.** `docs/quality/SUPPORT_MATRIX.md` records both as engine-proxy only, no physical-device run. | The manual device matrix in DOS-M09-008. |
| Storage eviction behaviour | **Unmeasured**, by explicit policy — vendor documentation is not measurement (ADR-0004 R1). | `conformance/observations/eviction.md`. |

### Decisions the owner must make, and what each costs

| Decision | Options and cost |
| --- | --- |
| Provision `FLY_API_TOKEN`? | Without it, every deploy is a workstation deploy: no gate, no ledger entry, no evidence artifact, and no record of *why*. With it, the workflow enforces preflight, readiness, the commit assertion, the smoke walk, the ledger entry, and a 365-day evidence artifact. Cost: one deploy-scoped credential to manage and rotate. |
| One machine or two? | Two costs roughly twice the machine line and lets a rolling deploy keep serving. One is cheaper and means a deploy takes the app out of rotation for a machine replacement. Either is defensible; the current state — two running while the config asks for one — is not, because nobody chose it. |
| Deploy on merge, or explicit trigger? | On merge is faster and drops every live socket without a human deciding to. Explicit trigger interrupts nobody by accident and adds a step. `deploy.yml` currently defaults to explicit and says why; this is unresolved and should be recorded either way. |
| The orphan volume in `iad` | Leaving it costs money and contradicts ADR-0004. Deleting it is destructive and irreversible. It is attached to nothing, so there is no urgency — but it should be settled deliberately, not during an incident. |

---

## Related documents

- `docs/architecture/ADR-0004-browser-first-client-and-hosting.md` — the ratified hosting decision, the hydration protocol, and the honest list of what the pivot lost.
- `docs/product/CONSTITUTION.md` — INV-23 (client-side storage is the only home for personal data), INV-24 (hydration protocol), INV-25 (honest storage-loss messaging), §9 measurable targets.
- `docs/quality/SUPPORT_MATRIX.md` — which browsers are supported and what that promises.
- `docs/quality/RELEASE_GATES.md` — the gate list this runbook is one input to.
- `conformance/README.md` — running the browser suite.
- `.github/workflows/deploy.yml` — the workflow this runbook's Path A describes.
