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

## #1 Standing decisions

- **#2 Root artifacts are generated glue** (v5 §2.7): the supervisor
  composes `children/0` from component declarations; the router (in
  dashboard's web layer) composes the same way. A ticket editing
  root files by hand means the composition mechanism is missing a
  feature.
- **#3 One Repo.** Stores own schemas and queries, never connections
  (v5 §2.4). Infra tables live under reserved prefixes; the audit's
  single-owner check enumerates against this doc's registry.
- **#4 Topology starts `single`** (v5 §2.5 split); the placement
  discipline is honored from the first process regardless.
- **#5 The build's shape lives in `config/*.exs`; the instance's shape
  comes from the environment** (ORC-4). The line is drawn explicitly,
  because without it everything found in `config/` gets moved behind
  the config layer wholesale. On the build side and staying
  there: the component roster (`:components`), which the composer
  reads at compile time and so could not come from the environment
  even if we wanted it to; the test-env switches `serve_health` and
  `start_persistence`, which select what this *build* starts, not how
  a deployment is tuned; and the test database's connection
  parameters, which configure the harness a sandboxed suite needs
  rather than any component's behaviour — routing those through the
  fake would be the fake standing between the suite and the database
  it is required to reach. On the instance side:
  `DATABASE_URL`, `FOUNDATION_POOL_SIZE`, `FOUNDATION_HEALTH_PORT` —
  the three values that differ between the reference instance and a
  laptop, declared in foundation's `config/0` and loaded once at boot.
  Dev and test reach them through the static source
  (`systems/substrate.md`), which means `config/dev.exs` seeds a
  `DATABASE_URL` rather than setting Ecto's discrete
  `username`/`hostname` keys: one declaration, one shape for
  `Repo.init/2` to merge, and dev exercising the same cast the
  deployment does.
- **#6 Two of the three carry foundation's slug — `FOUNDATION_POOL_SIZE`
  and `FOUNDATION_HEALTH_PORT`, not `POOL_SIZE` and `HEALTH_PORT`** (ORC-4).
  The substrate's rule is that a name off the slug spine is legal only with
  `external: true`, and that the flag confers nothing — "an `external: true`
  on a name nobody else imposes is a lie a reviewer can see". Only
  `DATABASE_URL` is imposed: App Platform injects it under a name we do not
  choose. Marking the other two external to keep a bare spelling would
  falsify that argument on the check's only three subjects. Neither is set
  on the reference instance, both carry their defaults (`10`, `8080`), and
  `SETUP.md` §2 names the spelling for the override. The rule: `external:
  true` marks names the world imposes, never names we chose and would rather
  not re-type.
- **#7 The test build reads its database URL through the static source
  too.** The harness switch this list protects is `pool:
  Ecto.Adapters.SQL.Sandbox`, and it stays in `config/test.exs`. The
  connection parameters stay there as well — built from the same `PG*`
  variables CI provides — but in `DATABASE_URL` shape, because Ecto's URL
  parsing *replaces* the discrete keys rather than merging with them, so a
  build setting both would have one of them silently win.
- **#8 `runtime.exs` stops reading the environment.** It is the file the
  substrate's whole config layer is an argument against: today it
  fetches three variables and hand-parses one of them, and it reports
  exactly one problem per boot because each way of failing there
  raises — `fetch_env!` on an unset `DATABASE_URL`, `to_integer` on a
  pool size someone typed wrong. The `sslmode` strip and the
  `verify_none` choice do not disappear: they become the declared cast
  on `DATABASE_URL`, which is where they get to fail by name and
  alongside everything else that is wrong. The file keeps only what
  `import Config` is for.
- **#9 TLS verification to the managed database is `verify_none`,
  deliberately, and this bullet — not the cast's docstring — is now its
  record** (ORC-83). `cast_database_url/1` strips the platform's injected
  `sslmode=require` (Ecto's URL parser rejects the query param as an option)
  and configures `ssl: [verify: :verify_none]` rather than `verify_peer`
  against a pinned CA. The standing decision is provider-neutral, because a
  systems doc is the wrong altitude for any one provider's topology to be
  the reasoning: **`verify_none` holds only where the operator controls the
  network path end to end; anywhere else, pin a CA and use `verify_peer`.**
- **#10 Library configuration is assembled, never re-declared.** Ecto and
  Oban read application env by their own contract and will keep doing it;
  the config layer feeds them rather than fighting them, so
  `Catapult.Repo.init/2` merges url and pool size in from the accessor and
  Oban's options are composed the same way when `oban_queues/0` starts
  contributing.
- **#11 If the plane ever needs a config source of its own, it belongs to
  foundation** — `lib/catapult/config/`, added to this doc's file map
  in the same change. Not needed today and deliberately not created
  speculatively: the plane runs substrate's shipped environment
  source, which is how that source stays exercised
  (`systems/substrate.md`).
- **#12 The roster and the source selection live in `Catapult.Boot`, and
  every entry point goes through it** (ORC-4).
- **#13 Boundary's strict external mode arms now, against one boundary,
  rather than later against all of them** (ORC-21). v5 §2.14 promotes the
  adapter conventions to compile grade — only `Store` subcomponents on Ecto,
  only the outbox wrapper on Oban's insert surface, only adapters on Req, no
  model-call library anywhere in plane code. Every one of those is a rule
  *about a sub-boundary*, and the tree has exactly one boundary today
  (`lib/catapult.ex`, `deps: []`), so none of them can be stated yet. What
  can be stated is the mode, in the root `mix.exs`, which makes the coarse
  boundary declare the external applications it actually calls.
- **#14 The arming is `check: [apps: [...]]`, not `type: :strict`, and the
  reason is a Boundary defect rather than a preference.**
- **#15 The list is the whole of what a `:prod` build can reach and
  Boundary can restrain, and `Catapult.Audit.BoundaryApps` reports the gap**
  (ORC-50; `systems/substrate.md` holds the check's subject, its three
  derived exclusions and its census).
- **#16 The list is written, never derived** (ORC-50).
- **#17 What it does not cover, so the gap is not mistaken for coverage:**
  Boundary documents that calls to `:elixir`, `:boundary` and pure Erlang
  applications cannot be restrained, so `:httpc` reaching a model provider
  from plane code compiles clean under the check. Conventions §11 is a
  compile error for every Elixir client *the app list names*, and for the
  Erlang ones it is the plane-owned transport ban the bullet below decides
  (ORC-52) — not an audit check in substrate, whose platform set carries no
  `:httpc` or model-call rule; a paragraph headed "so the gap is not
  mistaken for coverage" is the last place to manufacture coverage. The
  plane is where that residue matters most, because it is the tree §11 is
  written about. The claim has three homes and all three change together:
  this paragraph, `systems/substrate.md`'s enforcement roster, and
  `lib/catapult.ex`'s moduledoc — which is an unowned path
  (`systems/README.md`) and so belongs to the change that corrects the other
  two rather than to a system.
- **#18 The Erlang residue is a plane-owned `policies/0` check that bans
  the transport, and it arms now while it is green** (ORC-52). Three
  decisions — what, where, when — behind the refusal that makes them
  possible, which comes first.
- **#19 The decidable rule is one level out: no plane module calls a pure
  Erlang HTTP client.** The module in `:httpc.request/4` is a literal atom
  in the source, so the ban is exact at the grade the audit already runs at,
  needs no inference, and has the same shape as
  `Catapult.Audit.Checks.WallClock` — a remote call on a literal module
  atom, plus the `apply(:httpc, :request, _)` spelling, which is literal
  atoms too. A computed module is out of reach and is not chased, for the
  reason above. The ban is deliberately *broader* than §11: it catches every
  unbounded egress by that route rather than only the model-shaped one,
  which is v5 §2.2's every-HTTP-usage-inside-a- registered-adapter rule
  arriving for the applications the compiler cannot see. The banned set is
  named *modules*, and the asymmetry with `mix.exs` is worth spelling rather
  than glossing: a call site names a module, so this is a module list where
  the compiler's side is an application list — `:httpc` and `:inets` (the
  OTP client and the application whose `start/0` arms it), `:hackney`,
  `:gun`, `:ibrowse`. Beyond the grade they are the same list split by what
  the compiler can restrain: both author-visible, both extended by reviewed
  diff, neither inferred. The entry's required `policy:` string is where the
  rule is stated in prose, so the report cites the rule rather than the
  module. The escape rides `Catapult.Audit.Source` like every other check at
  this grade (`# catapult:allow erlang_http`) and has no sanctioned use in
  this tree today — a tag covering no violation is itself reported, so an
  unused one prunes itself.
- **#20 The transport layer stays off the list** — `:gen_tcp`, `:ssl`,
  `:socket` and friends.
- **#21 It is plane code**, at `Catapult.Foundation.Policies.ErlangHttp`,
  registered through foundation's `policies/0` against the
  working-directory-rooted scope every registered check takes. It may not be
  a substrate platform check and may not live there under another name: that
  set is inherited by every project that runs the audit at all, and
  generated projects *do* make model calls — through the LLM adapter, which
  is conventions §11's other bullet — so a shipped egress ban would fail the
  audit of a project doing what the platform told it to.
- **#22 The root project's compile-connected cap is 0 and is armed as a
  gate line** (ORC-21). Measured here rather than assumed: `mix xref graph
  --format stats` reports 0 compile dependencies across the seven tracked
  files, and `--label compile-connected --fail-above 0` exits 0. The
  number's home is `qualityGates`, not this repo's code, for the reason
  `systems/substrate.md` argues — a cap a ticket can edit is a cap the
  ticket that breaks it will edit.
- **#23 The plane declares a licensing policy rather than staying inert**
  (ORC-51). Two declarations and no new mechanism: `licensing: [allow:
  ~w(AGPL-3.0-only Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC)]` in
  the root `mix.exs`, and `licensing/0` on `Catapult.Foundation`
  returning `[distribution: :service, license: "AGPL-3.0-only"]`.
  `arming/2` maps `{:service, :listed}` to `[]`, so the plane's
  dependency closure stays unchecked exactly as `LICENSING.md`'s table
  says it should — the engine's `commanded` and `eventstore` are
  unchecked either way, and correctly.
- **#24 The plane's `allow:` list is Catapult's five plus its own
  identifier, and the five are not decoration** (ORC-51). The list has
  to contain `AGPL-3.0-only` or `bucket/2` reads the subject as
  unplaceable and reports it: the self-check and the bucket rule are
  one rule, which is what `systems/substrate.md` means by a project's
  list containing its own license even where nothing is checked.
- **#25 Every subject in the root project is `:service` under
  `AGPL-3.0-only`; a subject that is not belongs in another mix
  project** (ORC-51). This is what keeps the seam above closed — the
  plane states one policy because the plane is one class — and it is a
  one-line consequence rather than a decision each system re-takes:
  engine, delivery, generation, registry, dashboard, core_dsl and
  harness each declare `[distribution: :service, license:
  "AGPL-3.0-only"]` when they land, and the audit is what asks.
- **#26 ORC-74 and v5 §3.5 are in view, and neither moves this** (ORC-51).
  §3.5 adoption forks a *component* into a customer's graph and tree,
  which is legitimate precisely because `components/**` is Apache-2.0;
  the plane is not a component and its own classification is untouched.
  What the adjacency changes is what the dark ladder costs, not what
  the answer is.
- **#27 The dispatch-facing host port endpoint is a second path on the
  existing health listener, not a new listener — and not
  `api_surface/0`'s general composed router either, yet** (ORC-9).
  `Catapult.HealthEndpoint` serves `/health` and nothing else, and
  GitHub-hosted runners need a public target for the host port's
  context-fetch and result-report calls (`systems
  /generation.md`, `systems/delivery.md`; v5 §7.12.1's OIDC seam) — a
  target that has to share port 8080, the one public port this
  instance exposes (`SETUP.md` §2). Two things are true at once and
  the design holds both: `api_surface/0` (`systems/substrate.md`)
  is exactly the registry built for a component to declare a route,
  but its composer "waits for a web layer" that doesn't exist until
  dashboard's Phase 4/7 (`systems/dashboard.md`) — no router to hand
  the declaration to in Phase 3. So generation and delivery register
  their two routes through `api_surface/0` — ordinary use of a
  substrate registry the plane exercises the same way it exercises
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

  This is why `systems/generation.md` and `systems/delivery.md` both
  carry `system:foundation` alongside their own labels: this doc's
  mapped `application.ex`/`health_endpoint.ex` is where the change
  lands, and an undeclared touch is a mutex nobody took.
- **#28 What "absorbs `api_surface/0` generically" means** (ORC-35).
  `DispatchPlug` is *data-driven*: it reads the same aggregated
  `api_surface/0` table the composer already builds
  (`systems/substrate.md`'s "the roster is one table"), matches `{verb,
  path}` against it at request time exactly the way route-identity
  collision-checking already does (`{version, verb, path}` with every
  `:param` segment equal to every other), and dispatches with `apply(module,
  function, [conn, params])` — a runtime call through an atom pulled from a
  list, the same shape `Catapult.Component.Composer` already uses to call
  `children/0` and every other registry callback on a module it never
  `alias`es or `require`s. Neither hand-matched `path_info` clauses
  (`["health" | _]`, `["dispatch", "context", run_key]`, ...) nor literal
  router macros calling each target module by name: the first is hardcoded
  clauses standing in for a lookup over a table that already exists, the
  second is the macro coupling the compile-connected cap forbids. No new
  compile-time edge, because nothing about this differs in kind from what
  the composer already does today at zero compile-connected cost. `/health`
  dispatches the same way, as one more entry through the same table rather
  than a hardcoded first clause. The plug is still not a macro-composed
  router calling target modules directly, for the same reason the
  hand-wiring above is not.
- **#29 `SETUP.md` §2 and the README name the paths this listener serves,
  and they change with it**: `docs/non-goals.md`'s "no second home for the
  reference instance's live facts" entry is what a stale "`/health` is the
  only served path" in either would violate, one document over.
- **#30 A bounded, volatile last-N-failures buffer, fed by telemetry
  `CatapultWeb.Endpoint` already emits** (ORC-218). The
  reference instance answering 500 on every screen and on the
  provisioning surface for a day left nothing behind but App
  Platform's own runtime log — unnavigable for anything not happening
  right now, unforwarded, and read by nobody until this ticket. The
  fix is a small in-process record, not a backend: `systems
  /observability.md`'s own ORC-218 entry is the rule this bullet's
  mechanism satisfies.
- **#31 Fed off two hooks that already exist, measured rather than added —
  one for completeness, one for the trace.** `CatapultWeb.Endpoint`'s
  `render_errors:` config (`config/config.exs`) arms
  `Phoenix.Endpoint.RenderErrors`, which wraps this listener's entire
  `call/2` in a rescue and executes `:telemetry.execute([:phoenix,
  :error_rendered], %{duration: _}, %{conn:, status:, kind:, reason:,
  stacktrace:, log:})` before re-raising (verified against `deps/phoenix
  /lib/phoenix/endpoint/render_errors.ex`) — the exception and its stack
  trace, for anything that raises. But a 5xx that never raises never reaches
  that event (below), so the buffer's actual feed is the plug already ahead
  of it in the same file: `plug Plug.Telemetry, event_prefix: [:phoenix,
  :endpoint]`, whose `[:phoenix, :endpoint, :stop]` fires immediately before
  the response is sent on a conn that still carries the callback it
  registered, carrying the final `conn` — status included — whatever
  produced that status (verified against `deps/plug/lib/plug/telemetry.ex`;
  the "still carries the callback" qualifier is not decorative — the
  paragraph below names the one path where it doesn't).
  `Catapult.Foundation.FailureLog` attaches to both, and **whichever fires
  first for a given request creates the record; the other, if it fires at
  all, enriches the existing one rather than pushing a second** — correlated
  by the request id `plug Plug.RequestId` — already the plug ahead of
  `Plug.Telemetry` in the same file — writes to `Logger.metadata()` for
  every request regardless of whether `:assign_as` is set (verified against
  `deps/plug/lib/plug /request_id.ex`): both handlers run inside the
  request's own process, so both read the identical id back off
  `Logger.metadata()`, with no new plug and no conn threading added to reach
  it. A created record carries the request path and a `DateTime` from
  `Catapult.Clock` (no bare `DateTime.utc_now`); whichever event supplies a
  stack trace attaches it, and `:stop` additionally attaches the response
  body, capped. **The body is what a deliberate 5xx has instead of a
  trace.**
- **#32 Order is not fixed, because for one path `:stop` never fires at
  all, so "`:stop` is always the record" would silently drop that path's
  trace.**
- **#33 The predicate is "left this listener with `conn.status >= 500`,"
  not a grep for how it got there.**
- **#34 Scoped to this listener's own requests, not every process crash.**
  An Oban worker or an unrelated supervised process crashing is not fed
  here: Oban already has its own execution lifecycle (retries, `discarded`)
  for the first, and the ticket's own argument is about an HTTP-facing
  incident (every screen, the provisioning surface) — the same boundary
  `CatapultWeb.Endpoint` already draws.
- **#35 The buffer is plane code under `lib/catapult/foundation/`, not the
  observability component, because its audience is this instance's own
  operator** — the same class of concern `/health` and `DispatchPlug`
  already are, not a capability a generated project inherits by adopting a
  shared component. A generated project wanting the identical read surface
  is a separate, unasked product decision; nothing here presumes it.
  `Catapult.Foundation.FailureLog` is a `processes/0` entry like any other
  (`{:foundation_failure_log, :singleton}`), holding the last **50** records
  — small and stated. It declares no `max_heap_size:` guardrail, not a
  default one: there is no default to fall back on, since
  `Catapult.Guardrails` applies only what a `processes/0` entry names —
  `enforceable/0` is `[:max_heap_size]` alone, and an entry naming nothing
  gets nothing applied (verified against `components/substrate/lib/catapult
  /guardrails.ex`) — and 50 small records bounded in count is not the case
  this ticket's incident argues needs one. Oldest record drops first once
  the 51st arrives.
- **#36 One read surface beside `/health`: `GET /failures`, registered
  through `api_surface/0` on `Catapult.Foundation` exactly like delivery's
  provisioning routes, `version: "v1", audience: :internal`** — reached
  through the identical `Catapult.Foundation.DispatchPlug` path dispatch
  (this doc's ORC-9/ORC-35 entries above), a sixth path on the one listener
  rather than a new one. Bearer-authenticated, constant-time
  (`Plug.Crypto.secure_compare/2`), against a secret of foundation's own:
  **a new `FOUNDATION_OPERATOR_TOKEN`, declared in
  `Catapult.Foundation.config/0` exactly like `endpoint_secret_key_base`
  above (`secret: true`, no default), not a reuse of
  `DELIVERY_PROVISIONING_TOKEN`.**
- **#37 The phone-readable half is a dispatch-only GitHub Actions
  workflow, and it is author-owned** (invariants, above): the same shape
  `catapult-test-project.yml` already has — a `workflow_dispatch` job that
  curls `GET /failures` with the bearer token and prints the JSON to the
  run's own log, readable from the Actions tab on a phone with no other
  tooling. The route above is what it curls.
- **#38 No dashboard screen.** A route is what "readable from a phone
  within a minute" needs, and a rendered screen over the identical data is a
  later convenience with no argument for it yet — not a refusal, just
  nothing this argument asks for.

## #39 The live suite

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
- **The no-polling rule gains one named exception: a live check may
  bound-poll a run it dispatched itself** (ORC-216, design pass;
  `docs/conventions.md` §9, amended in the same change). The reason
  above is specific to what it was written about — a live check
  waiting out a *rollout* duplicates deploy detection, which already
  exists and is the plane's own job, at a slower and less safe
  cadence. A live check waiting on a dispatched generation run is not
  a second deploy detector: nothing else in this system observes that
  run's completion, and the observer is the same process that started
  it — the "one request" version of this check would just be the
  first poll with nothing to distinguish it from every poll after. The
  exception is narrow by construction, not by convention: a bounded
  overall deadline, an ordinary fixed poll interval against the
  plane's own terminal-status read (`systems/delivery.md`'s
  provisioning entry), and scoped to a run the same test call
  dispatched — never to a deploy, a rollout, or any state the suite
  did not itself create.
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

## #40 Initial vs target

Initial (Phase 1): application skeleton, Repo, config through the
substrate's config layer (ORC-4 — "via Vapor" as written here; see
`systems/substrate.md` for why the dependency did not land), infra
migrations for Oban. Target: EventStore migrations (with
engine), release tasks for seeds + migrations, DOKS manifests
adjacent (Phase 7).

## #41 Depends on

substrate.
