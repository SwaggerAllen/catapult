---
paths:
  - lib/catapult/application.ex
  - lib/catapult/boot.ex
  - lib/catapult/foundation.ex
  - lib/catapult/foundation/**
  - lib/catapult/health_endpoint.ex
  - lib/catapult/repo.ex
  - lib/catapult/release.ex
  - config/**
  - priv/repo/migrations_infra/**
  - test/catapult/*.exs
  - test/catapult/foundation/**
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
- **TLS verification to the managed database is `verify_none`,
  deliberately, and this bullet — not the cast's docstring — is now
  its record** (ORC-83). `cast_database_url/1` strips the platform's
  injected `sslmode=require` (Ecto's URL parser rejects the query
  param as an option) and configures `ssl: [verify: :verify_none]`
  rather than `verify_peer` against a pinned CA. The standing decision
  is provider-neutral, because a systems doc is the wrong altitude for
  any one provider's topology to be the reasoning: **`verify_none`
  holds only where the operator controls the network path end to end;
  anywhere else, pin a CA and use `verify_peer`.** Which operator,
  which network, and why that control holds for this deployment today
  are `SETUP.md` §2's facts, not this doc's to restate — the gap
  `verify_none` accepts is real regardless (a compromised or
  misconfigured resolver on the path is exactly what `verify_peer`
  would catch and `verify_none` does not), and end-to-end operator
  control is what makes that gap survivable rather than open. Backlog,
  not gating: nothing in `docs/build-plan.md`, the engine milestone
  (Phase 3) included, depends on verified TLS to the database.

  **The docstring's own phrase overclaims and this corrects it.** It
  says pinning "is recorded follow-up work (the maintenance lane)",
  and the maintenance lane (`docs/v5-design-decisions.md` §7.10) is a
  plane-side watcher over hex advisories, `mix hex.outdated`, and
  GitHub security advisories — it has no way to see a `verify_none`
  literal in application code, so nothing was going to re-surface this
  on its own. ORC-83 exists because a tech-debt scan caught it as a
  self-reported deferral with no tracked record, which is precisely
  what would have kept happening: the docstring is prose a reader has
  to already be looking at, this doc is what the next pass touching
  `cast_database_url/1` reads on the way in. Revisit condition: the
  moment `DATABASE_URL` (or a successor) resolves over a path the
  operator does not control end to end (`SETUP.md` §2 is where that
  stops being true, if it ever does), at which point the cast pins a
  CA and switches to `verify_peer`, and this bullet is what that
  ticket argues with.
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

  **The list is written, never derived** (ORC-50). Computing the
  closure inside `boundary/0` at project-config time is the tempting
  one-line version — nothing left to forget — and it fails on three
  counts, in increasing weight. It runs on every mix invocation
  including `deps.get`, before the compiled `.app` files the closure
  reads exist. It is plane-local, so a generated project — whose
  `mix.exs` comes from `bundles/platform-elixir` and whose list drifts
  the same way — inherits nothing. And it deletes the artifact review
  acts on: the list is the one place a human reads which applications
  are constrained, and a derivation bug would narrow it silently and
  in the permissive direction, which is the failure this ticket was
  filed about wearing the fix's clothes. The check is the loud half;
  the declaration is the readable half.

  **What it does not cover, so the gap is not mistaken for coverage:**
  Boundary documents that calls to `:elixir`, `:boundary` and pure
  Erlang applications cannot be restrained, so `:httpc` reaching a
  model provider from plane code compiles clean under strict mode.
  Conventions §11 is a compile error for every Elixir client *the app
  list names*, and for the Erlang ones it is the plane-owned transport
  ban the bullet below decides — new work as of ORC-52, not a gate this
  paragraph may describe in the present tense before it exists. The
  plane is where that residue matters most, because it is the tree §11
  is written about.

  **Corrected (ORC-52), because this paragraph claimed a gate that was
  never built.** It used to end "and an audit check for the Erlang ones
  (`systems/substrate.md`)". No such check exists: the audit's platform
  set is `WallClock`, `ProcessName`, `SecretInLog`, and nothing in
  substrate mentions `:httpc` or a model-call rule. A paragraph headed
  "so the gap is not mistaken for coverage" that itself manufactured
  the coverage is the whole of the ticket. The italics are the second
  half of the same correction and are not new work: `check: [apps:
  [...]]` checks the applications it names, so a newly added Elixir
  HTTP client is unchecked until it is named — which the amendment
  below already records as a §2.8 decision in the diff that adds it,
  i.e. review rather than a gate. Stating it once in the sentence that
  makes the claim is cheaper than leaving the qualifier two paragraphs
  away from the overclaim it qualifies. The claim has three homes and
  all three change together: this paragraph, `systems/substrate.md`'s
  enforcement roster, and `lib/catapult.ex`'s moduledoc — which is an
  unowned path (`systems/README.md`) and so belongs to the change that
  corrects the other two rather than to a system.

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
- **The Erlang residue is a plane-owned `policies/0` check that bans
  the transport, and it arms now while it is green** (ORC-52). Three
  decisions — what, where, when — behind the refusal that makes them
  possible, which comes first.

  **The check the old sentence promised cannot be built, so it is not
  what gets built.** "An audit check for the Erlang ones" reads as a
  check that finds a *model call*, and at AST grade the call is
  `:httpc.request(:post, {url, headers, type, body}, [], [])` — whether
  `url` reaches a model provider is data, decided at runtime and
  normally read from configuration. Recognising a provider hostname in
  a literal would catch a spelling nobody writes and report clean on
  every real instance of the thing it is named after: a check that
  passed without checking anything, which is the class ORC-37 was filed
  about and the class this ticket is filed about. Following `url` back
  to its binding is the dataflow inference this repo has refused twice
  already, in the secret-taint entry and the computed-config-key entry
  (`docs/non-goals.md`), each time for the same reason — a shallow
  analysis reported as a guarantee.

  **The decidable rule is one level out: no plane module calls a pure
  Erlang HTTP client.** The module in `:httpc.request/4` is a literal
  atom in the source, so the ban is exact at the grade the audit
  already runs at, needs no inference, and has the same shape as
  `Catapult.Audit.Checks.WallClock` — a remote call on a literal module
  atom, plus the `apply(:httpc, :request, _)` spelling, which is
  literal atoms too. A computed module is out of reach and is not
  chased, for the reason above. The ban is deliberately *broader* than
  §11: it catches every unbounded egress by that route rather than only
  the model-shaped one, which is v5 §2.2's every-HTTP-usage-inside-a-
  registered-adapter rule arriving for the applications the compiler
  cannot see. The banned set is named *modules*, and the asymmetry with
  `mix.exs` is worth spelling rather than glossing: a call site names a
  module, so this is a module list where the compiler's side is an
  application list — `:httpc` and `:inets` (the OTP client and the
  application whose `start/0` arms it), `:hackney`, `:gun`, `:ibrowse`.
  Beyond the grade they are the same list split by what the compiler
  can restrain: both author-visible, both extended by reviewed diff,
  neither inferred. The entry's required `policy:` string is where the
  rule is stated in prose, so the report cites the rule rather than the
  module. The escape rides `Catapult.Audit.Source` like every other
  check at this grade (`# catapult:allow erlang_http`) and has no
  sanctioned use in this tree today — a tag covering no violation is
  itself reported, so an unused one prunes itself.

  **The transport layer stays off the list** — `:gen_tcp`, `:ssl`,
  `:socket` and friends. The obvious objection to banning named HTTP
  clients is that a determined module can open a socket and write the
  request bytes itself; the objection is correct and does not change
  the answer. Those applications are what Postgres, the clustering
  transport and every other legitimate connection ride on, so banning
  them means an escape tag at every real call site, and a ban escaped
  everywhere is a ban nobody reads. The trade is asymmetric in the
  direction that decides it: a plane module reaching a provider
  through `:httpc` is a mistake somebody makes, while one hand-rolling
  HTTP over `:gen_tcp` is a deliberate evasion, and no check in this
  repo is built to stop an author who is trying. The named list grows
  by reviewed diff when a real client is missing from it; that is a
  different move from descending a layer.

  **It is plane code**, at `Catapult.Foundation.Policies.ErlangHttp`,
  registered through foundation's `policies/0` against the
  working-directory-rooted scope every registered check takes. It may
  not be a substrate platform check and may not live there under
  another name: that set is inherited by every project that runs the
  audit at all, and generated projects *do* make model calls — through
  the LLM adapter, which is conventions §11's other bullet — so a
  shipped egress ban would fail the audit of a project doing what the
  platform told it to. Being AGPL plane code is exactly what makes
  holding Catapult's own policy correct here, the same way
  `catapult.audit.all` is the sanctioned home for knowing this repo's
  layout (`systems/substrate.md`).

  **Now, rather than at a milestone where it has something to catch.**
  The ticket offered Phase 4 and Phase 6 as homes, and both are wrong
  for one mechanical reason: `:inets` ships with OTP, so `:httpc`
  requires no dependency and will never appear in a `mix.exs` or
  `mix.lock` diff. There is no arming moment for anyone to notice —
  which is *why* it is the residue, and why "wait until it has a
  subject" is waiting for a signal that cannot arrive. The rest is
  ORC-21's own argument for arming the app list against one boundary,
  one level in: the run is green today, so the diff is a module and a
  registration rather than a cleanup, and every plane module written
  between now and Phase 6 would otherwise land unchecked. The system's
  own precedent agrees from the other side — the live suite already
  rejected `:httpc` on its merits ("HTTP client: Req" below), so this
  codifies a decision foundation has made once already instead of
  anticipating one. Revisit condition: none for the arming. The
  *list* is expected to grow, and growing it is the reviewed diff the
  mirror-image argument above asks for.
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
  behaving exactly as recorded (`systems/substrate.md`), and the guard
  is
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
  project too, for the reason `systems/substrate.md` records:
  dependencies
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
- **The dispatch-facing host port endpoint is a second path on the
  existing health listener, not a new listener — and not
  `api_surface/0`'s general composed router either, yet** (ORC-9's
  design review: the finding that the ticket's callback needed a
  listener it never named). `Catapult.HealthEndpoint`'s moduledoc says
  "nothing else is served here," true the day it was written and false
  the moment GitHub-hosted runners need a public target for the host
  port's context-fetch and result-report calls (`systems
  /generation.md`, `systems/delivery.md`; v5 §7.12.1's OIDC seam) — a
  target that has to share port 8080, the one public port this
  instance exposes (`SETUP.md` §2). Two things are true at once and
  the design has to hold both: `api_surface/0` (`systems/substrate.md`)
  is exactly the registry built for a component to declare a route,
  but its composer "waits for a web layer" that doesn't exist until
  dashboard's Phase 4/7 (`systems/dashboard.md`) — no router to hand
  the declaration to yet, in Phase 3. So generation and delivery still
  register their two routes through `api_surface/0` — ordinary use of
  a substrate registry the plane exercises the same way it exercises
  its own shipped config source, which gets the routes
  collision-checked and shaped like every other route this platform
  will ever declare — but what consumes the registration in Phase 3 is
  not dashboard's future router. It is a small path-dispatching plug
  this system composes in `lib/catapult/application.ex`, in place of
  mounting `Catapult.HealthEndpoint` directly: `/health` keeps its own
  404-everything-else behavior on its own path, a second path forwards
  to delivery's handler (`lib/catapult/delivery/**`, since OIDC
  validation, run correlation and context/result handling *are* the
  host port, not a foundation concern), and both sit behind one
  ordinary runtime plug dispatch — no macro or behaviour coupling, so
  the compile-connected cap (`--fail-above 0`, above) is untouched.
  When dashboard's router lands and absorbs `api_surface/0`
  generically, this listener's hand-wiring is what gets deleted, not
  the registration underneath it.

  **Landed as a shape, not yet as code (ORC-35 design pass): what
  "absorbs `api_surface/0` generically" means, and the compile-connected
  question the shape raised — now measured, below.** `DispatchPlug`'s
  hand-matching
  (`path_info: ["health" | _]`, `["dispatch", "context", run_key]`,
  ...) is deliberately replaced by a *data-driven* successor rather
  than by literal router macros calling each target module by name:
  the new plug reads the same aggregated `api_surface/0` table the
  composer already builds (`systems/substrate.md`'s "the roster is one
  table"), matches `{verb, path}` against it at request time exactly
  the way route-identity collision-checking already does
  (`{version, verb, path}` with every `:param` segment equal to every
  other), and dispatches with `apply(module, function, [conn,
  params])` — a runtime call through an atom pulled from a list, the
  same shape `Catapult.Component.Composer` already uses to call
  `children/0` and every other registry callback on a module it never
  `alias`es or `require`s. No new compile-time edge, because nothing
  about this differs in kind from what the composer already does
  today at zero compile-connected cost; it only replaces two hardcoded
  clauses with a lookup over a table that already exists. `/health`
  keeps dispatching the same way, as one more entry through the same
  table rather than a hardcoded first clause. This retires the
  hand-matching that carried ORC-9's own reasoning ("no macro or
  behaviour coupling") without abandoning the reasoning itself — the
  new plug is still not a macro-composed router calling target modules
  directly, for the same reason the old one wasn't.

  This does not, on its own, get `docs/ui-spec.md`'s dashboard screens
  on screen. Those need LiveView sockets — a `Phoenix.Endpoint` and a
  `Phoenix.Router` with `live/2` routes — which is infrastructure nothing
  in this tree runs today, and unlike `api_surface/0`'s boundary-export
  routes, dashboard's own screens are wholly this system's: no other
  component needs to declare a LiveView route, so there is no
  cross-component registry to design here, only an ordinary router
  naming `event-log`, `explain-why` and whatever v1 adds directly
  (`systems/dashboard.md`). **Whether introducing that router holds
  the `compile-connected --fail-above 0` line was the ticket's own
  open question; it is answered now, measured rather than predicted.**

  The blocker the first pass named was real while it held: no router
  to compile, because Phoenix was not a dependency of this tree at all
  (`mix.exs`'s `deps do` carried no `phoenix`, no `phoenix_live_view`
  — measured against the list, not assumed), so the scratch probe
  ORC-32 established for exactly this kind of question — compile it,
  uncommitted, read the gate, discard it — had nothing to compile
  against. [PR #67](https://github.com/SwaggerAllen/catapult/pull/67)
  removes that blocker (`systems/dashboard.md`'s settled placement
  bullet has the detail) and is sequenced to merge before this ticket
  reaches dev, so the probe now has something to run against, and the
  probe has been run: a router carrying

  ```elixir
  scope "/", CatapultWeb do
    pipe_through(:browser)
    live("/event-log/:project_id", ProbeLive, :index)
    live("/explain-why/:project_id", ProbeLive, :show)
  end
  ```

  compiles with `mix xref graph --label compile-connected
  --fail-above 0` exiting 0 — the graph is empty — and `mix xref graph
  --label compile --source lib/catapult_web/probe_router.ex` shows the
  router with no outgoing compile edges at all, including none to
  either `live/2` target module. That confirms the prediction by the
  mechanism it named: `live/2` stores its target as data the
  dispatcher reads at runtime, the same shape `DispatchPlug`'s
  successor uses over `api_surface/0` above, not the
  `CompositeRouter.router/1`-reading-`__registered_commands__/0` shape
  that trips the ratchet. No `Module.concat/1` escape is needed for
  the dashboard router, the same way ORC-32 found none needed for its
  process manager. Settled, not carried forward: a real router that
  fails to hold `--fail-above 0` is still a finding back to the
  author, never a self-authorized raise of the number
  (`docs/non-goals.md`, "no compile-connected cap anywhere a ticket
  can edit it") — that sentence just no longer describes an open
  question here, only the ordinary backstop it is everywhere else.

  **One caveat travels with the settled result, because the probe
  didn't cover it.** The probe carried no `Phoenix.Endpoint` and no
  boundary declaration, and compiled reporting
  `CatapultWeb.ProbeRouter is not included in any boundary`. The
  ratchet result is about the router's own compile edges and holds
  regardless of that gap, but how `lib/catapult_web/**`'s modules
  register with the boundary compiler is a separate question this
  measurement does not answer — and `mix compile
  --warnings-as-errors` has the boundary compiler in its set, so it is
  a real gate this ticket's dev pass has to meet, not a loose end the
  ratchet already covered.

  This is why `systems/generation.md` and `systems/delivery.md` both
  carry `system:foundation` alongside their own labels: this doc's
  mapped `application.ex`/`health_endpoint.ex` is where the change
  lands, and an undeclared touch is a mutex nobody took.

  **Two facts stop being true the moment this ships, and neither file
  is design's to edit**: `SETUP.md` §2's "`/health` is the only served
  path," and the README's matching line. Flagged here so the
  implementing diff updates both in the same change — the failure mode
  `docs/non-goals.md`'s "no second home for the reference instance's
  live facts" entry exists to catch, one document over.

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
