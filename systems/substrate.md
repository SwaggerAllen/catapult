---
paths:
  - components/substrate/**
---

# substrate

The elixir-target platform substrate: everything a Catapult-built app
(and Catapult itself) adopts to honor the convention corpus.
**Distributed from git, and published to public hex.pm as a public
artifact** (v5 §3.1, revised from the mini_repo registry); Catapult
consumes it as a path dep — the plane is its first consumer.

## Owns

The component behaviour (`use Catapult.Component`) and the whole v5
§2.2 registry roster it declares — `config/0` (secret flags),
`pubsub_topics/0`, `oban_queues/0` (cron annotations),
`telemetry_events/0`, `events/0` (versions), `processes/0` (placement
and VM guardrails), `seeds/0`, `errors/0` (boundary failure
vocabulary with remedies), `externals/0` (wrapped third-party
services), `feature_flags/0`, `permissions/0`, `api_surface/0`,
`admin/0`, `policies/0` — with the roster table that gives each its
shape, the compile-time root composer with collision checks, and the
normalized inventory the audit reads; `licensing/0` (distribution
class and SPDX identifier), which claims no name and so sits outside
that table beside `config/0`; the boundary-export macro
(telemetry spans now, `@requires_permission` enforcement when identity
lands, and the export trace `api_surface/0` validates against); the
`children/0` and `ready?/0` composition points; the
configuration layer that honors
`config/0` — the source port, the shipped environment source, the
static fake, the boot-time load and the single accessor;
`mix catapult.audit` and its check registry; the health-endpoint plug
(SHA + per-component readiness); the injected clock behaviour; the
seeds release task.

## Standing decisions

- **One macro layer, two concerns.** Telemetry instrumentation and
  permission enforcement ride the same boundary-export macro —
  built once, because both need the same interception point and two
  macro layers on one function is a composition bug farm.
- **The audit is a check registry, not a monolith.** Platform
  extensions (v5 §9) register checks; the ES family registers the
  purity floor, delivery registers file-map checks. Rationale: the
  audit grows for the life of the platform; a registry grows by
  entries, a monolith by merge conflicts.
- **Registries fail the build on collision, never warn.** A warning
  about a name collision is a collision that ships.
- **The roster is one table, not one validator per registry** (ORC-22).
  Twelve name-claiming registries × (entry shape, known opts, required
  opts, spine rule, collision key) is a matrix, and hand-writing it as
  twelve validator functions is how a composer becomes the monolith the
  audit refused to be one level up. `Catapult.Component.Registries` holds
  one row per registry; aggregation, the collision report and the inventory
  are each one pass over it, and adding a registry is an entry rather
  than a debate — `systems/registry.md`'s idiom for artifact kinds,
  which is the same idiom for the same reason. Plural, and not
  `Catapult.Component.Registry`, because the singular reads as the
  artifact registry this repo also has a system doc for.

  **What this document records is the columns, not the rows.** The rows
  are code and the code is the inventory (`docs/non-goals.md`); a shape
  is spelled out below only where the shape itself is the argued
  decision. Without that line a roster ticket produces, in its own
  design doc, exactly the hand-maintained mirror the roster exists to
  make unnecessary.

  The one registry deliberately outside the table is `config/0`: it is
  the only one with a consumer, a boot half, and error messages worth
  their specificity, and `Catapult.Config` keeps them. Absorbing it
  would trade a good report for a uniform one.
- **The address is positional, the policy is opts, and an opt is not
  optional for sitting in a keyword list.** Every entry carrying more
  than a name follows `config/0`'s `{key, name, opts}` grain:
  positional elements identify the thing, the keyword tail is
  everything said *about* it, checked against the row's known-opts list
  the way the config layer already checks its own. Required opts are an
  ordinary column — `api_surface/0`'s `version:` and `audience:` are
  required and reported when absent — because the alternative is a
  five-element tuple whose fourth element nobody can count.

  This is where §4.4's literal `{exported_function, path, verb,
  version, audience}` gets respelled rather than transcribed: the same
  five facts as `{{fun, arity}, verb, path, opts}`, verb and path
  adjacent because that is how every router in the language spells a
  route and the composition that will consume this is a mechanical
  transform of that pair. The ticket's rule was that anything
  under-specified upstream is a doc edit first and code second; this
  is the edit.
- **Optional facts get sugar; mandatory ones get none.**
  `oban_queues/0` keeps its bare atom and grows `{name, opts}` for a
  cron annotation, and `processes/0` keeps `{name, placement}` and
  grows a third element for VM guardrails, because most queues have no
  schedule and most processes have no guardrail, and an entry that says
  only its name is what the diff should show. `events/0` gets no such
  sugar: the entry is `{type, version}`, with no bare form and no
  default version, because an unversioned event is precisely the state
  §2.4's upcasting discipline exists to prevent and a default of `1`
  would make the first version the one fact invisible in the diff. The
  claimed name is the type — two components declaring one type collide
  — while one component declaring the same type at two versions is
  ordinary and permanent, since old shapes live as long as the log
  does. No upcaster field: the pair already identifies it, and whether
  the function exists is a declared↔constructed check (ORC-21), not a
  field to restate it in.

  **Amended (ORC-21): `cron:` is a list of `{schedule, worker}`, not a
  string, because a crontab entry does not point at a queue.** The
  sketch above drew `cron: :string` and the composing half is what
  showed it under-specified: `Oban.Plugins.Cron` takes
  `{expression, worker}` or `{expression, worker, opts}` (verified
  against `oban 2.20`'s `validate_crontab/1`), and a worker's queue
  comes from its own `use Oban.Worker`. So a schedule names *what* runs
  and the queue is downstream of that — one string on a queue entry can
  say when but never what, and one queue hosting two periodic jobs
  cannot be spelled at all. The entry becomes
  `{:engine_work, cron: [{"0 * * * *", Engine.SweepWorker}]}`: the queue
  stays the claimed name and the address, the schedules ride as policy
  about it, which is the row grain rather than an exception to it. It
  buys a cross-fact worth checking, too — a scheduled worker whose own
  `queue:` is not the entry it was declared under is a job that will run
  somewhere nobody declared. Free to fix here for the same reason
  `events/0` was: nothing declares a queue yet, and a wrong shape is
  only cheap before it has entries.

  Making `events/0` breaking costs nothing today and could never be
  done cheaply again — nothing declares an event until the engine does.
  That is the roster-before-consumers argument arriving as a concrete
  saving rather than a principle.

  Two spellings are affordable only because nothing downstream sees
  them: **normalization happens once, in the inventory**, and every
  consumer — the collision report, the audit, the generators later —
  reads the wide form. A second normalizer anywhere is the defect this
  is trading against.
- **The spine check arms wherever a name is a global atom, and
  `external:` stays a config-only escape.** `errors/0` kinds,
  `permissions/0` and `feature_flags/0` atoms, `oban_queues/0` names
  and `telemetry_events/0` paths are all checked against the slug
  prefix. `pubsub_topics/0` is not, and the exception is the rule's
  proof: the composer renders `slug:name` from a bare atom, so a
  prefix there would be the slug written twice.

  **The escape does not travel with the check.** `external: true` stays
  a `config/0` opt and is added to no other row, because an env var
  name is the only claimed name a party outside this codebase can
  impose (`DATABASE_URL`, injected by the host platform). Nobody
  imposes a permission atom, a queue name or an error kind on us; a
  registry that offered the escape anyway would be offering a way to
  turn its own check off, which is the state the flag was invented to
  avoid. Arming queues and telemetry, which never had the check,
  belongs in this ticket for the same reason `events/0`'s shape change
  does: nothing declares either yet, and the check is a table column.
- **`errors/0`'s remedy ladder promotes by adding, never by
  replacing.** `{kind, meaning, opts}`, where `remedy:` is required
  prose and `runbook:` / `admin:` ride alongside as promotions. A
  graded remedy that *replaced* the sentence would put a bare link into
  the error payload and the generated catalog, and an operator who has
  to open a runbook to find out whether it is the right runbook has
  been handed something worse than one line of prose. Presence is
  structural, so the composer reports a remedy-less kind with no
  environment at all (v5 §2.14 wanted this as an audit failure and it
  arrives for free); whether a kind is ever *constructed* is the
  declared↔constructed check, and that waits for ORC-21.
- **A kill switch names a flag its own component declares.** The first
  cross-registry check, and what makes §2.2's promise literal — the
  switch tied to the thing it switches instead of to a naming
  convention. `externals/0`'s `kill_switch:` must appear in the same
  component's `feature_flags/0`; a switch pointing at a flag nobody
  registered is a switch that does nothing, discovered during the
  incident it was built for. `adapter:` and `fake:` name modules and
  are checked for loadability exactly as the composer already checks a
  component module: a fake declared and never written is a hole in the
  no-network rule (conventions §9), and CI is a better place to find it
  than the first test that reaches for it.

  **Data classification is a closed vocabulary, not a note.** §2.2 asks
  for a note; a note cannot be grouped, and grouping is the entire
  payoff — the generated "what does this app talk to" page is a
  compliance inventory and, hosted, a customer's egress inventory. Four
  atoms, highest applicable wins: `:none`, `:operational`,
  `:customer_content`, `:personal`. Credentials are deliberately not a
  class, because every adapter sends one and a class every entry
  carries separates nothing; what the field classifies is application
  data crossing the boundary in either direction.
- **`api_surface/0` validates against a trace `defexport` does not yet
  leave.** The macro composes a telemetry span and nothing else, so
  nothing in the substrate can currently answer "is this function a
  boundary export" — which is the whole of §4.4's thin-wrapper
  enforcement. It grows an accumulating attribute and a generated
  `__catapult_exports__/0`, in the shape of the
  `__catapult_component__/0` beside it. The payoff outruns this
  registry: the audit's
  every-export-has-a-test check and its exported-mutating-function
  permission check (v5 §2.14) are both blocked on this same fact, and
  neither now has to invent it.

  **Route identity is the path's shape, not its parameter names.**
  Collisions compare `{version, verb, path}` with every `:param`
  segment equal to every other, because `/projects/:id` and
  `/projects/:project_id` are one route to any router and two strings
  to a naive check. That is a claim about routes rather than about a
  router, which is what makes it safe to hold here while the
  composition that consumes it waits for a web layer.
- **`admin/0` mounts are relative to a root the component does not
  own.** An entry's path is a segment beneath the admin root, never an
  absolute `/admin/...`: where the root mounts is the composing
  application's decision (v5 §2.7), and a component spelling the prefix
  has hard-coded a fact belonging to someone else. Catapult will
  register none of these — its per-component admin surfaces are
  subsumed by the dashboard (conventions §13) — which makes this the
  roster's clearest case of a registry whose first consumer is not this
  repo, and a standing reminder that shipped substrate is not measured
  by what the plane happens to use.
- **`policies/0` scopes are working-directory-relative globs, and the
  shape is what enforces it.** An entry names a check module and the
  scope it applies to; a glob that is absolute or climbs out with `..`
  is a reported problem, not a convention someone remembers.
  `docs/non-goals.md` ruled out teaching `mix catapult.audit` where
  this repository keeps its components, and a registration surface that
  accepted `../../lib/**` would walk that reach back in through the
  front door while the task's own globs stayed innocent. Each mix
  project composes its own check set and runs the audit in its own
  directory; registration composes checks without touching that, which
  is the product-facing payoff — the ES family's purity floor travels
  with the ES family instead of being re-wired per project.

  **The behaviour lands; the runner does not.** A registry whose
  entries reference modules has to say what the module is, or its
  collision check is checking the names of things with no contract — so
  `Catapult.Audit.Check` and its one callback are part of the
  mechanism, and the loop that calls it plus the checks that adopt it
  are ORC-21's. The `policy:` field is a string and the composer checks
  nothing beyond that it is one: resolving it means reading the doc
  graph, and substrate ships into projects whose graph belongs to the
  plane rather than to the package.
- **The census is what makes an unconsumed registry visible.** The
  inventory is a function returning normalized data — never a document,
  per the no-hand-maintained-inventories rule — and `mix catapult.audit`
  prints a count per registry on every green run, not behind a flag. A
  registry aggregating into nothing is this ticket's deliberate state,
  and that state's failure mode is not collision but rot: twelve
  registries nobody looks at between now and Phase 3. One census line is
  the cheapest thing that makes an empty registry a fact somebody sees,
  and it keeps the inventory surface from being the one unconsumed
  registry itself — the recursion a mechanism-only ticket opens the
  moment nothing reads its output.
- **Every callback keeps an overridable empty default; none becomes
  `@optional_callbacks`.** Incremental adoption is what the default
  already buys. An optional callback buys the same thing and charges
  the composer a `function_exported?/3` guard at every call site: an
  aggregation that is total is one that cannot silently skip a
  component, and "declared nothing" versus "does not implement" is a
  distinction with no consumer.
- **An env var name is a claimed name like a queue or a topic.** Two
  components binding `DATABASE_URL` is the same class of bug as two
  claiming `:engine_default`, so it is checked where the others are —
  one more entry in the composer's problem list, reported in the same
  breath as the rest. This is what makes the registry load-bearing
  rather than descriptive: today the values are read ad hoc from
  application env and nothing anywhere notices two readers of one
  variable disagreeing about its meaning.
- **Env var names are declared, not derived, and an off-spine name is
  marked.** Conventions §3 renders the spine as a mechanical
  derivation — component `engine` gets `ENGINE_*` — and this repo
  already contains the counter-example: `DATABASE_URL` is injected by
  App Platform under a name we do not choose, and
  `FOUNDATION_DATABASE_URL` is not on offer. So the declaration
  carries the literal variable name (it already does — `config/0`'s
  entries are `{key, env_var, opts}`), the audit checks the prefix,
  and a name off the spine is legal only with `external: true` on the
  entry. The flag earns its place by making the two cases
  distinguishable: without it every off-spine name looks like
  sloppiness and the check has to be turned off to accommodate the one
  case that is not. With it, the audit stays armed and the exceptions
  are a grep. What it does not do is confer permission — an
  `external: true` on a name nobody else imposes is a lie a reviewer
  can see, which is the most a declaration can offer.
- **The cast is total, and the report enumerates.** The requirement is
  the composer's: one boot failure naming every problem, because N
  restart cycles to discover N missing variables is hostile to the
  operator who is holding the deploy. Vapor supplies half of this and
  the half it withholds is the reason this layer is not a call to
  `Vapor.load!/1`. Its `Env` provider does aggregate *missing*
  variables ("ENV vars not set: A, B") and its loader concatenates
  those across providers — but a binding's `map:` function is invoked
  bare inside an `Enum.map`, so the first value that fails to parse
  raises out of the load with no aggregation, no key name and no
  component. `String.to_integer/1` on a fat-fingered `POOL_SIZE` is
  an `ArgumentError` from inside a config library, and the four
  variables that were also wrong are not in the message. Hence: a
  declared cast returns `{:ok, value}` or `{:error, reason}` and
  never raises, the layer collects both classes — missing and
  uncastable — into one exception, and the opts vocabulary is ours
  (`default:`, `cast:`, `secret:`, `required:`, `external:`) rather
  than any library's.
- **The registry declares data; provider structs are an adapter's
  business.** `config/0` returns inert `{key, env_var, opts}` tuples
  and nothing that has to be `Code.ensure_loaded?`d to be understood.
  Inert data is readable by the audit, by the composer's collision
  check, by the settings surface v5 §7.10 will need and by a human
  reading a diff; a callback returning a library's structs is
  readable only by that library, and swapping the library then means
  editing every component instead of one adapter.
- **Two reports, at two times, deliberately.** Structure —
  collisions, malformed declarations, an unknown opt — is validated by
  the composer, which means CI's audit catches it with no environment
  at all. Values are validated at boot, and only at boot, because the
  environment CI has is not the environment that matters and a gate
  that asserts otherwise would be asserting something it cannot see.
  Keeping them separate is what lets the build-time half be
  exhaustive instead of best-effort.
- **The report names variables and reasons, never values.** An
  invalid-value message that quotes the value it rejected publishes a
  malformed secret into the boot log of the failing deploy, which is
  the log everyone then pastes into a ticket. `secret: true`'s
  audit-checked ban on secrets in logs and error payloads (v5 §2.2)
  starts here, in the first error payload the platform can emit, and
  it costs nothing to hold for every value rather than only the
  flagged ones — the operator needs to know *which* variable and
  *why*, and already has the value.
- **Loaded values live behind one accessor, not in application env.**
  The load happens once, before the root supervisor starts, into
  `:persistent_term` under a private key; components read through the
  accessor and nothing else. The alternative — writing the values into
  application env — is more inspectable and that is exactly its
  defect: it leaves the old door open, and `Application.get_env` on a
  component's value would remain correct forever, so the ad hoc
  reading this layer exists to end would end only by convention.
  Write-once-at-boot is also the access pattern `persistent_term` is
  for. The accepted cost is that values are not visible from a remote
  console without calling the accessor.

  **The store is keyed by slug, not by module** —
  `Catapult.Config.fetch!(:foundation, :health_port)` — settled at
  implementation (ORC-4). The slug is the spine every other claimed
  name hangs off (conventions §3) and the composer already fails the
  build on two components sharing one, so it is exactly as unique as
  the module and shorter to read. It also keeps the accessor from
  putting a component module into the caller's module graph, which is
  what a keyed-by-module store would have cost: `Catapult.Repo`
  reading `fetch!(Catapult.Foundation, …)` closes a cycle through the
  component that lists the Repo among its children, and cycles are a
  hard gate.
- **The port hands the source every name at once; there is no per-key
  lookup.** The signature in full, because the whole of "adopting
  Vapor later is one module and one compile-time line" rests on this
  shape fitting a source that is not the environment:

  ```elixir
  defmodule Catapult.Config.Source do
    @callback load(names :: [String.t()], opts :: term()) ::
                {:ok, %{optional(String.t()) => String.t()}}
                | {:error, problems :: [String.t()]}
  end
  ```

  Called once, before the root supervisor starts, with every name
  every component declared; `opts` is the source's own settings, which
  cannot themselves come from the config layer (see the compile-time
  selection decision below). `term()` rather than the `keyword()` this
  block was sketched with, because the same sketch says the static
  fake's seeded *map* is exactly this `opts` — and the map carries the
  argument (a seed keyed by name and valued with strings needs no
  special case anywhere in the layer), where the typing was
  incidental. Its shape is the source's business, which is the whole
  point of the parameter. `Catapult.Config.Env` implements it as
  one `System.get_env/0` and a `Map.take`. Nothing else is a callback:
  no `fetch/1`, no `get/2`, and in particular no `all/0`, because a
  source free to volunteer names nobody declared puts values into the
  system behind the registry's back, and the registry is the product.

  **Tested against a file source, which is what design review asked
  for.** A `Catapult.Config.File` over a flat TOML or JSON document
  implements `load/2` as one read, one parse and one `Map.take`, and
  it fits without the port bending — because the port never asks it a
  second question. A `fetch(name)` port would leave that same adapter
  three bad options: re-read and re-parse per key (N reads for N
  declarations, with no guarantee they saw one document), cache in
  `:persistent_term` behind the layer's back (a second store, absent
  from the report), or become a process whose lifecycle the port's
  shape does not model. That is the port that can only ever be env,
  and `load/2` is the shape that is not it.

  **The file source is also what proves the `{:error, _}` branch is
  not ceremony.** An environment source cannot fail — `System.get_env/0`
  always answers — so with only the shipped adapter in view that
  branch reads as a return nobody will ever construct. A file source
  fails four ways before it reaches a value (absent, unreadable,
  unparseable, wrong root shape), and it forces the distinction that
  makes the report survive a second source: **when the source itself
  fails, the layer reports that and stops**, rather than falling
  through to the per-declaration pass. "DATABASE_URL is not set" is a
  false statement about a file that was never opened, and forty such
  lines bury the one true one. Missing *values* enumerate; a missing
  *source* is the whole report.
- **The source's currency is named strings, and the namespace is the
  adapter's business.** A declaration's second element is a name, and
  the name is env-shaped (`SCREAMING_SNAKE`, on the slug spine) even
  under a source that is not the environment, because the environment
  is the transport every deployment has and a per-source rename table
  is a mapping no audit can read — the prefix check and `external:
  true` both stop meaning anything the moment one name has two
  spellings. A file source resolves the declared name inside its own
  document, and how it does that (top-level key, or a documented
  `DATABASE_URL` → `["database", "url"]` unfolding) is the adapter's,
  not the declaration's.

  Values crossing the port are strings. A TOML `pool_size = 20`
  arrives at the layer as `"20"` and the declared cast derives the
  integer, which looks wasteful and is deliberate: the alternative is
  `term()` values and casts that must accept both shapes, so every
  component in every generated project pays a two-headed cast for a
  source it does not run. The adapter discards typing the document
  had; the cast stays the single definition of what a value means,
  which is the reason casts became ours at all. Present-but-empty is
  present — `DATABASE_URL=""` is a value the source found, and whether
  empty is legal is the cast's business — because App Platform can
  inject an empty variable and "unset" and "set to nothing" deserve
  different lines in the report.

  **The boundary this draws, said plainly:** the port's domain is
  flat, string-valued, named settings arriving over some transport
  other than the environment. A document with nested structure and
  lists of maps is not a config source in this sense at all — it is
  content, and it belongs in `config/*.exs` or in a real document
  loader. That is precisely where Vapor is the right answer and this
  port is not, and the non-goal entry is written to that line rather
  than to a claim that the port handles everything.
- **One source, never several merged.** The layer takes exactly one.
  Vapor's loader `Map.merge`s provider results, so two providers
  offering one name silently pick a winner — already the reason it is
  not a dependency, and it would be no better for being our own code.
  The case that would force layering is real, so it is named here to
  be recognised rather than rediscovered: secrets from a mounted file,
  everything else from the environment. When it arrives, layering is
  either per-declaration source selection or an ordered list **whose
  overlaps are a reported problem** — the discipline the composer
  already applies to queues and topics, applied to transports — and
  never a merge. Until then provenance is trivial: every value came
  from the one place, and no report needs a field to say which.
- **Refresh and watch are questions about the accessor, not about the
  port** — the second half of what design review asked. A remote
  source (Vault, Parameter Store, Consul) fits `load/2` today,
  unchanged: one round trip at boot for every name at once is what a
  remote is best at, and "unreachable" is exactly the `{:error, _}`
  the file source proved was load-bearing. What a remote cannot do
  through this port is push, and that limitation is not the port's to
  fix. `docs/non-goals.md` records load-once; the thing actually
  standing between us and watching is the accessor's contract —
  `:persistent_term`, written once before the supervisor starts, read
  by callers who may hold what they read. A source pushing into a
  store nobody re-reads has changed nothing.

  So the growth path, named at its real size. The *port* takes it as
  `@optional_callbacks watch: 2`, which the environment and static
  sources decline and the layer guards with `function_exported?/3`:
  that part genuinely is one module and one line, and it is the answer
  to "does the shape fit." What is not one line is what the accessor
  then owes — a re-validation path that can **reject** an update
  without taking the node down (a boot report may exit; a running
  node's may not), a rule for the process holding a value it read a
  minute ago, and atomicity for two values that must change together.
  Four decisions and a supervision tree: a ticket, not a refactor, and
  nothing in this shape prejudges any of them. The nearer cousin —
  a source needing to be a running process merely to *load*, a remote
  with a connection pool — is smaller still and changes the call site
  rather than the port: the layer would start the source under a
  bootstrap supervisor before calling `load/2`. One place, recorded
  here so it is not met as a surprise.
- **The config source is chosen at compile time, because it is the
  bottom turtle.** v5 §2.12 has every external's real-vs-fake
  selection ride config; config's own source therefore cannot, since
  reading an environment variable to decide whether to read
  environment variables is the circle it looks like. The source is an
  `Application.compile_env` choice: the shipped environment source in
  every real build, the static fake in test — the same shape as the
  clock, and for the same reason.

  **The selection carries the source's own settings, and that is the
  one bounded exception to "one reader of the environment."** A
  source's configuration cannot come from the config layer without
  reintroducing the circle, so it rides the compile-time value as a
  tuple — `{Catapult.Config.Static, %{"DATABASE_URL" => "ecto://..."}}`,
  `{Catapult.Config.File, path: "/etc/app.toml"}` — and lands as
  `load/2`'s `opts`. If some future adapter's own setting genuinely
  must be dynamic (the path of the file to read), the adapter reads it
  from the environment itself, below the layer. That is legitimate and
  it is the only such read: a source's bootstrap, never a component's
  value, which is the whole of what the layer was built to own.

  The static fake's seeded map is exactly this `opts`, keyed by name
  and valued with strings like any other source, which is why the fake
  needs no special case anywhere in the layer — and why a test seeds
  `"10"` rather than `10`. Seeding post-cast values would be the
  obvious convenience and it is the wrong one: it would leave every
  declared cast unexercised by every test that is not about casts,
  which is most of them.

  **Dev selects the static source too, and that is what settles
  `.env`.** v5 §2.2 sketched per-component `.env` files alongside
  prefixed env vars; they are not built, and the reason is that a
  dotenv file exists to feed environment variables to a process that
  reads the environment. Dev does not: its values already live in
  `config/dev.exs`, in the file a developer edits, under review, with
  no untracked local file to explain when someone's machine behaves
  differently from everyone else's. The environment source is what a
  deployment runs, which is where variables actually come from
  something other than us. **The fake is not a hole:** the static
  source validates its map against the same declarations — a missing
  key or a value that fails its cast is the same report — because a
  source that skipped validation would let a key enter the system
  undeclared, and the declaration is the whole product here.
- **The fake ships in `lib/`, not in `test/support/`.** Conventions §9
  says the fake ships with the port; for a package the sharper form is
  that it ships in the package. `test/support` is compiled only in
  this project's test env and is absent from the hex tarball, so a
  fake living there is a fake every generated project has to write
  again — and writing it again is exactly how a test ends up reading
  real env, which is the rule the fake exists to keep.
- **Vapor is not a substrate dependency.** The ticket's open question,
  answered against the placement this doc previously assumed (see
  *Depends on*). Measured rather than asserted: `vapor 0.10.0` — the
  current release, dated 2020-08-12 — declares `jason`, `norm`, `toml`
  and `yaml_elixir` as ordinary runtime dependencies, so adopting it
  here puts a TOML parser and a YAML parser (`yamerl`, in turn) into
  the release of every project Catapult generates, in order to read
  environment variables. Substrate has three runtime dependencies
  today. The same argument that kept `mix_audit` out applies with the
  numbers larger: a dependency substrate declares is a dependency
  imposed on trees we do not own, and this one is dormant, which
  matters concretely now that `hex.audit` is armed — an advisory
  against `yamerl` would need a release from a project that has not
  cut one in six years, and the acknowledgement machinery in the
  root's `mix.exs` is what that looks like when it happens.

  **And the residue is thin.** Once the casts are ours (they must be),
  the aggregation is ours (Vapor drops it at the first raise), the
  store is ours (0.10 ships no store), the provenance keying is ours
  (Vapor's loader `Map.merge`s provider results, so two components
  binding the same key name silently pick a winner) and the file and
  dotenv providers are unused (12-factor: the environment is the
  source), what Vapor contributes to the path we actually need is
  `System.get_env/0` and a struct. Substrate therefore ships an
  environment source with no dependencies at all, and the plane runs
  that same source — which is the property that matters most, because
  Catapult being substrate's first consumer is how the shipped path
  gets exercised, and a plane on a Vapor adapter would leave the
  path every generated project runs as the one nobody runs.

  **This is a scoping of conventions §1's blessed list, not a
  substitution, and the sketch says so out loud** (§1: don't
  substitute without a systems-doc decision — this is that decision).
  Vapor remains the sanctioned answer the day a project needs config
  from a file, a remote source, or a format the environment cannot
  carry; nothing here needs that, and the port means adopting it then
  is one new module and one compile-time line, not a migration.

  **The second pass split that sentence in two, because the port
  demonstration showed it was true of only half of it.** A flat file
  or a remote parameter store *is* one module and one line: it answers
  `load/2` with named strings and every other decision in this layer
  stands. A format the environment cannot carry — a nested document,
  lists of maps — is not an adapter behind this port at all, and
  pretending otherwise is how a port ends up with a `term()` value
  type and casts that accept two shapes. That case is a different
  problem which happens to share the word "config", and Vapor as an
  ordinary library in the consumer that has it is a better answer than
  Vapor squeezed through this seam. Saying which half is cheap
  matters more than saying it is cheap: the reversal the author was
  promised is real for the transports, and the case it does not cover
  is one this platform has never had. It is
  also what makes this whole entry cheap to reverse: the placement
  question is decidable by the author without redesign, because the
  port is the decision and the adapter is not.
- **The gate set is a property of a mix project, not of the repo.**
  The audit's greps are `Path.wildcard("lib/**/*.ex")`, rooted at the
  working directory — deliberately, because this task ships into
  every generated project and the shape of *this* tree is not a fact
  it may hold. The consequence is the rule: every mix project here
  runs the whole conventions §2 set in its own directory, and adding
  a mix project means adding its gate block. Stated as the whole set
  rather than as a list, so a gate added to §2 later is in scope
  without anyone re-enumerating — which is how `xref` (never named
  in the ticket) and `hex.audit` (added to §2 by ORC-37 after the
  ticket was written) are both covered. In the substrate the greps
  are the entire value of the run: it declares no components, so the
  composer check validates an empty list and the audit is exactly
  its two greps there.

  **The invoker that names both projects lives in the root
  `mix.exs`,** as a `catapult.audit.all` alias running
  `catapult.audit` and then `cmd --cd components/substrate mix
  catapult.audit`. This is not the cross-project reach ruled out in
  `docs/non-goals.md` and the distinction is the point: the shipped
  task stays cwd-rooted and layout-ignorant, while knowledge of
  where *this* repo keeps its components sits in this repo's own
  `mix.exs` — AGPL plane code that never reaches a hex consumer and
  whose literal job is knowing the project's layout. The audit is
  the one gate that earns an invoker, because it is the only one
  whose absence is invisible: `mix credo` at the root plainly checks
  the root, while `mix catapult.audit` at the root reads as though
  it audits the repository and does not. That asymmetry is this
  ticket's bug, and a third mix project would reproduce it silently
  against a convention held only in memory. Two costs, both
  accepted. The alias does not collapse the substrate CI block —
  substrate must still run its own `deps.get` before anything
  resolves there, verified: with `components/substrate/deps` absent
  the alias dies on dependency resolution. It dies loudly, exit 1,
  which is the property that matters — an invoker that skipped a
  project it could not resolve would be the fail-open this ticket
  exists to close. And the second leg's failures print
  substrate-relative paths (`lib/catapult/clock.ex:3`) with nothing
  marking which project they came from, which is the very confusion
  the stale file map caused. If that is worth fixing, it is fixed in
  the task by naming the directory it audited — layout-ignorant, and
  true in every generated project — never by the alias annotating
  output it does not own.
- **`catapult:allow` spans one line or two, and marks code, never
  prose.** *(Amended in implementation, ORC-30 — the sketch said
  same-line only; see below.)* The tag is honored on the matching line
  or on the comment line directly above it, and on no wider span,
  because any wider one asks each reader to work out how far a given
  escape reaches and an escape whose extent is arguable is worse than
  none. The line above must itself be a comment, or a tagged violation
  would excuse an untagged one on the next line.

  **Why not same-line only, as drawn:** `mix format` relocates *every*
  trailing comment onto its own line above — verified across statement
  position, `def ..., do:` heads, list, map and argument elements, with
  no form found that survives. Since `mix format --check-formatted` is
  itself a hard gate with no escape of its own (conventions §2), a
  same-line-only rule is a hatch that no file in a formatted tree can
  hold, and the two gates would simply contradict each other. This also
  re-reads the evidence the sketch built on: `clock.ex`'s tag sits one
  line above the code it excuses not because the hatch was unexercised,
  but because the formatter put it there. That the gap was invisible
  from inside stands — the tag was written for a check that never
  looked at the file — but the placement was never the tell.

  **Documentation that names a banned construct is reworded, not
  tagged:** an allow tag asserts "this occurrence is a deliberate
  exception", and spending it on a sentence *about* the ban degrades
  the one signal review has, in a package whose docs get published.
  This half of the decision is unchanged. The cost is real and accepted —
  the clock's moduledoc and the audit's own cannot spell the
  construct they forbid. Turning the gate on was therefore not free:
  the substrate audit failed on five hits, and four of them were
  prose — the clock's moduledoc and three lines of the audit's own
  moduledoc and messages — reworded rather than tagged. The fifth was
  `clock.ex`'s runtime `utc_now`, the single legitimate exception,
  whose tag was already correctly placed under the amended rule.
- **The supply gate is Hex-sourced; `mix_audit` is a second opinion,
  not the signal.** `mix deps.audit` reads a third-party git mirror
  (`mirego/elixir-security-advisories`) cloned at run time and
  matched by package name and version range, and it disagrees with
  Hex on the tree we actually ship — verified against cowlib 2.19.0,
  three independent ways. The mirror's range for GHSA-g2wm-735q-3f56
  stops at `<= 2.16.1` where the advisory itself says "affects from
  2.9.0" with no patched release; GHSA-w4f7-4cxr-rv3c is filed there
  under `gun`, so a cowlib dependency never matches it; and when the
  clone fails, `MixAudit.Repo.synchronize/0` discards the `git` exit
  status, globs an empty directory, prints "No vulnerabilities
  found." and exits 0. That last one is the reason for this decision:
  a gate whose failure mode is a clean report is worse than no gate.
  `mix hex.audit` is a built-in Hex task — no dependency to add — it
  exits 1 on findings, and its data rides the registry fetch that
  `deps.get --check-locked` already requires, so a fetch it could not
  perform fails the build earlier instead of passing here. Both run;
  only the Hex one is load-bearing. **Retirement is Hex's alone** —
  `mix_audit` has no retirement check at any version, so the gate set
  did not cover retired packages until `hex.audit` joined it.
  Accepted residue, named so it is not rediscovered: an advisory that
  reaches the GitHub database and not Hex's feed, on a run where the
  mirror clone also failed, still reports clean.
- **An advisory we cannot act on is acknowledged in `mix.exs`, never
  absorbed by a blind gate.** Arming a Hex-sourced gate against a
  tree with two unpatched cowlib advisories fails every build until
  upstream ships a release we do not control, so the gate needs a way
  to say "seen, and nothing to do yet": Hex's
  `hex: [ignore_advisories: [...]]`, listing advisory IDs, which
  prints them under *Ignored advisories* and exits 0. The exit code
  matches today's; the epistemic status does not, and that is the
  entire change — "No vulnerabilities found." becomes a named list
  with an author behind it. It stays honest in both directions: an
  advisory that is not on the list still fails the build, and an
  entry matching nothing in the lockfile warns that it can be
  removed, so the acknowledgement expires by itself the day the
  dependency is bumped. Acknowledgements are per-ID and never
  per-package — ignoring `cowlib` wholesale would re-blind the gate
  to the next advisory against it, which is the failure this
  decision exists to prevent.
- **Substrate carries its own supply gate and never takes an audit
  dependency to get one.** It resolves its own lockfile, so the
  root's audit does not cover it — the versions coincide today, which
  is luck rather than a property, and nothing would report the day
  they diverge. It is Apache-2.0 and ships into generated projects
  (`LICENSING.md`), so a dependency added here lands in every tree
  built from it; `hex.audit` needing nothing in `deps` is precisely
  what makes the gate affordable at this end.
- **The license check reads declarations, never paths — and it takes
  two of them, because the two questions have different subjects**
  (ORC-16). Dependencies are a *mix project's* fact: one lockfile, one
  `deps/`, one working directory the audit runs in. Distribution class
  is a *component's* fact: how that code reaches the people who use it.
  Neither declaration substitutes for the other.

  - `package: [licenses: [...]]` in `mix.exs` — what this **project**
    conveys. A project with a package block is fetched by somebody, and
    being fetched is what conveyance is.
  - `licensing/0` on a **component** — `distribution:` and `license:`,
    below. It refines the project's policy and is checked against
    itself.

  A project's dependency policy is the **strictest** among its own
  declaration and every component it composes, because the dependency
  tree is shared: nothing offline can attribute `plug` to one component
  rather than another, and any attribution that tried would be a guess
  running in the permissive direction.

  **Why both, measured rather than reasoned.** `components/substrate`
  declares no components at all — the repo's only `use
  Catapult.Component` is `Catapult.Foundation`, in the plane's `lib/`,
  registered by the *root* project's config. Substrate ships the
  mechanism, not components that adopt it. A check armed solely by
  component class would therefore read the one tree ORC-16 was filed
  about, find no subject, and report clean: the failure mode ORC-37
  spent a whole ticket on. `package:` is what covers a library that
  ships mechanism, and it is the one declaration nothing that ships can
  forget — `mix hex.build` in `components/substrate` today exits
  `Missing metadata fields: description, licenses, links`.

  **What neither of them is, is a path.** `docs/non-goals.md` rules out
  teaching this task where *this* repository keeps its components, and
  ORC-16's own "for every mix project under `components/`" is that
  reach in its purest form. Since the review it is not even a true
  description of the tree: `components/*` will hold components that are
  not open source at all, so the directory now answers a question
  nobody asked it. The concrete consequence, landing with the check:
  substrate gains `package: [licenses: ["Apache-2.0"]]`, which *is* the
  arming, plus the `licensing: [allow: [...]]` list it is held to, and
  `LICENSING.md` gains the classification section and loses
  `components/*` from its ladder bullet and its path rule. One more
  edit there after the third pass: the ladder's "Test" bullet describes
  a check held to *the project's stated list* rather than to a
  permissive allowlist of the tool's, and names substrate's `allow:`
  entry as the machine-readable form of the five identifiers this
  document already argues for. `LICENSING.md` is where Catapult's own
  policy belongs; the list is that policy in a form the audit can read.

  **Arming and standard are two facts, and the third pass separated
  them.** `package:` and `licensing/0` decide *whether* a tree is
  checked; the project's `allow:` list decides *against what*. A
  project that arms the check and states no list is inert rather than
  held to ours (below), so the pair is not redundant — a declaration
  can arm a check that then has nothing to measure with, and the census
  line exists to say exactly that.
- **`licensing/0` is one callback carrying both facts, and it sits
  outside the roster table beside `config/0`** (ORC-16). It returns a
  keyword list — `[distribution: :distributed, license: "Apache-2.0"]`
  — with both opts required, an overridable empty default, and no
  `@optional_callbacks`; that rule is untouched.

  **One callback, not two,** because the facts are only meaningful as a
  pair. A license says nothing about obligation until you know who
  receives the code; a class says nothing about terms. It is also the
  roster's own grain applied to a subject that already has an address:
  the address is positional and everything said *about* it is opts, the
  component *is* the address, `slug/0` spells it, and licensing is the
  opts tail and nothing else. Two callbacks would also manufacture two
  half-declared states that mean nothing and have to be reported
  anyway.

  **Outside the table** for `config/0`'s stated reason and one more.
  The extra one: it claims no name. Two components declaring
  `Apache-2.0` is the ordinary case rather than a collision, so the
  `:claim` and `:identity` columns — the reason the table exists — sit
  empty, and the fold over `rows/0` grows a row it must skip. That is
  the `function_exported?/3` guard the no-optional-callbacks decision
  refused, wearing a hat: an aggregation that is total is one that
  cannot silently miss a component. `config/0`'s own reason then
  applies unchanged — a consumer, and error messages worth their
  specificity, which "your `:distributed` component declares
  `AGPL-3.0-only` for itself" is and no uniform table report could be.
  One shape hazard, named so the next pass does not walk into it: a
  keyword list *is* a list of two-tuples, so a table-driven aggregator
  reads one declaration as two entries, and holding it in the table
  would mean teaching `split/2` a no-positional-fields spelling.
- **The class chooses between two dependency policies, not three, and
  the reasons differ where the list does not** (ORC-16). The review
  named four cases; they collapse to two policies — *checked* against
  the project's list, or *unchecked* — and the collapse is what makes
  "strictest wins" a total order rather than a merge.

  | The subject's own terms | How it reaches people | Dependencies | Because |
  | --- | --- | --- | --- |
  | on the project's list | conveyed (`:distributed`, or a published `package:`) | **checked** | a recipient would inherit terms nobody offered them |
  | `LicenseRef-*` | conveyed | **checked** | we would be conveying a work under terms we have not met |
  | on the project's list | `:service` | unchecked | we offer source on those terms, so nothing a dependency asks is a cost already unpaid |
  | `LicenseRef-*` | `:service` | **checked** | AGPL §13 would oblige an offer of source to our own users |
  | any | `:internal` | unchecked | nothing is conveyed and nobody is served |

  **The check reads two things off a license identifier and infers
  nothing else, and that is what removed a row.** The second pass's
  table carried *public copyleft, conveyed → unchecked*, on the true
  observation that a recipient of an AGPL work has already accepted
  every term a dependency could add. It never said how the check
  recognises copyleft, and with a list compiled into the check the
  omission was survivable — "a listed identifier that is not one of our
  five" was copyleft closely enough, because we owned both sides of the
  comparison. A project-stated list ends that. The residue of someone
  else's list is not copyleft; it is whatever that project did not
  write down, and reading it as copyleft leaves the tree **unchecked**
  — an inference running in the permissive direction, which is the one
  direction this check may not fail in, and the same inference the
  no-normalization decision below refuses in the same words.

  What replaces the row is stricter and more legible than the row was:
  a project that conveys under copyleft says so by putting its own
  identifier on its own list, and its dependencies are then checked
  against a list containing it. The self-check still passes (a subject
  is held to the standard it holds its dependencies to, unchanged), the
  whole arrangement is readable in one file, and the case the old row
  passed in silence — `GPL-2.0-only` inside an `AGPL-3.0-only` work, a
  real incompatibility — now fails. Nothing in this repo sat on that
  row either way: the plane is `:service`, substrate is `Apache-2.0`
  conveyed.

  So an identifier is `LicenseRef-*`, or it is on the project's list,
  and there is no third bucket. **An identifier in neither is a
  reported problem**, wherever it is a subject's own declaration —
  `:internal` included, where it decides nothing about dependencies and
  is still a declaration the project's own policy cannot place. That is
  what stops `license: "Proprietary"` from reading as an open-source
  identifier and taking the unchecked branch.

  One consequence, named because it reads as a bug the first time: a
  project's `allow:` list contains its own license too, even where
  nothing is checked — a plane that states a policy at all lists
  `AGPL-3.0-only` beside identifiers no dependency will ever be
  measured against. That is the self-check and the bucket rule being
  one rule instead of two, and it is what the list means read plainly:
  *the terms acceptable in this tree*, ours included. A project that
  would rather not answer states no policy and is inert.

  **"Ours" and "proprietary" are read off the identifier, not declared
  again.** SPDX already spells "no listed license applies":
  `LicenseRef-<id>`. So a `:service` component under
  `LicenseRef-Catapult-Hosted` is the closed case and one under any
  listed identifier is the open one, with no third class and no
  `proprietary: true` beside a license that already says so — two
  places to state one fact are two places that can disagree.

  **The list is shared; the reason is not, and the report prints the
  reason.** Shared now means one list per project rather than one list
  per platform, and the sharing is what the argument rests on either
  way. This is the distinction the review asked to get into the
  sketch, made structural rather than remembered: a proprietary
  `:service` component failing on a GPL dependency must not read as a
  shipped-layer failure, because nobody receives that component and the
  allowlist protecting recipients is not what is being enforced. Its
  line says AGPL §13 and an offer of source to our own users. Applying
  the shipped-layer allowlist with the shipped-layer *reason* to a
  hosted-only component is not conservative, it is wrong, and a report
  that says which reason armed it cannot make that mistake quietly.

  **The strict row ships as drawn, and configurability is what makes it
  cheap.** Design review took the second pass's push-back: proprietary
  `:service` is held to the same list as the shipped layer rather than
  to "no copyleft", so `MPL-2.0` and `EPL-2.0` are outside that row
  until a project's list says otherwise. The argument that carried it
  is kept where the next pass will look for it — "everything except
  copyleft" cannot be enumerated, so a denylist would have the check
  deciding the copyleft-ness of identifiers it has never seen, which is
  the inference the paragraph above just removed a row to avoid. What
  used to be the standing cost of that strictness is now an entry in a
  list the project owns.
- **A subject is held to the standard it holds its dependencies to,
  and silence is reported rather than defaulted** (ORC-16). The two
  decisions the review left to this pass, and they resolve together.

  **Its own license is checked by the same rule.** A `:distributed`
  component declaring `AGPL-3.0-only` in a project whose list does not
  contain it is the defect one level up and strictly worse than a
  copyleft dependency: a dependency is one package a consumer could
  route around, and the component *is* the thing shipping. It is free
  because it is not a second predicate — the same list, with the
  subject's own identifier in place of the dependency's — and it is why
  the table's first column reads "the subject's own terms" rather than
  "the component's".

  The third pass sharpened rather than softened this. With the list
  now the project's, the self-check says something a platform-wide list
  could not: *you are shipping under terms you would not accept from a
  dependency in this tree*. That is a contradiction inside one file
  rather than a disagreement with Catapult's opinion, which is both a
  better verdict and one a generated project can act on without
  arguing with us.

  **An undeclared component is a reported problem, never a default
  class.** `:distributed` is the safe default for the dependency half
  and there is no safe default for the other half: no license a
  component "probably" carries, and a defaulted class paired with an
  absent identifier makes the self-check above a verdict about nothing.
  A pair whose halves cannot both be defaulted has no default. The
  deciding argument is the second one, though: a default makes every
  project's audit print a policy verdict nobody asserted, which is a
  check that passed without checking anything — the exact shape this
  ticket exists to remove from the ladder. The cost is bounded and
  one-time (one callback, two facts, on a module that already declares
  a slug, with every missing one reported at once) against an unbounded
  alternative where the first component whose class was assumed wrong
  is discovered by counsel. Note what this is *not*: it is not a
  compile-time requirement and not a boot failure. The empty default
  keeps `use Catapult.Component` sufficient to compile, exactly as
  `errors/0`'s required `remedy:` does, and the absence surfaces where
  every other structural absence does.
- **A licensing verdict never fails a boot** (ORC-16). The composer
  validates the declaration's *shape* — unknown opt, missing opt, a
  `distribution:` outside the vocabulary — because that is what it does
  for every other declaration and it needs no environment. The
  *policy* — the project's list, the closure, the undeclared report —
  is the audit's alone. This is the "two reports at two times" line drawn
  along a second axis, and the reason is blunt: a production node
  refusing to start because a transitive dependency's license string is
  unrecognized is a catastrophic response to a question with no runtime
  consequence whatsoever. CI red is the correct severity for a legal
  fact; a node that will not boot is not.
- **The predicate is ours; the list is the project's** (ORC-16, third
  pass — design review's reversal, and the reason it is not the waiver
  the entry below still refuses). The criterion is unchanged and stays
  ours: not "permissive" but *imposes no terms on the linking
  application*, which is what `LICENSING.md` actually requires — a
  customer's application inherits nothing — and what makes an addition
  decidable instead of a debate about what "permissive" means. What
  changed is whose list the criterion produces.

  `Catapult.Audit.License` ships into every generated project. Five
  SPDX identifiers compiled into it is Catapult's legal position
  imposed on codebases we know nothing about, and a project that needs
  `MPL-2.0`, `EPL-2.0`, `Zlib` or `Unicode-3.0` is not evading a gate —
  it is enforcing its own. That is a **policy difference**, and the
  line keeping it clear of the waiver is the review's: a policy is
  stated once, applies uniformly to every dependency in the tree, and
  is reviewable *as* a policy, where a waiver is stated per dependency
  and is read only by whoever added it. The check acquiring a different
  subject is not the check being switched off.

  **The project states it in `mix.exs` beside `package:`**, under one
  `licensing:` key carrying the policy and the overrides together:

  ```elixir
  licensing: [
    allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC),
    overrides: [cowboy_telemetry: "Apache-2.0"]
  ]
  ```

  For the three reasons the overrides landed there: it is where a
  project already speaks to mix, it puts both facts under one review,
  and it spares a task that ships everywhere a path convention of its
  own. Measured rather than assumed, because an unrecognized key in
  project config is exactly the kind of thing that turns out to warn:
  a `mix new` project with this key added compiles clean and
  `Mix.Project.config()[:licensing]` reads it back verbatim — the same
  door `:docs` and `:dialyzer` come through, and the audit already
  reads `Mix.Project.config()[:app]`.

  **One list per project, not one per class** — a push-back on the
  review's wording, small and reversible. Dependencies are a mix
  project's fact, which is the whole reason `package:` is what arms
  this check; a list per class would leave a project composing a
  `:distributed` component and a proprietary `:service` one resolving
  to the *intersection* of two lists over one shared `deps/`. That
  turns strictest-wins from a total order back into a merge whose
  result is written in no file and citable in no report — the defect
  the one-source config decision above refuses by name. A project that
  genuinely needs two policies needs two dependency trees, which is two
  mix projects, which is what it already had to be. Say so if you would
  rather the list were keyed by class.

  **A project stating no policy is inert, and the census line says so.**
  Not defaulted to ours: a default makes every project's audit print a
  policy verdict nobody asserted, which is the undeclared-component
  ruling one level up and the same sentence. Not a failure either — a
  project that states no policy has declined the check, in one visible
  place, and the census line naming the absence on every run is what
  keeps declining from being silent. The seam a reader should worry at
  is named rather than left to be found: deleting the `allow:` list
  disarms the gate. It disarms it in a diff, in the file `package:`
  lives in, under one review, and every run afterwards says on stdout
  that nothing was checked — which is more than any of the waiver
  shapes below would have offered.

  **The default value lives where projects come from, not in the
  check.** Catapult's five — `Apache-2.0`, `MIT`, `BSD-2-Clause`,
  `BSD-3-Clause`, `ISC` — are what `bundles/platform-elixir` writes
  into a generated project's `mix.exs`, literally, so the project can
  read what it is being held to and edit it. Never `allow:
  Catapult.Bundle.default_licenses()`, which is the constant one level
  in and the path rule wearing a different hat. `bundles/` does not
  exist yet, so the obligation is recorded in
  `systems/platform_content.md` where the layer's own ticket will find
  it, and substrate states its five by hand today — as it must in any
  case, not being a generated project. ISC is not decorative there:
  cowboy, cowlib and ranch are all ISC (measured), so the first shipped
  component that serves HTTP lands on it.

  ORC-16 named "ERLPL where applicable", and it is applicable nowhere:
  measured across both trees today, every dependency is Apache-2.0, MIT
  or ISC. `ErlPL-1.1` and `MPL-2.0` do satisfy the predicate —
  file-level copyleft binds the files it covers, not the work that
  links them — but their residues differ from each other in patent and
  disclosure terms, and a residue is worth reading against a package a
  reviewer can open rather than accepted in the abstract. Design review
  accepted the deferral, and configurability is what makes it cheap:
  the day a real dependency asks, the answer is a line in one project's
  `allow:` list rather than a release of this package.

  **What the check honestly claims** is that no dependency in a checked
  tree *declares* terms nobody accepted. That is not verification — hex
  metadata is the publisher's own assertion, and the counsel pass
  `LICENSING.md` schedules is what verification means. Saying so is the
  difference between a rung on the v5 §4.5 ladder and a gate that
  flatters itself; what it buys is noticing, at merge time, cheaply,
  forever.
- **An override supplies a fact; nothing supplies a permission**
  (ORC-16). A dependency whose license the metadata cannot answer — no
  `hex_metadata.config` at all, or a spelling the list does not contain
  — is resolved by an entry in `mix.exs` naming the license a human
  read out of that package's own LICENSE file. It is then checked like
  any other: an override recording `GPL-3.0-only` fails the audit
  exactly as the metadata would have.

  There is deliberately **no ignore list, no `catapult:allow` reaching
  this check, and no per-dependency waiver.** The project-stated
  `allow:` list above is not the exception it can be mistaken for, and
  the two are worth holding side by side because they are the same
  keyword list: `allow:` says *these terms are acceptable in this tree*
  and every dependency is then measured against it, while a waiver
  would say *this dependency is measured against nothing*. One is a
  statement a reviewer can disagree with once; the other accumulates,
  is argued once and inherited forever, and turns a verdict into a
  negotiation. The fix for a copyleft dependency is not taking the
  dependency. The asymmetry with
  `ignore_advisories` above is the whole argument: an advisory is
  imposed on us by the world and often has no action until an upstream
  we do not control ships, whereas nobody imposes a dependency on
  anyone — it is the one supply-chain fact that is wholly our own
  choice. A hatch here could only ever be spent breaking the rule
  `LICENSING.md` calls the most important one in it. Same line
  `external: true` draws, for the same reason: an escape exists where
  an outside party imposes something on us, and nowhere else.

  **Licenses match as exact SPDX identifiers, with no normalization
  table and no reading of LICENSE text.** The cost is measured and, as
  of this pass, zero: every dependency in substrate's checked closure
  declares a clean identifier, and the near-miss in this repo —
  `cowboy_telemetry`, which declares `["Apache 2.0"]` — sits in the
  plane's tree, which the table above leaves unchecked. So no override
  exists on landing; the mechanism exists because the first one will be
  a sentence in a diff rather than a silent coercion. A normalization
  table is the cheaper fix and the wrong one: its failures are silent
  and biased permissive, and teaching a reader that near-misses are
  handled invites the next one, which is a string like
  `GPL-2.0-with-classpath-exception` whose distance from `GPL-2.0-only`
  is the entire question. Text inference is the same defect with a
  bigger surface — a fuzzy match over prose deciding a legal question,
  with no line in the diff where a human agreed. Overrides live in
  `mix.exs` rather than in the data file ORC-16 named — `licensing:
  [overrides: [...]]`, the same keyword list the policy sits in, which
  is the placement the third pass made general rather than an exception
  carved for one field.
- **Scope is what a consumer would fetch, computed from metadata
  already on disk** (ORC-16). The in-scope set is the transitive
  closure over non-optional `requirements` in each dependency's
  `hex_metadata.config`, seeded by the project's own deps that survive
  into `:prod`. Measured in substrate: 5 packages in scope of 8 on disk
  — plug, mime, plug_crypto, telemetry and jason, all `Apache-2.0`,
  while credo, bunt and file_system are dev/test only and reach no
  generated project. Excluding them is not laxity; it is what makes "no
  exceptions" affordable, because a rule that failed the build over a
  linter's license would need a hatch inside a month and the hatch is
  what the entry above refuses.

  Two format facts, both measured, because the naive read of either is
  a wrong answer that looks right: `requirements` has two encodings — a
  flat proplist carrying `name` from mix-built packages, and a
  `{name, proplist}` tuple from rebar-built ones such as cowboy — and
  an entry may be `optional`, which makes it the consumer's dependency
  rather than ours, as `jason` declares `decimal`.

  **`mix.lock` is not the source, and an absent package is a problem
  rather than a skip.** The lock carries names and checksums and no
  license at all; the metadata file carries the license, the version and
  the requirement graph, and sits beside the code whose terms are in
  question. A dependency in scope with no directory or no metadata is
  reported, never passed over — the reason `catapult.audit.all` dies
  loudly on unresolved deps instead of skipping the project, and the
  reason ORC-37 existed. Offline throughout: `:file.consult/1` over
  files `deps.get --check-locked` has already placed, so conventions
  §9's no-network rule reaches the audit without an exception.
- **The check is a built-in of the task, in its own module, and is not
  a `Catapult.Audit.Check`** (ORC-16). `Catapult.Audit.License` holds
  the table, the closure and the report, because the audit is a check
  registry rather than a monolith and this check is larger than both
  greps together. What it holds no part of is the list of identifiers:
  the table is a rule about how code reaches people and stays ours, the
  list is a legal position and belongs to whoever is being held to it,
  and a module shipping into every generated project may carry the
  first and not the second. It does not adopt the behaviour, and the
  next pass should not make it: that callback takes a
  working-directory-relative glob, a dependency tree is not a path
  scope, and forcing it through means passing a scope value meaning
  "ignore this argument" — a callback lying about its contract in its
  first implementation.
  `policies/0` is how a *component* ships a check into projects that
  adopt it; this one is the task's own, present in every project and
  armed or silent by declaration.

  **The inert state is never silent.** The check adds a census line
  naming the policy it reached, the subject that set it, and where the
  list came from — armed by substrate's own `Apache-2.0` package
  against the five identifiers its `allow:` states, or unchecked
  because every subject is a public-licensed service, or inert because
  the project states no policy at all. That third state is the one the
  configurable list creates and the only one that could be mistaken for
  a pass, which is why it is on stdout of every green run: a gate whose
  failure mode is a clean report is the thing ORC-37 was filed about,
  and "inert" is that report.

  **It arms green, and that is the point.** Every dependency in every
  checked tree passes today, so the check finds nothing the day it
  lands. That is what a ratchet is, and it is the only moment arming is
  free: the rung `LICENSING.md` files as "Test (planned)" costs one
  review now and nothing afterwards, where the same rung added once a
  copyleft dependency is in costs the dependency.

### The enforcement roster (ORC-21)

The checks v5 §2.14 gathered as sleepers, designed as a set because
three of them turn out to be the same decision and two of them are not
build work at all.

- **The AST upgrade lands on `Catapult.Audit.Check`, not on Credo.**
  §2.14 adopted "AST-grade custom Credo checks", and this argues with
  the host rather than the grade — said out loud, per the rule about
  recorded decisions. Credo cannot host them without a cost this
  package has already refused three times. `Credo.Check` is a
  `__using__` macro, so a check module compiles only where Credo is
  loadable; `Mix.Dep.Loader` loads a dependency's own children with
  `env: :prod`, so substrate's `only: [:dev, :test]` Credo is never
  fetched into a consumer's tree, and a check in `lib/` would fail to
  compile there. Both ways out are worse than the thing they buy: a
  Credo dependency in every generated tree, or a fourth mix project and
  a second package on the release train.

  Meanwhile the mechanism these checks want shipped last ticket.
  `policies/0` registers a `Catapult.Audit.Check` against a
  working-directory-relative scope, and the runner is this roster's; a
  target project inherits exactly the checks its components declare,
  which is the whole argument for that registry. Hosting the platform's
  own checks anywhere else would give `catapult:allow` a second
  implementation one ticket after it got its first — the two-homes
  failure the registry idiom exists against, and the reason this is one
  decision rather than a preference.

  **The cost is IDE surfacing, and it is real:** a Credo check
  underlines in the editor where an audit finding waits for CI. The
  reversal is what makes that affordable, so it is priced rather than
  promised — a Credo check that delegates to `run/1` is a wrapper in
  whichever project wants one, and no logic moves. What the wrapper
  needs is a parseable report, so the format joins the contract instead
  of remaining a habit: a problem that names a location spells it
  `path:line: message`, which is what the greps already emit.
- **`catapult:allow` reads a comment the parser found, and an escape
  that excuses nothing is itself a problem.** This is what §2.14 means
  by "a real mechanism rather than same-line text", and it is smaller
  than it sounds: the tag stays in a comment, because the violations
  are lines inside function bodies and there is nowhere else for a
  line-grained escape to live. What changes is who reads it.
  `Code.string_to_quoted_with_comments/2` yields comments with their
  line numbers, so the tag is matched against a comment rather than
  against a substring of a source line — which fixes the symmetric half
  of the bug the AST grade was adopted for. A ban that no longer
  false-positives on a string literal must also stop honouring an allow
  tag written *inside* one, or the escape becomes the new false
  positive. ORC-30's span survives untouched (the offending line, or
  the comment line directly above it) because comment line numbers are
  exactly what that span was always about.

  The new half is free only at AST grade and worth taking there: a tag
  excusing a line with no violation is reported. An escape list nobody
  prunes is how the next reader learns the ban is negotiable, and this
  repo has already chosen that shape once — Hex warns that an
  `ignore_advisories` entry matching nothing can be removed, so the
  acknowledgement expires by itself. Same property, same reason.
- **The compile-connected ratchet is a gate line, never a constant the
  audit reads.** Both halves of §2.14's xref item are stock:
  `mix xref graph --label compile-connected --fail-above N` exits 1
  above the threshold with no code behind it, so an audit check would
  be a second implementation of a number `mix xref` already computes.
  The placement is the decision, and this pipeline decides it rather
  than taste: a cap in `config/*.exs` or in the audit is a cap the
  agent adding a compile dependency can raise in the same commit that
  made it necessary, and a ratchet the ratcheting party can turn is not
  one. In `qualityGates` the number sits in an author-owned file, which
  makes "raising it is a reviewed change" literally true instead of
  aspirational.

  **It arms at zero, today, in both projects** — measured, not
  estimated: `mix xref graph --format stats` reports 0 compile
  dependencies at the root and 0 in `components/substrate`, and
  `--label compile-connected --fail-above 0` exits 0 in each. The
  strongest cap this metric will ever have is available for the price
  of a line, and every later value is a concession. That is also why
  the erosion metric is worth arming before there is erosion to
  measure: a baseline recorded after the first compile dependency lands
  is a baseline that already contains it.
- **The audit reports a missing gate; it never runs one.** Sobelow's
  arming rule is the case that decides this. An audit that shells out
  to another gate swallows that tool's exit code and its output
  formatting, and becomes a meta-runner whose own report is the least
  interesting thing in it — while `qualityGates` and `ci.yml` are
  already the place where a gate is a line. So the audit's finding is
  the gap: *this project has a web layer and no sobelow gate*, which is
  the part invisible from anywhere else, and arming it is the ordinary
  author edit every other gate takes.

  **The predicate is `:phoenix` in the dependency tree, never a
  directory name.** §2.14's shorthand — arms "when `catapult_web`
  appears" — names a path in *this* repo, and a shipped, cwd-rooted
  task may not hold that fact any more than it may know where this repo
  keeps its components (`docs/non-goals.md`). A generated project puts
  its web layer wherever its own spine says; the dependency is the
  thing that is true in all of them.
- **The two VM guardrails are not one grade, and the registry should
  stop implying they are.** §2.5 says the BEAM enforces both. It
  enforces one. `max_heap_size` is a real process flag, kills the
  process, and is exactly the runtime-grade guardrail described.
  `erlang:process_flag(:max_message_queue_len, _)` does not exist —
  `badarg`, verified on the pinned OTP — and the only queue-length
  facility in the VM is `:erlang.system_monitor/2`'s
  `long_message_queue`, which notifies rather than kills, is
  node-global rather than per-process, and is **singular**: setting a
  system monitor returns and discards the previous one, so any
  dependency that wants `long_gc` silently disables our mailbox
  guardrail. A guardrail a library can turn off by accident is the
  fail-open shape this repo has ruled on twice already, and it is worse
  here than in the supply gate, because what stops being reported is a
  process about to take the node down.

  So `max_heap_size` stays an enforced bound, and the mailbox bound
  becomes a declared threshold that is *sampled and reported* — the opt
  renamed `message_queue_alarm_len:` so the declaration states its own
  grade, since `max_` is a promise the platform cannot keep. Where the
  sampling lives is `systems/observability.md`'s. Renaming costs
  nothing today (nothing declares a guardrail yet) and the alternative
  is a field that will be read as enforcement by every operator who
  ever greps for it.

  **Guardrails are applied by the process and checked by the composer;
  the composer does not thread `spawn_opt`.** A flag can only be set
  from inside its own process (`process_flag/3` covers `save_calls` and
  nothing else), so the only external route is `spawn_opt` on the start
  call — which requires the composer to know each child's option
  conventions, for children it did not write, and fails outright for
  the first child whose `start_link` accepts no options. That is the
  audit's layout knowledge wearing a different hat. A one-line call in
  `init/1` reading the component's own declaration is what the process
  owns anyway, and declared↔applied is then the same check shape as
  declared↔constructed and declared↔emitted — a third instance of a
  pattern the platform already has two of.

  **Amended in build (ORC-21): the checker is the audit, not the
  composer**, and the sentence above is right about everything except
  which organ holds it. The composer sees declarations; declared↔applied
  needs *call sites*, and a call site is a fact about a tree. So it
  lands beside the other declaration↔tree check
  (`Catapult.Audit.Declarations`), which is what the last clause of that
  same sentence already says — the pattern it is a third instance of is
  an audit check both times. The composer's half is unchanged and it is
  the important half: it still never threads `spawn_opt`.
- **`errors/0`'s struct is generated from the registry, so one
  direction of declared↔constructed is a compile error rather than an
  audit finding.** §2.14 asks for the check both ways. The expensive
  way is an AST pass hunting `kind:` keys, which is a check guessing at
  what construction looks like; the cheap way is to make construction
  go through something the registry built. `use Catapult.Error` defines
  the component's error struct from its declared kinds — conventions
  §8's `%Engine.Error{kind: ...}` spelling is unchanged and callers
  still match on the struct — and an undeclared kind then cannot be
  constructed at all. What is left for the audit is the direction a
  compiler cannot see: a kind declared and never constructed, which is
  dead vocabulary in a catalog operators read. Remedy presence is
  already the composer's (ORC-22), so §2.14's third clause needs
  nothing.

  The generated catalog is a rendering of the inventory on demand and
  never a committed file — the no-hand-maintained-inventories rule, and
  the same shape as the census. It ships with the docs-site
  composition, which conventions §13 defers, so it is not this roster's
  to build.

  **Amended in build (ORC-21): the grade is construction-time, and the
  registry is read at construction rather than at compile time.** Two
  corrections, both found by writing it, and the second is the one that
  matters:

    * *Compile error was never on offer.* Elixir validates a struct
      literal's **keys** at compile time and never its values, so no
      generator can make `%Engine.Error{kind: :invented}` fail to
      compile. What the generated `new/2` does buy is that the
      vocabulary a caller can *build* is the vocabulary the composer
      validated, with meaning and remedy carried from the declaration
      rather than copied — and the residue is one narrow shape, a
      hand-built literal, instead of the open set an AST pass would
      have had to cover.
    * *Reading `errors/0` while compiling the error module deadlocks
      the canonical usage.* `Engine.Error` would wait for `Engine`,
      and conventions §8's own spelling has `Engine` constructing
      `%Engine.Error{}`, which makes `Engine` wait for `Engine.Error`.
      That is a compile cycle, and `mix xref graph --format cycles
      --fail-above 0` is a hard gate — a mechanism whose adoption trips
      one of this repo's own gates is not a mechanism. `new/2` resolves
      against the registry at call time, which costs a list scan on a
      failure path and buys back the whole hazard.

  Everything downstream of the paragraph above is unchanged: the audit
  keeps exactly the declared-and-never-constructed direction
  (`Catapult.Audit.Declarations`), and remedy presence stays the
  composer's.
- **Secret config values are wrapped, not audited.** "Never appears in
  logs or error payloads" is a claim about values, and an audit sees
  source: the honest static version is a shallow check one hop from the
  accessor, which misses every value bound to a variable first. The
  type is what holds it everywhere — `fetch!/2` on a `secret: true`
  entry returns a wrapper whose `Inspect` and `String.Chars`
  implementations redact, and whose value comes out only through an
  explicit unwrap. Then interpolation, `inspect/1`, a crash dump and a
  `Logger` call are all safe by construction rather than by a check
  that has to see them, and §2.2's "settings surfaces mask by
  construction" stops being a separate rule about one screen. The
  audit's residue is small and exact, which is the point: an unwrap
  inside a logging call, one hop, no inference.

  **The cost is one call site, today.** Every consumer of a secret must
  unwrap, and the only declared secret in the tree is `DATABASE_URL` on
  its way into `Repo.init/2`. This is the `events/0` argument again and
  it is the last time it will be cheap: the wrapper is free while there
  is one reader and a migration once there are twenty.
- **Export metadata carries registered vocabulary and nothing else.**
  `defexport`'s span emits empty metadata today, and §2.2's
  error-rate-by-kind is the first thing to put something in it: a
  registered error kind, taken from the export's own return. The rule
  arriving with it matters more than the field — metadata never carries
  arguments or return bodies. Span metadata and Logger metadata are the
  operational channel (conventions §10), content stays out of it by
  §2.11, and the alternative would put the secret wrapper above in the
  position of defending a second surface.

  §2.2's Logger floor rides the same interception point: `component:`
  at every export entry, and `trace_id:` **only when absent**. An
  export that overwrote an inherited trace id would cut every trace at
  the first internal boundary crossing, which is the seam tracing
  exists to cross; generating one where there is none is what makes an
  export the root of its own trace. The macro restores the outer
  `component:` on the way out, because a nested export that leaves its
  own slug behind misattributes every later log line in its caller — a
  bug that costs two `Logger.metadata/1` calls to not have.
- **The ES property templates are a macro, and that is why StreamData
  is not a dependency.** §2.4 ships templates with the family; a
  template that is copied stops matching the invariant the day the
  family changes one, and nobody re-copies. A macro that injects the
  replay-determinism, idempotency and round-trip properties keeps "the
  property is the floor" literal — adopting the family is what makes
  the property present. The dependency question then answers itself: a
  module that only *quotes* `StreamData` never compiles against it, so
  the property generator ships here while `stream_data` is a test-scope
  dependency of the project that expands it. That asymmetry is also why
  the Credo decision above went the other way — `use Credo.Check` runs
  at the check module's own compile time, where quoting cannot help.
- **The external-HTTP rule is a boundary declaration, not an audit
  check** — which collapses two roster items into one and moves them
  out of the audit entirely. Boundary's `type: :strict` reports every
  call to an external application not allowed in a boundary's `deps:`,
  and `check: [apps: [...]]` forces the same for a named application
  regardless. "Only `Store` subcomponents depend on Ecto", "only the
  outbox wrapper on Oban's insert surface", "only adapters on Req", and
  §2.2's every-HTTP-usage-inside-a-registered-adapter are all one
  sentence in that vocabulary. §2.14's third grep — raw topic strings —
  lands here too rather than at AST grade: the rule that matters is
  that PubSub is reached through the platform's wrapper (conventions
  §10 threads trace context there), and "nothing outside the wrapper
  calls `Phoenix.PubSub`" is a boundary fact, not a string-shaped one.

  **The residue is Erlang, and it stays an AST check.** Boundary
  documents that calls to `:elixir`, `:boundary` and pure Erlang
  applications cannot be restrained — so a plane module reaching a
  model provider through `:httpc` is invisible to the compile grade,
  and conventions §11 becomes *mostly* a compile error rather than
  wholly one. Naming which half is which is the difference between a
  gate and a belief about a gate.

  The one thing `externals/0` still owes the audit needs no new field:
  an entry's `adapter:` and `fake:` must declare a behaviour in common.
  A fake that has drifted off its adapter's contract is a test lying
  about a system it never called, and both modules already carry the
  answer in their own attributes.

- **The apps list that arms that declaration is checked for
  completeness, by `Catapult.Audit.BoundaryApps`** (ORC-50). The
  entry above buys compile-grade enforcement for *named* applications,
  and the naming is where it leaks: an application absent from
  `boundary: [default: [check: [apps: [...]]]]` is not partially
  checked, it is silently exempt, and a clean `mix compile` over a
  dependency nobody constrained looks exactly like a clean
  `mix compile` over one that is. ORC-21 priced the omission as "a
  line in the same diff that added it"; the price assumes the omission
  gets noticed and nothing notices it. This is the fail-open shape the
  platform has refused twice on its own merits — `mix_audit` reporting
  clean from a clone it never made (ORC-37), the licensing check
  declining silently (ORC-16) — arriving a third time with no
  equivalent tell, so it gets the same treatment: a check, and a census
  line on every green run saying what the tell would have said.

  **The subject is what a `:prod` build can reach, and it is computed
  rather than listed.** Seed from the project's own `deps` that survive
  into `:prod` — the `only:` filter `Catapult.Audit.License` already
  applies — then walk each application's compiled `.app` file
  (`Application.spec(app, :applications)` and
  `:included_applications`), keeping only what `Mix.Project.deps_apps/0`
  also contains, which is how OTP's own applications fall out without a
  list of their names. Measured from a **dev**-env run
  against `MIX_ENV=prod mix run`'s own answer: the two sets are
  identical, eighteen applications, so the audit reports the same
  subject in whatever env it is invoked. That property is the reason
  for the mechanism rather than a bonus of it — a gate whose subject
  changes with `MIX_ENV` reports different coverage on different runs
  and cannot be reasoned about from its output.

  **It does not share `Catapult.Audit.License`'s closure, and the
  divergence is the point.** That walk answers *what a consumer would
  fetch*, from publishers' `hex_metadata.config`, and it deliberately
  does not descend into a path dep, because a path dep is another mix
  project audited in its own right. This one answers *what this build
  can reach*, which includes a path dep's own dependencies — and the
  plane is the case: `:plug` and `:telemetry` reach `lib/` through
  `components/substrate`, not through any root `deps` entry. Sharing
  the walker would have imported that exclusion as a hole one level in.

  **Three exclusions, none of them a waiver, and none of them a name
  anybody writes.** They are derived, so there is nothing to forget and
  nothing to spend:

    * **`:boundary` itself**, because `Boundary.Checker` opens
      `check_external_dep?/3` with `Boundary.app(view, reference.to) !=
      :boundary`. Naming it is inert by construction.
    * **Applications contributing no Elixir modules** — `:cowboy`,
      `:cowlib`, `:ranch`, `:telemetry`, `:cowboy_telemetry` here.
      `Boundary.Mix.app_modules/1` filters to `Elixir.*` and the check
      resolves a callee's application through that map, so a call to
      `:cow_http` resolves to no application and no list entry can
      restrain it. Demanding those names would put lines in the list
      that read as coverage and deliver none, which is this entry's own
      complaint pointed the wrong way.
    * **Path deps**, derived from `:path` in the dep options. Not a
      preference: naming `:catapult_substrate` in the list reproduces
      the ORC-21 defect exactly — measured at twelve forbidden
      references and exit 1 under `--warnings-as-errors`, on
      `mix compile --force` and on the incremental compile alike — for
      the same reason strict does, because `check_external_dep?/3`
      treats "named in `check.apps`" and "`type: :strict`" as one
      condition and everything downstream of it is identical.

  **Both modes, not either.** `Boundary.Definition` expands a bare atom
  to `{app, :runtime}` and `{app, :compile}`, so a list may legally
  carry one mode alone — and a `{app, :runtime}` entry leaves
  compile-time calls unchecked, which is the same fail-open one level
  smaller. Coverage means both modes; a half-covered application is
  reported.

  **Coverage, never equality.** A name in the list that the closure
  does not contain is not a problem: `:req` is `only: :test` and is
  named deliberately, and a list is free to say more than the floor
  requires. The residue that leaves — a typo'd or stale application
  name is inert rather than reported — is named here rather than
  absorbed, and it is bounded by the fact that no name is load-bearing
  in the permissive direction.

  **A built-in of `mix catapult.audit`, not a `policies/0` entry**, on
  `Catapult.Audit.License`'s recorded criterion rather than by analogy
  with it: `Catapult.Audit.Check.run/1` takes a working-directory
  glob, and a dependency graph is not a path scope, so registering
  this would mean passing a scope argument that means "ignore me".
  `policies/0` is how a *component* ships enforcement into projects
  that adopt it; this is the task's own, present everywhere and armed
  or silent by declaration. It takes no dependency on Boundary either —
  it reads a keyword list out of `Mix.Project.config()` and never calls
  the library, which is what keeps it shippable in a substrate that
  refuses dependencies on other people's behalf.

  **Armed by the declaration it audits, inert otherwise, and it says
  which.** A project stating `check: [apps: [...]]` in its
  project-level `boundary` default has the list this check is about; a
  project stating `type: :strict` needs no list and the check is inert;
  a project stating neither may still declare per-boundary rules this
  check cannot see, because `use Boundary` options are module
  attributes rather than project config. Each state prints its own
  census line, for ORC-16's reason — the inert state is the only one
  that could be mistaken for a pass. The armed line carries the
  exclusions by name rather than only a count, because the excluded
  applications *are* the residual gap and a number is not a tell:

      boundary apps: 11 of 11 restrainable named, out of 18 reachable;
      5 unrestrainable (cowboy, cowboy_telemetry, cowlib, ranch,
      telemetry); 1 path dep (catapult_substrate); boundary itself

  which is the same sentence `lib/catapult.ex` and
  `systems/foundation.md` already write about the Erlang residue, moved
  to where it is re-derived from the tree on every run instead of
  standing in prose that can go stale.

  The limit worth knowing before the first carve-out:
  `Boundary.Definition.normalize!/3` merges a module's own `check:`
  over the project default with `Map.merge`, so a boundary declaring
  any `check:` key **replaces** the apps list rather than extending it.
  There are zero such boundaries today, so no check is built for it —
  building enforcement for a pattern with no subject is what
  `docs/non-goals.md` refuses in three other places. The revisit
  condition is the first `use Boundary` in this tree carrying a
  `check:` key, which is an AST predicate of exactly the shape
  `Catapult.Audit.Source` already serves.

### The config declared↔read check (ORC-48)

`config/0` was the last registry with no declared↔used fact in the
audit, while every neighbour has one — errors are declared↔constructed,
guardrails declared↔applied, telemetry declared↔emitted. ORC-4 deferred
it on a stated blocker ("both of which want the check registry to grow
first"); the registry grew two tickets later and nothing re-opened this
half, so what follows is the design that retires the deferral rather
than a new proposal.

**Sized honestly, because it is smaller than its neighbours.** One
direction is already caught, late: `Catapult.Config.fetch!/2` raises on
an undeclared key, so this moves that from a runtime raise on whichever
code path production reaches first to a line in CI. The other direction
is caught nowhere — a declared value nobody reads is dead configuration
that still fails a boot when its variable is missing, and the operator
holding that deploy is being stopped by a value the code would not have
used.

- **The join key is the accessor's own two arguments, so this check is
  exact where declared↔applied is approximate.** `fetch!(slug, key)`
  names a declaration completely — the slug is the spine every claimed
  name hangs off and the store is already keyed by it — so the join is
  on the pair, and there is no name-shaped ambiguity of the sort
  `Guardrails.apply!/2`'s single `name` leaves. That is a property of
  the accessor's signature rather than of this check, and it is worth
  naming because it is the reason the check can afford to be strict
  about literals below.
- **Two directions, one parse of the tree, and — deliberately —
  different subjects.** *Declared and never read* takes as its subjects
  only the declarations of components whose own source the audit's scope
  covers. *Read and never declared* takes as its subjects every
  `fetch!/2` call in scope, joined against **every** declaration the
  project composes, in-scope or not.

  The asymmetry is not tidiness, it is the direction this check may not
  fail in. A component shipped from a package declares its config in a
  module whose `lib/` is the package's, not the consumer's, so a
  consumer's audit sweeping its own tree would find no reads for any of
  them and report every one as dead — with the remedy the message
  carries being *delete the declaration*, which breaks the boot of every
  project that adopts it. A check whose advice is destructive on a tree
  its author never read is the shape `Catapult.Audit.License`'s inert
  state was designed against, arriving one registry over. Meanwhile the
  reverse — a call in *this* tree naming a key nothing declares — is
  joinable with complete information wherever the declaration lives, so
  that direction keeps the wider subject and loses nothing.

  **The predicate is not a directory name and not a dependency list:**
  the declaring component's compile-time source (`module_info(:compile)`)
  either is one of the files `scope` expanded to, or it is not. The scope
  glob is already this task's only definition of *code this project
  audits*, so the discriminator is the one fact the task is allowed to
  hold — the same reason sobelow's predicate is `:phoenix` in the tree
  rather than `catapult_web` on disk (`docs/non-goals.md`). Measured on
  the pinned toolchain rather than assumed: `Catapult.Foundation` reports
  `<cwd>/lib/catapult/foundation.ex` and the path-dep'd `Catapult.Config`
  reports `<cwd>/components/substrate/lib/catapult/config.ex`, which
  `lib/**/*.ex` does not match. The task compiles before it audits, so
  the recorded path is this run's.

  This is the sibling checks' bug too, and it is fixed there in the same
  place: `Catapult.Audit.Declarations` sweeps once for all three, and a
  shipped component's error kinds and guardrails have exactly the same
  false-dead problem the day one exists. Repairing config alone would
  leave two checks with a known destructive failure mode and no ticket
  pointing at them.
- **A read the join cannot resolve is a problem in its own right, and
  suppresses only what it makes unknowable.** `fetch!/2` reached with a
  non-literal slug or key is reported at its call site. The alternative
  is worse than it looks: ignoring it silently makes the other direction
  report a live declaration as dead, and *that* message tells the reader
  to delete a value the boot requires — one wrong line printed with the
  same confidence as the right ones. So the unjoinable call is what the
  report names, and while it stands the declarations it could have been
  reading are not also reported dead: a non-literal key suppresses that
  slug, a non-literal slug suppresses the direction. Suppression costs
  no coverage, because the run is already red on the call site; what it
  buys is that the audit prints one line per cause, and never advice
  that would break a boot.

  Implementation found a third thing that makes a read unknowable and
  the same argument settles it: **a file in scope that does not parse
  suppresses the dead direction, and reports nothing of its own.** Its
  reads cannot be seen, so every declaration is a candidate false dead;
  and the line is already owed by somebody else — the file-scoped checks
  sweeping the identical scope report an unparseable file by contract
  (`Catapult.Audit.Source`), so the run is red and the cause is named
  exactly once. The task compiles before it audits, which is what makes
  this unreachable in practice rather than merely survivable.

  Neither this nor the dead direction takes `catapult:allow`, for
  `Declarations`' standing reason and one more: an escape on an
  unjoinable read would silently re-arm exactly the false-dead report
  the suppression exists to prevent, so the tag would fix one line by
  corrupting another. A declaration nobody reads is deleted and a
  computed key is spelled; both remedies are one line and always
  available.
- **The check does not police *who* reads.** ORC-4's sentence says "a
  component reading a key it did not declare", and this narrows it to
  *a key nobody declared*, out loud, because the strict reading needs a
  path→component map and this task may never hold one — the audit
  learning which files belong to which component is the layout knowledge
  `docs/non-goals.md` refuses at the task's front door. It is also the
  right narrowing on the merits: `fetch!/2` takes a slug precisely so a
  reader can name a value it does not own, `Catapult.Repo` is the tree's
  own example, and whether that coupling is acceptable is a boundary
  question the boundary compiler is the organ for.
- **What each direction may name.** The read directions name a location
  and spell it `path:line: message`, which is the contract every check
  with a line owes its Credo wrapper. The dead direction names no
  location — it reports an absence, exactly as its two siblings do — and
  names the component, the key and **the env var**, because removing the
  variable from the deploy environment is the other half of the remedy
  and the variable is what an operator greps. Naming a variable is not
  naming a value: `Catapult.Config`'s rule that no report ever quotes
  what it rejected is untouched, and this report has no access to a
  value at all.
- **The runtime raise stays where it is.** `fetch!/2` keeps raising on
  an undeclared key. CI covers `lib/**/*.ex`; a release task, a test, an
  `iex` session and any dynamically-reached call are outside it, and an
  accessor whose contract depended on a gate having run would be
  correct only in the tree that ran it.
- **Scope is the audit's `lib/**/*.ex`, so a value read only by tests is
  dead.** That is the answer rather than an oversight: config exists for
  the running application, and a declaration whose only reader is a test
  is a variable every deploy must set for a value production never
  consults. Widening the glob to cover `test/` would make exactly that
  case report clean.
- **The audit task loses its empty-components short circuit, and config
  is why** (found in implementation). `declaration_problems/1` returned
  early when a project composed nothing, which was free while both
  checks took a registry as their subject. The read direction does not:
  a project that composes nothing declares nothing, so a `fetch!/2` call
  in its tree is a read *nothing* can explain — the one case where an
  empty registry makes the report more interesting rather than less. The
  saving stays where it belongs, on the two checks that skip their own
  sweep when their entries are empty.
- **`config/0` gets no census line.** The census exists because most of
  the roster consumes nothing and an unconsumed registry rots quietly;
  `config/0` is the registry that never had that problem — it is the one
  with a consumer, a boot half and its own report — and from this ticket
  a dead entry is a red build rather than a number nobody reads. A
  second inventory surface for the one registry outside the roster table
  would be the count restating what the check already asserts.
- **The one hole is a renamed alias, and it announces itself.** Reads
  are matched as qualified calls whose module's last segment is
  `Config` — in both spellings, because the piped
  `:engine |> Config.fetch!(:key)` is the same call reaching the parser
  at a different arity, and leaving that unmatched would have been a
  second hole of a worse kind (found in implementation: an arity-shaped
  miss makes a *live* declaration report dead, and credo's SinglePipe is
  tagged controversial, so nothing else in the gate set forbids the
  spelling). What stays is the alias: `alias Catapult.Config, as: Cfg`
  hides a read — a limit `Catapult.Audit.Source.alias?/2` imposes on
  every check in the family, not a new one. Here it is the benign case, and uniquely so: hiding a
  read does not hide a violation, it makes the declaration that read
  serves report as dead, so the check's other direction is what surfaces
  it. A ban that goes quiet when someone renames an alias is the failure
  this repo cares about; a check that goes *loud* on the wrong line is a
  bad afternoon with a correct ending.
## Initial vs target

Initial (Phase 1): behaviour + registries, export macro
(telemetry-only), audit v0, health, clock, seeds. Target: permission
enforcement wired to identity's principal behaviour; the full check
registry; published on the release train.

The registry roster arrives whole at **mechanism grade** — shape,
aggregation, collision check, inventory — and consumes nothing
(ORC-22). That is the deliverable rather than a shortfall: retrofitting
a registry once its consumers exist means editing every component,
while a registry aggregating into nothing costs a table row. Deferred
is the consuming half, each to the ticket that has the consumer:
FunWithFlags binding (the delivery loop, conventions §13),
`@requires_permission` enforcement (identity, Phase 7), the root API
router and OpenAPI generation (a web layer), the admin dashboard's
mounts (Phase 4), the generated error catalog and the
declared↔constructed checks (ORC-21), and the audit's policy-check
runner (ORC-21). Nothing on that list can be reached from here, and
none of it changes a declaration when it arrives — which is the
property the roster is buying.

**Amended (ORC-21) on two of those, now that the roster above has
designed them.** The error catalog is not ORC-21's after all: it is a
rendering of the inventory and it ships with the docs-site composition
conventions §13 defers, so it moves off this list to that one. And the
declared↔constructed check shrinks rather than lands whole — the
undeclared-kind direction becomes a compile error the generated struct
gives for free, leaving the audit only the declared-and-never-
constructed direction. Three declarations do change when the roster's
enforcement arrives, against the property this paragraph claims:
`oban_queues/0`'s `cron:` takes a worker, `processes/0`'s mailbox opt
is renamed, and `secret: true`'s accessor returns a wrapper. All three
are shape corrections found by designing the consuming half, all three
cost nothing while the registries are empty, and that is the argument
for changing them now rather than evidence against the roster — the
alternative is the same three edits with entries to migrate.

The config layer arrives whole rather than as a stub — port, source,
fake, load, accessor — because a registry the composer does not honor
is the state ORC-4 exists to end, and half of it would be the same
state with more files. What is deferred is the audit's side: the
declared↔read check (a value declared and never read, a component
reading a key it did not declare) and `secret: true`'s enforcement
beyond the boot report, both of which want the check registry to grow
first.

**The deferral above is retired: one half shipped, the other is
designed one section up** (ORC-48). The blocker it named expired in
ORC-22, when `policies/0` and `Catapult.Audit.Check` shipped the check
registry both halves were waiting on. `secret: true`'s enforcement
beyond the boot report is the wrapper type plus
`Catapult.Audit.Checks.SecretInLog` and landed in ORC-21; the
declared↔read check is this ticket's. The
paragraph stays as written rather than being edited into agreement,
because a deferral whose stated reason expires silently is what ORC-48
was filed about — the record of what was waiting on what is the part
worth keeping, and the amendment is what makes the wait priced rather
than forgotten.

## Depends on

Nothing in this repo (it is the bottom). Boundary and PromEx as
library deps.

**Vapor was named here and is not, per the standing decision above**
(ORC-4). Recorded as an amendment rather than a quiet deletion,
because the line was a real prediction from the Phase 0 pass and the
next reader of conventions §1 will expect to find it: the config layer
is a port with a zero-dependency environment source, and Vapor — if it
is ever wanted — is an adapter in a project that wants it, never a
dependency this package imposes.
