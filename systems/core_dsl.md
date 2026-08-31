---
paths:
  - lib/catapult/dsl/**
  - test/catapult/dsl/**
  - catapult.yaml
---

# core_dsl

The DSL: the frozen core vocabulary (tiers, scopes, edges, fragments,
handles, context walks, grammars, readiness, generators, the
predicate language), the bundle loader (`bundle.yaml` + registered
files → validated union), `extends:` content layering, and the
**extension registry** (v5 §9) through which platform extensions add
annotation namespaces, declaration kinds, generator types,
context-source kinds, and audit profiles.

## Standing decisions

- **The core is frozen; growth happens in extensions** (v5 §9).
  A change to core vocabulary is a platform-versioned event with a
  migration story; an extension is an entry. When in doubt, it's an
  extension.
- **No bundle-side code, ever.** Bundles declare instances against
  installed-extension vocabulary; the predicate language stays
  non-Turing-complete (v5 §6). This is a correctness property the
  scheduler and audit lean on, not a style choice.
- **All validation at load time where possible**: type-level
  acyclicity (libgraph), cross-references, cardinality shapes,
  extension schemas. A bundle that loads is a bundle the engine can
  run; instance-level checks (dependency cycles) run at projection
  time.
- **Destructive bundle change over a populated graph is a cutover,
  never a hot edit** (v5 §6): additive loads freely; removals,
  renames, and restructures go through the cutover ticket — drain,
  reviewed graph-transform list, migrate, then flip the active
  bundle. The loader may load the new bundle for validation, but
  the engine switches graphs only at a completed cutover. **The
  drain is per axis** (v5 §7.19): it stands on the chain axis, where
  flow instances complete, and relaxes on the workflow axis, where a
  blocked ticket is in-flight for as long as its human prerequisite
  takes. Blocked tickets ride a workflow cutover and re-resolve
  against the new sequence, anchored on the system statuses — the
  part of a ticket's history no bundle change can delete. The flip
  is recorded as an event on both axes; the re-resolution joins a
  ticket's status history against the bundle-version timeline and
  needs both in the log.
- **Grammar machinery lives here** (validators derived from bundle
  declarations); engine and generation call it. One validator source
  because commit-time rejection (engine) and pre-flight validation
  (generation, CLI later) must agree byte-for-byte.
- **`catapult.yaml` is the loader's, not the bundle's** (dsl-syntax.md
  §1-2). It names one bundle per axis and nothing else — it is what
  the loader reads to find `bundles/` in the first place, not content
  the loader validates against a bundle schema. That makes it this
  system's file, same as any other loader input, and distinct from
  `bundles/**`'s content, which `platform_content` owns. Previously
  unowned (repo-root, no system's map claimed it, not on
  `systems/README.md`'s unowned list either) — the gap this ticket's
  sketch closes.
- **Four core-grammar growth events landed directly, not through the
  extension registry** (ORC-84, design review): a fourth scope kind,
  `cascade_visit` (§3.1 — one node per node a flow's own cascade walk
  visits, for a planning tier, engine-minted rather than fanout-minted);
  a context walk's hop chain lengthened from exactly one to any number,
  plus a `~` suffix reversing a hop (§7.1 — walker matches the edge's
  `target` instead of its `source`); a new context-walk source,
  `all.<tier>.<projection>` (§7.2 — every declared instance of a tier,
  no edge); and edges gaining an `instances:` list, several
  source/target sites sharing one name and mechanism (§4.1). None of
  these are extension points in the §9/§12 sense — annotation
  namespaces, declaration kinds, generator types, context-source
  *kinds*, enforcement profiles are all vocabulary the grammar
  references, installed or not; these four are the grammar's own
  productions (how many hops a walk may chain, what scope kinds exist
  at all), which the extension registry has no callback for and was
  never meant to carry. "The core is frozen; growth happens in
  extensions" therefore doesn't route these anywhere — there is no
  extension shaped to hold a scope kind. What actually governs a core
  grammar change is the sentence right after: "a platform-versioned
  event with a migration story." This entry is that story. All four
  landed inside a content-porting ticket rather than a dedicated
  `core_dsl` ticket because that ticket's own design review directed
  it, in these words, after the first pass tried the alternative
  (recording each gap as a non-goal) and was told that was the wrong
  move: "a missing DSL construct is a `docs/dsl-syntax.md` proposal,
  not a reason to ship the bundle without the capability" — the same
  instruction this ticket had already given, and this pass had already
  followed, for `mint.<name>` (§3's join-target field-source
  addendum, landed the same way one pass earlier). Design review's
  sign-off is the reviewed change; a dedicated ticket would be
  re-litigating a decision already made in daylight, not making a new
  one. Every addition is additive to the closed sets it extends (no
  existing bundle content stops parsing) and ships with loader tests
  (`test/catapult/dsl/context_walk_test.exs`,
  `test/catapult/dsl/loader_test.exs`) exercising the new productions
  directly, not only through `bundles/default/`'s own use of them.
  Revisit condition: none for the mechanism split itself (extensions
  still own vocabulary, core still owns grammar); a *fifth* grammar
  growth event still wants the same daylight this one got, whether or
  not another ticket happens to be carrying it.
- **A fifth core-grammar growth event, same daylight, same ticket**
  (ORC-84, author decision revising `docs/v5-design-decisions.md`
  §7.19): a tier declaration gains `reviews: <tier>` (dsl-syntax.md
  §3.3), marking it a review tier for the named tier rather than a
  generation tier of its own. Unlike the four above, this isn't a new
  scope kind, edge form, or context-walk source — it's a new relation
  *between two tier declarations*: `reviews:` fixes the declaring
  tier's scope and cardinality to the named tier's, 1:1, without
  restating `scope:`, and it obligates a load-time check with no
  precedent in the closed sets §13 already validates — that the
  review tier's own `context:` names the same set of walks as the
  reviewed tier's `context:`. Landed here rather than in a dedicated
  ticket for the identical reason the first four did: the author's
  decision superseded this ticket's own prior (and design-review-
  corrected) handling of the chain's review mechanism, mid-flight, and
  said so explicitly — "It lands mid-flight... the difference is that
  it reaches the branch as ticket direction the pass reads before it
  starts... the doc edit is this pass's to make." No loader tests
  accompanied the design pass that added this paragraph (the six
  plane-code files this ticket's design role may touch were already
  stripped once by a prior review comment and stayed stripped —
  `lib/catapult/dsl/**` and `test/catapult/dsl/**` were left for this
  ticket's own dev pass, same as the four above). **Landed by that dev
  pass**, alongside the four-item entry above (same commit): `reviews:`
  is implemented in `Catapult.Dsl.Tier`/`Catapult.Dsl.Chain`, with
  loader tests exercising it directly (`test/catapult/dsl/loader_test
  .exs`); `bundles/default/` now loads clean end to end (25 tiers — 17
  generation/projection plus 8 review — 6 edges, 5 flows, 2 workflow
  gates). Revisit condition: none — this *is* the daylight the entry
  above asked for.
- **Depth's grammar generalizes to a pair, and a new declarable form
  configures `critique`'s participation** (ORC-92, design pass;
  `docs/dsl-syntax.md` §13, §15.4, §15.5; `docs/v5-design-decisions.md`
  §7.19 — both grammar sections' own shape changed again
  at ORC-105's fourth pass, below, without disturbing this decision).
  Two changes land together, by the ticket's
  own sequencing constraint: `depth:`'s shape check widens from
  "non-negative integer" to "non-negative integer, or a list of
  exactly two" — `Catapult.Dsl.Gate.parse_depth/2` and
  `Catapult.Dsl.Environment`'s own copy both need the second clause,
  and §13 gains a shape-check rule validating all three depth sites
  the same way — and the loader gains a new, singular, non-globbed
  declaration kind: `critique.yaml` at a workflow bundle's root,
  structural-parsing-only in the same shape `Gate` and `Environment`
  already use (unknown keys rejected, `depth:` defaulting to `0`),
  with no other fields — no `after:`, no `role:`, nothing that would
  make it look like a review-status declaration, because it
  configures a fixed kind rather than declaring one (§15.1's line
  stays exactly as strict). Updating `bundles/**` content ahead of
  this landing fails every bundle load; updating the parser without
  the content leaves the content silently unable to say what this
  ticket argues it should. Neither order is safe done alone, so this
  is one change, not two.

  **Not built: a globbed directory for status participation
  generally.** The tempting generalization —
  `statuses/<name>.yaml`, one file per configurable fixed kind,
  mirroring `gates/` and `environments/` — is refused for now: there
  is exactly one configurable kind (`critique`), and a directory
  earns nothing over a fixed single path until a second kind
  actually needs the same knob. Revisit condition: a second system
  status wanting a workflow-declared participation depth — at which
  point the fixed path generalizes to a directory the same way
  `gates/` already shows the shape for.

  **Not built: a named-pass selector for the `[first, rest]` pair.**
  `first`/`rest` are positional, never a name a bundle chooses
  (`scaffold`, `refactor_flow`) — a chain has no vocabulary for its
  own flows on the workflow axis to begin with (v5 §7.18), and
  inventing one here to save a pair's two positions a name would be
  the identical cross-axis leak the axis split already forbids
  everywhere else. Revisit condition: none — the coupling this
  refuses is structural, not a gap waiting on more flows to exist.
- **`Chain.t()` carries its resolved `predicates.yaml` map forward**
  (ORC-8, named here because the reactive scheduler is the first
  runtime consumer). `Chain.build/3` already resolves and validates
  every named predicate a bundle's four slots (`scope_filter`,
  `cardinality.when`, an edge `constraint`, a flow `completion`,
  dsl-syntax.md §8) reference — then discards the map once load-time
  validation passes. Nothing downstream can evaluate a `scope_filter`
  reference against live graph state without it; re-parsing
  `predicates.yaml` independently would double-implement this system's
  own load path and risk drifting from what the loader actually
  validated. The fix is a field, not a second reader: `Chain.t()` gains
  `predicates: %{String.t() => Predicate.t()}`, populated from the
  value `build/3` already computes. `systems/engine.md` records the
  runtime-evaluator decision this field exists to serve.
- **A project's queue sequence and a container's are two declaration
  shapes, not one shape parameterized by kind, and work-item types are
  now a registry** (ORC-105, design pass, superseding both ORC-103's
  own unmerged milestone-only draft of this entry and this same
  ticket's own two earlier, since-reversed drafts — a shared
  fixed-sequence shape off one `container:` field checked against a
  two-member registry, then a `flow:`/`opens:` pair on every queue
  entry; `docs/dsl-syntax.md` §15.6-§15.9; `docs/v5-design-decisions.md`
  §7.8). `queues/project.yaml` is optional and singular
  (`critique.yaml`'s shape) and holds whatever queue array the
  workflow bundle authors — no anchor check, no fixed count, no
  platform vocabulary to validate names against. `queues/containers/
  <name>.yaml` is directory-shaped like `gates/` — a bundle may
  declare many named containers — and each one's `queues:` array must
  hold exactly the five platform-fixed anchor names, in exactly this
  order, undeclarable by either axis for the identical re-resolution-
  anchor reason system statuses are: `setup`, `prep`, `main`, `retro`,
  `cleanup`. There is no per-container-kind sequence table and no
  kind registry — `container:` names the declaration itself, the same
  way a `gate:` file names its own gate. `types/<name>.yaml` registers
  a plain work-item type as a list of the declared gates (§15.2) it
  visits — inverting the gate's own former `ticket_types:` field,
  which is retired outright — and shares one namespace with container
  declarations: a bundle's containers and its plain types are one
  registry. Every queue entry, project or container, carries exactly
  one field, `flow:`, required, naming a member of that registry; the
  loader does not branch on which kind of declaration the name
  resolves to, only on what that declaration's own content contains —
  this replaces the earlier `flow:`/`opens:` pair outright, not merely
  renames half of it. The loader gains two structural checks with no
  exact precedent in the closed sets §13 already validates: **a
  declaration-graph check** over container names connected by `flow:`
  edges whose target resolves to another container (an edge into a
  plain type is not part of this graph — a plain type has no further
  `flow:` of its own, so it is always a leaf), which must be acyclic
  with a self-reference rejected as the degenerate one-node cycle —
  this is the check that bars a container from nesting its own kind
  and the one that bounds nesting depth, and it replaced an earlier,
  wrong-altitude draft of the same idea that checked ancestry on
  *instances* rather than *declarations* (rejected because it leaves
  unbounded depth declarable, caught only mid-flight); and a scoping
  check that a `blocks:` entry must name a queue declared in the same
  file, never a queue nested inside what the blocking queue's `flow:`
  opens. `boundary`, the single static agent step this replaces, is
  retired from §15.1's list outright — nothing takes its slot there,
  because `retro` and `setup` dispatch as ordinary chain flows through
  a declared queue rather than through a tier's `delivery.agent_step`;
  `setup` specifically is its own anchor entry, first in a minted
  container's own five-entry sequence — not a value stashed on
  `prep`'s own `flow:`, which an earlier draft of this same ticket got
  wrong (it runs `setup` once per container instead of once per mint)
  — so there is nowhere `flow:` needs to name two things on one
  declaration. The machinery this grammar drives — the dispatcher, the
  sweep, the scan/setup/retro passes, and the ticket→milestone
  `Stubbed`/`Urgent` interactions that give it a subject — is
  `systems/delivery.md`'s (`Catapult.Delivery.ContainerLifecycle`).

- **A fourth ORC-105 pass unified `queues/project.yaml`, `queues/
  containers/<name>.yaml` and `types/<name>.yaml` into one declaration
  shape, retired `after:`, and moved `critique.yaml`/`gates/`/
  `environments/` positioning inline** (design pass, superseding the
  three-file-shape entry above; `docs/dsl-syntax.md` §15.1-§15.9;
  `docs/v5-design-decisions.md` §7.8, §7.18, §7.19). Every declaration
  is now `types/<name>.yaml`: `type:` names it, `skeleton:` picks
  `ticket`, `container` or `none` (§15.1's per-skeleton fixed anchor
  set), and `statuses:` is one ordered array holding both the
  skeleton's own anchors and whatever gates (`review:`), environments
  (`environment:`) or `critique` entries the author interleaves among
  them — position is the array index, full stop; no declaration in
  this grammar carries an `after:` field anymore, on a gate or an
  environment either, which is the one change reaching past this
  ticket's own container feature into gate/environment declarations
  as they exist today. `gates/<gate>.yaml` and `environments/<env>
  .yaml` still exist as named, reusable declarations (role, throwback,
  escalation, depth; promotion, lifetime) — what moved out of them is
  only position, since a citing type's own array now says where each
  one runs, and two types may run the same gate in different relative
  order without either being wrong. `critique.yaml` is retired outright
  (superseding ORC-92's form, `docs/v5-design-decisions.md` §7.19): a
  `critique` entry must sit immediately after a `generation` entry in
  the same array, which is also the load-time reason a `container`- or
  `none`-skeleton type can never declare one — it has no `generation`
  anchor to pair with. The loader gains three checks with no exact
  precedent in the closed sets §13 already validates: a `statuses:`
  entry must carry exactly one of `status:`/`review:`/`environment:`;
  `flow:`/`blocks:` are legal only on a queue-shaped `status:` entry
  (a container's five anchors, or any entry in a `none`-skeleton
  type); and a `ticket`-skeleton type's array must contain `pending`
  (first), `generation`/`checks`/`merge`/`deploy` (each at least once,
  in that relative order, `generation`/`merge` may recur) and
  `terminal` (last). **Also reversed:** `extends:` narrows to the
  chain axis; a workflow bundle carries no `extends:` field at all,
  since v5 §3.1's fork-tailor-merge lifecycle — already the model for
  bundles and policy packs generally — turns out to be the one a
  workflow bundle was always shaped for, not a runtime-composed layer
  (`docs/dsl-syntax.md` §11). The machinery is unaffected in shape by
  this pass beyond what it inherits from the grammar being one file
  format instead of three.

- **A fifth ORC-105 pass corrected two errors the fourth pass's own
  three-valued `skeleton:` field had baked in, and added one field**
  (design pass; `docs/dsl-syntax.md` §15.1-§15.9;
  `docs/v5-design-decisions.md` §7.8). `skeleton:` is optional rather
  than `ticket | container | none` — a type declaring neither has no
  anchors at all, which retires the loader's "at most one loaded
  `skeleton: none` declaration" check outright rather than replacing
  it: rootness is a node nothing else's `flow:` targets, derived from
  the declaration graph the loader already builds, never a value a
  second check has to police. **The declaration-graph acyclicity
  check's own node set was wrong** — the fourth pass admitted only
  `container`-skeleton types as nodes, which excluded every `flow:`
  edge *into* a skeleton-less type by construction and left a real
  cycle undetected (`milestone.main` naming `flow: project` alongside
  `project.build-out` naming `flow: milestone`); the loader now treats
  any type with a queue-shaped anchor — `container`-skeleton or
  skeleton-less alike — as a graph node, which closes the hole and
  also reverses the fourth pass's own "a `flow:` naming a
  `none`-skeleton type is a load error." **Gates and environments
  widen onto skeleton-less types too** — the fourth pass's restriction
  read an argument for why a project needs no re-resolution anchor as
  an argument about what its array may contain, which the governing
  rule never actually claimed. **New: `singleton: true` on a
  queue-shaped anchor entry**, bounding a queue to at most one work
  item over its lifetime for plane code to address directly
  (`milestone`'s `setup` and `retro` are the motivating declarations)
  — not a load-time check (assignment history is live state), and the
  loader's job stops at accepting the field; a second assignment to a
  singleton queue is dispatch behavior, not a grammar concern, and was
  first recorded in `docs/v5-design-decisions.md` §7.8 as filing
  `Blocked` rather than refusing the dispatch — corrected at this same
  ticket's sixth pass below, since a lifetime bound and a "files
  `Blocked`" response turned out to disagree with each other. **Not
  built as part of this pass**, same as the third and fourth: the
  dispatcher, the sweep, the scan/setup/retro machinery, and the
  singleton-queue rejection check — ORC-104's.

- **A sixth ORC-105 pass named the plane's entry point explicitly and
  corrected `singleton:`'s own semantics, both gaps the fifth pass's
  own record left open** (design pass; `docs/dsl-syntax.md` §2, §13,
  §15.2, §15.6-§15.7; `docs/v5-design-decisions.md` §7.8). Derived
  rootness answers "is this type a root," never "which root does the
  plane dispatch a fresh project from" — a bundle declaring `epic`
  without nesting it under anything else already has two roots, so
  "the project is a project by convention" named nothing the loader
  could check. `entry:`, a new required key on a workflow bundle's own
  `bundle.yaml`, names that type instead, checked at load the same way
  `role_holders:` and `mirror_mapping:` are checked when supplied: the
  name resolves, the resolved type carries a queue-shaped anchor, and
  it is a root in the declaration graph. **`singleton:` was wrong at
  the fifth pass in what it bounded** — "0 or 1 unresolved right now"
  rather than "at most one, ever, over the queue's whole lifetime" —
  which is why a second work item was recorded as admitted-and-
  `Blocked`: under a population bound, a queue whose sole item has
  reached `terminal` looks exactly like an empty queue with room. It
  is neither; the loader's own check is unaffected (still not a
  load-time constraint, since assignment history is live state), but
  the dispatcher's job changes from "admit and file `Blocked`" to "a
  loud error, permanently, once one work item has ever been assigned."
  **Not built as part of this pass**, same as every pass before it:
  the dispatcher, the sweep, the scan/setup/retro machinery, the
  entry-point load check, and the singleton-lifetime rejection check —
  ORC-104's.

- **ORC-115 (design pass, corrected on two later design reviews)
  narrows `throwback:` to a single-target escape hatch and gives a
  `statuses:` array a grouping construct the fourth ORC-105 pass's
  unification didn't have** (`docs/dsl-syntax.md` §15.10, §13, §15.4;
  `docs/v5-design-decisions.md` §7.8, §7.16, §7.19). A `statuses:`
  entry may now be a bare, unnamed sub-array holding a contiguous run
  of the entries already legal elsewhere in the array
  (`status:`/`review:`/`environment:`, unchanged); the loader gains
  three checks with no exact precedent in the closed sets §13 already
  validates — a sub-array nested inside a sub-array is a load error
  (this pass's own grammar is flat, deliberately, see below); a
  sub-array must hold exactly one entry whose `status:` is a
  non-review-shaped agent-balled system status (`generation`, `design`,
  `architecture`, `implementation`, `retro` or `setup` — §15.1's own
  `ball` column minus `critique` and `reconcile`, both review-shaped
  and excluded for the reason §15.5 already excludes `critique` from
  standing alone; `merge` is not a candidate either, its own `ball`
  having moved from `agent` to `plane`, ORC-151), zero or
  two-or-more being a load error naming the count found; and a
  queue-shaped anchor (`flow:`/`blocks:`) may not sit inside one. A
  `review:` entry's decline defaults to its citing sub-array's own
  earliest entry — its own leading `pending`, when the sub-array has
  one (every generation-shaped sub-array does, §13's tightened check),
  its own non-review-shaped entry directly otherwise (a fourth-pass
  correction from resolving to that entry unconditionally) — computed
  at throwback time from the loaded bundle, never stored, the same
  posture `ready_scopes` and staleness already take. A gate sitting
  first in its own sub-array, or in no sub-array at all, has no
  earlier entry there to fall back to, so this derivation gives it no
  default and it must declare `throwback:` explicitly (ORC-181,
  `docs/dsl-syntax.md` §15.4, §13, §15.10).

  **The pass this entry originally recorded held `throwback:`
  unaffected — a real, bounded allow-list stays the only legal decline
  targets, and the derivation only fills the empty-list gap — on the
  strength of a claim that turned out false: that `Catapult.Engine
  .Aggregate`'s `DeclineGate` clause enforces list membership. It
  doesn't; that check is the (unbuilt) command edge's, per the
  module's own moduledoc.** Corrected, the author's decision is
  recorded instead: a decline's legal targets are never narrower than
  `docs/v5-design-decisions.md` §7.19's own Blocked-return rule — any
  earlier status in the ticket's effective sequence.

  **A second correction pulled back from retiring the field outright.**
  Unbounded legality removes only one of `throwback:`'s two jobs. It
  bounded legality, and that job is gone. It also named a decline's
  *landing point* — the one-click action a bare decline takes — and
  that job is untouched: the sub-array's own earliest entry — its own
  leading `pending` for a generation-shaped group, §13 — is the
  derived default, and `throwback:` is what a gate declares
  instead, for the gate that wants a different one. A list stops
  meaning anything the moment it stops bounding (naming several targets
  said "any of these is legal," a legality claim), so the field narrows
  to a single optional status rather than disappearing.
  `Catapult.Dsl.Gate`'s `throwback: [String.t()]` narrows to
  `throwback: String.t() | nil`, and `Catapult.Dsl.Workflow
  .gate_throwback_problems/2`'s membership check narrows to match — a
  smaller field, not a removed one, and still dev's diff to make, not
  design's.

  **What survives and what changed, named against the actual default
  bundle:** before this pass, an *undeclared* `throwback:` (`[]`,
  §15.4's old default) left a gate with zero legal exits — an
  unreachable gate, not a feature — so every declared gate in
  `bundles/default-flow/gates/**` names one today out of necessity.
  After this pass, no gate *needs* to declare anything: the derivation
  supplies a default and the earlier-prefix rule supplies everything
  else a human might pick — but a gate that wants a landing point other
  than its derived default still declares one. `ux-review`'s `[pending]`
  is exactly that gate: `pending` sits outside `ux-review`'s own
  sub-array and differs from the derived default (`generation`), so the
  declaration is doing real work and survives, narrowed to a bare
  `pending`. `engineering-review`'s `[generation, ux-review]` is mixed:
  `generation` restates the derived default (redundant, droppable), and
  `ux-review` is a second landing point the narrowed field can no
  longer hold beside it — which one `bundles/**` keeps is an ordinary
  bundle-authoring call, not this record's to make. §15.1's fixed
  vocabulary loses none of its three jobs (gates/environments/critique
  position against it, chain tiers bind to it, cutover re-resolution
  anchors on it) — only the middle job's *legality*-bounding half,
  which no longer needs any bundle-declared list; the landing-point half
  survives on the narrowed field.

  **Not decided by this pass, named rather than glossed over:** nested
  sub-arrays (a homonym risk against `container`-skeleton nesting,
  §15.6, this pass's own open question); and a throwback from a gate
  sitting outside every sub-array, targeting into one. (A third item
  this pass left open — whether a population anchor could ever sit
  inside a sub-array, and the dispatch question behind folding
  `setup`/`retro` into `milestone`'s own array — is resolved at
  ORC-148, below.) **Built at ORC-141**, dev's diff against this
  record: the loader changes this entry describes, in
  `lib/catapult/dsl/workflow.ex` and `lib/catapult/dsl/gate.ex` — the
  `throwback:` field narrows from a list to a single optional status
  (`String.t() | nil`) and its load-time check narrows to match, and
  `gate_throwback_problems/2`'s "earlier in the array" logic is reused
  at the command edge as a runtime check for the undeclared case
  (`Catapult.Engine.Commands.DeclineGate`).

- **ORC-148 (design pass) reverses the fourth pass's own governing
  sentence — a skeleton fixes a required backbone, never an exclusive
  membership — and retires `singleton:` outright** (`docs/dsl-syntax
  .md` §13, §15.1, §15.2, §15.5-§15.10; `docs/v5-design-decisions.md`
  §7.8; `systems/delivery.md`). "A container is any work item whose
  skeleton has queues, a ticket is any work item whose skeleton has a
  generation" (§15.2's own fourth-pass sentence) was read, in the
  loader, as an *exclusive* membership rule: `Catapult.Dsl.Workflow
  .container_shape_problems/2` required a `container`-skeleton type's
  array to hold *exactly* its five fixed anchors, nothing else, and
  `Status.parse/4`'s `queue_shaped?` — whether `flow:`/`blocks:` (and,
  until now, `singleton:`) are legal on a given entry — was computed
  once per type from `skeleton:` alone. Nothing in this section's own
  prose ever argued for that exclusivity; it was the third file
  format's residue, the same kind of accidental coupling the fourth
  pass's own unification was written to remove from everywhere else.
  **The fix moves the check from the type's `skeleton:` to the entry's
  own name and content:** `flow:`/`blocks:` are now legal on a
  *population anchor* (`prep`/`main`/`cleanup`, or any entry in a
  skeleton-less type's array) and illegal on the fixed agent/world
  kinds (`pending`, `generation`, `critique`, `checks`, `merge`,
  `deploy`, `setup`, `retro`, `terminal`), whichever type's array
  either sits in; the declaration-graph node set and `entry:`'s own
  check both move from "is this type's `skeleton:` `container` or
  absent" to "does this type's array hold a population anchor at all."
  A `container`-skeleton type's required backbone (its five anchors,
  each at least once, in order) and a `ticket`-skeleton type's (unchanged)
  are exactly as fixed as before; what they no longer do is cap what
  else a declaring bundle may additionally interleave from the shared
  vocabulary. **This is what lets `setup` and `retro` fold inline:**
  each becomes an ordinary agent-balled entry directly in `milestone`'s
  own array — `retro` grouped with the sign-off gates around it in a
  §15.10 sub-array (the shape ORC-115 named and left unreachable,
  above), `setup` needing no group at all — dispatched by
  `milestone`'s own chain-bundle tiers exactly as a `generation` entry
  dispatches by a ticket-skeleton type's, with no `flow:` and no
  separately minted child. `types/setup.yaml` and `types/retro.yaml`
  are deleted rather than kept as dispatch targets (`bundles/**`,
  dev's diff). **`singleton: true` retires rather than narrows**,
  because the cardinality it bounded stops existing: it closed a
  *queue* to a second assignment once populated, and `setup`/`retro`
  stop being queues the moment they have no `flow:` to nest a child
  through — there is exactly one `milestone` instance and exactly one
  array position each occupies, which is the "at most one, ever"
  property with nothing left for a field to declare. **This also
  settles the question ORC-115 left open** — whether a container
  instance can be an agent dispatch target at all — the same direction
  as the rest of this reversal: dispatching from a work item with a
  queue and one without were never different operations, only
  different status flows attached to the identical mechanism
  (`docs/v5-design-decisions.md` §7.8, `systems/delivery.md`'s own
  diff against this). **Not built as part of this pass:** the loader
  changes (`lib/catapult/dsl/status.ex`, `type.ex`, `workflow.ex`), the
  `bundles/default-flow/**` fold itself, and the dispatcher/executor
  work `systems/delivery.md` files against its own Target list — all
  dev's diff against this record, not design's.

- **ORC-151 (design pass) splits the fixed vocabulary's `merge` kind
  in two, naming the review it always implied** (`docs/dsl-syntax.md`
  §15.1, §13, §15.5, §15.10, new §15.11; `docs/v5-design-decisions.md`
  §7.5, §7.19). `merge` carried two jobs at once — reading a produced
  PR against its own argument, and mechanically joining it into the
  parent branch — and `Catapult.Dsl.SystemStatus.agent_steps/0` has
  carried `:reconcile` since Phase 3 with no matching `phase:` to
  declare it against. `reconcile` joins the fixed table as the second
  **review-shaped** kind alongside `critique` (the parallel category to
  "generation-shaped," named for the first time this pass), agent-balled
  and required — stated positionally, not per skeleton, at this same
  pass's own design review — wherever a `merge` entry appears: a
  `merge` entry must be preceded, earlier in the same array, by a
  `reconcile` entry, `container`-skeleton arrays included (closing a
  gap the skeleton-keyed framing left open — `dsl-syntax.md` §15.2's
  `milestone.yaml` example previously ran `setup` and `retro` each
  through a bare `checks → merge → deploy`, merging unread), never
  opt-in the way `critique` is, since no ticket merges without having
  been read against its own argument first. `reconcile` may also
  recur, the way a generation-shaped entry and `merge` already could —
  `dsl-syntax.md` §15.11's own worked example carries two, one closing
  the architecture phase's own join and one closing implementation.
  `merge`'s own `ball` changes from `agent` to `plane`: mechanical,
  effected by the plane once `reconcile` approves, barring a conflict
  (which routes to `Blocked` the ordinary way). This closes the finding
  ORC-148's own dev pass filed against itself: `Catapult.Delivery
  .ContainerLifecycle.inline_dispatch_point?/1` excluded `merge` by
  name, inside a module whose own moduledoc asserts it branches on no
  status name — the predicate generalizes to "agent-balled and not
  review-shaped," which excludes `merge` because it is no longer
  agent-balled, needing no name check. The sub-array anchor rule
  (§15.10) generalizes the identical way: "non-critique agent-balled"
  becomes "non-review-shaped agent-balled," admitting any number of
  `reconcile` entries alongside `critique` ones without counting toward
  the sub-array's required-one anchor. **Gate scope is derived from
  position relative to the nearest `reconcile` before it** — a gate
  earlier than every `reconcile` in a type's own array approves the
  citing tier's own artifact; one sitting after a `reconcile` approves
  what that `reconcile` has already joined and, per this same ticket's
  third design review below, already **merged** in from every child
  beneath it, superseded again by a later `reconcile` if one follows —
  closing a gap `v5-design-decisions.md` §7.16 left open (what a gate
  scoped to a join, rather than to one generation's own sub-array,
  approves), with no new field: computed from array position, the
  identical "derive, don't declare" posture `throwback:`'s own default
  already takes. **No `docs/non-goals.md` entry**, for the reason the
  design record gives in full: growing this closed table is covered by
  that file's existing admission rule without amendment, the same
  non-entry `design`/`architecture` got at ORC-148. **Not built as part
  of this pass:** the loader changes (`lib/catapult/dsl/system_status.ex`'s
  `@statuses` table and `generation_shaped?/1`'s new sibling, `status
  .ex`'s `non_critique_agent_step?/1` rename and generalization,
  `workflow.ex`'s backbone and sub-array checks widening to include
  `reconcile` and the new merge-preceded-by-reconcile positional
  check), the `bundles/**` content that declares it, and the
  dispatcher change `systems/delivery.md` files against its own Target
  list — all dev's diff against this record, not design's.

- **A third design review on this same ticket retires `fanout` from
  the fixed table, moves architecture's own fan-out onto the ticket
  tree, and makes `merge` implicit outside the root** (`docs/dsl-syntax.md`
  §15.1, §13, §15.11; `docs/v5-design-decisions.md` §7.10, §7.15,
  §7.19). Three changes, none reopening the split above:
  **`fanout` retires**, its only remaining job (marking a feature's own
  wait before its implementation-phase `reconcile`) now a dispatch
  precondition rather than a status of its own — the edge type of the
  identical name (`Catapult.Dsl.Edge`'s `@types`, node-id minting) is
  untouched. **Architecture's own fan-out — sysarch, each comparch,
  each subcomparch — dispatches through its own ticket instance of the
  one declared type, spawned when the plan names it** (the existing
  child-spawn rule, `v5-design-decisions.md` §7.10, applied
  recursively) **rather than as `depth:`-filtered scope-runs inside one
  ticket**, which could never give a subcomparch `critique` its own
  bounce (a ticket has one status at a time, so one ticket's one
  `critique` visit throws the whole tree back). `reconcile` itself
  drops the `depth:` this ticket's second pass gave it: whether an
  instance runs its own join is now a fact about that instance's own
  children, never a declared ceiling. **`merge` becomes depth-0 by
  rule and fires only at the root** — every `ticket`-skeleton type
  still declares exactly one, reconcile-preceded, load-checked
  unchanged; a non-root instance's own copy of that declaration never
  reaches it by its own dispatch, and instead merges when its parent
  enters `reconcile` (`v5-design-decisions.md` §7.2's child-blocks-parent,
  read as a precondition on entry and, symmetrically, as the merge
  trigger). This is not plane logic branching on grouping — the second
  pass's own citation of `docs/non-goals.md`'s automation-protocol
  entry against an implied-merge mechanism is withdrawn as a
  misapplication of that entry's admission rule, which is about states
  and, by §15.10's own extension, about groupings a bundle authors;
  tree shape is neither. `docs/v5-design-decisions.md` §7.15's own
  "children spawn at `Building`" passage, stale against §7.10's already-
  recorded amendment before this pass, is corrected to match. **Not
  built as part of this pass:** the same loader and dispatcher work
  named above, now covering `SystemStatus.@statuses`'s `fanout` removal
  and the tree-shape-derived `reconcile`/`merge` dispatch rather than a
  depth-filtered one — all dev's diff against this record.

- **A fourth design review on ORC-151 fixes five worked-example defects
  the third pass's own draft left standing, and settles two questions
  it left open** (`docs/dsl-syntax.md` §13, §15.1, §15.2, §15.4, §15.5,
  §15.10, §15.11; `docs/v5-design-decisions.md` §7.6, §7.10, §7.19).
  **`implementation` joins the fixed table as a third named generation
  kind** — the third pass's own worked example had dispatched a tier's
  code through a bare second `checks`, but `checks` is world-balled CI
  against produced work, never a generation run; deliberately gateless
  in the shipped default (the touchpoint budget calibrates two author
  gates, `v5-design-decisions.md` §7.10, and a third keyed to
  implementation is that entry's own named exception, not the ordinary
  case). **`pending` recurs, once per generation-shaped entry's own
  sub-array**, tightening "somewhere earlier in the array" — with
  `fanout` retired, `pending` is the only plane-balled wait position
  left, and a shared leading `pending` licensing several sub-arrays at
  once left later ones with nowhere to queue; throwback's own derived
  default (§15.10) now falls back to a generation-shaped sub-array's
  own leading `pending` rather than straight to its agent step,
  matching the repair-loop mapping (`Ready for rework`/`Reworking`)
  rather than skipping the queued wait. **A declared gate may now be
  cited twice within one type's own array**, the analogue of
  `critique`'s existing citing-it-more-than-once precedent, extended
  from a system status to a named declaration — `architecture-review`,
  cited once before a `reconcile` and once after, is the exercised
  case. **Two type declarations, not one array depth-filtered**: the
  third pass's own worked example had instantiated "one declared
  type… once per node" with the feature ticket itself at its own depth
  0, which cannot be `types/feature.yaml` — `design` has no `depth:`
  field to make it no-op below the root the way a gate or `critique`
  can — so the feature's own type and the type architecture's
  recursive fan-out spawns are two separate declarations; this is
  `v5-design-decisions.md` §7.6's "Child" lifecycle, read correctly for
  the first time, not that document's own feature lifecycle
  depth-filtered. Two further defects were comment/naming fixes with no
  structural consequence: the worked example's own `merge` comment had
  described children merging at their *own* dispatch of `merge` rather
  than at their *parent's* `reconcile` (the rule was always the latter,
  stated correctly elsewhere in the same section); and `comparch-review`
  renamed to `architecture-review`, since naming a gate for the tier it
  reviews is the implicit-anchor-meaning defect §11 exists to keep out,
  and its own two positions already derive their different scopes from
  where they sit, not from a second name. **Not built as part of this
  pass:** the same loader and dispatcher work named above, now covering
  the new kind, the two-type split, and the tightened `pending`/gate
  checks — all dev's diff against this record.

- **A sixth design review on ORC-151 closes one gap the fifth pass's
  own fix left open** (`docs/dsl-syntax.md` §13, §15.5;
  `docs/v5-design-decisions.md` §7.19). The fifth pass amended
  `critique`'s load-time adjacency rule in §13 to admit an intervening
  `checks` — "immediately after a generation-shaped entry, or
  immediately after that entry's own `checks`, never before it" — but
  the amendment landed only there. §15.5, the section §13's own
  citation points at as the rule's other statement, still read the
  pre-amendment sentence with no mention of `checks`, and three further
  restatements inside §13 itself — the container/ticket-skeleton
  interleaving passage, the `skeleton:`-decoupling section's own
  "critique's admission" bullet, and the project-level widening
  passage — were equally unamended, so every worked example the fifth
  pass had just reordered was, read against any of those four sites
  alone, a load error. All five now carry the identical caveat; §15.5's
  own worked-example paragraph, which had
  claimed "the adjacency rule above already says this precisely" while
  the rule above did not yet say it, is folded into the rule statement
  itself rather than left as a second, narrating paragraph. This is
  the sixth consecutive round this ticket has corrected one statement
  of a rule and left a sibling statement stale — `merge`, the reconcile
  count, `checks`'s position, the child lifecycle, `pending`, and now
  `critique`'s own adjacency rule against itself — so a rule with three
  or more statements in this document (critique adjacency, `pending`
  precedence, the depth-bearing sites, the generation-shaped kind list)
  needs every statement edited in the same pass that changes any one of
  them, not just the site a review happens to quote. **Not built as
  part of this pass:** unchanged from the fifth pass's own note — the
  loader and dispatcher work is dev's diff against this record, not
  design's, and nothing here changes what it must cover.

- **A fifth design review on ORC-151 fixes three defects the fourth
  pass's own worked examples and lifecycle mapping left standing**
  (`docs/dsl-syntax.md` §13, §15.1, §15.2, §15.5, §15.11;
  `docs/v5-design-decisions.md` §7.19). **`checks` now sits between a
  generation-shaped entry and the `critique` that reviews it**, not
  after — every worked example had the order backwards, in two cases
  running the human gate ahead of CI too. `critique`'s own load-time
  adjacency rule (§13, §15.5) widens to admit an intervening `checks`
  ("immediately after a generation-shaped entry, or immediately after
  that entry's own `checks`, never before it"), and both worked
  examples (`types/feature.yaml`, `types/component.yaml`) reorder to
  match — one `checks` per generation-shaped sub-array, always ahead of
  its `critique`. **§15.1's own lifecycle mapping is corrected to carry
  three `Todo`s and three `Checks`, matching `feature.yaml`'s three
  generation-shaped sub-arrays**, not the single occurrence of each it
  showed before — a direct violation of this same ticket's own
  `pending`-once-per-sub-array rule (§13), stated as a tracker
  lifecycle rather than a load error. This is the fifth consecutive
  pass the mapping and the worked example have disagreed (`merge`, the
  reconcile count, `checks`'s position, the child lifecycle, now
  `pending`), so the fix adds a standing instruction rather than a
  sixth one-off correction: the two describe one type and are edited
  together going forward. **`reconcile`'s own worked-example comments
  are reworded from "present iff this instance has children" to match
  how `depth:`'s own filtering is already described** — the array
  entry is declared once for the type, unconditionally, like every
  other entry; what varies per instance is whether its own *effective
  sequence* selects anything from it, exactly the "derive, don't
  declare" framing this same section already gives `depth:` itself.
  The prior wording read as if the entry disappeared from a
  per-instance copy of the array, which nothing here does. **Not built
  as part of this pass:** the same loader and dispatcher work named
  above, now covering the widened critique-adjacency check — dev's
  diff against this record, not design's.

- **ORC-155 (design pass) gives a `status:` entry a bundle-authored
  `name:` distinct from its kind, and namespaces a position by the
  sub-array it sits in** (`docs/dsl-syntax.md` §13, §15.1, §15.4,
  §15.9, §15.12; `docs/v5-design-decisions.md` §7.19). ORC-151 left
  every recurring kind — three `pending`, three `checks`, two
  `reconcile` in `dsl-syntax.md` §15.2's `types/feature.yaml` worked
  example alone — addressable only by kind, which
  a card, a rail entry, a `throwback:` or a `blocks:` reference all
  need to name unambiguously and cannot: `CatapultWeb.Live.Positions
  .key/1` round-trips exactly the `{:kind, atom} | {:gate, name}` pair
  the projection stores, with no way to say *which* `pending`. `name:`
  answers it without growing §15.1's closed kind table a fourth time
  for a need no chain lifecycle actually has (the identical reasoning
  §15.9 already gives for `design`/`architecture`/`implementation` not
  needing a fifth or sixth member): a position's identity is
  `<anchor>.<name>`, the sub-array's own one non-review-shaped
  agent-balled entry supplying the anchor (§15.10), bare at the top
  level, one level of qualification only. **This retires the "same
  declared gate cited twice" pattern §15.4 settled at the fourth
  design review above**: two citations landing in the same sub-array
  now collide under the new uniqueness-within-a-namespace check, and a
  citation told apart from its sibling only by which side of a
  `reconcile` it falls on is exactly the second qualification level
  this ticket refuses. `architecture-review`, cited twice in
  `feature.yaml` and again in §15.11's `component.yaml`, is the
  exercised case ORC-151 left standing; ORC-155 renames the citation
  scoped to what `reconcile` has joined to a gate of its own,
  `architecture-synthesis-review`, in both worked examples — the two
  already reviewed different things and now say so by name, rather
  than by which side of a join they happen to sit on. **Also new: a
  load-time check that no declared gate name collides with any
  addressable status name** — safe by construction while status names
  were platform-fixed kinds, not once a bundle can author one. **Not
  built as part of this pass:** the loader changes (`lib/catapult/dsl
  /status.ex`'s known-key list and its `depth:` gate, which must key on
  kind rather than on the parsed name string now that the two can
  differ; `workflow.ex`'s namespace/uniqueness and gate-disjointness
  checks; `system_status.ex` is unaffected, since every predicate it
  exports already reads kind), the projection column
  (`Catapult.Delivery.Store.tickets_for_project/1` gains a name column
  beside `status_kind`), and `CatapultWeb.Live.Positions`' own
  round-trip encoding, extended to carry the qualifying anchor — all
  dev's diff against this record, not design's.

- **A design review on ORC-148 corrected two things the pass above got
  wrong and settled one it had left implicit** (`docs/dsl-syntax.md`
  §13, §15.1, §15.5, §15.7, §15.10; `docs/v5-design-decisions.md`
  §7.8). The pass above's own worked examples — `milestone.yaml`'s
  `main blocks: [retro]` beside `retro` folded inline with no `flow:`
  — contradicted its own load-time rule: `blocks:` still required its
  target to be a population anchor, which an inline `retro` is not, so
  the shape the pass argued for would not have loaded. **`blocks:`
  inverts to an entry guard, checked once at the transition it guards,
  never a standing hold a projection recomputes** — `Q1 blocks: [Q2]`
  means `Q2` cannot be *entered* while `Q1` still carries unresolved
  work, checked exactly once, not continuously for as long as `Q2`
  runs. This removes a real defect the standing-hold reading carried:
  a queue refilling while the guarded entry was already mid-run pulled
  the container back out of it, and `retro`'s own output landing back
  in `main` would have made a completion-hold `blocks:` interrupt
  `retro` with its own result. **Reaching `terminal` gains an
  unconditional, undeclarable guard** — every one of a container's own
  queues holding no unresolved work — separate from whatever `blocks:`
  a bundle authors, so a queue nobody thought to name in some other
  entry's `blocks:` list cannot be quietly closed over on the way to
  `terminal`; this system's dispatcher enforces it, the loader checks
  nothing new. **`generation`'s closed vocabulary gains two named
  kinds, `design` and `architecture`**, both generation-shaped
  everywhere `generation` itself is checked (backbone membership,
  `pending`-precedes, blocked-exit, critique pairing, sub-array
  agent-balled counting) — platform-fixed in the same table, not
  bundle-authored, which is what a blocked ticket's re-resolution
  anchor set needs to stay undeclarable. Plain `generation` is
  unaffected and stays correct for a type with one generation-shaped
  visit; `setup`, `retro` and the seed pass keep it unchanged. **A
  sub-array is referenced by an entry it contains, never by a name of
  its own** — `blocks:`'s own load-time check resolves its target by
  containment, unique within the citing array, rather than requiring
  the target to be a population anchor; a reference resolving to zero
  or to two-or-more matches is the load error, not the shape of the
  entry it lands on. **Not built as part of this pass**, the same
  boundary the pass above draws: `lib/catapult/dsl/status.ex`,
  `workflow.ex` and `system_status.ex`'s own diff against this record —
  the `blocks:` check, the `design`/`architecture` kind additions, and
  the dispatcher's move from a standing-hold projection to a
  transition-time check — are dev's, not design's.

- **ORC-198 (design pass) splits `Type.namespaced_positions/1`'s one
  ambiguity computation into two, because ORC-155's own `name:` is
  exactly what makes them able to disagree** (`docs/dsl-syntax.md`
  §15.12). `namespaced_positions/1` computes a single ambiguity set —
  `Enum.frequencies_by(& &1.bare)` — and its `canonical` field answers
  one question with it: is this entry's own *authored name* the string
  a reference resolves to unqualified, or does it need `<anchor>.name`
  because that bare string recurs elsewhere in the type's array? That
  is exactly right for what `Catapult.Dsl.Workflow.resolve_reference/2`
  and `earlier_names/2` need (§15.12's own "stays bare when
  unambiguous" rule), and the two stay in step because both are keyed
  on `bare`.

  A second question gets asked of the same set, and ORC-155's `name:`
  is what pulls it apart from the first: does this entry's own
  *runtime position* — its `status:`/`review:`/`environment:` value,
  the field every `position()` constructor reads and `name:` never
  touches (this doc's ORC-155 entry above: "every load-time predicate,
  and every plane branch, still reads the kind — never the name") —
  recur elsewhere in the array, so that two occurrences collide once
  reduced to `{:kind, atom}` and need their anchor carried at runtime
  regardless of whether they're also nameable apart? Before `name:`
  existed the two questions had one answer, because bare **was**
  kind. `name:` was built precisely so two same-kind entries could
  carry distinct labels (`docs/dsl-syntax.md` §15.12, ORC-155) — and a
  bundle exercising exactly that, two `status: pending` entries with
  distinct `name:` overrides, now recurs on kind while *not* recurring
  on bare: `canonical` reads "unambiguous" for both (their names don't
  collide, the point of naming them), while `Catapult.Delivery
  .FeatureLifecycle.Sequence.to_position/1` — reading `status:`, never
  `name:` — still builds `{:kind, :pending}` for both. Reproduces the
  "first occurrence wins, silently" failure ORC-171 fixed, through the
  one door `name:` itself opens, and ORC-171's own reproduction never
  exercised a per-occurrence override so never hit it.

  The two sets are not one a subset of the other, so neither is safe
  to derive from the other: `status: pending` beside `status: checks,
  name: pending` recur on bare with **distinct** kinds — a real
  reference ambiguity (`blocks: [pending]` cannot pick one), no
  runtime collision at all, since the two resolve to different
  `position()` shapes. Two distinct-`name:` `status: pending` entries
  are the opposite — no reference ambiguity, each name resolves to
  exactly one entry — but a real runtime collision. `bare`/`qualified`/
  `canonical` keep meaning exactly what ORC-155 gave them, unchanged,
  since `resolve_reference/2` and `earlier_names/2` are correctly keyed
  on bare already. `namespaced_entry()` gains a second, independent
  field, `kind_ambiguous: boolean()` — true when this entry's own kind
  (`status:`/`review:`/`environment:` value, never `name:`) recurs
  elsewhere in the type's own array — for the runtime-collision
  question alone. **Not built as part of this pass:** the
  `kind_ambiguous` field itself, `type_test.exs` coverage for the two
  sets' divergence, and every consumer's switch from the reused
  `canonical == bare` test to this field — `systems/delivery.md`'s own
  ORC-198 entry names the three call sites — are dev's diff against
  this record, not design's.

## Initial vs target

Initial (Phase 3): core vocabulary, loader, design-dialect extension
set (delivery annotations arrive with delivery). Target: full
extension registry with delivery + runtime dialects registered;
bundle-diff support for the registry's handle machinery.

## Depends on

substrate. Content it loads lives in platform_content.
