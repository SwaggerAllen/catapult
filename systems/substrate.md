---
paths:
  - components/substrate/**
---

# substrate

The elixir-target platform substrate: everything a Catapult-built app
(and Catapult itself) adopts to honor the convention corpus. Shipped
as a hex package via the registry; Catapult consumes it as a path dep
— the plane is its first consumer.

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
  arming, and `LICENSING.md` gains the classification section and loses
  `components/*` from its ladder bullet and its path rule.
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
  the allowlist, or *unchecked* — and the collapse is what makes
  "strictest wins" a total order rather than a merge.

  | The subject's own terms | How it reaches people | Dependencies | Because |
  | --- | --- | --- | --- |
  | on the allowlist | conveyed (`:distributed`, or a published `package:`) | **checked** | a recipient would inherit terms nobody offered them |
  | public copyleft (AGPL, GPL) | conveyed | unchecked | a recipient has already accepted every term a dependency could add |
  | `LicenseRef-*` | conveyed | **checked** | we would be conveying a work under terms we have not met |
  | any public license | `:service` | unchecked | we offer source; nothing a dependency asks is a cost already unpaid |
  | `LicenseRef-*` | `:service` | **checked** | AGPL §13 would oblige an offer of source to our own users |
  | any | `:internal` | unchecked | nothing is conveyed and nobody is served |

  **"Ours" and "proprietary" are read off the identifier, not declared
  again.** SPDX already spells "no listed license applies":
  `LicenseRef-<id>`. So a `:service` component under
  `LicenseRef-Catapult-Hosted` is the closed case and one under any
  listed identifier is the open one, with no third class and no
  `proprietary: true` beside a license that already says so — two
  places to state one fact are two places that can disagree.

  **The list is shared; the reason is not, and the report prints the
  reason.** This is the distinction the review asked to get into the
  sketch, made structural rather than remembered: a proprietary
  `:service` component failing on a GPL dependency must not read as a
  shipped-layer failure, because nobody receives that component and the
  allowlist protecting recipients is not what is being enforced. Its
  line says AGPL §13 and an offer of source to our own users. Applying
  the shipped-layer allowlist with the shipped-layer *reason* to a
  hosted-only component is not conservative, it is wrong, and a report
  that says which reason armed it cannot make that mistake quietly.

  **Where this is stricter than the review said, and the push-back is
  invited.** "Proprietary `:service` — no copyleft" would admit
  MPL-2.0 and EPL-2.0; the five-identifier allowlist does not, so that
  row is enforced more tightly than specified. Deliberate, on the
  review's own argument — "an allowlist is cheap to widen and
  expensive to narrow after something has shipped against it" — plus
  the fact that a denylist cannot be written: "everything except
  copyleft" is unenumerable, so the check would have to decide
  copyleft-ness of unknown identifiers, which is the inference the
  normalization decision below refuses. Nothing is proprietary today,
  so the cost of the extra strictness is currently zero and the first
  real dependency to ask widens the list by an entry. Say so if you
  would rather the row shipped at "no copyleft" and this is a case for
  a second list.
- **A subject is held to the standard it holds its dependencies to,
  and silence is reported rather than defaulted** (ORC-16). The two
  decisions the review left to this pass, and they resolve together.

  **Its own license is checked by the same rule.** A `:distributed`
  component declaring `AGPL-3.0-only` for itself is the defect one
  level up and strictly worse than a copyleft dependency: a dependency
  is one package a consumer could route around, and the component *is*
  the thing shipping. It is free because it is not a second predicate —
  the same table, with the subject's own identifier in place of the
  dependency's — and it is why the table's first column reads "the
  subject's own terms" rather than "the component's".

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
  *policy* — the allowlist, the closure, the undeclared report — is the
  audit's alone. This is the "two reports at two times" line drawn
  along a second axis, and the reason is blunt: a production node
  refusing to start because a transitive dependency's license string is
  unrecognized is a catastrophic response to a question with no runtime
  consequence whatsoever. CI red is the correct severity for a legal
  fact; a node that will not boot is not.
- **The allowlist is not a list of permissive licenses; it is a list of
  licenses that impose no terms on the linking application** (ORC-16).
  The distinction is the one the policy actually needs —
  `LICENSING.md`'s requirement is that a customer's application
  inherits nothing — and it is what makes additions decidable instead
  of a debate about what "permissive" means. It opens closed, with five
  SPDX identifiers: `Apache-2.0`, `MIT`, `BSD-2-Clause`,
  `BSD-3-Clause`, `ISC`. ISC is not decorative — cowboy, cowlib and
  ranch are all ISC (measured), so the first shipped component that
  serves HTTP lands on it.

  ORC-16 named "ERLPL where applicable", and it is applicable nowhere:
  measured across both trees today, every dependency is Apache-2.0, MIT
  or ISC. ErlPL-1.1 and MPL-2.0 do satisfy the predicate — file-level
  copyleft binds the files it covers, not the work that links them —
  but their residues differ from each other in patent and disclosure
  terms, and a residue is worth reading against a package a reviewer
  can open rather than accepted in the abstract. So they are entries
  the day a real dependency asks, the same shape as `externals/0`'s
  data classes and `ignore_advisories`: an entry with an author behind
  it, never a category left ajar.

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
  this check, and no per-dependency waiver.** The fix for a copyleft
  dependency is not taking the dependency. The asymmetry with
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
  `mix.exs` beside `package:` rather than in the data file ORC-16 named:
  it is where a project already speaks to mix, it puts the two facts
  under one review, and it spares a task that ships everywhere a path
  convention of its own.
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
  greps together. It does not adopt the behaviour, and the next pass
  should not make it: that callback takes a working-directory-relative
  glob, a dependency tree is not a path scope, and forcing it through
  means passing a scope value meaning "ignore this argument" — a
  callback lying about its contract in its first implementation.
  `policies/0` is how a *component* ships a check into projects that
  adopt it; this one is the task's own, present in every project and
  armed or silent by declaration.

  **The inert state is never silent.** The check adds a census line
  naming the policy it reached and the subject that set it — armed by
  substrate's own `Apache-2.0` package, or unchecked because every
  subject is a public-licensed service — for the reason the roster
  prints counts nobody consumes yet: a gate whose failure mode is a
  clean report is the thing ORC-37 was filed about, and "inert" is that
  report.

  **It arms green, and that is the point.** Every dependency in every
  checked tree passes today, so the check finds nothing the day it
  lands. That is what a ratchet is, and it is the only moment arming is
  free: the rung `LICENSING.md` files as "Test (planned)" costs one
  review now and nothing afterwards, where the same rung added once a
  copyleft dependency is in costs the dependency.

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

The config layer arrives whole rather than as a stub — port, source,
fake, load, accessor — because a registry the composer does not honor
is the state ORC-4 exists to end, and half of it would be the same
state with more files. What is deferred is the audit's side: the
declared↔read check (a value declared and never read, a component
reading a key it did not declare) and `secret: true`'s enforcement
beyond the boot report, both of which want the check registry to grow
first.

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
