# Catapult — confirmed non-goals

The negative space, recorded with reasons (v5 §1.1's doctrine, eaten
by us first). Proposing one of these is not forbidden — but per
orchestration's rule, do it knowing you are arguing against a
recorded decision, and say so explicitly.

- **No self-bootstrap.** Catapult is not built from its own doc
  graph; orchestration delivers it (v5 §1.3). Reasons: the
  self-modification crash risk (a bad deploy bricking the tool that
  fixes it), the size mismatch (Catapult is smaller than its target
  class, so self-hosting proves little), and the historical fact
  that the byte-identity bootstrap requirement is much of why v4
  never shipped. The sane residue: Catapult consumes the shared
  components as an ordinary library user.
- **No absorption of existing codebases.** Projects enter as fresh
  scaffolds; documentation and tracker history seed the feature set;
  code is regenerated. The platform's structure is narrow by design
  and existing apps won't conform to it; an absorption mode is a
  different product. (Author decision, Polyphony conversation.
  Revisit condition: none foreseeable soon — "so far out of scope we
  may as well not think about it.") Boundary sharpened at the mocks
  pass: user-supplied mocks and design systems enter as **seed
  evidence and pinned artifacts** (v5 §4.1, §5.4) — read, rendered,
  designed against, never absorbed; business logic still
  regenerates.
- **No workflow interpreter in the DSL, no bundle-side code, no
  Turing-complete predicates** (v5 §6, §7.10, §9). The plane's
  Commanded aggregates are the semantics; declarations configure
  them. Extensions are platform-shipped. This is a correctness
  property the scheduler, audit, and security posture lean on.
- **No per-project protocol restructuring** (v5 §7.10). Projects
  bind tracker ids and tune marked thresholds; states and gates are
  platform-fixed, because prompts, plane logic, and shared
  vocabulary are all written against them.
- **No tracker product.** Linear is the working UI, behind the
  Tracker port. The tell that would reopen this: catching ourselves
  teaching Linear state (custom fields carrying doc-graph data,
  load-bearing prose parsing). Until then, the port keeps the exit
  cheap and we build zero tracker UI.
- **No dashboard-as-working-surface** (v5 §7.4, systems/dashboard.md).
  Debugging and observation only, *for the work loop* — artifact
  review and ticket action live in Linear and PRs. Settings and
  onboarding (the bindings UI, v5 §7.10) and the configuration
  surface (a composer that files graph-state changes as PRs — it
  never bypasses a gate) are ops and authoring-composition, not the
  work loop, and are explicitly in-bounds.
- **Catapult never executes target-project code** (v4 §A.10.5
  carried forward, sharpened): agent runs execute code in their own
  CI/runner environments; the plane dispatches and observes but
  never runs generated code in-process. The plane's blast radius is
  its own.
- **No multi-writer projects.** One driving author per project;
  collaborators read. The coordination model for concurrent human
  writers is a different system (v4 §A.0.1 commitment 4, still
  true in v5).
- **No experimentation/percentage-rollout flag machinery** (v5
  §2.10): release flags, ops kill-switches, actor targeting — no
  more. Machinery without a customer at this scale.
- **No LiveView/React mixing within one frontend target** (v5 §1.4):
  one product tier, one stack per target.
- **No hand-maintained inventories**: no code inventory in systems
  docs (the code is the inventory), no hand-written permission
  matrices, no hand-written API docs where generation exists.
  Documents that mirror code drift silently; every such document is
  generated or absent.
- **No second home for the reference instance's live facts.** App
  name, region, public hostname, port, autodeploy, the migrate
  PRE_DEPLOY job: `SETUP.md` §2 records them and nothing else
  restates them. The README says the deployment exists, that
  `/health` is the only served path, and points at §2 — nobody
  opens a README to find a database cluster name, so the one home
  is the file a reader is already in when the values matter.
  (Author decision, ORC-40.) This is the entry above one level up
  rather than a case of it: that rule is scoped to documents
  mirroring *code*, and these are prose facts about a running
  system, but the failure mode is identical and we have first-hand
  evidence. ORC-2's README paragraph (`4a4aa91`) sourced the
  deployment to `.do/app.yaml` one commit after `b5c878f` deleted
  that file — the same paragraph, in its first week, citing
  something that no longer existed. The next drift is a hostname or
  a port, which a reader acts on. Corollary, and the reason no
  check is added: **no doc-lint holding the two files in
  agreement.** A lint is what a second copy needs; one home needs
  nothing, and these facts leave the tree entirely at
  open-sourcing, so the lint would be written to be deleted.
  **Amended (ORC-29): the public hostname's home moves, it does not
  multiply.** The live suite has to dereference that value and prose
  cannot be dereferenced, so the hostname becomes
  `config/test.exs`'s `:live_base_url` and §2 names the key where it
  used to print the URL. Every other fact in §2 stays put. The
  amendment is faithful to the reason rather than the letter: what
  ORC-40 was written about is a stale copy nobody checks — a README
  paragraph citing a file deleted one commit earlier — and a
  hostname the live suite reads at every boundary is checked by
  machine once a milestone, going red and naming itself when it
  drifts. Prose never had that property. The rule the amendment
  keeps: still one home, and a fact acquiring a code consumer moves
  to where code can read it rather than getting a copy there.
- **No vendored, pinned or freshness-checked copy of the advisory
  database** (ORC-37). The obvious repair for `mix deps.audit`'s
  fail-open — clone `mirego/elixir-security-advisories` ourselves,
  assert it is non-empty and recent, fail the build otherwise — makes
  us the maintainer of a fork of someone else's mirror of the GitHub
  Advisory Database, with its refresh cadence as our build's
  liveness dependency. The gate is bought far more cheaply by
  sourcing the signal from Hex, which cannot report clean from a
  fetch it did not make. Revisit condition: Hex's advisory feed
  proving materially behind the GitHub database in practice, which
  would be an argument for a real second source rather than for
  babysitting this one.
- **No `mix_audit` dependency in `components/substrate/`** (ORC-37).
  Substrate is Apache-2.0 and ships into every generated project, so
  each dependency it declares is one imposed on trees we don't own.
  `mix hex.audit` is built into Hex and covers substrate's lockfile
  for free; adding a package to obtain a weaker second opinion spends
  other people's dependency budget to do it.
- **No removal of `mix deps.audit` now that Hex covers the gate**
  (ORC-37). Demoted is not deleted: it reads the GitHub Advisory
  Database, which is a genuinely different source, and it earned its
  place the day it armed by catching the postgrex advisory and
  forcing the series bump (ORC-3). Two sources disagreeing is the
  condition this ticket made legible, not a defect to resolve by
  dropping one until the Hex feed is shown to dominate it.
- **No cross-project reach in `mix catapult.audit` itself** (ORC-30).
  The task's file globs stay rooted at the working directory. It is
  not taught to descend into `components/**`, not given a `--path`,
  and not taught to discover sibling mix projects, so that one run
  covers the tree. Reason: the task is substrate code — Apache-2.0,
  shipped into every generated project — and the layout of *this*
  repository is not a fact it may hold. Two runs of a layout-ignorant
  task beat one run of a task that knows where Catapult keeps its
  components, because the second kind is what a customer inherits.
  **The sanctioned form is the opposite end of the same wire:** a
  `catapult.audit.all` alias in the *root* `mix.exs` that invokes the
  task once per project (`cmd --cd components/substrate mix
  catapult.audit`). That is AGPL plane code which never reaches a hex
  consumer and whose job is precisely to know this project's own
  layout, so it is in bounds and is not an exception to this entry —
  the prohibition is on the *task* carrying the knowledge, never on
  this repo carrying it. Do not delete the alias as a violation of
  this line; it is the line's intended shape. The accepted
  consequence is a standing decision in `systems/substrate.md`: the
  conventions §2 gate set runs per mix project, and a new mix project
  brings its own gate block. Revisit condition: enough mix projects
  that the repeated block is itself what drifts — at which point the
  answer is CI looping over discovered projects, still one
  working-directory-rooted audit each, and still not a glob that
  reaches.
- **No `:live` tag on a test that doesn't cross a real network
  boundary to a real external system** (ORC-29). The tag buys a seat
  in the once-per-milestone suite and nothing else, so a `:live`
  test that exercises the health plug in-process — or over a
  listener this same job started — reproduces the empty gate this
  ticket was filed about, one level in, and worse: `no-tests` at
  least says nothing was checked, where a green run over a local
  fixture claims the world was. If a test needs no deployed thing,
  it belongs in the default suite, where its determinism is an asset
  instead of a disguise.
- **No `test/live/` directory** (ORC-29). Live tests sit beside the
  system they exercise, under that system's file map, and the tag
  alone decides the cadence. A directory is a second axis that can
  disagree with the first, and one directory holding every system's
  live tests would give a single file map a veto over every system's
  tickets — the mutex collision the maps exist to prevent.
- **No polling or retry-until-deployed in the live suite** (ORC-29).
  Deploy detection is the plane's job and already exists (poll the
  App Platform API, compare SHAs). A live check that waits out a
  rollout is a second, slower deploy detector, and its long timeout
  is exactly where a real outage hides. A bounded per-request
  timeout is the whole budget.
- **No asserting the deployed SHA equals this checkout's** (ORC-29).
  Autodeploy fires on the merge to main and the boundary run follows
  within minutes, so equality races the rollout and produces a flake
  — and a flaky boundary signal costs more than the coverage it
  would buy, which is the failure mode ORC-29 exists to stop. Assert
  the SHA is stamped (not the `"dev"` fallback), which catches the
  real defect — an image that never went through the build path —
  without racing anything.
- **No argv-sniffing in the `test` alias** (ORC-29). The tempting
  version notices `--only live` and skips `ecto.create`/
  `ecto.migrate` so the live-suite job needs no database, saving an
  author-owned workflow edit. Rejected: that alias is what makes
  `mix test` correct for every other run in the repo, and a version
  that drops migrations on the strength of a flag fails silently and
  in the one direction that matters — a suite passing against a
  stale schema. The job gets CI's environment instead; the edit is
  cheap and it is visible.
- **No config-library dependency in `components/substrate/`, Vapor
  included** (ORC-4). This is the third entry of the same shape and
  the shape is now the rule: substrate is Apache-2.0 and ships into
  every generated project, so a dependency it declares is one imposed
  on trees we do not own. The measurement, because this one was an
  open question rather than an instinct: `vapor 0.10.0`, released
  2020-08-12 and the newest there is, declares `jason`, `norm`, `toml`
  and `yaml_elixir` as ordinary runtime dependencies, so it would put
  a TOML parser and a YAML parser into every generated release in
  order to read environment variables — against three runtime
  dependencies in substrate today. What remains of Vapor once the
  casts, the aggregation, the store and the provenance keying are ours
  (`systems/substrate.md` argues each) is `System.get_env/0`, so
  substrate ships an environment source with no dependencies and the
  plane runs that same source. **Not a ban on Vapor**, which is still
  conventions §1's blessed answer and is still what a project reaching
  for file, remote or non-string config should adopt — a ban on
  substrate being the thing that decides that for everyone. Revisit
  condition: config the environment genuinely cannot carry, in the
  substrate itself rather than in one consumer, at which point the
  port takes an adapter and this entry is what gets argued with.
  **Sharpened at the second pass (ORC-4), because "the port takes an
  adapter" was doing too much work:** the port's domain is flat,
  string-valued named settings arriving over a transport other than
  the environment, and that is what an adapter is for — a mounted
  secrets file, a remote parameter store. A *structured* document,
  with nesting and lists of maps, is not a config source in this
  sense; it is content, and it belongs in `config/*.exs` or a real
  document loader. Vapor is the right answer on that side of the
  line and this port is the wrong one, so the revisit condition
  splits: flat settings from a new transport are an adapter, and a
  structured document is not a reason to argue with this entry at
  all — it is a different problem that never wanted the config layer.
- **No `.env` files** (ORC-4), against v5 §2.2, which sketched
  per-component `.env` alongside prefixed env vars. A dotenv file
  feeds environment variables to a process that reads the
  environment; under the compile-time source selection in
  `systems/substrate.md`, dev reads `config/dev.exs` instead, so
  there is nothing for the file to feed. What it would add is an
  untracked local file that changes behaviour — the "works on my
  machine" surface, bought for an ergonomic gain over editing a
  tracked config file that is close to zero. Revisit condition: a
  developer needing a real secret locally that cannot be committed —
  which is a keychain or a shell profile, not a feature of the config
  layer.
- **No runtime reconfiguration** (ORC-4). Config is read once, before
  the root supervisor starts, and does not change until the next
  boot: no watcher, no reload signal, no swapping a value on a running
  node. Reason: a value that can change under a running process is a
  value every reader must re-read and no reader can hold, which is a
  distributed-systems problem bought in exchange for redeploying —
  and this platform's deploy model is one environment, autodeploy on
  green, so the redeploy is the cheap thing here. It is also the same
  boundary the flag-machinery entry above draws: the cases that
  actually want live change are kill switches and rollouts, and those
  are named non-goals, not features waiting for a config watcher.
  Load-once is what makes `:persistent_term` correct and what lets the
  boot report be the only report. **Amended at the second pass (ORC-4)
  with where the cost actually sits,** since design review asked what
  happens if a remote source ever wants watch semantics: not in the
  port. `Config.Source.load/2` is a pull, a remote fits it unchanged,
  and push would arrive as an `@optional_callbacks watch: 2` that the
  shipped sources decline — one module and one line. The reason this
  entry stands is the *accessor*: a value that can change is a value
  no caller may hold, and holding it is what `:persistent_term`
  write-once buys. Whoever argues with this line is therefore arguing
  for a re-validation path that can reject an update without killing
  the node, a rule for readers holding stale values, and atomicity
  across values that must change together — three decisions, not a
  callback. Naming them is the point: the port stays cheap to grow so
  that the expensive half is the half being debated.
- **No per-test or per-process config overrides** (ORC-4). The test
  fake is seeded once, statically, and offers no
  `put_config(pid, key, value)` — no process-dictionary scoping, no
  ownership tree in the shape of the Ecto sandbox. Reason: a value
  that varies per test case is an argument wearing config's clothes,
  and the honest fix is the function taking it. The dishonest fix is
  the one being ruled out here, because it costs shared mutable state
  under `async: true` — the flake class conventions §9 calls a
  protocol requirement to avoid, since two CI reds escalate to a
  human. Revisit condition: a boundary export whose behaviour must
  genuinely differ by a declared config value within one suite, where
  passing it as an argument would distort the production signature.
  That case is real enough to name; it has not appeared yet, and
  building the machinery before it does would mean building the
  sandbox's hardest feature on speculation.
- **No per-key lookup on the config source port — no `fetch/1`, no
  `get/2`, no `all/0`** (ORC-4, second pass). `Config.Source.load/2`
  takes every declared name in one call and returns what it found;
  the obvious alternative, a source answering one key at a time, is
  ruled out here so the next pass does not reach for it as the
  simpler shape. It is simpler only for the environment.
  `System.get_env/1` per key is free; a file or remote source asked
  per key must either re-read and re-parse its whole document N times
  with no guarantee the N reads saw one document, or cache behind the
  layer's back in a store the boot report cannot see, or become a
  process whose lifecycle a two-callback port does not model. Each of
  those is discovered *after* someone has written the adapter, which
  is the wrong time. `all/0` is out for a different reason and a
  firmer one: a source free to volunteer names nobody declared lets
  values into the system behind the registry, and the registry being
  load-bearing rather than descriptive is the entire ticket. Revisit
  condition: none foreseeable — a source that cannot answer `load/2`
  cannot answer `fetch/1` either.
- **No layering or precedence chain of config sources** (ORC-4, second
  pass). The layer takes one source, chosen at compile time, not an
  ordered list. This is not an oversight to be repaired by the pass
  that first wants two: Vapor's loader `Map.merge`s provider results,
  so two providers offering one name silently pick a winner, and that
  is cited in `systems/substrate.md` as a reason not to depend on it —
  writing the same behaviour ourselves would be the same defect with
  our name on it. The case that will eventually ask for this is
  legitimate and predictable (secrets from a mounted file, everything
  else from the environment), so the revisit condition is written in
  advance rather than left open: layering arrives as per-declaration
  source selection, or as an ordered list **whose overlaps are a
  reported problem in the boot report**, and never as a merge. A
  precedence rule that resolves an overlap quietly is the same class
  of bug as two components claiming one queue, and this platform fails
  the build on that.
- **No `docs/0` callback, and no `cli/0` row in the roster yet**
  (ORC-22). Both are named in v5 §2.2 and both are deliberately
  outside the registry roster, for different reasons. `docs/` is a
  directory whose path derives from the slug (conventions §3): there
  is nothing to declare, nothing that can collide, and a callback
  returning a path the spine already fixes would be a derivation
  written twice — the failure the spine table exists to prevent.
  `cli/0` is `api_surface/0`'s shape with an escript composer instead
  of a router, and it stays out on a narrower argument than the one
  this ticket is built on: the retrofit cost ORC-22 pays down is the
  cost of components having already declared their names *somewhere
  else*, and no component can declare a CLI command anywhere today
  because there is no escript to declare it to. Nothing shadows it,
  so nothing is being deferred except a table row. Revisit condition
  for `cli/0`: the escript, at which point it is one row and this
  entry is what says the wait was priced rather than forgotten.
- **No prose data-classification field on `externals/0`** (ORC-22),
  against v5 §2.2's word "note". The field's entire payoff is a
  grouping — the generated "what does this app talk to" page is a
  compliance inventory and, in the hosted shape, a customer's egress
  inventory — and free text cannot be grouped, filtered, or checked,
  so a note would leave the audit with a column it can only print.
  The vocabulary is four atoms with highest-applicable-wins
  (`systems/substrate.md`), and credentials are not among them
  because every adapter sends one and a class every entry carries
  separates nothing. Revisit condition: a real external that none of
  the four describes — which is an argument for a fifth atom, an
  entry rather than a debate, and never for reopening the closed
  vocabulary itself.
- **No `policies/0` scope glob that leaves the working directory**
  (ORC-22). Absolute paths and `..` segments are a reported problem
  in the declaration, not a discipline anyone has to remember. This
  is the shape-level guard on the ORC-30 entry above: that entry
  stops `mix catapult.audit` from being taught where this repository
  keeps its components, and a registration surface accepting
  `../../lib/**` would walk the same reach back in through the front
  door while the task's own globs stayed innocent — worse, because it
  would arrive as customer-authored data rather than as a diff to the
  task. Revisit condition: none. A check needing to see another
  project is a check registered in that project.
- **No default version on an `events/0` entry, and no bare-atom form**
  (ORC-22). The obvious convenience — accept `:project_created` and
  mean version 1 — is ruled out here so the next pass does not add it
  as an ergonomic win. An unversioned event is the exact state v5
  §2.4's upcasting discipline exists to prevent, and a default makes
  the *first* version the one fact absent from the diff, which is the
  version every later upcaster is written against. The shape is free
  to fix now because nothing declares an event until the engine does,
  and it will never be free again. Revisit condition: none — this is
  the cheap half of the ES cliff, and the expensive half is what
  happens if it is skipped.
- **No `@optional_callbacks` on the component behaviour** (ORC-22).
  Every registry callback keeps an overridable empty default instead.
  Incremental adoption is what the default already buys; optional
  callbacks buy the same thing and charge the composer a
  `function_exported?/3` guard at every call site, so an aggregation
  that is total today becomes one that can silently skip a component.
  "Declared nothing" and "does not implement" is a distinction with
  no consumer, and the composer reporting every problem at once is
  the property being protected. Revisit condition: a callback whose
  empty default is a *meaningful* claim rather than an absence —
  which would be a callback that should have been two.
- **No `import Plug.Conn` beside `import Plug.Test` in a test module
  that calls nothing from it** (ORC-38). The deprecation being paid
  off names its own replacement — "Please use `import Plug.Test` and
  `import Plug.Conn` directly instead" — and `Plug.Test.__using__/1`
  does expand to exactly those two lines, so the mechanical
  translation is the one the compiler asks for and the one the next
  pass will reach for. It is wrong at both call sites here: neither
  health test calls a `Plug.Conn` function — they build a conn with
  `conn/2` and read `status`, `resp_body` and `halted` off the struct
  — so the second import is unused, and Elixir says so, in the same
  place and at the same volume (`warning: unused import Plug.Conn`,
  measured on both files before this was written). A warning traded
  for a warning delivers nothing of what the ticket was filed for,
  which was the recurrence and not the deprecation. The rule, stated
  once so it survives the next test file the compiler gives the same
  advice to: translate the `use` into the imports the module actually
  exercises. Today that is `import Plug.Test` alone, and both suites
  then run warning-free. Revisit condition: none, and none is needed
  — a test that calls `put_req_header/3` or any other `Plug.Conn`
  function adds the import as an ordinary consequence of using it,
  and this entry is only the reason it is not there before then.
