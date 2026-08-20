# Catapult — reference instance setup

The remaining **human** steps (build-plan Phase 2), one-time and
attended. Everything code-shaped already lives in the repo:

- `Dockerfile` + `Catapult.Release.migrate` (the deploy artifacts;
  the migrate release task is the PRE_DEPLOY job)
- `pipeline.config.json` — tracker ids, the state mapping (read live
  from the team), actors (author = controlplane, the sanctioned
  solo-workspace exception), gates, preview, agents, and the live
  app's `deploy.endpoint`.
- The ten pipeline stubs under `.github/workflows/` (toolchain blocks
  read `.tool-versions`; live-suite runs `mix test --only live`, which
  the foundation's `/health` smoke test now answers — ORC-29). **The
  five that run this project's own commands — the four agents and the
  live suite — carry `ci.yml`'s `env` and `services` blocks and a deps
  step for both mix projects**, because an agent runs the config's
  `qualityGates` and the live suite runs the test command: the rule is
  that a stub carries the project's *environment*, not just its
  toolchain (orchestration `069e7b2`). Three runs here were spent
  bootstrapping that by hand before the rule existed. The other five
  run no project commands and deliberately have none of it.
- Two of the ten are **run by you, from a phone**, and neither is on a
  schedule:
  - **pipeline-preflight** — exercises every credential-bearing call
    the pipeline makes, reads only. Run it after changing a
    `permissions:` block, after rotating a token, and at hookup. A
    green run means "the reads are fine", not "the permissions are
    fine", and it names the write scopes it did not exercise.
  - **pipeline-order** — "what goes into `Designing` next, and what
    can run beside it", from the ticket graph, rendered to the run
    summary rather than buried in a step log. Derived every time and
    never stored: the mutex labels that decide what parallelises do
    not exist until each design pass writes them, so a saved ordering
    is wrong by construction rather than by neglect.
- `preview/index.html` — the placeholder export (preview is
  mandatory by decision; the real storybook replaces it in Phase 4)
- `ci.yml`'s pipeline-audit step, **self-arming**: it skips with a
  notice until `PIPELINE_REPO_TOKEN` exists and the branch carries a
  ticket key, then runs for real with no further change

Do the steps in order; values you create early are consumed late.

## 1. Orchestration's court (two acts)

- **Merge the `PROJECTS` registration** — the wrangler.toml edit is
  already committed on orchestration's
  `claude/catapult-orchestration-siege-union-vnrgdh` branch
  (`476df42`: this repo, sweep workflow, main ref, our Linear
  project id). Merging it to main redeploys the Worker on its own
  (worker-deploy fires on `worker/` changes).
- Add `SwaggerAllen/catapult` to the `DISPATCH_TOKEN` fine-grained
  token's repository list in GitHub settings — the separate act
  that's easy to forget; a beat that can't reach the repo just logs
  404s hourly.

## 2. The reference instance (App Platform) — LIVE; facts recorded

**Done, through DO's dashboard** — `/health` answers with
`foundation: true` and main's real SHA. **The live app is the
authority on its own configuration**: there is deliberately no
committed app-spec file (one existed, was never read by anything,
and drifted from reality five times in one afternoon — the
no-hand-maintained-inventories rule applies to us too). Export the
current spec from the dashboard if it's ever needed; that export is
generated, therefore trustworthy.

The facts a future session needs, recorded as facts:

- App `catapult`, region `sfo`; app id is in
  `pipeline.config.json`'s `deploy.endpoint`. Public URL: the
  `:live_base_url` key in `config/test.exs` — `/health` is the only
  served path. The hostname's home moved there when the `:live`
  suite acquired a code consumer for it (ORC-29): prose cannot be
  dereferenced, and a value the boundary suite reads once a
  milestone goes red and names itself when it drifts, which is the
  property this section could never have. Still one home, not two
  (`docs/non-goals.md` records the amendment to ORC-40's rule).
- **Public port is 8080, fixed by App Platform** — the prod listener
  defaults to it (foundation's `config/0` declaration;
  `FOUNDATION_HEALTH_PORT` overrides, and was `HEALTH_PORT` before
  ORC-4 put env var names on the slug spine — it is not set on the
  instance, so the rename changed nothing there).
- Database: managed PG 16, component/cluster
  `db-pgsql-sfo2-33976`; both components' `DATABASE_URL` use the
  bindable ref `${db-pgsql-sfo2-33976.DATABASE_URL}`, unencrypted
  (encryption breaks substitution). The declared cast on
  `DATABASE_URL` strips the URL's `sslmode` query and configures TLS
  itself — `runtime.exs` did this until ORC-4, and no longer reads the
  environment at all. `DATABASE_URL` keeps its name because App
  Platform injects it: it is the one declaration flagged
  `external: true`.
- **The cluster allows 22 connections, and that is a budget four
  consumers share**: `Catapult.Repo` (`FOUNDATION_POOL_SIZE`), the
  event store's own Postgrex pool (`ENGINE_EVENT_STORE_POOL_SIZE`),
  and one connection each for Oban's and the event store's
  notification listeners. Two full instances are live at once during
  a rolling deploy, so the ceiling is a *cutover* number:

      peak = 2 × (both pools + 2)

  The PRE_DEPLOY migrator's own two land before the new instance
  starts, overlapping only the instance being replaced, so they are
  never the peak. Keep the peak under **19**, leaving the cluster's
  maintenance reserve alone — the Overview graph is the authority on
  both the limit and live usage, and beats this arithmetic if they
  disagree.
- **Set on the instance: `FOUNDATION_POOL_SIZE=4`,
  `ENGINE_EVENT_STORE_POOL_SIZE=2`** — peak 16. Deliberately
  asymmetric: the Repo serves the projector's writes, Oban's workers
  as queues land, the health check and the scheduler's readiness
  sweep, while the event store's pool serves appends and subscription
  reads that are low-concurrency in a plane this size. An even 3/3 is
  the same peak with the headroom in the quieter place. **4/4 is 20
  and 5/5 is 24** — the second is over the raw limit, and the first
  leaves nothing for a reserve.
- **Both default to `2` in code**, so a deploy is correct with neither
  variable set. That matters more than it looks: a first attempt sized
  them from the environment alone and left the code defaults at 10,
  which meant merging the fix re-broke the deploy on its own. The only
  deployment this code has is this one. Raising the plan raises the
  ceiling, which is why the ceiling lives here and not in a comment.
- **Autodeploy is ON and must stay on** — reconcile's merge to main
  is the deploy trigger; the migrate job runs PRE_DEPLOY.
- The `DIGITALOCEAN_TOKEN` repo secret wants **read-only App
  scope** — deploy detection is a single GET.

Remaining here: verify **daily backups + PITR** on the cluster
(restore semantics: v5 §8 — after any restore the plane resyncs
from tracker/host as signals before resuming authority).

## 3. Secrets, webhook, repo settings (GitHub UI)

- Actions secrets on this repo:
  - `LINEAR_API_KEY`
  - Model credentials: `CLAUDE_CODE_OAUTH_TOKEN` (from
    `claude setup-token`, tried first) and/or `ANTHROPIC_API_KEY`
    (the failover) — at least one
  - `PIPELINE_REPO_TOKEN` — same token value as the dummy project's
    (Contents read-only on the orchestration repo)
  - `AGENT_GITHUB_TOKEN` — **add this repo to that token's
    repository list**; without it agents fall back to `GITHUB_TOKEN`
    and degrade loudly (CI never triggers on agent pushes, previews
    don't build, deploys aren't recorded, bot PRs wait for manual
    check approval)
  - `CLOUDFLARE_API_TOKEN` (Pages-scoped) + `CLOUDFLARE_ACCOUNT_ID`
  - `DIGITALOCEAN_TOKEN` (deploy detection against the App Platform
    API)
- **GitHub webhook on this repo** (per-repo, unlike Linear's
  team-level one): Settings → Webhooks → Add webhook — the Worker
  URL, content type `application/json`, the `WEBHOOK_SECRET` value
  (from the orchestration repo's secrets), events: **Workflow runs**
  + **Deployment statuses**. Skipping it breaks nothing visibly; it
  makes every CI hop wait for the hourly cron.
- Settings → Actions → General → ✅ **Allow GitHub Actions to create
  and approve pull requests**.
- Branch protection on `main`: require the `ci` checks + pull
  requests. Only reconciliation merges within the pipeline; your
  direct pushes are the deliberate admin bypass.
- Repo variable `PIPELINE_KILL_SWITCH=true` **parks** the project. It
  halts dispatch inside the binary *and* skips the sweep job itself
  (orchestration `cd41b83`), which is what makes parking free: Actions
  bills each job rounded up to the minute, so an idle project on the
  hourly beat otherwise spends around 730 minutes a month producing
  nothing. Both guards stay, deliberately — a hand-dispatched run with
  the flag set still refuses inside the binary, so the two agree
  instead of one covering for the other. Clear it before expecting
  work: a parked project looks exactly like a broken pipeline.
- Then run **pipeline-pages-provision** once (Actions → Run
  workflow) — creates the `catapult-storybook` Pages project named
  in the config. Needs the Cloudflare secrets above.

## 4. Verification (Phase 2's exit)

Move **ORC-2** (the README-touch verification ticket) into
**Designing** — that is the starting gun. `Todo` means committed,
not started (who-has-the-ball: nobody), and the sweep deliberately
never pulls it forward; the design agent dispatches on Designing
*entry*, so starting work is always the author's act. From there
watch it flow design → dev → reconcile → deploy unattended. Its
`Done` is the exit criterion; from there, Phase 3 is worked by the
pipeline. The ci audit step arms itself on the first ticket-keyed
PR now that `PIPELINE_REPO_TOKEN` exists — confirm its step stops
saying "skipped".

## 5. The live suite's job environment — author-owned, one edit

ORC-29 landed the repo's first `:live` test, so
`mix test --only live` now matches something. The job that runs it
still needs the rest of `ci.yml`'s environment before it can get
that far:

- a `mix deps.get` step — the tree cannot compile without it, and
  `mix test` compiles before it filters;
- the Postgres service and `PGHOST`/`PGUSER`/`PGPASSWORD`, because
  the `test` alias creates and migrates `catapult_test` on every
  run, live filter or not.

Copy both from `ci.yml` into `pipeline-live-suite.yml`'s `live` job,
after the `setup-beam` step. Agents cannot make this edit — a push
token without `workflow` scope has GitHub reject the entire push, so
`.github/workflows/**` is author-owned by construction
(`systems/README.md`).

Teaching the `test` alias to skip database setup when it sees
`--only live` in argv is the tempting alternative and is a recorded
non-goal (`docs/non-goals.md`): that alias is what makes `mix test`
correct for every other run in the repo, and a version that drops
migrations on the strength of a flag fails silently in the one
direction that matters — a suite passing against a stale schema.
