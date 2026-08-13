# Catapult — reference instance setup

One-time, attended (build-plan Phase 2). This is a runbook, not
backlog: tickets are exclusively work orchestration delivers, and
none of this can be a ticket because the pipeline doesn't run until
it's done. Values marked `TODO` get filled in as steps complete.

## Already in place (verify, don't create)

- **Linear team + project**: provisioned; the pipeline's states and
  labels exist in the team (shared with orchestration's test
  project). Record the ids below via `pipeline ids`.
- **Cloudflare Worker metronome + Linear webhook**: deployed from the
  orchestration repo; one Linear webhook on the team serves every
  project, routed by Linear project id. Our side, two acts in
  orchestration's court: add this repo to `worker/wrangler.toml`'s
  `PROJECTS` with our Linear project id as `trackerProject` (merging
  redeploys the Worker itself), and add this repo to the
  `DISPATCH_TOKEN` fine-grained token's repository list in GitHub
  settings — the separate act that's easy to forget; a beat that
  can't reach the repo just logs 404s. **The GitHub webhook is
  different — per repository, ours to create** (step 3): the repo
  emits the events, so each project registers its own.

## 1. Deploy the reference instance (App Platform)

Build the deploy artifacts (attended — pre-pipeline work):

- `Dockerfile` building the OTP release (stamp `GIT_SHA` via build
  arg so `/health` reports it).
- `.do/app.yaml`: web service from the Dockerfile; `PRE_DEPLOY` job
  running the migrator (`Catapult.Release.migrate/0` — release task
  TODO, part of this step) with the infra migrations path; managed
  Postgres 16 attached (`DATABASE_URL` injected); `PORT` set;
  deploy-on-push **off** — the pipeline's reconcile merge is the
  deploy trigger once live, and before that, deploys are manual.
- Managed Postgres: verify **daily backups + PITR** are enabled (DO
  managed databases include them — confirm retention). The event
  log is the plane's state of record; restore semantics are
  recorded in v5 §8 (after any restore: resync from tracker/host as
  signals before resuming authority — never revert the world to a
  rewound log).

Then: create the app, verify `GET /health` returns the SHA and
`foundation: true`.

- App id / deployments endpoint: `TODO` (goes in `deploy.endpoint`)

## 2. Pipeline config

`pipeline.config.json` at the repo root (schema: orchestration
`internal/config`). Values:

- `tracker.teamId` / `tracker.projectId`: `TODO` (from
  `pipeline ids`)
- `states`: map every protocol state to the team's state names
  (already provisioned — copy the mapping from the test project's
  config; the vocabulary now includes `Canceled`)
- `designOwnedPaths`: `["screens/**", "storybook/**", "systems/*.md",
  "docs/non-goals.md"]` — the sample config puts systems docs and the
  non-asks doc under design ownership (the sketch is a diff against
  them); screens/storybook stay empty of content until dashboard
  screens exist, but the paths are still the declaration
- `componentPaths`: `["lib/catapult_web/components/**"]` — feeds the
  class audit ("a new component was announced"); its absence is
  silent-but-not-broken — the audit prints that it skipped, so set it
  now
- `nonAsksPath`: `"docs/non-goals.md"` — agent runs are *handed* the
  non-asks document (orchestration `0c891eb`/`ef13e84`); ours already
  exists and stays where it is
- `qualityGates`: the CI gate list (format, credo --strict, compile
  --warnings-as-errors, catapult.audit, test) — must match
  `.github/workflows/ci.yml`
- `deploy`: `{ "provider": "digitalocean", "endpoint": TODO,
  "timeout": "30m" }`
- `staleClaimGrace`: `"20m"`
- `preview`: **mandatory, by decision** (optional-now-mandatory-later
  is the painful direction; Catapult may be the only backend-only
  project ever). Ship a placeholder export until dashboard screens
  exist: `preview/index.html` (a static "no storybook yet — dashboard
  screens arrive Phase 4" page), `buildCommand:
  "mkdir -p dist && cp preview/index.html dist/"`, `outputDir:
  "dist"`, `pagesProject`: `TODO` (a name only — the project itself
  is created by the **pipeline-pages-provision** workflow, step 3).
  The placeholder is replaced by the real storybook export when
  Phase 4's dashboard screens land.
- `actors`: author + controlplane Linear user ids: `TODO` — the two
  may share one id (the sanctioned solo-workspace exception: a
  personal API key IS the author; resolution is deterministic,
  controlplane wins)
- `agents`: stub workflow filenames for design, dev, reconcile,
  boundary, live-suite (from step 3)

## 3. Stub workflows, CI audit, and repo settings

- Copy the stubs from orchestration `examples/stubs/` (sweep —
  webhook-era with the hourly fallback beat — the four agents,
  live-suite, pages-provision, preview-cleanup). **There is no
  preview stub anymore**: previews publish from the agent runs
  themselves (orchestration `a70f2af`); the config's `preview` block
  still drives them. The agents are now **composite actions** the
  stubs call from the `.pipeline/` checkout — the stubs stay
  ten-line bindings. **Keep the stubs' toolchain block verbatim**:
  it ships Elixir because the dummy project is Elixir, and so are
  we — the one per-project part of a stub costs us nothing. The
  live-suite stub's command: `mix test --only live` (no `:live`
  tests exist yet — the suite passes empty, which is correct).
- **Extend `.github/workflows/ci.yml` with the pipeline audit step**
  (DESIGN §9's three checks — mutex, doc lint, class — one command).
  Use orchestration's `setup-pipeline` action to put the binary on
  PATH (builds once per pipeline commit, cached), then:
  `pipeline audit --changed-files /tmp/changed --added-files
  /tmp/added --ticket <key>` with both lists from `git diff
  --name-only` / `--diff-filter=A` against `origin/main...HEAD` (the
  recipe in `examples/stubs/README.md`; ticket key parses from the
  branch name). Without `--added-files` the class audit says it
  skipped rather than passing. This step lands **at hookup, not
  before** — it needs the `.pipeline/` checkout and
  `PIPELINE_REPO_TOKEN`, which don't exist until this runbook runs.
- Run **pipeline-pages-provision** once (creates the Pages project
  named in the config).
- Actions secrets: `LINEAR_API_KEY`, the model credentials —
  `CLAUDE_CODE_OAUTH_TOKEN` and/or `ANTHROPIC_API_KEY`, at least
  one (landed upstream, orchestration `d4fe42c`: subscription runs
  first, the API key retries on a failed pass; set one and that one
  is used; set neither and the model step fails loudly before any
  call) —
  `PIPELINE_REPO_TOKEN` (fine-grained, Contents read-only on the
  orchestration repo — lets workflows check out `.pipeline/`; same
  token value as the dummy project's), **`AGENT_GITHUB_TOKEN`** (the
  user identity the agents act as — *add this repo to that token's
  repository list*; without it the stubs fall back to `GITHUB_TOKEN`
  and degrade loudly: CI never triggers on agent pushes, previews
  don't build, deploys aren't recorded, and bot PRs wait for manual
  check approval), `CLOUDFLARE_API_TOKEN` (the Pages-scoped token) +
  `CLOUDFLARE_ACCOUNT_ID`, and `DIGITALOCEAN_TOKEN` (deploy
  detection against the App Platform API).
- **Create the GitHub webhook on this repo** (per-repo, unlike
  Linear's team-level one): Settings → Webhooks → Add webhook — the
  Worker URL, content type `application/json`, the `WEBHOOK_SECRET`
  value (from the orchestration repo's secrets), events: **Workflow
  runs** + **Deployment statuses**. Skipping it doesn't break
  anything; it makes the CI hop wait for the hourly cron in a way
  nothing reports.
- Repo setting: "Allow GitHub Actions to create and approve pull
  requests" — on. Optional but worth knowing: repo variable
  `PIPELINE_KILL_SWITCH=true` halts dispatch (DESIGN §13).
- Branch protection on `main`: require the `ci` checks + pull
  requests. Within the pipeline only reconciliation merges; the
  author's direct pushes are the deliberate admin bypass.

## 4. Agent-facing CLAUDE.md

**Nothing to copy — the design changed** (orchestration `274cb42`):
the protocol half is `prompts/repo-context.md` in the orchestration
repo, **injected into every agent run's prompt at claim time** from
the `.pipeline/` checkout, so protocol edits reach every project on
the next run with no copies to drift. This repo's `CLAUDE.md` holds
only what this repo alone can say — toolchain, verification
commands, layout, pointers into `docs/` — and is ours, hand-written
(done; see the repo root).

## 5. Verification

Create the first Linear ticket (trivial, e.g. a README touch) and
watch it flow design → dev → reconcile → deploy unattended. That
ticket is Phase 2's exit criterion and the backlog's first entry.
