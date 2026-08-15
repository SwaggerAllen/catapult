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

## Initial vs target

Initial (Phase 1): application skeleton, Repo, config through the
substrate's config layer (ORC-4 — "via Vapor" as written here; see
`systems/substrate.md` for why the dependency did not land), infra
migrations for Oban. Target: EventStore migrations (with
engine), release tasks for seeds + migrations, DOKS manifests
adjacent (Phase 7).

## Depends on

substrate.
