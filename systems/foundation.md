---
paths:
  - lib/catapult/application.ex
  - lib/catapult/boot.ex
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
  `DATABASE_URL`, `FOUNDATION_POOL_SIZE`, `FOUNDATION_HEALTH_PORT` —
  the three values that differ between the reference instance and a
  laptop, declared in foundation's `config/0` and loaded once at boot.
  Dev and test reach them through the static source
  (`systems/substrate.md`), which means `config/dev.exs` seeds a
  `DATABASE_URL` rather than setting Ecto's discrete
  `username`/`hostname` keys: one declaration, one shape for
  `Repo.init/2` to merge, and dev exercising the same cast the
  deployment does.

  **Two of those three were drawn as `POOL_SIZE` and `HEALTH_PORT`,
  and implementation renamed them** (ORC-4). The substrate's rule is
  that a name off the slug spine is legal only with `external: true`,
  and that the flag confers nothing — "an `external: true` on a name
  nobody else imposes is a lie a reviewer can see". Only `DATABASE_URL`
  is imposed: App Platform injects it under a name we do not choose.
  Marking the other two external to keep their spelling would have
  falsified that argument in the same commit that first armed the
  check, on its only three subjects. Renaming costs nothing
  operationally — neither is set on the reference instance, both carry
  the same defaults they had (`10`, `8080`), and `SETUP.md` §2 names
  the new spelling for the override. The rule the rename keeps:
  `external: true` marks names the world imposes, never names we chose
  and would rather not re-type.

  **And the test build reads its database URL through the static
  source too**, which is the only reading of the two bullets above
  that is self-consistent: the harness switch this list means to
  protect is `pool: Ecto.Adapters.SQL.Sandbox`, and it stays in
  `config/test.exs`. The connection parameters stay there as well —
  built from the same `PG*` variables CI provides — but in
  `DATABASE_URL` shape, because Ecto's URL parsing *replaces* the
  discrete keys rather than merging with them, so a build setting both
  would have one of them silently win. One shape in every environment
  is what makes `Repo.init/2` the same code everywhere.
- **`runtime.exs` stops reading the environment.** It is the file the
  substrate's whole config layer is an argument against: today it
  fetches three variables and hand-parses one of them, and it reports
  exactly one problem per boot because each way of failing there
  raises — `fetch_env!` on an unset `DATABASE_URL`, `to_integer` on a
  pool size someone typed wrong. The `sslmode` strip and the
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
- **The roster and the source selection live in `Catapult.Boot`, and
  every entry point goes through it** (ORC-4). Root glue in v5 §2.7's
  sense, and its own module rather than functions on
  `Catapult.Application` for a reason implementation found: the
  application is not the only entry point. `Catapult.Release.migrate/0`
  runs under `eval` with the app loaded but not started, and mix's ecto
  tasks call `Catapult.Repo.init/2` after `app.config` — both need
  configuration and neither boots a supervision tree. Hanging the load
  off `Catapult.Application` would put `Repo → Application → Foundation
  → Repo` in the module graph, and `mix xref graph --format cycles
  --fail-above 0` is a hard gate (conventions §2). The load being
  idempotent is what lets three entry points ask for it without
  arranging who goes first; load-once (`docs/non-goals.md`) is what
  makes that safe rather than lucky.
- **Boundary's strict external mode arms now, against one boundary,
  rather than later against all of them** (ORC-21). v5 §2.14 promotes
  the adapter conventions to compile grade — only `Store`
  subcomponents on Ecto, only the outbox wrapper on Oban's insert
  surface, only adapters on Req, no model-call library anywhere in
  plane code. Every one of those is a rule *about a sub-boundary*, and
  the tree has exactly one boundary today (`lib/catapult.ex`, `deps:
  []`), so none of them can be stated yet. What can be stated is the
  mode: `boundary: [default: [type: :strict]]` in the root `mix.exs`,
  which makes the coarse boundary declare the external applications it
  actually calls. That is a one-line diff and a short list right now,
  and it is N boundaries at once at any later moment — worse, every
  carve-out between now and then would land a boundary that has never
  been checked, so the retrofit grows with exactly the work it is
  supposed to constrain. Arming the mode is therefore not the same
  ticket as arming any of the four rules: the rules arrive with the
  boundaries they constrain, in those systems' tickets, and this
  decision is what makes each of them a `deps:` line instead of a
  migration.

  **What it does not cover, so the gap is not mistaken for coverage:**
  Boundary documents that calls to `:elixir`, `:boundary` and pure
  Erlang applications cannot be restrained, so `:httpc` reaching a
  model provider from plane code compiles clean under strict mode.
  Conventions §11 is a compile error for every Elixir client and an
  audit check for the Erlang ones (`systems/substrate.md`); the plane
  is where that residue matters most, because it is the tree §11 is
  written about.

  **Amended in build (ORC-21): the arming is
  `check: [apps: [...]]`, not `type: :strict`, and the reason is a
  Boundary defect rather than a preference.** Strict additionally
  requires naming implicit boundaries *inside* `:catapult_substrate`,
  and Boundary's cached view (`Boundary.Mix.View.refresh/2`) drops a
  **path dep's** boundaries on every incremental compile and rebuilds
  them only from loaded applications — which the cache-hit path never
  loads. Measured, not inferred: `mix compile --force` is clean and the
  very next `mix compile` reports all fifteen substrate calls as
  forbidden, so the second compile in any CI job fails on state rather
  than on code (`mix credo` compiles before `mix compile
  --warnings-as-errors` in `ci.yml`, so this is the ordinary path and
  not a corner). The app list — `:ecto`, `:ecto_sql`, `:oban`, `:plug`,
  `:plug_cowboy`, `:req` — is checked identically and stably, and it is
  exactly the four rules' applications plus the HTTP listener, so every
  paragraph above holds unchanged: the rules still arrive as `deps:`
  lines on the boundaries they constrain. What is lost is the one thing
  strict adds beyond the list, and it is named rather than absorbed: a
  *newly added* dependency is unchecked until it is named here, which
  is a line in the same diff that added it and a §2.8 decision either
  way. Revisit condition: Boundary loading a path dep's applications on
  the cache-hit path, at which point `type: :strict` is a one-line
  change and this list is deleted.

  **Amended (ORC-50): the accepted cost above is retired, and the list
  stops being the four rules' applications.** "A line in the same diff
  that added it" prices an omission that gets noticed, and nothing
  noticed it — the list has been short of six applications the plane's
  own build resolves (`:db_connection`, `:decimal`, `:jason`, `:mime`,
  `:plug_crypto`, `:postgrex`) since the day it was written, each of
  them silently exempt rather than partially checked. So the list
  becomes the whole of what a `:prod` build can reach and Boundary can
  restrain, and `Catapult.Audit.BoundaryApps` reports the gap
  (`systems/substrate.md` holds the check's subject, its three derived
  exclusions and its census). Two measurements decide the shape and
  both are cheap to re-run: naming all eleven costs **zero** forbidden
  references, because the plane calls none of them today — the
  expensive version of this ticket is the one the engine would have
  filed — and naming `:catapult_substrate` costs twelve and a red
  build, which is this entry's own defect reproduced through the list
  instead of through strict, so the path dep is excluded by derivation
  rather than by a name anyone writes.

  What the amendment does **not** change is the paragraph above it: the
  list is still a literal a reviewer reads in a diff, still not derived
  inside `mix.exs`. A `boundary/0` that computed itself would delete
  the one artifact review can act on and would fail open exactly where
  a derivation bug put it, with nothing to say so. The check is the
  half that has to be loud; the declaration is the half that has to be
  readable, and they are different halves on purpose. The revisit
  condition is unchanged and now retires two things at once: Boundary
  loading a path dep's applications on the cache-hit path makes
  `type: :strict` a one-line change, which deletes this list *and*
  renders the check inert on its own terms.
- **The root project's compile-connected cap is 0 and is armed as a
  gate line** (ORC-21). Measured here rather than assumed: `mix xref
  graph --format stats` reports 0 compile dependencies across the seven
  tracked files, and `--label compile-connected --fail-above 0` exits
  0. The number's home is `qualityGates`, not this repo's code, for the
  reason `systems/substrate.md` argues — a cap a ticket can edit is a
  cap the ticket that breaks it will edit. Recorded here because the
  value is a fact about *this* project's tree, and the day it stops
  being 0 the diff that raised it should have to say so.
- **The plane declares a licensing policy rather than staying inert**
  (ORC-51). Two declarations and no new mechanism: `licensing: [allow:
  ~w(AGPL-3.0-only Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]` in
  the root `mix.exs`, and `licensing/0` on `Catapult.Foundation`
  returning `[distribution: :service, license: "AGPL-3.0-only"]`.
  `arming/2` maps `{:service, :listed}` to `[]`, so the plane's
  dependency closure stays unchecked exactly as `LICENSING.md`'s table
  says it should — the engine's `commanded` and `eventstore` are
  unchecked either way, and correctly.

  Measured on this tree rather than reasoned, because "nothing
  changes in the closure" is the whole point and a claim worth
  checking: before, `licensing: inert — this project states no
  licensing policy, so nothing was checked`; after, `licensing:
  unchecked against 6 identifiers — no subject arms a dependency check
  (Catapult.Foundation :service "AGPL-3.0-only")`. The verdict acquires
  a subject and a reason somebody asserted, in place of a sentence
  about the absence of one.

  **The half that is worth a ticket is the other one.**
  `Catapult.Audit.License` never reaches `undeclared_problems/1` while
  a project is inert, so today the missing declaration is not reported
  either — the check and its own precondition are both dark. Measured:
  with the policy stated and `licensing/0` deleted again, the audit
  fails with *"Catapult.Foundation declares no licensing/0, so this
  project's policy cannot place it"*. Stating the policy is therefore
  what makes every plane component the engine adds state its class in
  the diff that adds it, instead of a retrofit sweep across seven
  systems later — the retrofit `LICENSING.md`'s declaration model is
  most exposed to, since a class nobody was asked for is a class
  somebody guesses.

  Both edits are one commit, and not because of an ordering hazard:
  the `mix.exs` line alone fails the audit on the undeclared component,
  and `licensing/0` alone changes nothing while the project is inert.
  It is one decision landing in two files, one of which (`mix.exs`) is
  unowned by construction (`systems/README.md`).

  **`:service`, not `:internal`.** The plane is reached over a network
  by people who are not its operator — the hosted tier is the product —
  which is the case `:service` exists to name and the reason
  `LICENSING.md` chose AGPL over plain GPL in the first place.
  `:internal` is the class whose entire meaning is that nothing
  triggers, and asserting it about the one program AGPL §13 was picked
  for would be a false declaration made in public, which is precisely
  the failure the declaration model trades a path rule for.
- **The plane's `allow:` list is Catapult's five plus its own
  identifier, and the five are not decoration** (ORC-51). The list has
  to contain `AGPL-3.0-only` or `bucket/2` reads the subject as
  unplaceable and reports it: the self-check and the bucket rule are
  one rule, which is what `systems/substrate.md` means by a project's
  list containing its own license even where nothing is checked.

  Why the other five, when no dependency in this tree will ever be
  measured against them, is the question the next pass will ask, so the
  measurement is here. The list is consulted the instant any subject in
  this project arms the check, and against the six identifiers above
  the plane's whole closure produces exactly **one** problem —
  `cowboy_telemetry`, which declares `["Apache 2.0"]` and is the
  near-miss `systems/substrate.md` already names. Against
  `["AGPL-3.0-only"]` alone it produces one per dependency. A list that
  is correct only for as long as it is unused is a policy that gets
  written under time pressure, inside the diff that first needed it and
  for reasons that diff supplies.

  **The seam, named rather than left to be found.**
  `AGPL-3.0-only` is on the list, so if this project's check ever armed
  for the *proprietary-`:service`* reason — AGPL §13 obliging an offer
  of source to our own users — an AGPL dependency would pass a check
  whose entire reason is that it must not. That is one-list-per-project
  behaving exactly as recorded (`docs/non-goals.md`), and the guard is
  the decision below rather than a second list keyed by class.
- **Every subject in the root project is `:service` under
  `AGPL-3.0-only`; a subject that is not belongs in another mix
  project** (ORC-51). This is what keeps the seam above closed — the
  plane states one policy because the plane is one class — and it is a
  one-line consequence rather than a decision each system re-takes:
  engine, delivery, generation, registry, dashboard, core_dsl and
  harness each declare `[distribution: :service, license:
  "AGPL-3.0-only"]` when they land, and the audit is what asks.

  The two things that would break it already have somewhere else to be.
  Anything **conveyed** — a published package, code generated into a
  customer's tree — is Apache-2.0 under `components/**` or `bundles/**`
  (`LICENSING.md`), and `components/*` are their own mix projects with
  their own lockfiles and their own `allow:` lists. A hosted-tier
  proprietary `:service` component under `LicenseRef-*` is its own mix
  project too, for the reason `docs/non-goals.md` records: dependencies
  are a mix project's fact, and a project needing two policies needs
  two dependency trees. So the day something in the plane's own tree
  wants a different class is the day it is not in the plane's own tree.
- **ORC-74 and v5 §3.5 are in view, and neither moves this** (ORC-51).
  §3.5 adoption forks a *component* into a customer's graph and tree,
  which is legitimate precisely because `components/**` is Apache-2.0;
  the plane is not a component and its own classification is untouched.
  What the adjacency changes is what the dark ladder costs, not what
  the answer is.

  ORC-74 would teach `Catapult.Audit.License` to resolve a **git**
  dependency's terms from its own `licensing/0`, since a git dep has no
  `hex_metadata.config`. Foundation's declaration is correct under both
  readings — the terms this code carries are `AGPL-3.0-only` whether
  the reader is this project's own audit or a consumer resolving a
  git dep — so the two tickets are order-independent and this one adds
  no second spelling for that resolver to disagree with. The coincidence
  is what makes the ordering free, though, not an argument that the two
  facts are the same fact: nobody git-deps the plane, so the plane's
  declaration is never itself a resolution subject, and a component
  that *is* one would want reading in ORC-74's terms rather than these.

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
