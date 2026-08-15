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
