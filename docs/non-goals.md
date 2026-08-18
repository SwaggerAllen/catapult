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
- **No per-project restructuring of the *automation* protocol** (v5
  §7.10, §7.16). Projects bind tracker ids and tune marked
  thresholds; the agent and queue states, and the graph connecting
  them, are platform-fixed, because prompts, plane logic, and shared
  vocabulary are all written against them. **Narrowed at §7.16 from a
  flat "states and gates are platform-fixed":** review states — the
  ones whose only job is routing a human — are *declared*, vary by
  ticket type, and default to a UX review and an engineering review.
  The entry's stated reason survives the narrowing intact, because
  nothing dispatches from a review state and no prompt is written
  against one. The admission rule that replaces the flat version:
  **a state may be declared iff no plane logic branches on it.** We
  fix the shape of the automation, not the shape of the
  organization. What stays refused is a project rewiring the
  automation graph itself.
- ~~**No tracker product.**~~ **Reversed** (v5 §7.17). This entry
  held that Linear was the working UI behind a Tracker port, that we
  would build zero tracker UI, and it named the tell that would
  reopen it: catching ourselves teaching the tracker state it cannot
  hold. The tell arrived, repeatedly — an external state store
  because the tracker cannot record *who* wrote a change; protocol
  state riding in comments behind markers; an unmapped state halting
  a sweep for hours; comment ordering contradicting its own API
  contract; §7.16's stale-transition rejection undeliverable at the
  point of action; and §7.16's declared review states needing to be
  provisioned into a product that does not know what they mean.
  **Catapult ships its own ticket UI to every user.** External
  trackers become an add-on: an *outbound* projection of top-level
  tickets only, for teams that must report into a larger org's
  system. Inbound acceptance is not committed and, if it happens, is
  a narrow explicit command surface rather than a write path. Kept
  rather than deleted because the reversal is the record: this entry
  named its own reopen condition and the condition came true, which
  is the process working.
- **No inbound write path from a mirrored tracker** (v5 §7.17) — the
  live half of the entry above. Mirroring outward is a read model
  leaving the building and is safe by construction. Accepting
  arbitrary state changes back in reintroduces unmapped states,
  last-write-wins and unattributable writes into a system that just
  escaped them. Anything inbound is a §7.1 signal, validated like any
  other, never a state change adopted on the tracker's word.
- ~~**No dashboard-as-working-surface**~~ **Reversed with the tracker
  reversal** (v5 §7.17). The entry held debugging and observation
  only, with artifact review and ticket action living in Linear and
  PRs; it cannot survive owning the tracker, because owning it is
  precisely deciding that ticket action lives here. Two of its
  carve-outs stand unchanged and were always in-bounds: settings and
  onboarding (the bindings UI, v5 §7.10), and the configuration
  surface — a composer that files graph-state changes as PRs and
  never bypasses a gate.
  **What replaces the line is not "anything goes".** Review comes
  home where the native surface is *better*, not merely available,
  and §7.17 records the two reasons it is: our docs diff per sentence
  rather than per line, and the graph of tickets under a top-level
  ticket is a view a general tracker cannot easily replicate. The
  extent is settled in `docs/ui-spec.md`. The entry's real warning —
  that a pipeline this deep generates constant temptation to grow UI
  — is not retired by the reversal, and its **successor rule** is
  `docs/ui-spec.md` §2: reads are projections and writes are
  commands; **no screen introduces protocol vocabulary**; every
  screen answers a named question or performs a protocol-defined
  action. The middle one is the one to cite, because the temptation
  never arrives as "build a tracker" — it arrives as "add one field
  here", and a field here is vocabulary.
- **Catapult never executes target-project code** (v4 §A.10.5
  carried forward, sharpened): agent runs execute code in their own
  CI/runner environments; the plane dispatches and observes but
  never runs generated code in-process. The plane's blast radius is
  its own.
- **No concurrent authoring of artifact bodies** (v5 §7.16).
  Narrowed, deliberately, from a former `No multi-writer projects`
  entry — **small teams are supported**, and that entry contradicted
  both §1's target class ("single-author / small teams") and §2.9's
  identity component, which ships orgs, membership, invitations and
  roles-as-data. It was inherited from v4 §A.0.1 commitment 4 rather
  than decided here, and the narrowing is a reconciliation, not a
  reversal. What remains out is what v4 actually carved out: two
  people editing the same artifact body under merge semantics the
  plane would have to invent. Bodies live in git, PRs already carry
  those semantics, and the plane does not grow a second set.
  Concurrent *action on the delivery protocol* — several people
  holding a sign-off role, racing each other on transitions — is in,
  and is optimistic concurrency (§7.16): first writer wins, a stale
  `from` is rejected rather than applied.
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
- **No Credo-hosted platform checks, and no Credo in a generated
  tree** (ORC-21), against v5 §2.14, which adopted "AST-grade custom
  Credo checks" by name. The grade is adopted; the host is not, and
  the reason is mechanical rather than preferential. `Credo.Check` is
  a `__using__` macro, so a check module compiles only where Credo is
  loadable, and Mix loads a dependency's own children with
  `env: :prod` (`Mix.Dep.Loader`) — so substrate's `only: [:dev,
  :test]` Credo never reaches a consumer, and a check shipped in
  `lib/` would fail to compile in every tree that adopted it. Buying
  the host means either a Credo dependency imposed on trees we do not
  own — the fourth entry of that shape in this file — or a fourth mix
  project and a second package on the release train, and both are
  spent on IDE surfacing. `policies/0` + `Catapult.Audit.Check` is the
  inheritance mechanism, it shipped in ORC-22, and a second one would
  give `catapult:allow` two implementations. Revisit condition, and it
  is cheap by construction: a project that wants editor surfacing
  writes a `Credo.Check` delegating to `run/1`. That is a wrapper, in
  the project that wants it, and no check logic moves — which is why
  the report format (`path:line: message`) is part of the contract.
- **No compile-connected cap anywhere a ticket can edit it** (ORC-21).
  Not `config/*.exs`, not a module attribute in the audit, not a
  checked-in baseline file: `mix xref graph --label compile-connected
  --fail-above N` is stock and already exits 1, so the only question
  is where N lives, and the pipeline answers it. An agent that adds a
  compile dependency can raise a cap that sits in the tree, in the
  same commit that made it necessary, with a plausible sentence in the
  PR body — and a ratchet the ratcheting party can turn is not a
  ratchet. `qualityGates` is author-owned, which is what makes v5
  §2.14's "may never rise without a reviewed change" literal. The
  accepted cost is that lowering it is also an author edit, including
  on the runs where a refactor earned the lower number. Revisit
  condition: none while agents write the diffs — this entry is about
  who holds the number, and that does not change with scale.
- **No `system_monitor`-based mailbox guardrail, and no kill grade for
  a full mailbox** (ORC-21), against v5 §2.5's "the BEAM itself
  enforces them", which is true of the heap bound and false of the
  queue bound. Verified rather than assumed:
  `erlang:process_flag(:max_message_queue_len, _)` raises `badarg` —
  there is no such flag — and `:erlang.system_monitor/2` is node-wide,
  notify-only, and singular, so setting one discards the previous
  settings and any dependency reaching for `long_gc` disables our
  guardrail without a word. A check whose failure mode is silence is
  the shape this repo has already refused twice. The mailbox threshold
  is sampled and reported (`systems/observability.md`); killing is
  rejected separately and on its own merits, since a process that is
  behind is usually the only thing holding the work. Revisit
  condition: a per-process, VM-enforced queue bound appearing in OTP —
  at which point the field changes grade rather than the decision
  changing shape.
- **No `spawn_opt` threading by the composer** (ORC-21). VM guardrails
  are applied by the process in `init/1` and *checked* by the
  composer, never injected into a child spec's start call. A process
  flag can only be set from inside its own process — `process_flag/3`
  covers `save_calls` and nothing else — so the only external route is
  `spawn_opt`, which requires the composer to know the option
  conventions of start functions it did not write, and has no answer
  at all for a child whose `start_link` takes no options. That is the
  same defect as a shipped task knowing this repository's layout, one
  level in: generic composition machinery holding specific knowledge
  about things it composes. Revisit condition: none — declared↔applied
  is the check shape the platform already uses twice.
- **The audit never runs another gate, and never detects one by
  directory name** (ORC-21). v5 §2.14 arms Sobelow on Phoenix-bearing
  projects; the audit's part is to *report the missing gate*, not to
  shell out to it. A task that invokes other tools swallows their exit
  codes and their output formatting and becomes a meta-runner, while
  `qualityGates` and `ci.yml` are already where a gate is one line
  somebody can read. The second half is the ORC-30 rule applied to a
  new check: the predicate is `:phoenix` in the dependency tree, never
  "`catapult_web` exists", because a directory name is this repo's
  layout and the task ships into projects whose spine puts their web
  layer elsewhere. Revisit condition: none for the layout half. For
  the first half, a gate with no other home would be an argument — and
  it would be an argument for giving it a home, not for the audit
  growing a runner.
- **No taint analysis for secret config values** (ORC-21). v5 §2.2
  asks that secret-flagged values never appear in logs or error
  payloads, and the tempting reading is a static check that follows a
  value from the accessor to a `Logger` call. It is not built: a value
  bound to a variable, put in a map, or passed to a helper is out of
  reach of any check that is also free of false positives, and a
  redaction check that misses is worse than none because it is
  reported as coverage. The wrapper type is what holds the property
  everywhere at once — a redacting `Inspect`, an explicit unwrap — and
  the audit keeps only the exact, one-hop residue: an unwrap inside a
  logging call. Revisit condition: none. If the wrapper is ever found
  insufficient the answer is a narrower unwrap surface, not a deeper
  analysis.
- **No license check that decides *which* projects to check by
  reading the tree** (ORC-16), against the ticket's own words — "for
  every mix project under `components/`". That is the cross-project
  reach two entries' worth of argument already rules out, arriving
  through a new door: a task that walks `components/*` knows where
  this repository keeps its components, and it ships into customer
  trees where that glob means nothing and where a permissive-deps
  requirement is not Catapult's to impose. The sanctioned form is a
  declaration the project makes about itself — `package: [licenses:
  [...]]`, checked when it names something the allowlist contains,
  inert when it names nothing (`systems/substrate.md`). That delivers
  the ticket's stated scope as a property: the plane declares no
  package, so its dependencies are never checked, with no exclusion
  list for anyone to maintain. The property that makes it safe rather
  than merely tidy is that the arming declaration is one hex already
  demands — `mix hex.build` refuses a package with no `licenses`,
  measured — so nothing that ships can forget it. Revisit condition:
  none. A shipped artifact that cannot say what it is licensed under
  has a bigger problem than the audit.
  **Amended at the second pass (ORC-16): a second declaration joins
  it, and the entry gets stronger rather than weaker.** Design review
  changed the premise — `components/*` will hold components that are
  not open source, so the directory no longer even describes the
  shipped layer — and the answer is `licensing/0` on the component
  (`distribution:` and `license:`), read alongside the project's
  `package:`. Both remain declarations and neither is a path, which is
  what this entry is about. The reason both are needed is measured and
  is the sharpest argument the entry has: `components/substrate`
  declares no components at all, so a check armed only by component
  class would read the one tree ORC-16 was filed about, find no
  subject, and report clean. Two declarations, no glob.
  **Third pass, for the phrase above that has since acquired a second
  reading:** "checked when it names something the allowlist contains"
  means the project's own list, not a platform-wide one, now that the
  list is data each project states. Arming and standard are separate
  facts — the declarations decide *whether* a tree is checked, the
  list decides *against what* — and a project that arms the check
  while stating no list is inert with a census line, per the entry
  further down. Neither of them became a path.
- **No exception mechanism on the license check — no ignore list, no
  `catapult:allow`, no per-dependency waiver** (ORC-16). The obvious
  symmetry is with `ignore_advisories` a few entries up, and the
  symmetry is false: an advisory is imposed on us by the world and
  frequently has no action until an upstream we do not control cuts a
  release, whereas nobody imposes a dependency on anyone. It is the
  one supply-chain fact that is entirely our own choice, so the fix
  for a copyleft dependency in the shipped layer is not taking it,
  and a waiver could only ever be spent breaking the rule
  `LICENSING.md` calls the single most important one in it. This is
  the same line `external: true` draws — an escape exists where an
  outside party imposes a name on us and nowhere else. The overrides
  file is not a hole in this: it supplies a *license*, read by a human
  out of a package's own LICENSE, and that license is then checked
  like any other, so an override naming `GPL-3.0-only` fails the build
  exactly as the metadata would have. Revisit condition: a dependency
  genuinely worth an exception is worth replacing instead; if one ever
  is not, the argument belongs in `LICENSING.md` as a change to the
  policy, in daylight, never in the audit as a way around it.
  **Amended at the third pass (ORC-16), and the amendment is the
  entry's own sentence taken seriously.** Design review reversed half
  of what the second pass wrote here: the *allowlist* is data each
  project states in its `mix.exs`, and Catapult's five identifiers are
  a default value rather than the rule (`systems/substrate.md`). That
  is not the hole this entry refuses, and the two are worth reading
  together precisely because they are the same keyword list. "This
  dependency is copyleft and we accept it anyway" is a **waiver** —
  per-dependency, argued once and inherited forever, read only by
  whoever added it — and is still refused, with nothing above weakened.
  "Our list of acceptable licenses is not yours" is a **policy
  difference**: stated once, applied uniformly to every dependency in
  the tree, and reviewable as a policy. The check acquires a different
  subject; it does not switch off. The reason it had to become
  configurable is this entry's own logic pointed at ourselves —
  `Catapult.Audit.License` ships into every generated project, so five
  identifiers compiled into it is Catapult's legal position imposed on
  a codebase nobody here has read, which is the same imposition
  this file refuses when the subject is a dependency substrate
  declares. The line, stated once so the next pass does not have to
  re-derive it: a project may say what terms are acceptable in its
  tree, and may never say that one package is measured against nothing.
- **No normalization table for license spellings, and no inference
  from LICENSE file text** (ORC-16). Matching is exact SPDX
  identifiers; anything else is unrecognized and therefore a problem,
  resolved by an override entry a reviewer reads. The cost is
  measured and, once the class rules landed, zero on this tree:
  `cowboy_telemetry` declares `["Apache 2.0"]`, which no amount of
  being obviously fine makes an SPDX identifier — but it is a plane
  dependency, and the plane is a public-licensed service and therefore
  unchecked, so no override exists on landing. The near-miss is kept
  here as the illustration it always was. The cheaper fix is refused
  because its failures run silent and in the permissive
  direction. A table that maps "Apache 2" teaches its next
  reader that near-misses are handled, and the next near-miss is a
  string like `GPL-2.0-with-classpath-exception`, whose distance from
  `GPL-2.0-only` is the entire question the check exists to ask. Text
  inference is the same defect with a bigger surface: a fuzzy match
  over prose, deciding a legal question, with no line in the diff
  where a human agreed. Revisit condition: none — an override costs
  one line and one reading, and the readings are rare by construction
  (zero in the checked closure today).
- **No per-file license headers, for now** (ORC-16, carrying the
  ticket's own deferral so it is not re-proposed as the obvious
  adjacent win). The inventory check answers what the *dependencies*
  impose; what carries attribution for our own files — headers in
  every source file, or a `NOTICE` file at each project root — is a
  separate decision with a real cost either way, and taking it now
  would mean stamping thousands of lines against a posture counsel
  has not reviewed. Revisit condition, and it is dated rather than
  open: the repository opening to outside contributions, which is
  when `LICENSING.md`'s `LICENSE` texts and CLA land and when the
  attribution question has to be answered anyway.
- **No fourth distribution class and no `proprietary:` flag beside the
  license** (ORC-16). `distribution/0`'s vocabulary stays the three the
  review named — `:distributed`, `:service`, `:internal` — and the
  "ours versus proprietary" split the `:service` rules turn on is read
  off the declared identifier instead: SPDX already spells "no listed
  license applies" as `LicenseRef-<id>`. A `:proprietary_service`
  class, or a boolean riding alongside, would be a second place to
  state a fact the identifier already states, and two places that can
  disagree is how a check ends up enforcing the wrong rule with
  complete confidence. It also keeps the vocabulary describing *how
  code reaches people*, which is what obligations key on and what makes
  the three classes legible to someone who has never heard of
  Catapult's business model — the property the review picked them for.
  Revisit condition: a real licensing consequence that turns on
  something other than conveyance, network use or neither, which would
  be a fourth way code reaches people rather than a fourth adjective
  for the same three.
- **No licensing verdict at boot, and no allowlist inside the
  composer** (ORC-16). The composer validates that `licensing/0` is
  well-formed, exactly as it does every other declaration and for the
  same reason (it needs no environment); it never holds the allowlist
  and never decides whether a license passes. Reason: the composer runs
  at boot as well as under the audit, so an allowlist there means a
  production node refusing to start because a transitive dependency's
  license string is unrecognized — a catastrophic response to a
  question with no runtime consequence at all. The severity that fits a
  legal fact is CI red. This is not a claim that the check is
  unimportant; it is a claim that the failure has to land where a human
  is already reading, not where a deploy is already halfway out.
  Revisit condition: none. There is no license question whose answer
  changes what a running node should do. (The check does not hold the
  allowlist either, for an unrelated reason — see the entry on
  `Catapult.Audit.License` below. The composer does not hold it because
  it runs at boot; the check does not hold it because it ships into
  other people's projects.)
- **No `licensing/0` row in the registry roster table** (ORC-16),
  against the obvious consistency argument, and this entry exists
  because that argument is a good one. The table is one row per
  *name-claiming* registry, and its `:claim` and `:identity` columns
  are the reason it exists: two components declaring `Apache-2.0` is
  the ordinary case rather than a collision, so a licensing row would
  carry two empty columns and the fold over `rows/0` would need to skip
  it — the `function_exported?/3` guard the no-optional-callbacks entry
  refused, arriving as a table row instead of a callback. The shape
  does not fit either: a keyword list *is* a list of two-tuples, so a
  table-driven aggregator reads one declaration as two entries. It sits
  beside `config/0` on `config/0`'s own recorded criterion — a
  consumer, and error messages worth their specificity. Revisit
  condition: a second declaration of this shape, at which point the
  argument is for a small table of component-scalar facts and never for
  folding them into the claims table.
- **No defaulted distribution class for a component that declares
  none** (ORC-16). Defaulting to `:distributed` is the safe direction
  for the dependency half and is ruled out anyway, because the pair
  cannot be half-defaulted — there is no license a component "probably"
  carries, and a defaulted class paired with an absent identifier makes
  the component's self-check a verdict about nothing. The deciding
  reason is the other one: a default makes every project's audit print
  a policy verdict nobody asserted, which is a check that passed
  without checking anything, and removing exactly that from the ladder
  is the ticket. An undeclared component is reported instead, at audit
  time, alongside every other structural absence — not at compile time,
  since the overridable empty default stays (`errors/0`'s required
  `remedy:` is the same treatment). Revisit condition: none. A
  component whose author will not say who receives it is the case the
  check was built for, not a case for the check to guess at.
- **No per-component attribution of dependencies** (ORC-16). The check
  does not try to work out which component pulled `plug` in, and a
  project's dependency policy is instead the strictest among every
  subject it composes. Reason: mix has no per-component dependency
  declarations, so any attribution would be a call-graph guess made
  offline, and its errors would run in the permissive direction — the
  one direction this check may not fail in. The shared-tree fact is
  also simply true: every dependency in a project is available to every
  component in it, whatever brought it in. Revisit condition: a real
  per-component dependency declaration in the language, which is not a
  thing mix has and not a thing to build here.
- **No allowlist inside `Catapult.Audit.License`, and no default policy
  applied to a project that states none** (ORC-16, third pass). The
  check ships into every generated project and carries the *rule* — how
  code reaches people, which classes are checked, and for which reason
  — while the list of acceptable SPDX identifiers is data the project
  states in its own `mix.exs`. A constant in the module is the same
  mistake as the path rule one level in: it holds a fact about the
  world outside the package, in a package that runs everywhere. The
  second half matters more and is easier to lose: a project that states
  no list is **inert with a census line saying so**, never held to
  Catapult's five by default. A default would make every project's
  audit print a policy verdict nobody asserted, which is the
  undeclared-component ruling in this same ticket and the same
  sentence — and the honest reading of a silent green run would be that
  a legal question about someone else's codebase was answered by us.
  The sane starting value still exists; it is emitted as literal data
  into a generated project's `mix.exs` by `bundles/platform-elixir`
  (`systems/platform_content.md`), which is the place a project's files
  come from, and never as a call back into a shipped module that
  resolves it. Revisit condition: none for the constant. The inert
  state is worth watching — if generated projects turn out to lose the
  block routinely, the answer is the generator asserting it, never the
  check assuming it.
- **No allowlist keyed by distribution class within one mix project**
  (ORC-16, third pass), against design review's own wording ("the
  allowlist per class is data the project states") and recorded here
  because reversing it is a one-line change if the author wants it.
  Dependencies are a mix project's fact — one lockfile, one `deps/`,
  one working directory — which is the entire reason `package:` arms
  the check. A list per class leaves a project composing a
  `:distributed` component and a proprietary `:service` one resolving
  to the *intersection* of two lists over one shared tree, which turns
  strictest-wins from a total order into a merge whose result is
  written in no file and citable in no report. That is the same defect
  as merging config sources, refused for the config layer above and
  refused here for the same reason. What stays per class is the *reason* a tree is checked and
  the report line that prints it. A project genuinely needing two
  policies needs two dependency trees, which is two mix projects, which
  is what it already had to be. Revisit condition: a single mix project
  with a legitimate reason to hold subjects under different lists —
  which would be an argument that the check's subject is not the
  project, and would want answering there rather than by adding a
  keyed map.
- **No classification of a license identifier as copyleft** (ORC-16,
  third pass). The check answers two questions about an identifier —
  is it spelled `LicenseRef-*`, and is it on the project's list — and
  infers nothing else; there is no third bucket and no small table of
  copyleft identifiers to produce one. This removed a row from the
  second pass's table (*public copyleft, conveyed → unchecked*), which
  was true about obligations and undecidable in code: the residue of a
  project-stated list is not copyleft, it is whatever that project did
  not write down, and reading it as copyleft leaves the tree
  **unchecked** — an inference in the permissive direction, which is
  the one direction this check may not fail in. It is the same refusal
  as the normalization table above, arriving where it is
  tempting to think we would be guessing about ourselves rather than
  about a stranger's package. Conveying under copyleft deliberately is
  still expressible and is now better expressed: put the identifier on
  the project's own list, and dependencies are checked against a list
  containing it — which catches `GPL-2.0-only` inside an
  `AGPL-3.0-only` work, a real incompatibility the dropped row passed
  in silence. Revisit condition: none. Every use anyone proposed for a
  copyleft bucket is served by the project's list saying so out loud.
- **No dataflow inference for a computed config key, and no reading a
  dynamic `fetch!/2` as a wildcard** (ORC-48). The declared↔read check
  joins two literal atoms — the accessor's own slug and key — and a call
  it cannot join is reported at its call site rather than resolved.
  Chasing the value of a variable back to its binding is the shape the
  secret rule already refused one registry over, for the same reason: a
  shallow analysis pretending to be a guarantee. The cheaper alternative
  is the one worth naming, because it is what the next pass will reach
  for — treat `fetch!(:foundation, key)` as reading *everything*
  `:foundation` declares, so nothing false-positives. That is a whole
  slug's worth of coverage switched off by a call that says so nowhere,
  in a check whose entire subject is dead declarations; the silence is
  the defect, not the strictness. Reporting the unjoinable call keeps
  the run red and names the cause, which is the same trade as reporting
  an unparseable file instead of skipping it. Revisit condition: a
  legitimate computed read, which would be an argument for a second
  accessor that declares what it may reach, never for the check
  guessing.
- **No `catapult:allow` escape on either direction of the config
  declared↔read check** (ORC-48). `Catapult.Audit.Declarations` already
  refuses the tag for what it reports — the escape excuses a *line* the
  parser found, and a dead declaration is the absence of one — and the
  unjoinable-read direction does name a line, so the exception has to be
  refused on its own merits rather than inherited. It is: an allow tag
  on an unjoinable read would silently re-arm the false-dead report the
  suppression exists to prevent, so the tag would quiet one line by
  making another line lie, and the lying line's advice is *delete this
  declaration* against a value the boot requires. Both remedies are one
  line and always available — delete the declaration, or spell the key —
  which is the condition under which this repo has consistently declined
  to build an escape. Revisit condition: none. An escape here is a way
  to keep dead configuration forever, which is the thing being checked.
- **No reader-identity rule on config reads — the check does not police
  *who* reads a key** (ORC-48), against ORC-4's own phrasing ("a
  component reading a key it did not declare"), narrowed out loud rather
  than quietly. Two reasons, and the second would stand alone. The
  mechanical one: deciding that a call site belongs to a component means
  a path→component map inside `mix catapult.audit`, which is the layout
  knowledge this file refuses at that task's front door — worse here
  than in the `components/*` case, because a generated project's spine
  puts its components wherever it likes and the map would be wrong
  rather than merely absent. The substantive one: `Catapult.Config
  .fetch!/2` takes a slug *precisely* so a reader can name a value it
  does not own, `Catapult.Repo` reading `:foundation`'s database URL is
  the tree's own example, and whether a cross-component read is
  acceptable coupling is a boundary question with a boundary compiler
  already answering it. The check keeps the half that is a registry
  fact: a key nobody declared. Revisit condition: none foreseeable —
  ownership of a *call site* is not a fact the config registry holds.
- **No widening the audit's scope to `deps/**` to find a shipped
  component's readers** (ORC-48). The declared↔read check reports a
  declaration as dead only when the declaring component's own source is
  inside the scope it is auditing, and the obvious repair for the
  resulting blind spot — sweep the dependencies too, so a package's
  declarations are checked against the package's code — is refused. It
  makes every project's audit an audit of its dependencies' internals,
  it scales with the closure rather than with the tree somebody wrote,
  and it produces findings whose only available remedy is a PR to
  someone else's repository. The package's own CI is where its
  declarations meet its own `lib/`, which is exactly where this check
  already runs, once per mix project. Revisit condition: none. A
  component's declarations are checked in the project that compiles
  them, and every project compiles its own.
- **No destination-detecting model-call check — nothing reads a URL,
  a hostname or a provider name out of an HTTP call's arguments**
  (ORC-52). The sentence this ticket retired promised "an audit check
  for the Erlang ones", and the natural reading is a check that finds a
  *model call*. It is refused because it cannot be built honestly: at
  AST grade the call is `:httpc.request(:post, {url, ...}, [], [])` and
  whether `url` reaches a model provider is data, decided at runtime and
  normally read from configuration. Matching a provider hostname in a
  literal catches a spelling nobody writes and reports clean on every
  real instance of the thing the check is named after — a check that
  passed without checking anything, which is what this ticket was filed
  about, reintroduced by its own fix. Chasing `url` back to its binding
  is the third request for dataflow inference in this file, and it gets
  the answer the secret-taint entry and the computed-config-key entry
  got: a shallow analysis reported as a guarantee is worse than a stated
  gap. What is built instead bans the *transport* — no plane module
  calls a pure Erlang HTTP client (`systems/foundation.md`) — which is
  decidable, broader than §11, and exact. Revisit condition: none. The
  destination is not a static fact and no amount of check will make it
  one.
- **No Erlang-egress ban in `components/substrate/`, in
  `@platform_checks` or hosted there under another name** (ORC-52). The
  audit's platform set is inherited by every project that runs the task
  at all, and "the plane makes no model calls" is a *plane* rule:
  conventions §11's second bullet has generated projects making model
  calls through the LLM adapter, so a package-wide egress ban would fail
  the audit of a project doing exactly what the platform told it to do.
  Hosting the module there unregistered fails on the other axis this
  file has used four times — the list of banned modules is
  Catapult's policy, and a policy compiled into a package that ships
  into trees we do not own is the `Catapult.Audit.License` allowlist
  mistake one registry over. Substrate ships the mechanism
  (`Catapult.Audit.Check`, `Catapult.Audit.Source`, the `policies/0`
  row) and a project states its own ban with it; a project inherits the
  ability, not the ban. Revisit condition: a ban true of every project
  that adopts the substrate, which this one is not by construction.
- **No transport-layer ban — `:gen_tcp`, `:ssl`, `:socket` and friends
  stay off the banned list** (ORC-52). The obvious objection to banning
  named HTTP clients is that a determined module can open a socket and
  write the request bytes itself, and the objection is correct and does
  not change the answer. Those applications are what Postgres, the
  clustering transport and every other legitimate connection ride on, so
  banning them means an escape tag at every real call site, and a ban
  escaped everywhere is a ban nobody reads. The trade is also asymmetric
  in the direction that decides it: a plane module reaching a provider
  through `:httpc` is a mistake somebody makes, while one hand-rolling
  HTTP over `:gen_tcp` is a deliberate evasion, and no audit check in
  this repo is built to stop an author who is trying. Revisit condition:
  none. The named list grows by reviewed diff when a real client is
  missing from it; that is a different move from descending a layer.
- **No milestone-gating for the Erlang egress ban** (ORC-52), against
  the filing ticket's own suggestion that Phase 4 or Phase 6 would be a
  reasonable home for the check. Recorded because it is the reasonable-
  sounding move and it is wrong for a mechanical reason worth keeping:
  `:inets` ships with OTP, so `:httpc` needs no dependency and will
  never appear in a `mix.exs` or `mix.lock` diff. There is no arming
  moment for anyone to notice — that is *why* it is the residue the
  compile grade leaves — so "wait until it has something to catch" is
  waiting for a signal that cannot arrive, and the practical result is
  a doc that promises a gate for two phases, which is the state this
  ticket exists to end. ORC-21's argument for arming the boundary app
  list before there were boundaries to constrain applies unchanged: the
  run is green today, so the diff is a module and a registration rather
  than a cleanup of everything written in between. Revisit condition:
  none.
- **No catalogue of the ecosystem's HTTP clients to close the Elixir
  half** (ORC-52). `check: [apps: [...]]` checks the applications it
  names, so an Elixir HTTP client added as a dependency is unchecked
  until it is named there — a real residue, corrected into
  `systems/foundation.md`'s sentence rather than left implied. The
  tempting closure is a check that knows `:tesla`, `:finch`, `:mint`,
  `:httpoison` and the rest, reports one present in the closure and
  absent from the list, and it is refused: its coverage is a list of
  the world maintained by us, its failure mode is silence for every
  client not on it, and silence is what this ticket was filed about. The
  existing mechanism is better than the check would be — an Elixir
  client cannot be called without being a dependency, a dependency is a
  §2.8 named decision visible in the same diff, and the `check:` line
  belongs in that diff. Revisit condition: none. This is the one half of
  §11's enforcement where the thing being added announces itself.
