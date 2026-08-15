---
paths:
  - lib/catapult/application.ex
  - lib/catapult/foundation.ex
  - lib/catapult/health_endpoint.ex
  - lib/catapult/repo.ex
  - lib/catapult/release.ex
  - config/**
  - priv/repo/migrations_infra/**
  - test/catapult/*.exs
  - test/support/**
  - test/test_helper.exs
---

# foundation

Catapult's own application root: the composed supervisor, the single
Repo, release tasks, app configuration, and ownership of
infrastructure persistence (Oban, EventStore, and any library that
manages its own tables — reserved prefixes, migrations shipped here,
reached only through their APIs per v5 §2.4).

## Standing decisions

- **Root artifacts are generated glue** (v5 §2.7): the supervisor
  composes `children/0` from component declarations; the router (in
  dashboard's web layer) composes the same way. A ticket editing
  root files by hand means the composition mechanism is missing a
  feature.
- **One Repo.** Stores own schemas and queries, never connections
  (v5 §2.4). Infra tables live under reserved prefixes; the audit's
  single-owner check enumerates against this doc's registry.
- **Topology starts `single`** (v5 §2.5 split); the placement
  discipline is honored from the first process regardless.
- **The build's shape lives in `config/*.exs`; the instance's shape
  comes from the environment** (ORC-4). The line is what stops the
  next pass moving everything it finds in `config/` behind the config
  layer, so it is drawn explicitly. On the build side and staying
  there: the component roster (`:components`), which the composer
  reads at compile time and so could not come from the environment
  even if we wanted it to; the test-env switches `serve_health` and
  `start_persistence`, which select what this *build* starts, not how
  a deployment is tuned; and the test database's connection
  parameters, which configure the harness a sandboxed suite needs
  rather than any component's behaviour — routing those through the
  fake would be the fake standing between the suite and the database
  it is required to reach. On the instance side and moving:
  `DATABASE_URL`, `POOL_SIZE`, `HEALTH_PORT` — the three values that
  differ between the reference instance and a laptop, declared in
  foundation's `config/0` and loaded once at boot. Dev and test reach
  them through the static source (`systems/substrate.md`), which means
  `config/dev.exs` seeds a `DATABASE_URL` rather than setting Ecto's
  discrete `username`/`hostname` keys: one declaration, one shape for
  `Repo.init/2` to merge, and dev exercising the same cast the
  deployment does.
- **`runtime.exs` stops reading the environment.** It is the file the
  substrate's whole config layer is an argument against: today it
  fetches three variables and hand-parses one of them, and it reports
  exactly one problem per boot because each way of failing there
  raises — `fetch_env!` on an unset `DATABASE_URL`, `to_integer` on a
  `POOL_SIZE` someone typed wrong. The `sslmode` strip and the
  `verify_none` choice do not disappear: they become the declared cast
  on `DATABASE_URL`, which is where they get to fail by name and
  alongside everything else that is wrong. The file keeps only what
  `import Config` is for.
- **Library configuration is assembled, never re-declared.** Ecto and
  Oban read application env by their own contract and will keep doing
  it; the config layer feeds them rather than fighting them, so
  `Catapult.Repo.init/2` merges url and pool size in from the
  accessor and Oban's options are composed the same way when
  `oban_queues/0` starts contributing. The rejected shape is the
  obvious one — leave `DATABASE_URL` in `runtime.exs` because Ecto
  wants app env anyway — and it is rejected because it keeps a second
  reader of the environment alive, which is precisely the thing being
  removed. One reader, one report, and the libraries get their
  keyword lists.
- **If the plane ever needs a config source of its own, it belongs to
  foundation** — `lib/catapult/config/`, added to this doc's file map
  in the same change. Not needed today and deliberately not created
  speculatively: the plane runs substrate's shipped environment
  source, which is how that source stays exercised
  (`systems/substrate.md`).

## The live suite

The health endpoint is served from here, so the repo's first
`:live` test is foundation's: one smoke test of the reference
instance's `/health` at the milestone cadence (conventions §9).
Recorded as decisions rather than left to the implementation
because each has a cheaper alternative that is wrong (ORC-29).

- **The tag is the cadence mechanism; there is no live directory.**
  A `:live` test lives beside the system it exercises, inside that
  system's file map — this one in `test/catapult/`, which foundation
  already maps. A `test/live/**` tree would be a second axis that can
  disagree with the tag (a tagged test outside it, an untagged test
  inside it), and one directory holding every system's live tests
  would put a single file map in the path of every system's tickets
  — precisely the collision the maps exist to prevent.
- **The default suite excludes `:live`, in `test_helper.exs`.**
  Without the exclusion the first live test lands in per-ticket CI,
  against §9's one unconditional rule ("no network in per-ticket CI.
  Ever."), and every ticket's merge starts depending on the
  reference instance being up. `--only live` re-includes it: that is
  the entire mechanism, and it is why the boundary's command needs
  no project-specific flag.
- **The live suite runs in CI's environment, differing only in the
  filter.** `mix test` is aliased to create and migrate
  `catapult_test`, and the tree cannot compile before `mix deps.get`,
  so the live-suite job needs the same deps step and the same
  Postgres service `ci.yml` carries — even though the live test
  itself touches neither. Rejected: teaching the `test` alias to skip
  database setup when it sees `--only live` in argv. That alias is
  what makes `mix test` correct for every other run, and a version
  that drops migrations on the strength of a flag fails silently in
  the one direction that matters. `.github/workflows/**` is
  author-owned (systems/README.md), so the decision is recorded here
  and executed there.
- **The reference instance's public base URL moves into the tree, as
  `config/test.exs`'s `:live_base_url`.** It has to be dereferenced
  by code now, and prose cannot be dereferenced; SETUP.md §2 keeps
  every other fact and names this key in place of the value, so the
  hostname's home moves rather than multiplies (amending ORC-40 —
  see `docs/non-goals.md`). Test config rather than `config.exs`
  because prod code must not be able to read the app's own public
  URL: the first use anyone finds for such a value is building links
  out of it, and the instance is then effectively in the tree twice
  again. `CATAPULT_LIVE_BASE_URL` overrides it, so the suite can be
  aimed at another deployment without a commit.
- **The check asserts the endpoint's contract, not agreement with
  this checkout.** 200, `ok: true`, every configured component
  ready, and a SHA that is not the `"dev"` fallback — never
  `sha == GITHUB_SHA`. Autodeploy fires on the merge to main and the
  boundary run follows within minutes, so an equality assertion
  races the rollout and the failure it produces is a flake; §9's
  determinism rule binds this suite too, whose nondeterminism budget
  is the network and not our assertions. The `"dev"` comparison is
  the load-bearing half anyway: it separates a deployment that came
  through the real build path from an image serving an unstamped
  SHA.
- **One request, a bounded timeout, no polling.** Deploy detection
  already exists and is the plane's job; a live check that waits out
  a rollout is a second, slower deploy detector whose long timeout is
  exactly where a real outage hides.
- **HTTP client: Req — a new direct dependency**, named here rather
  than ported in (conventions §1 blesses it but `deps` does not yet
  carry it). `only: :test` while the live suite is its only
  consumer; the constraint widens the day the first external adapter
  (Tracker, Host, Deploy) lands in Phase 3. Rejected: `:httpc`, to
  avoid the dependency — it would make the one place we speak HTTP
  the one place not speaking it the blessed way, weeks before the
  ports arrive.

A red here is a statement about the reference instance — down,
unhealthy, or serving an unstamped build — not about whatever merged
last; §9 already routes it to a milestone blocker.

## Initial vs target

Initial (Phase 1): application skeleton, Repo, config through the
substrate's config layer (ORC-4 — "via Vapor" as written here; see
`systems/substrate.md` for why the dependency did not land), infra
migrations for Oban. Target: EventStore migrations (with
engine), release tasks for seeds + migrations, DOKS manifests
adjacent (Phase 7).

## Depends on

substrate.
