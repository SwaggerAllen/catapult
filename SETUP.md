# Catapult — reference instance setup

One-time, attended (build-plan Phase 2). This is a runbook, not
backlog: tickets are exclusively work orchestration delivers, and
none of this can be a ticket because the pipeline doesn't run until
it's done. Values marked `TODO` get filled in as steps complete.

## Already in place (verify, don't create)

- **Linear team + project**: provisioned; the pipeline's states and
  labels exist in the team (shared with orchestration's test
  project). Record the ids below via `pipeline ids`.
- **Cloudflare Worker metronome**: wired on the Cloudflare side.
  Our side: set this repo's sweep workflow as the dispatch target in
  the worker's config, then run the action once to confirm.

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
- `preview`: **blocked on the preview-optional decision** — either
  orchestration makes the block optional (preferred; a backend-only
  project is a legitimate config) or this repo ships a placeholder
  static export. Resolve before this step.
- `milestoneNaming`: `"debt: / product: prefixes"`
- `actors`: author + controlplane Linear user ids: `TODO`
- `agents`: stub workflow filenames for design, dev, reconcile,
  boundary, live-suite (from step 3)

## 3. Stub workflows and repo settings

- Copy the stubs from orchestration `examples/stubs/` (sweep, the
  four agents, live-suite; skip preview until the decision above,
  skip record-deploy — that's the dummy project's). The live-suite
  stub's command: `mix test --only live` (no `:live` tests exist
  yet — the suite passes empty, which is correct).
- Actions secrets: `LINEAR_API_KEY`, `ANTHROPIC_API_KEY`.
- Repo setting: "Allow GitHub Actions to create and approve pull
  requests" — on.
- Branch protection on `main`: require the `ci` checks + pull
  requests. Within the pipeline only reconciliation merges; the
  author's direct pushes are the deliberate admin bypass.

## 4. Agent-facing CLAUDE.md

Copy the project CLAUDE.md from orchestration's template —
**maintained there, not here**: orchestration runs the agents, so
the agent-facing operating instructions are its protocol surface;
this repo only hosts the copy (plus a pointer to
`docs/conventions.md` and `systems/`). Re-copy on orchestration
upgrades.

## 5. Verification

Create the first Linear ticket (trivial, e.g. a README touch) and
watch it flow design → dev → reconcile → deploy unattended. That
ticket is Phase 2's exit criterion and the backlog's first entry.
