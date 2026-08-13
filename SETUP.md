# Catapult — reference instance setup

The remaining **human** steps (build-plan Phase 2), one-time and
attended. Everything code-shaped already lives in the repo:

- `Dockerfile` + `.do/app.yaml` + `Catapult.Release.migrate` (the
  deploy artifacts; the migrate release task is the PRE_DEPLOY job)
- `pipeline.config.json` — tracker ids, the state mapping (read live
  from the team), actors (author = controlplane, the sanctioned
  solo-workspace exception), gates, preview, agents. **One TODO
  remains**: `deploy.endpoint`, filled in step 2.
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

## 2. Deploy the reference instance (App Platform)

1. Create (or pick) the **managed Postgres 16 cluster** and put its
   name in `.do/app.yaml`'s `cluster_name` TODO. A dev database would
   boot but has no PITR/backups, which this runbook requires.
2. `doctl apps create --spec .do/app.yaml` (or paste the spec into
   the dashboard).
3. Verify `GET /health` returns `foundation: true` and a **real git
   SHA**. If it says `"dev"`, the build context carried no `.git`
   and no `GIT_SHA` build arg — set a `GIT_SHA` build-time env on
   the app, or adjust; deploy detection is blind until the SHA is
   real.
4. Verify **daily backups + PITR** are enabled on the cluster
   (restore semantics: v5 §8 — after any restore, the plane resyncs
   from tracker/host as signals before resuming authority).
5. Fill `deploy.endpoint` in `pipeline.config.json`:
   `https://api.digitalocean.com/v2/apps/<app-id>/deployments`.

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

Promote **ORC-2** (the README-touch verification ticket) from
Backlog to Todo and watch it flow design → dev → reconcile → deploy
unattended. Its `Done` is the exit criterion; from there, Phase 3
is worked by the pipeline. The ci audit step arms itself on the
first ticket-keyed PR now that `PIPELINE_REPO_TOKEN` exists —
confirm its step stops saying "skipped".
