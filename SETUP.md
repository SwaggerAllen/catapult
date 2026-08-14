# Catapult — reference instance setup

The remaining **human** steps (build-plan Phase 2), one-time and
attended. Everything code-shaped already lives in the repo:

- `Dockerfile` + `Catapult.Release.migrate` (the deploy artifacts;
  the migrate release task is the PRE_DEPLOY job)
- `pipeline.config.json` — tracker ids, the state mapping (read live
  from the team), actors (author = controlplane, the sanctioned
  solo-workspace exception), gates, preview, agents, and the live
  app's `deploy.endpoint`.
- The eight pipeline stubs under `.github/workflows/` (toolchain
  blocks read `.tool-versions`; live-suite runs
  `mix test --only live`, which passes empty until `:live` tests
  exist — correct)
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
  `pipeline.config.json`'s `deploy.endpoint`. Public URL:
  `https://catapult-ezten.ondigitalocean.app` — `/health` is the
  only served path (the design agent's finding: this hostname had
  no committed source of truth; now it does, here).
- **Public port is 8080, fixed by App Platform** — the prod listener
  defaults to it (`config/runtime.exs`; `HEALTH_PORT` overrides).
- Database: managed PG 16, component/cluster
  `db-pgsql-sfo2-33976`; both components' `DATABASE_URL` use the
  bindable ref `${db-pgsql-sfo2-33976.DATABASE_URL}`, unencrypted
  (encryption breaks substitution). `runtime.exs` strips the URL's
  `sslmode` query and configures TLS itself.
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
- Optional: repo variable `PIPELINE_KILL_SWITCH=true` halts dispatch.
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
