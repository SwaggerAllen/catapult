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

## #1 Owns

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

## #2 Standing decisions

- **#3 One macro layer, two concerns.** Telemetry instrumentation and
  permission enforcement ride the same boundary-export macro —
  built once, because both need the same interception point and two
  macro layers on one function is a composition bug farm.
- **#4 The audit is a check registry, not a monolith.** Platform extensions (v5 §9) register checks;
  the ES family registers the purity floor, delivery registers file-map checks.
- **#5 Registries fail the build on collision, never warn.** A warning
  about a name collision is a collision that ships.
- **#6 The roster is one table, not one validator per registry** (ORC-22). Twelve name-claiming
  registries × (entry shape, known opts, required opts, spine rule, collision key) is a matrix, and
  hand-writing it as twelve validator functions is how a composer becomes the monolith the audit
  refused to be one level up. `Catapult.Component.Registries` holds one row per registry; aggregation,
  the collision report and the inventory are each one pass over it, and adding a registry is an entry
  rather than a debate — `systems/registry.md`'s idiom for artifact kinds, which is the same idiom for
  the same reason.

  The one registry deliberately outside the table is `config/0`: it is
  the only one with a consumer, a boot half, and error messages worth
  their specificity, and `Catapult.Config` keeps them. Absorbing it
  would trade a good report for a uniform one.
- **#7 What this document records is the columns, not the rows.** The rows are code and the code is
  the inventory (`docs/non-goals.md`); a shape is spelled out below only where the shape itself is the
  argued decision.
- **#8 Two of v5 §2.2's names are outside the roster on purpose, for different reasons** (ORC-22).
  There is no `docs/0` callback and never will be: `docs/` is a directory whose path derives from the
  slug (conventions §3), so there is nothing to declare and nothing that can collide, and a callback
  returning a path the spine already fixes is a derivation written twice — the failure the spine table
  exists to prevent. `cli/0` is out on a narrower argument, and a priced one: it is `api_surface/0`'s
  shape with an escript composer instead of a router, and the retrofit cost of a roster is the cost of
  components having already declared their names *somewhere else*.
- **#9 The address is positional, the policy is opts, and an opt is not
  optional for sitting in a keyword list.** Every entry carrying more
  than a name follows `config/0`'s `{key, name, opts}` grain:
  positional elements identify the thing, the keyword tail is
  everything said *about* it, checked against the row's known-opts list
  the way the config layer already checks its own. Required opts are an
  ordinary column — `api_surface/0`'s `version:` and `audience:` are
  required and reported when absent — because the alternative is a
  five-element tuple whose fourth element nobody can count.
- **#10 Optional facts get sugar; mandatory ones get none.**
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

  Two spellings are affordable only because nothing downstream sees
  them: **normalization happens once, in the inventory**, and every
  consumer — the collision report, the audit, the generators later —
  reads the wide form. A second normalizer anywhere is the defect this
  is trading against.
- **#11 Amended (ORC-21): `cron:` is a list of `{schedule, worker}`, not a string, because a crontab
  entry does not point at a queue.**
- **#12 The spine check arms wherever a name is a global atom, and
  `external:` stays a config-only escape.** `errors/0` kinds,
  `permissions/0` and `feature_flags/0` atoms, `oban_queues/0` names
  and `telemetry_events/0` paths are all checked against the slug
  prefix. `pubsub_topics/0` is not, and the exception is the rule's
  proof: the composer renders `slug:name` from a bare atom, so a
  prefix there would be the slug written twice.
- **#13 The escape does not travel with the check.** `external: true` stays a `config/0` opt and is
  added to no other row, because an env var name is the only claimed name a party outside this
  codebase can impose (`DATABASE_URL`, injected by the host platform).
- **#14 `errors/0`'s remedy ladder promotes by adding, never by
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
- **#15 A kill switch names a flag its own component declares.** The first
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
- **#16 Data classification is a closed vocabulary, not a note.** §2.2 asks for a note; a note
  cannot be grouped, and grouping is the entire payoff — the generated "what does this app talk to"
  page is a compliance inventory and, hosted, a customer's egress inventory. Four atoms, highest
  applicable wins: `:none`, `:operational`, `:customer_content`, `:personal`. Credentials are
  deliberately not a class, because every adapter sends one and a class every entry carries separates
  nothing; what the field classifies is application data crossing the boundary in either direction.
- **#17 `api_surface/0` validates against the trace `defexport` leaves.**
  A telemetry span alone could not answer "is this function a boundary
  export", which is the whole of §4.4's thin-wrapper enforcement, so
  the macro also accumulates `@catapult_exports` and generates
  `__catapult_exports__/0` from it, in the shape of the
  `__catapult_component__/0` beside it. One fact, three consumers: the
  audit's every-export-has-a-test check and its
  exported-mutating-function permission check (v5 §2.14) read the same
  trace rather than each inventing one.
- **#18 Route identity is the path's shape, not its parameter names.** Collisions compare `{version,
  verb, path}` with every `:param` segment equal to every other, because `/projects/:id` and
  `/projects/:project_id` are one route to any router and two strings to a naive check.
- **#19 `admin/0` mounts are relative to a root the component does not own.** An entry's path is a
  segment beneath the admin root, never an absolute `/admin/...`: where the root mounts is the
  composing application's decision (v5 §2.7), and a component spelling the prefix has hard-coded a
  fact belonging to someone else.
- **#20 `policies/0` scopes are working-directory-relative globs, and the shape is what enforces
  it.** An entry names a check module and the scope it applies to; a glob that is absolute or climbs
  out with `..` is a reported problem, not a convention someone remembers.
- **#21 The behaviour lands; the runner does not.** A registry whose entries reference modules has
  to say what the module is, or its collision check is checking the names of things with no contract —
  so `Catapult.Audit.Check` and its one callback are part of the mechanism, and the loop that calls it
  plus the checks that adopt it are ORC-21's. The `policy:` field is a string and the composer checks
  nothing beyond that it is one: resolving it means reading the doc graph, and substrate ships into
  projects whose graph belongs to the plane rather than to the package.
- **#22 The census is what makes an unconsumed registry visible.** The inventory is a function
  returning normalized data — never a document, per the no-hand-maintained-inventories rule — and `mix
  catapult.audit` prints a count per registry on every green run, not behind a flag.
- **#23 Every callback keeps an overridable empty default; none becomes `@optional_callbacks`.**
- **#24 An env var name is a claimed name like a queue or a topic.** Two components binding
  `DATABASE_URL` is the same class of bug as two claiming `:engine_default`, so it is checked where
  the others are — one more entry in the composer's problem list, reported in the same breath as the
  rest.
- **#25 Env var names are declared, not derived, and an off-spine name is marked.** Conventions §3
  renders the spine as a mechanical derivation — component `engine` gets `ENGINE_*` — and this repo
  already contains the counter-example: `DATABASE_URL` carries the name every Postgres client
  expects rather than the one the spine would derive, and `FOUNDATION_DATABASE_URL` is not on offer. So the declaration carries the literal
  variable name (it already does — `config/0`'s entries are `{key, env_var, opts}`), the audit checks
  the prefix, and a name off the spine is legal only with `external: true` on the entry.
- **#26 The cast is total, and the report enumerates.** The requirement is
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
- **#27 The registry declares data; provider structs are an adapter's business.** `config/0` returns
  inert `{key, env_var, opts}` tuples and nothing that has to be `Code.ensure_loaded?`d to be
  understood.
- **#28 Two reports, at two times, deliberately.** Structure — collisions, malformed declarations,
  an unknown opt — is validated by the composer, which means CI's audit catches it with no environment
  at all. Values are validated at boot, and only at boot, because the environment CI has is not the
  environment that matters and a gate that asserts otherwise would be asserting something it cannot
  see.
- **#29 The report names variables and reasons, never values.**
- **#30 Loaded values live behind one accessor, not in application env.** The load happens once,
  before the root supervisor starts, into `:persistent_term` under a private key; components read
  through the accessor and nothing else.
- **#31 Load-once is the rule, not merely the current implementation** (ORC-4). Config is read once,
  before the root supervisor starts, and does not change until the next boot: no watcher, no reload
  signal, no swapping a value on a running node.
- **#32 The store is keyed by slug, not by module** — `Catapult.Config.fetch!(:foundation,
  :health_port)` (ORC-4).
- **#33 The port hands the source every name at once; there is no per-key
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

  Called once, before the root supervisor starts, with every name every
  component declared; `opts` is the source's own settings, which cannot
  themselves come from the config layer (see the compile-time selection
  decision below). `opts` is `term()` rather than `keyword()`, because
  the static fake's seeded *map* is exactly this `opts`: a seed keyed by
  name and valued with strings needs no special case anywhere in the
  layer, and its shape is the source's business, which is the whole
  point of the parameter. `Catapult.Config.Env` implements it as one
  `System.get_env/0` and a `Map.take`. Nothing else is a callback: no
  `fetch/1`, no `get/2`, and in particular no `all/0`, because a source
  free to volunteer names nobody declared puts values into the system
  behind the registry's back, and the registry is the product.
- **#34 The file source is also what proves the `{:error, _}` branch is not ceremony.** An
  environment source cannot fail — `System.get_env/0` always answers — so with only the shipped
  adapter in view that branch reads as a return nobody will ever construct. A file source fails four
  ways before it reaches a value (absent, unreadable, unparseable, wrong root shape), and it forces
  the distinction that makes the report survive a second source: **when the source itself fails, the
  layer reports that and stops**, rather than falling through to the per-declaration pass.
  "DATABASE_URL is not set" is a false statement about a file that was never opened, and forty such
  lines bury the one true one. Missing *values* enumerate; a missing *source* is the whole report.
- **#35 The source's currency is named strings, and the namespace is the
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
  empty is legal is the cast's business — because a platform can inject
  an empty variable and "unset" and "set to nothing" deserve different
  lines in the report.
- **#36 The boundary this draws, said plainly:** the port's domain is flat, string-valued, named
  settings arriving over some transport other than the environment. A document with nested structure
  and lists of maps is not a config source in this sense at all — it is content, and it belongs in
  `config/*.exs` or in a real document loader.
- **#37 One source, never several merged.** The layer takes exactly one.
- **#38 Refresh and watch are questions about the accessor, not about the port**.
- **#39 The config source is chosen at compile time, because it is the
  bottom turtle.** v5 §2.12 has every external's real-vs-fake
  selection ride config; config's own source therefore cannot, since
  reading an environment variable to decide whether to read
  environment variables is the circle it looks like. The source is an
  `Application.compile_env` choice: the shipped environment source in
  every real build, the static fake in test — the same shape as the
  clock, and for the same reason.

  The static fake's seeded map is exactly this `opts`, keyed by name and valued with strings like any
  other source, which is why the fake needs no special case anywhere in the layer — and why a test
  seeds `"10"` rather than `10`.
- **#40 The selection carries the source's own settings, and that is the one bounded exception to
  "one reader of the environment."** A source's configuration cannot come from the config layer
  without reintroducing the circle, so it rides the compile-time value as a tuple —
  `{Catapult.Config.Static, %{"DATABASE_URL" => "ecto://..."}}`, `{Catapult.Config.File, path:
  "/etc/app.toml"}` — and lands as `load/2`'s `opts`. If some future adapter's own setting genuinely
  must be dynamic (the path of the file to read), the adapter reads it from the environment itself,
  below the layer. That is legitimate and it is the only such read: a source's bootstrap, never a
  component's value, which is the whole of what the layer was built to own.
- **#41 Dev selects the static source too, and that is what settles `.env`.** v5 §2.2 sketched
  per-component `.env` files alongside prefixed env vars; they are not built, and the reason is that a
  dotenv file exists to feed environment variables to a process that reads the environment. Dev does
  not: its values already live in `config/dev.exs`, in the file a developer edits, under review, with
  no untracked local file to explain when someone's machine behaves differently from everyone else's.
  The environment source is what a deployment runs, which is where variables actually come from
  something other than us. **The fake is not a hole:** the static source validates its map against the
  same declarations — a missing key or a value that fails its cast is the same report — because a
  source that skipped validation would let a key enter the system undeclared, and the declaration is
  the whole product here.
- **#42 The fake ships in `lib/`, not in `test/support/`.** Conventions §9 says the fake ships with
  the port; for a package the sharper form is that it ships in the package.
- **#43 It is seeded once, statically, and offers no `put_config(pid, key, value)`** — no
  process-dictionary scoping and no ownership tree in the shape of the Ecto sandbox.
- **#44 Vapor is not a substrate dependency.**
- **#45 This is a scoping of conventions §1's blessed list, not a substitution** (§1: don't
  substitute without a systems-doc decision — this is that decision). Vapor remains the sanctioned
  answer the day a project needs config from a file, a remote source, or a format the environment
  cannot carry; nothing here needs that, and the port means adopting it then is one new module and one
  compile-time line, not a migration.
- **#46 The gate set is a property of a mix project, not of the repo.** The audit's greps are
  `Path.wildcard("lib/**/*.ex")`, rooted at the working directory — deliberately, because this task
  ships into every generated project and the shape of *this* tree is not a fact it may hold. The
  consequence is the rule: every mix project here runs the whole conventions §2 set in its own
  directory, and adding a mix project means adding its gate block.
- **#47 The invoker that names both projects lives in the root `mix.exs`,** as a
  `catapult.audit.all` alias running `catapult.audit` and then `cmd --cd components/substrate mix
  catapult.audit`.
- **#48 `catapult:allow` spans one line or two, and marks code, never
  prose.** *(Amended in implementation, ORC-30 — the sketch said
  same-line only; see below.)* The tag is honored on the matching line
  or on the comment line directly above it, and on no wider span,
  because any wider one asks each reader to work out how far a given
  escape reaches and an escape whose extent is arguable is worse than
  none. The line above must itself be a comment, or a tagged violation
  would excuse an untagged one on the next line.
- **#49 Documentation that names a banned construct is reworded, not tagged:** an allow tag asserts
  "this occurrence is a deliberate exception", and spending it on a sentence *about* the ban degrades
  the one signal review has, in a package whose docs get published.
- **#50 The supply gate is Hex-sourced; `mix_audit` is a second opinion, not the signal.**
- **#51 An advisory we cannot act on is acknowledged in `mix.exs`, never
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
- **#52 Substrate carries its own supply gate and never takes an audit dependency to get one.** It
  resolves its own lockfile, so the root's audit does not cover it — the versions coincide today,
  which is luck rather than a property, and nothing would report the day they diverge.
- **#53 The license check reads declarations, never paths — and it takes
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
- **#54 What neither of them is, is a path.** The gate-set decision above rules out teaching this
  task where *this* repository keeps its components, and "for every mix project under `components/`"
  is that reach in its purest form.
- **#55 Arming and standard are two facts.** `package:` and `licensing/0` decide *whether* a tree is
  checked; the project's `allow:` list decides *against what*. A project that arms the check and
  states no list is inert rather than held to ours (below), so the pair is not redundant — a
  declaration can arm a check that then has nothing to measure with, and the census line exists to say
  exactly that.
- **#56 `licensing/0` is one callback carrying both facts, and it sits
  outside the roster table beside `config/0`** (ORC-16). It returns a
  keyword list — `[distribution: :distributed, license: "Apache-2.0"]` —
  with both opts required, an overridable empty default, and no
  `@optional_callbacks`.
- **#57 The class chooses between two dependency policies, not three, and
  the reasons differ where the list does not** (ORC-16). The cases
  collapse to two policies — *checked* against the project's list, or
  *unchecked* — and the collapse is what makes "strictest wins" a total
  order rather than a merge.

  | The subject's own terms | How it reaches people | Dependencies | Because |
  | --- | --- | --- | --- |
  | on the project's list | conveyed (`:distributed`, or a published `package:`) | **checked** | a recipient would inherit terms nobody offered them |
  | `LicenseRef-*` | conveyed | **checked** | we would be conveying a work under terms we have not met |
  | on the project's list | `:service` | unchecked | we offer source on those terms, so nothing a dependency asks is a cost already unpaid |
  | `LicenseRef-*` | `:service` | **checked** | AGPL §13 would oblige an offer of source to our own users |
  | any | `:internal` | unchecked | nothing is conveyed and nobody is served |

  **The check reads two things off a license identifier and infers nothing else, and that is why there
  is no *public copyleft, conveyed → unchecked* row.**

  Instead, a project that conveys under copyleft says so by putting its own identifier on its own
  list, and its dependencies are then checked against a list containing it.

  So an identifier is `LicenseRef-*`, or it is on the project's list,
  and there is no third bucket. **An identifier in neither is a
  reported problem**, wherever it is a subject's own declaration —
  `:internal` included, where it decides nothing about dependencies and
  is still a declaration the project's own policy cannot place. That is
  what stops `license: "Proprietary"` from reading as an open-source
  identifier and taking the unchecked branch.

  One consequence, named because it reads as a bug the first time: a project's `allow:` list contains
  its own license too, even where nothing is checked — a plane that states a policy at all lists
  `AGPL-3.0-only` beside identifiers no dependency will ever be measured against.
- **#58 "Ours" and "proprietary" are read off the identifier, not declared again.** SPDX already
  spells "no listed license applies": `LicenseRef-<id>`. So a `:service` component under
  `LicenseRef-Catapult-Hosted` is the closed case and one under any listed identifier is the open one,
  with no third class and no `proprietary: true` beside a license that already says so — two places to
  state one fact are two places that can disagree.
- **#59 The list is shared; the reason is not, and the report prints the reason.** Shared means one
  list per project, and the sharing is what the argument rests on.
- **#60 The strict row stays strict, and configurability is what makes it cheap.** Proprietary
  `:service` is held to the same list as the shipped layer rather than to "no copyleft", so `MPL-2.0`
  and `EPL-2.0` are outside that row until a project's list says otherwise.
- **#61 A subject is held to the standard it holds its dependencies to,
  and silence is reported rather than defaulted** (ORC-16). The two
  resolve together.
- **#62 Its own license is checked by the same rule.**
- **#63 An undeclared component is a reported problem, never a default class.**
- **#64 A licensing verdict never fails a boot** (ORC-16). The composer validates the declaration's
  *shape* — unknown opt, missing opt, a `distribution:` outside the vocabulary — because that is what
  it does for every other declaration and it needs no environment. The *policy* — the project's list,
  the closure, the undeclared report — is the audit's alone.
- **#65 The predicate is ours; the list is the project's** (ORC-16), and
  that is why it is not the waiver the entry below refuses. The
  criterion is ours: not "permissive" but *imposes no terms on the
  linking application*, which is what `LICENSING.md` actually requires —
  a customer's application inherits nothing — and what makes an addition
  decidable instead of a debate about what "permissive" means. The list
  the criterion produces is the project's.

  **The project states it in `mix.exs` beside `package:`**, under one
  `licensing:` key carrying the policy and the overrides together:

  ```elixir
  licensing: [
    allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC),
    overrides: [cowboy_telemetry: "Apache-2.0"]
  ]
  ```
- **#66 One list per project, not one per class.**
- **#67 A project stating no policy is inert, and the census line says so.**
- **#68 The default value lives where projects come from, not in the check.** Catapult's five —
  `Apache-2.0`, `MIT`, `BSD-2-Clause`, `BSD-3-Clause`, `ISC` — are what `bundles/default` writes into
  a generated project's `mix.exs`, literally, so the project can read what it is being held to and
  edit it. Never `allow: Catapult.Bundle.default_licenses()`, which is the constant one level in and
  the path rule wearing a different hat. The obligation on `bundles/default` is recorded in
  `systems/platform_content.md`, and substrate states its five by hand — as it must in any case, not
  being a generated project.
- **#69 An override supplies a fact; nothing supplies a permission**
  (ORC-16). A dependency whose license the metadata cannot answer — no
  `hex_metadata.config` at all, or a spelling the list does not contain
  — is resolved by an entry in `mix.exs` naming the license a human
  read out of that package's own LICENSE file. It is then checked like
  any other: an override recording `GPL-3.0-only` fails the audit
  exactly as the metadata would have.

  There is deliberately **no ignore list, no `catapult:allow` reaching this check, and no
  per-dependency waiver.**
- **#70 Nor is a minimal one-identifier `allow:` list the honest minimum on a project whose check is
  unarmed.**
- **#71 Licenses match as exact SPDX identifiers, with no normalization table and no reading of
  LICENSE text.**
- **#72 A git-distributed dependency resolves through an ordered rung
  ladder, not straight to `overrides:`** (ORC-74). `unresolved/2` fires
  today for any dependency with no `hex_metadata.config`, and that file
  is a hex-fetch artifact — every dependency reached over git rather
  than hex lands there, unconditionally, the day §3.1 lands any of them.
  Applied to Catapult's own components consumed by another component or
  by a generated project (v5 §3.5's dependency mode), that turns
  `unresolved/2`'s "record an override" instruction into a standing
  requirement that every consumer hand-maintain a license entry for the
  platform's own packages — the inventory `docs/non-goals.md`'s
  no-hand-maintained-inventories rule refuses, produced by the one check
  built to prevent exactly that shape of drift. The fix is four rungs,
  tried in this order, no tie-breaking and no reconciliation between
  them — the order is the decision, and the census names which one
  answered rather than folding "resolved" into one undifferentiated
  fact (below):

  1. **`hex_metadata.config`.** Unchanged: `declared_licenses/1`'s
     existing reading of a publisher's own conveyed assertion.
  2. **The dependency's own `licensing/0`.** `Catapult.Component
     .Licensing.declared/1` already reads this — today only for the
     *auditing* project's own composed `components`, to build the
     self-check subject list. This rung turns the same function on the
     *dependency*'s compiled code: `Catapult.Component.Licensing` gains
     a function that, given an OTP application atom, loads it
     (`Application.load/1` — offline, the same call this task already
     makes on the audited project's own `app`) and returns every module
     in it carrying the composer's own `__catapult_component__/0`
     marker (`Catapult.Component.Composer.component?/1`'s predicate,
     read from the application's module list instead of a hand-declared
     config). `Catapult.Audit.License` calls `declared/1` on each. One
     answering module resolves the rung; two that agree resolve it once;
     two that disagree resolve nothing, per the no-reconciliation rule
     below. Zero answering modules — every third-party git dependency,
     and any Catapult component not yet carrying `licensing/0` — leaves
     the rung unanswered rather than failing; rung 3 gets the next try.

     Deliberately not read off the auditing project's own `:components`
     config. That list is what the project composes into its own
     supervision tree, and a dependency it resolves without adopting —
     v5 §3.5's default consumption mode, the ordinary case for a
     component reached this way — is never on it. Reading that list
     instead of the dependency application's own modules would silently
     blind this rung to the exact case it was built for.
  3. **An explicit `SPDX-License-Identifier:` line in the dependency's
     own LICENSE file** — the rung that reaches a *third-party* git
     dependency, which rung 2 cannot, since it never declared any
     `licensing/0` to read. Checked at `deps/<app>/LICENSE`, then
     `LICENSE.md`, then `LICENSE.txt`, then `COPYING` — a fixed, closed,
     ordered list, the same discipline `licensing/0`'s known opts and
     `licensing:`'s known keys already hold to — and the first of the
     four that exists is the one read; the rest are not consulted even
     if they also exist. A file with exactly one such line, whose value
     is a single token — no internal whitespace, so no `OR`, `AND`,
     `WITH` or parenthesis — resolves to that token. A file with zero
     such lines, two or more, or one whose value is not a single token
     does not resolve at this rung. `MIT OR Apache-2.0` is refused
     deliberately and not by oversight: it is a real, formal SPDX
     expression rather than prose, so declining to parse it reads as
     an inconsistency the moment somebody hits one. `AND`/`OR`/`WITH`
     and parentheses are a small grammar with precedence rules, and
     shipping one into every generated project to save one human
     reading one LICENSE file is the trade already declined for prose,
     arriving through a more sympathetic door. Nothing here reads a
     LICENSE file's prose: the rung matches one line's own declared
     syntax and stops if it can't, never inferring what a paragraph of
     legal text means — the same distinction the no-normalization entry
     already draws for hex metadata, held to for a second source.
  4. **`overrides:` in `mix.exs`.** Unchanged in shape, narrowed in when
     it is reached, and this is the consequence worth naming rather than
     discovering: today an override for `app` is read *before* metadata,
     so it silently corrects a present-but-unrecognized hex metadata
     value — the `nearly` fixture in `license_test.exs`, standing in for
     the real case this repo has measured, `cowboy_telemetry`'s
     `["Apache 2.0"]` (the no-normalization decision above).
     Under first-match-wins, rung 1 already answers for that dependency
     — a non-empty `licenses` list is a resolution whether or not any
     entry is a recognized identifier — so rung 4 is never reached for
     it. What changes for a human: an override can no longer *correct* a
     metadata value that parsed to something, only *supply* one where
     nothing above supplied anything at all. A misspelled hex metadata
     entry still fails the audit, exactly as any other unrecognized
     identifier does, and the fix is the place a wrong identifier has
     always been fixed — the project's own `allow:` list, if the
     spelling is one the project is willing to name outright — never a
     table and never a widened override.
  5. **Unresolved.** Fails, exactly as now. The message stays the "read
     its LICENSE and record it as `overrides:`" instruction it already
     is (`unresolved/2`); its parenthetical explaining why nothing
     answered grows a clause for each rung that was tried and came up
     empty, so a human reading a failed run knows what was already
     checked rather than re-deriving it.
- **#73 No reconciliation between rungs, anywhere in this design** — the same rule, applied at three
  seams rather than derived three times. Hex metadata and a component's own `licensing/0` are never
  cross-checked against each other, so a hex-published Catapult component whose package metadata
  disagrees with its own `licensing/0` is not caught by this path (unchanged from the ORC-16 note
  above; a missing or malformed `licensing/0` is still `undeclared_problems/1`'s concern for a
  component in the auditing project's own list, and a *dependency's* malformed `licensing/0` is that
  dependency's own `mix catapult.audit` run's problem to report — never re-diagnosed by a consumer,
  for the reason the declared↔read check settles below: the audit's scope is never widened to
  `deps/`). Rung 2's disagreeing modules and rung 3's disagreeing declaration lines both refuse to
  average, vote, or prefer one. And the rung order itself is the top-level instance: first to answer
  wins, nothing below is consulted once something above has — `overrides:` included, which no longer
  races hex metadata for a dependency it used to occasionally out-run.
- **#74 The census names which rung answered, not only that something did.** `armed_census/3`'s "N
  dependencies checked against M identifiers" line is silent today on how any of the N were resolved,
  and a green run built entirely on `overrides:` reads identically to one verified against every
  publisher's own metadata — the check-that-checked- nothing shape this ticket exists to remove from
  the ladder, arrived at through a different door than ORC-16's inert state but the same failure. The
  census gains a count per rung — metadata, component, license-file, override — printed alongside the
  total on every green run, so "resolved" from a publisher's registry assertion and "resolved" from a
  human's override are never one undifferentiated fact again.
- **#75 Scope is what a consumer would fetch, computed from metadata already on disk** (ORC-16). The
  in-scope set is the transitive closure over non-optional `requirements` in each dependency's
  `hex_metadata.config`, seeded by the project's own deps that survive into `:prod`.

  Two format facts, both measured, because the naive read of either is
  a wrong answer that looks right: `requirements` has two encodings — a
  flat proplist carrying `name` from mix-built packages, and a
  `{name, proplist}` tuple from rebar-built ones such as cowboy — and
  an entry may be `optional`, which makes it the consumer's dependency
  rather than ours, as `jason` declares `decimal`.
- **#76 `mix.lock` is not the source, and an absent package is a problem rather than a skip.** The
  lock carries names and checksums and no license at all; the metadata file carries the license, the
  version and the requirement graph, and sits beside the code whose terms are in question. A
  dependency in scope with no directory or no metadata is reported, never passed over — the reason
  `catapult.audit.all` dies loudly on unresolved deps instead of skipping the project, and the reason
  ORC-37 existed. Offline throughout: `:file.consult/1` over files `deps.get --check-locked` has
  already placed, so conventions §9's no-network rule reaches the audit without an exception.
- **#77 This walk is not shared with `Catapult.Audit.BoundaryApps`**, and the obvious reuse argument
  is recorded rather than left to be made again. The two closures answer different questions from
  different sources: this one is *what a consumer would fetch*, read out of publishers'
  `hex_metadata.config`, and it stops at a path dep because a path dep is another mix project audited
  in its own right; the boundary closure is *what this build can reach*, read out of compiled `.app`
  files, and it must descend into a path dep because the plane's `lib/` reaches `:plug` and
  `:telemetry` only through `components/substrate`.
- **#78 The check is a built-in of the task, in its own module, and is not
  a `Catapult.Audit.Check`** (ORC-16). `Catapult.Audit.License` holds
  the table, the closure and the report, because the audit is a check
  registry rather than a monolith and this check is larger than both
  greps together. What it holds no part of is the list of identifiers:
  the table is a rule about how code reaches people and stays ours, the
  list is a legal position and belongs to whoever is being held to it,
  and a module shipping into every generated project may carry the first
  and not the second. It does not adopt the behaviour: that callback
  takes a working-directory-relative glob, a dependency tree is not a
  path scope, and forcing it through means passing a scope value meaning
  "ignore this argument" — a callback lying about its contract in its
  first implementation. `policies/0` is how a *component* ships a check
  into projects that adopt it; this one is the task's own, present in
  every project and armed or silent by declaration.
- **#79 The inert state is never silent.** The check adds a census line naming the policy it
  reached, the subject that set it, and where the list came from — armed by substrate's own
  `Apache-2.0` package against the five identifiers its `allow:` states, or unchecked because every
  subject is a public-licensed service, or inert because the project states no policy at all.

### #80 The enforcement roster (ORC-21)

The checks v5 §2.14 gathered as sleepers, designed as a set because
three of them turn out to be the same decision and two of them are not
build work at all.

- **#81 The AST upgrade lands on `Catapult.Audit.Check`, not on Credo.** §2.14 adopted "AST-grade
  custom Credo checks", and this argues with the host rather than the grade — said out loud, per the
  rule about recorded decisions.

  **The cost is IDE surfacing, and it is real:** a Credo check
  underlines in the editor where an audit finding waits for CI. The
  reversal is what makes that affordable, so it is priced rather than
  promised — a Credo check that delegates to `run/1` is a wrapper in
  whichever project wants one, and no logic moves. What the wrapper
  needs is a parseable report, so the format joins the contract instead
  of remaining a habit: a problem that names a location spells it
  `path:line: message`, which is what the greps already emit.
- **#82 `catapult:allow` reads a comment the parser found, and an escape
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

  The new half is free only at AST grade and worth taking there: a tag excusing a line with no
  violation is reported.
- **#83 The compile-connected ratchet is a gate line, never a constant the
  audit reads.** Both halves of §2.14's xref item are stock —
  `mix xref graph --label compile-connected --fail-above N` exits 1
  above the threshold with no code behind it — so an audit check here
  would be a second implementation of a number `mix xref` already
  computes. Where the number lives, and why nowhere a ticket can reach,
  is conventions §2's.
- **#84 Arm it before there is erosion to measure.**
- **#85 The audit reports a missing gate; it never runs one.** Sobelow's
  arming rule is the case that decides this. An audit that shells out
  to another gate swallows that tool's exit code and its output
  formatting, and becomes a meta-runner whose own report is the least
  interesting thing in it — while `qualityGates` and `ci.yml` are
  already the place where a gate is a line. So the audit's finding is
  the gap: *this project has a web layer and no sobelow gate*, which is
  the part invisible from anywhere else, and arming it is the ordinary
  author edit every other gate takes.
- **#86 The predicate is `:phoenix` in the dependency tree, never a directory name.** §2.14's
  shorthand — arms "when `catapult_web` appears" — names a path in *this* repo, and a shipped,
  cwd-rooted task may not hold that fact any more than it may know where this repo keeps its
  components (the gate-set decision above).
- **#87 The two VM guardrails are not one grade, and the registry should stop implying they are.**
  §2.5 says the BEAM enforces both. It enforces one.

  So `max_heap_size` stays an enforced bound, and the mailbox bound becomes a declared threshold that
  is *sampled and reported* — the opt renamed `message_queue_alarm_len:` so the declaration states its
  own grade, since `max_` is a promise the platform cannot keep. Where the sampling lives is
  `systems/observability.md`'s.
- **#88 Guardrails are applied by the process and checked by the audit; the composer does not thread
  `spawn_opt`.** A flag can only be set from inside its own process (`process_flag/3` covers
  `save_calls` and nothing else), so the only external route is `spawn_opt` on the start call — which
  requires the composer to know each child's option conventions, for children it did not write, and
  fails outright for the first child whose `start_link` accepts no options. That is the audit's layout
  knowledge wearing a different hat. A one-line call in `init/1` reading the component's own
  declaration is what the process owns anyway, and declared↔applied is then the same check shape as
  declared↔constructed and declared↔emitted — a third instance of a pattern the platform already has
  two of.
- **#89 The checker is the audit, not the composer.** The composer sees declarations;
  declared↔applied needs *call sites*, and a call site is a fact about a tree. So it lands beside the
  other declaration↔tree check (`Catapult.Audit.Declarations`) — the pattern it is a third instance of
  is an audit check both times. The composer's half is the important half: it never threads
  `spawn_opt`.
- **#90 `errors/0`'s struct is generated from the registry, so one
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
- **#91 Amended in build (ORC-21): the grade is construction-time, and the registry is read at
  construction rather than at compile time.**
- **#92 Secret config values are wrapped, not audited.** "Never appears in
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
- **#93 Export metadata carries registered vocabulary and nothing else.**
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
- **#94 The ES property templates are a macro, and that is why StreamData is not a dependency.**
  §2.4 ships templates with the family; a template that is copied stops matching the invariant the day
  the family changes one, and nobody re-copies. A macro that injects the replay-determinism,
  idempotency and round-trip properties keeps "the property is the floor" literal — adopting the
  family is what makes the property present. The dependency question then answers itself: a module
  that only *quotes* `StreamData` never compiles against it, so the property generator ships here
  while `stream_data` is a test-scope dependency of the project that expands it.
- **#95 The external-HTTP rule is a boundary declaration, not an audit
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

  **The residue is Erlang, and it is not a check this package ships** (ORC-52). Boundary documents
  that calls to `:elixir`, `:boundary` and pure Erlang applications cannot be restrained — so a plane
  module reaching a model provider through `:httpc` is invisible to the compile grade, and conventions
  §11 is *mostly* a compile error rather than wholly one.

    * **Substrate ships the mechanism and nothing else.**
      `Catapult.Audit.Check`, `Catapult.Audit.Source` and the
      `policies/0` roster row are exactly what a project needs to state
      a ban of its own at this grade, and all three are already here.
      A project inherits the ability, not the ban.
    * **This ban may not join `@platform_checks`, or live here under
      another name.** That set is inherited by every project that runs
      the task at all, and "no model calls" is a *plane* rule:
      conventions §11's second bullet has generated projects making
      model calls through the LLM adapter, so a package-wide egress ban
      would fail the audit of a project doing exactly what the platform
      told it to do. Hosting it here unregistered is the same defect
      one level in — the list of banned modules is Catapult's
      policy, and a policy compiled into a package that ships into
      trees we do not own is the `Catapult.Audit.License` allowlist
      mistake, one registry over (the predicate-is-ours decision
      above).

  The one thing `externals/0` still owes the audit needs no new field:
  an entry's `adapter:` and `fake:` must declare a behaviour in common.
  A fake that has drifted off its adapter's contract is a test lying
  about a system it never called, and both modules already carry the
  answer in their own attributes.

- **#96 The apps list that arms that declaration is checked for completeness, by
  `Catapult.Audit.BoundaryApps`** (ORC-50).

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
- **#97 The subject is what a `:prod` build can reach, and it is computed rather than listed.** Seed
  from the project's own `deps` that survive into `:prod` — the `only:` filter
  `Catapult.Audit.License` already applies — then walk each application's compiled `.app` file
  (`Application.spec(app, :applications)` and `:included_applications`), keeping only what
  `Mix.Project.deps_apps/0` also contains, which is how OTP's own applications fall out without a list
  of their names.
- **#98 It does not share `Catapult.Audit.License`'s closure, and the divergence is the point.**
  That walk answers *what a consumer would fetch*, from publishers' `hex_metadata.config`, and it
  deliberately does not descend into a path dep, because a path dep is another mix project audited in
  its own right. This one answers *what this build can reach*, which includes a path dep's own
  dependencies — and the plane is the case: `:plug` and `:telemetry` reach `lib/` through
  `components/substrate`, not through any root `deps` entry.
- **#99 Both modes, not either.** `Boundary.Definition` expands a bare atom to `{app, :runtime}` and
  `{app, :compile}`, so a list may legally carry one mode alone — and a `{app, :runtime}` entry leaves
  compile-time calls unchecked, which is the same fail-open one level smaller. Coverage means both
  modes; a half-covered application is reported.
- **#100 Coverage, never equality.** A name in the list that the closure does not contain is not a
  problem: `:req` is `only: :test` and is named deliberately, and a list is free to say more than the
  floor requires.
- **#101 A built-in of `mix catapult.audit`, not a `policies/0` entry**, on
  `Catapult.Audit.License`'s recorded criterion rather than by analogy with it:
  `Catapult.Audit.Check.run/1` takes a working-directory glob, and a dependency graph is not a path
  scope, so registering this would mean passing a scope argument that means "ignore me". `policies/0`
  is how a *component* ships enforcement into projects that adopt it; this is the task's own, present
  everywhere and armed or silent by declaration. It takes no dependency on Boundary either — it reads
  a keyword list out of `Mix.Project.config()` and never calls the library, which is what keeps it
  shippable in a substrate that refuses dependencies on other people's behalf.

### #102 What a check may infer (the standing limit)

Every check in `mix catapult.audit` decides on facts a parser can see
in the file in front of it. Where an honest answer would need the
value of a variable, the check reports the call it cannot resolve
rather than guessing, and the residue is stated rather than covered.
One property is the reason, and it is why all of the rulings below
came out the same way: **a shallow analysis reported as a guarantee is
worse than a stated gap.** A check that misses is read as coverage,
and a run that passed without checking anything is the exact defect
these checks are filed about.

Five requests for inference have been refused on that rule, recorded
so the next pass reaching for one finds the answer rather than
re-deriving it.

- **#103 No taint analysis for secret config values** (ORC-21). v5 §2.2
  asks that secret-flagged values never appear in logs or error
  payloads, and the tempting reading follows a value from the accessor
  to a `Logger` call. A value bound to a variable, put in a map, or
  passed to a helper is out of reach of any check that is also free of
  false positives. The wrapper type holds the property everywhere at
  once — a redacting `Inspect`, an explicit unwrap — and the audit
  keeps only the exact one-hop residue: an unwrap inside a logging
  call. If the wrapper is ever found insufficient the answer is a
  narrower unwrap surface, not a deeper analysis.
- **#104 No dataflow for a computed config key**, and no reading a dynamic
  `fetch!/2` as a wildcard (ORC-48). Treating `fetch!(:foundation, key)`
  as reading *everything* `:foundation` declares, so nothing
  false-positives, is the cheaper alternative, and it is a whole slug's
  worth of coverage switched off by a call that says so nowhere, in a
  check whose entire subject is dead declarations — the silence is the
  defect, not the strictness. Reporting the unjoinable call keeps the
  run red and names the cause, the same trade as reporting an
  unparseable file instead of skipping it. A legitimate computed read
  would be an argument for a second accessor that declares what it may
  reach, never for the check guessing.
- **#105 No destination detection on a model call** (ORC-52): nothing reads
  a URL, a hostname or a provider name out of an HTTP call's
  arguments. At AST grade the call is `:httpc.request(:post, {url,
  ...}, [], [])`, and whether `url` reaches a model provider is data —
  decided at runtime, normally read from configuration. Matching a
  provider hostname in a literal catches a spelling nobody writes and
  reports clean on every real instance of the thing the check is named
  after. What is built instead bans the *transport*: no plane module
  calls a pure Erlang HTTP client (`systems/foundation.md`), which is
  decidable, broader than conventions §11, and exact. The destination
  is not a static fact and no amount of check will make it one.
- **#106 No catalogue of the ecosystem's HTTP clients** to close the Elixir
  half (ORC-52). `check: [apps: [...]]` checks the applications it
  names, so an Elixir HTTP client is unchecked until it is named there
  — a real residue, carried in `systems/foundation.md`'s own sentence
  rather than left implied. A check that knows `:tesla`, `:finch`,
  `:mint`, `:httpoison` and the rest has a coverage list of the world
  maintained by us, and a failure mode of silence for every client not
  on it. The existing mechanism is better than the check would be: an
  Elixir client cannot be called without being a dependency, a
  dependency is a v5 §2.8 named decision visible in the same diff, and
  the `check:` line belongs in that diff. This is the one half of
  §11's enforcement where the thing being added announces itself.
- **#107 No reader-identity rule on config reads** (ORC-48) — the check does not police *who* reads
  a key, narrowing ORC-4's own phrasing out loud rather than quietly.

The same rule decides where an escape may exist, and twice the answer
has been nowhere.

- **#108 No `catapult:allow` on either direction of the declared↔read check** (ORC-48).
  `Catapult.Audit.Declarations` already refuses the tag for what it reports — the escape excuses a
  *line* the parser found, and a dead declaration is the absence of one — but the unjoinable-read
  direction does name a line, so the exception is refused on its own merits rather than inherited.
- **#109 No exemption list on the boundary-apps check** (ORC-50): no ignore entry, no
  `catapult:allow`, no per-application waiver. Three kinds of application sit outside the completeness
  requirement and every one of them is *derived*, so no name is written and none can be spent —
  `:boundary` itself (`Boundary.Checker.check_external_dep?/3` opens by excluding it), applications
  contributing no `Elixir.*` modules (`Boundary.Mix.app_modules/1` filters them out, so no list entry
  could restrain a call into one), and path deps (read off `:path` in the dep options; naming one
  reproduces ORC-21's defect at twelve forbidden references and a red build, measured).

### #110 The config declared↔read check (ORC-48)

`config/0` was the last registry with no declared↔used fact while every
neighbour had one — errors declared↔constructed, guardrails
declared↔applied, telemetry declared↔emitted. This check closes it, and
`Catapult.Audit.Declarations`' own moduledoc carries the design where it
would be edited: the two directions and why they deliberately take
different subjects, the in-tree predicate and why the destructive
direction is what decides it, the suppression rule for an unjoinable
read, and why no `catapult:allow` is honoured on either side. Two
things belong here instead.

- **#111 The join is exact where declared↔applied is approximate, and that is a property of the
  accessor's signature rather than of this check.** `fetch!(slug, key)` names a declaration completely
  — the slug is the spine every claimed name hangs off and the store is already keyed by it — so the
  join is on the pair, with none of the name-shaped ambiguity `Guardrails.apply!/2`'s single `name`
  leaves.

- **#112 `config/0` gets no census line.**

## #113 Initial vs target

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

## #114 Depends on

Nothing in this repo (it is the bottom). Boundary and PromEx as
library deps.

**Vapor was named here and is not, per the standing decision above**
(ORC-4). Recorded as an amendment rather than a quiet deletion,
because the line was a real prediction from the Phase 0 pass and the
next reader of conventions §1 will expect to find it: the config layer
is a port with a zero-dependency environment source, and Vapor — if it
is ever wanted — is an adapter in a project that wants it, never a
dependency this package imposes.
