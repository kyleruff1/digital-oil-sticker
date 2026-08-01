# Secret rotation

DOS-M09-005. Covers the secrets this app actually has, what rotating each one
breaks, and how to prove the rotation took.

**This procedure has never been rehearsed.** No one has run it against
`digital-oil-sticker`, in production or anywhere else. Every step below is
derived from reading the code and the deployed configuration, not from having
watched it happen. That is why this document contains no durations: nothing has
been timed, and inventing a number would be worse than admitting the gap. The
section [What a rehearsal would establish](#what-a-rehearsal-would-establish)
lists exactly what is still unknown.

**Rotation is owner-gated.** It restarts the machines, which drops every live
LiveView socket, which interrupts anyone mid-form. That is a decision about
interrupting people, not a maintenance chore, so a human asks for it. This is
the same reasoning that made `deploy.yml` `workflow_dispatch`-only.

---

## 1. The inventory

Measured 2026-08-01 with `flyctl secrets list --app digital-oil-sticker`
(flyctl v0.4.77):

| Secret | Digest | Status |
| --- | --- | --- |
| `SECRET_KEY_BASE` | `d109e2a29364206c` | Deployed |

That is the whole list. One secret.

The list is short because of the architecture, not because something is missing.
There is no database credential because there is no user database — records live
in the browser's IndexedDB (INV-23). There is no third-party API key because
there is no third party (INV-4, INV-22). There is no object-store or backup
credential because there is no backup (INV-5). If a future change adds a secret,
it belongs in this table and needs its own section here before it ships.

### Environment variables that are not secrets

`config/runtime.exs` reads more than one variable from the environment. Only one
of them is confidential; the rest are configuration and are in version control
on purpose. Rotating something that is not a secret is wasted downtime, so the
distinction is worth stating.

| Variable | Where it comes from | Why it is not a secret |
| --- | --- | --- |
| `PHX_HOST` | `fly.toml [env]` — `digital-oil-sticker.fly.dev` | The public hostname. It is in DNS. |
| `PORT` | `fly.toml [env]` — `8080` | Matches `internal_port`. Public config. |
| `PHX_SERVER` | Set by the release start script | A boolean switch. |
| `CATALOG_DATABASE_PATH` | Deliberately unset | When unset, `runtime.exs` resolves the baked artifact via `Application.app_dir/2`, which survives release version bumps. |
| `CATALOG_POOL_SIZE` | Unset; defaults to `8` | A tuning number. |
| `DNS_CLUSTER_QUERY` | Unset | Unused; no clustering. |
| `GIT_SHA`, `BUILD_TIMESTAMP` | Docker build args, baked into `Release` | Build identity. `/version` publishes them intentionally. |

### The signing salts in version control are also not secrets

Anyone auditing this repo will find two values that look alarming:

- `lib/digital_oil_sticker_web/endpoint.ex` — `signing_salt: "sN71ocqW"`
- `config/config.exs` — `live_view: [signing_salt: "jkLsyI7y"]`

Both are committed. That is correct and does not need rotating. Phoenix derives
the actual signing key by running `secret_key_base` and the salt through a key
derivation function; the salt's job is domain separation, so that a token minted
for the session store cannot be replayed against the LiveView socket. The
secrecy lives entirely in `secret_key_base`. A committed salt with a secret key
base yields a secret derived key.

The practical consequence for this procedure: **rotating `SECRET_KEY_BASE`
rotates every derived key at once**, even though the salts never move. You do
not rotate the salts, and changing them would invalidate exactly the same
tokens while gaining nothing.

---

## 2. What `SECRET_KEY_BASE` signs in this app

Rotation's blast radius is precisely the set of things this key signs, so it is
worth being exact rather than reasoning from what the key signs in a typical
Phoenix app.

**1. The session cookie `_digital_oil_sticker_key`.** `Plug.Session` is
configured with `store: :cookie`, so the cookie is signed but not encrypted
(there is no `encryption_salt`). Its contents are readable by the client and
tamper-evident to the server.

What is in it: the CSRF token that `protect_from_forgery` puts there, and
nothing else. Verified — there is no `put_session/3` call anywhere in `lib/`.
The router's `:browser` pipeline plugs `:fetch_session`, but no LiveView and no
controller ever writes to it. That follows directly from INV-3: no accounts, so
there is no session state to keep.

**2. The LiveView session and static tokens.** Every rendered page carries
`phx-session` and `phx-static` attributes, signed with `secret_key_base` plus
the LiveView signing salt. Every route in this app sits inside
`live_session :garage`, so every page has them. The socket join presents the
token, and the server verifies it before the LiveView mounts.

**3. The CSRF token**, which is derived from the session and therefore moves
with it.

### What it does not protect

Not one byte of the user's data. The garage, the service history, the odometer
readings, and the reminder intent are in IndexedDB in the user's own browser
(INV-23). They are not signed with this key, not encrypted with this key, and
not reachable by anyone holding it. An attacker who stole `SECRET_KEY_BASE`
could forge a session cookie and a socket token — and would then be looking at
the same empty server-side state every other visitor gets, because the server
has no user records to serve. That is worth understanding before rotating: the
key protects request integrity, not confidentiality of data the server does not
have.

---

## 3. What rotation costs, stated honestly

**Every open session is invalidated and every client reconnects and re-hydrates.
No user data is lost.**

The second sentence is not reassurance-by-assertion; it follows from INV-24.1,
which requires that the server hold the user's records only in socket assigns
for the lifetime of that socket and never persist, cache, replicate, or forward
them. The server was never the system of record. Discarding every socket
discards a per-connection cache, not a record. The record is sitting in the
user's IndexedDB, which a server-side key rotation cannot reach even in
principle.

The recovery path is in the code, verified by reading
`assets/js/hooks/local_store.js`: `mounted()` calls `hydrate()`, and
`reconnected()` calls `hydrate()` as well, with a comment recording why — a
reconnect must not assume surviving server-side assigns. Both the reconnect path
and the fresh-page-load path re-read IndexedDB. That is INV-7's amended
requirement implemented, and it is what makes rotation survivable.

### Why this is unusually cheap here

| | Conventional app | This app |
| --- | --- | --- |
| Session holds | Identity, auth state, often in-flight work | A CSRF token |
| On invalidation the user | Is logged out, lands on a sign-in screen | Sees a page reload |
| In-flight work | May be lost with the server-side session or draft | Was never on the server |
| Records | On the server; a rotation gone wrong is a support incident | In the user's browser; untouched |
| Recovery requires | Re-authentication | Nothing; the hook re-hydrates |

In a conventional app, invalidating every session at once is a decision you make
carefully, because you are logging out every user and throwing away whatever
they had going. Here there is no login to be thrown back to and no server-side
draft to lose. The blast radius is small for an architectural reason, not by
luck — and it stays small only as long as INV-23 and INV-24.1 hold. If a future
change ever puts a personal row on the server, this section stops being true and
must be rewritten before that change ships.

### What is genuinely lost

Unsubmitted keystrokes. A form field someone has typed into but not yet
committed does not survive a full page load, exactly as it would not survive a
manual refresh. INV-24.2 defines committed as "the hook confirmed the client
write", so the line is clean: **anything the UI has shown as saved is in
IndexedDB and survives; anything not yet shown as saved may not.**

---

## 4. Rotating `SECRET_KEY_BASE`

Owner action. Read section 3 first, then decide the window.

If you are rotating because you suspect the key is exposed, rotate now and
accept the interruption — an exposed signing key is worse than an interrupted
form. If you are rotating for hygiene, pick a low-traffic window. **There is no
traffic measurement in place to tell you what that window is** (unmeasured; Fly
metrics or a period of request-log sampling would establish it).

### Step 1 — Record what is live now

```bash
flyctl secrets list --app digital-oil-sticker
curl -fsS https://digital-oil-sticker.fly.dev/version
flyctl status --app digital-oil-sticker
```

Write down the current digest, the `git_sha`, and the machine states. Rotation
restarts machines. If something is already unhealthy you want to know that
before you restart it, or you will spend the next hour blaming the rotation for
a pre-existing fault.

### Step 2 — Generate the new value locally

```bash
cd app && mix phx.gen.secret
```

Do not paste the result into chat, an issue, a commit, or anything that produces
a CI log. It goes from your terminal into `flyctl` and nowhere else.

You do not need to store it. There is exactly one consumer, and Fly holds it
after step 3. This is a meaningful difference from a key that encrypts data at
rest: **losing this value costs you another rotation, not any data**, because
nothing durable was ever encrypted with it.

### Step 3 — Set it

```bash
flyctl secrets set SECRET_KEY_BASE="<value>" --app digital-oil-sticker
```

This is the moment every socket drops. Per Fly's documented behaviour, setting a
secret updates the machine configuration and restarts the machines so they pick
it up — that restart is what invalidates the old key. *Vendor-documented, not
observed here.*

If you would rather pair the rotation with a deploy so users are interrupted
once instead of twice, `flyctl secrets set --stage` writes the secret without
restarting and it takes effect on the next `flyctl deploy`. Unrehearsed, and it
means a window in which the stored secret and the running secret differ — so if
you use it, deploy promptly and do not leave it staged.

### Step 4 — Watch the restart

```bash
flyctl status --app digital-oil-sticker
flyctl logs --app digital-oil-sticker
```

Both machines should return to `started` with checks passing.

**Unmeasured and important:** two machines run in `ord`
(`2862e40c6e0758`, `48ee567fd20ee8`, both `started`, measured 2026-08-01) while
`fly.toml` declares `min_machines_running = 1`. Whether Fly rolls them one at a
time or restarts both together under that declaration has not been observed
here. If it rolls them, there is no outage window; if it restarts both, there is
a short one. This is the single most useful thing a rehearsal would tell you,
and it is the reason no outage duration appears anywhere in this document.

### Step 5 — Verify

Four checks, each answering a question the others cannot.

| Question | Command | Pass condition |
| --- | --- | --- |
| Did Fly take the new value? | `flyctl secrets list --app digital-oil-sticker` | `DIGEST` differs from step 1. As of 2026-08-01 it is `d109e2a29364206c`; after rotation it must not be. |
| Can the machine serve? | `curl -fsS https://digital-oil-sticker.fly.dev/ready` | `"status":"ready"` and all six named checks `ok`. |
| Is it still the same build? | `curl -fsS https://digital-oil-sticker.fly.dev/version` | `git_sha` matches step 1. |
| Can a browser actually establish a signed socket? | Load `https://digital-oil-sticker.fly.dev/` in a fresh browser profile | Page goes live, garage hydrates. |

Why each one:

- **The digest is the only proof available.** `flyctl` never shows the value
  back to you — the output has a `DIGEST` column and no value column. A changed
  digest is how you know the set landed.
- **Readiness, not liveness.** `/health` checks nothing by design, so a 200 from
  it proves only that the BEAM is answering. `/ready` runs
  `catalog_present`, `catalog_payload_matches_boot`, `catalog_read_only`,
  `catalog_schema_supported`, `catalog_queryable`, and `release_identified`, and
  returns 503 if any fail.
- **The build must not move.** Rotation changes a secret, not the code. If
  `git_sha` changed, something else deployed and you are now debugging two
  changes at once.
- **The browser check is not redundant.** `/ready` consults nothing about token
  signing — that is deliberate, since a readiness probe should not depend on
  request-scoped state. So a ready machine and a machine that can mint a
  verifiable socket token are two different claims, and only a real page load
  tests the second one. A rotation that somehow produced an unusable key would
  pass every other check on this list.

Optionally, if you still have a browser tab open from before the rotation,
confirm it recovers on its own and comes back with its records intact.
Unrehearsed.

---

## 5. Rotation mid-session: someone is logging an oil change

The realistic worst case. A user is on `/service/new` filling in an oil change
when the machines restart. What happens, step by step:

**If they already saved the entry.** It is in their IndexedDB. INV-24.2 means
the UI did not show it as committed until the hook confirmed the client write,
so "it looked saved" and "it is saved" are the same statement. Rotation cannot
touch it. There is nothing to recover because nothing was at risk.

**If they are mid-form.** The socket drops. LiveView attempts to reconnect and
presents a `phx-session` token signed with the old key. The server rejects it,
and LiveView falls back to a full page load, which mints a fresh token under the
new key. `mounted()` fires, the hook re-hydrates from IndexedDB, and their
garage and history come back. The fields they had typed but not submitted are
gone — the same outcome as if they had hit refresh.

**What they must not see.** Two things, both of which would be defects in the
hydration path rather than in this procedure:

- An empty-garage claim. INV-24.3 forbids flashing "no vehicles yet" or any
  other empty-garage message before hydration resolves; a user with a full
  garage must never be told it is empty, not even for one frame. If a rehearsal
  ever shows that flash during the post-rotation reload, file it against
  hydration as an INV-24.3 violation. It is a release blocker.
- Any suggestion that data was lost or that they need to sign back in. There is
  no sign-in (INV-3) and nothing was lost. Copy implying otherwise violates
  INV-21 and INV-25.

**Mitigation.** There is none that removes the interruption. Rotation restarts
the machines; restarting the machines drops the sockets. You can only reduce the
odds of hitting someone by choosing the moment, and choosing the moment requires
traffic data this project does not collect. Say plainly that this is the
accepted cost rather than pretending a workaround exists.

---

## 6. `FLY_API_TOKEN` — does not exist yet

Measured 2026-08-01: `flyctl tokens list` returns nothing and `gh secret list`
is empty. All twelve releases were pushed from a workstation using the owner's
personal `flyctl` authentication.

Two consequences:

1. **There is no deploy token to rotate.** The credential that can currently
   deploy this app is the owner's own Fly login. Rotating *that* is an account
   action (`flyctl auth logout` and re-authenticate), not an app action, and it
   affects every Fly app the owner has — out of scope for this document.
2. **`deploy.yml` is inert.** Its `preflight` job checks for `FLY_API_TOKEN` and
   emits a warning if it is absent, precisely so that a missing credential
   announces itself instead of a workflow silently succeeding at nothing.

When the owner does provision it, the procedure is below. It is recorded now so
that the first person to need it is not improvising.

**Creating it:**

```bash
flyctl tokens create deploy --app digital-oil-sticker
gh secret set FLY_API_TOKEN --repo <owner>/<repo>
```

Paste the token from the terminal into the `gh secret set` prompt. Do not write
it to a file first — a token in a file is a token in your shell history, your
editor's recovery directory, and possibly your backups.

Give it an expiry if `flyctl` in use supports it, so the token has an end date
rather than living forever. *Unverified: whether `flyctl` v0.4.77 accepts an
`--expiry` flag on `tokens create deploy` was not tested. Run
`flyctl tokens create deploy --help` and confirm before relying on it.*

**Rotating it — order matters:**

1. Create the new token.
2. `gh secret set FLY_API_TOKEN` with the new value.
3. Run one deploy and let it succeed, proving the new token works.
4. Only then `flyctl tokens revoke <id>` on the old one.

Revoking first leaves you with no working deploy path and a workflow that
reports itself inert — which is a safe failure, but a needless one, and an
awkward position to be in if you were rotating because you needed to ship a fix.

Rotating this token drops no sockets and interrupts nobody. It is not
owner-gated for the reasons `SECRET_KEY_BASE` is; it is owner-gated only because
creating and revoking Fly credentials is an account action.

---

## 7. There is no rotation cadence, and setting one is an owner decision

Nothing schedules a rotation today. That is a gap, not a policy. The options and
what each costs:

| Option | Exposure window | Cost |
| --- | --- | --- |
| Rotate only on suspicion | Unbounded — a quiet exposure stays live indefinitely | Zero routine interruption |
| Fixed calendar cadence (quarterly, annually) | Bounded by the interval | One interruption per rotation, and with no traffic data you cannot pick a safe moment |
| Rotate alongside a scheduled deploy, using `--stage` | Bounded by deploy frequency | Effectively free — a deploy already drops every socket, so the rotation adds no new interruption. But it ties key lifetime to release cadence rather than to a security judgement, so a quiet period means a long-lived key |

The third option is cheap in a way specific to this app, because the thing that
makes rotation expensive elsewhere — logged-out users losing work — does not
apply here. That is worth weighing, but it is a judgement about how long a
signing key should live, and that judgement is the owner's.

Record the decision in this section once made, with the date. An undocumented
cadence is the same as no cadence.

---

## What a rehearsal would establish

The honest list of what is unknown, and what would resolve each item. Every one
of these is a question this document currently cannot answer.

| Unknown | What would measure it |
| --- | --- |
| Whether Fly rolls the two `ord` machines or restarts both at once | Run the rotation while watching `flyctl status` and `flyctl logs` |
| How long the socket outage actually lasts, if there is one | Time it during a rehearsal, from `secrets set` to a browser socket going live again |
| Whether an already-open tab recovers cleanly | Leave a tab open with a populated garage, rotate, watch it |
| Whether the post-rotation reload ever flashes an empty garage (INV-24.3) | Same rehearsal, watching the first frames after the reload |
| Whether `--stage` behaves as documented on this app | Rehearse a staged rotation paired with a deploy |

Until a rehearsal happens, treat every step in section 4 as a plan rather than a
known-good runbook, and rehearse it deliberately rather than discovering it
during an incident.

---

## Related open items (not rotation, but adjacent and owner-gated)

- **`min_machines_running = 1` while two machines run.** Measured 2026-08-01.
  `fly.toml` declares one; `ord` has two. This is an unrecorded posture, and it
  is the variable that determines whether a rotation has a hard outage window.
  The owner must settle it — either update `fly.toml` to match reality or scale
  to match the declaration.
- **The running machines predate the current `fly.toml`.** Both v12 machines
  report `1 total, 1 passing` checks, while `fly.toml` now declares two
  (`/ready` at 15s, `/health` at 30s). The second check has not reached the
  running machines. It will land on the next deploy. Noted here so that a
  verification step expecting two checks is not read as a rotation failure.
- **Orphan volume `vol_4y8d01doz7gmz21r`** (1 GB, `iad`, unattached), left over
  from before ADR-0004 — which forbids volumes outright, since the catalog is a
  build artifact and there is no server-side state to persist. Deleting it is
  destructive and is the owner's call. Not a secret and out of scope for this
  procedure, cross-referenced only because it sits in the same category of
  leftovers nobody has decided about.
