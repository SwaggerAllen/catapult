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
  orchestration repo; one webhook on the team serves every project,
  routed by Linear project id. Our side, two acts in orchestration's
  court: add this repo to `worker/wrangler.toml`'s `PROJECTS` with our
  Linear project id as `trackerProject` (merging redeploys the Worker
  itself), and add this repo to the `DISPATCH_TOKEN` fine-grained
  token's repository list in GitHub settings — the separate act that's
  easy to forget; a beat that can't reach the repo just logs 404s.

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
  config)
- `designOwnedPaths`: `["screens/**", "storybook/**"]` (empty of
  content until dashboard screens exist — the paths are still the
  declaration)
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

## 3. Stub workflows and repo settings

- Copy the stubs from orchestration `examples/stubs/` (sweep — now
  webhook-era with the hourly fallback beat, the four agents,
  live-suite, preview, pages-provision, preview-cleanup; skip
  record-deploy — that's the dummy project's). The live-suite stub's
  command: `mix test --only live` (no `:live` tests exist yet — the
  suite passes empty, which is correct).
- Run **pipeline-pages-provision** once (creates the Pages project
  named in the config).
- Actions secrets: `LINEAR_API_KEY`, `ANTHROPIC_API_KEY`,
  `PIPELINE_REPO_TOKEN` (fine-grained, Contents read-only on the
  orchestration repo — lets workflows check out `.pipeline/`; same
  token value as the dummy project's), `CLOUDFLARE_API_TOKEN` (the
  Pages-scoped token) + `CLOUDFLARE_ACCOUNT_ID`, and
  `DIGITALOCEAN_TOKEN` (deploy detection against the App Platform
  API).
- Repo setting: "Allow GitHub Actions to create and approve pull
  requests" — on.
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
