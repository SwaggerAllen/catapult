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
  `docs/dsl-syntax.md` §13, §15.4, §15.5; `docs/v5-design-
  decisions.md` §7.19 — both grammar sections' own shape changed again
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
  entry; `docs/dsl-syntax.md` §15.6-§15.9; `docs/v5-design-
  decisions.md` §7.8). `queues/project.yaml` is optional and singular
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
  declaration. **Not built as part of this pass**: the dispatcher, the
  sweep, the scan/setup/retro machinery, and the ticket→milestone
  `Stubbed`/`Urgent` interactions this needs to have a subject at all
  — ORC-104's, which this entry gives a grammar to build against.

  **Retiring `boundary` from `Catapult.Dsl.SystemStatus`
  (`lib/catapult/dsl/system_status.ex:35,52`) is dev's diff, not
  design's** (§7 of the design record, settled): the constant module
  is core_dsl's own mapped path, and design's committable paths stop
  at doc content. Filed against ORC-104 rather than actioned here —
  the type and the `@agent_steps` list both still name `:boundary`
  today, which means the loader still accepts a chain declaring
  `agent_step: boundary` even though no tier ever has and the grammar
  record above no longer sanctions one. That gap is real but narrow
  (nothing in `bundles/**` declares it, so no bundle content silently
  breaks); closing it is one line in each of two places, and belongs
  in the same change that builds the queue grammar's loader support
  rather than a doc-only pass touching code outside its lane.

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
  (`docs/dsl-syntax.md` §11). **Not built as part of this pass**, same
  as the third: the dispatcher, the sweep, the scan/setup/retro
  machinery — ORC-104's, unaffected in shape by this pass beyond what
  it inherits from the grammar being one file format instead of three.

  **`queue`'s rename to `pending` in `Catapult.Dsl.SystemStatus`
  (`lib/catapult/dsl/system_status.ex`) is dev's diff, not design's**,
  the identical boundary the `:boundary` retirement above draws: the
  constant module is core_dsl's own mapped path. Filed against
  ORC-104 alongside it — the module still names the fixed-vocabulary
  member `:queue` today, which is harmless until a bundle's own
  container queue and a ticket's own system status need to coexist in
  loader error messages or generated UI copy, at which point the two
  senses collide in exactly the way the doc rename exists to prevent.

- **A fifth ORC-105 pass corrected two errors the fourth pass's own
  three-valued `skeleton:` field had baked in, and added one field**
  (design pass; `docs/dsl-syntax.md` §15.1-§15.9; `docs/v5-design-
  decisions.md` §7.8). `skeleton:` is optional rather than
  `ticket | container | none` — a type declaring neither has no
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

- **ORC-115 (design pass) narrows `throwback:` from mechanism to
  escape hatch, and gives a `statuses:` array a grouping construct the
  fourth ORC-105 pass's unification didn't have** (`docs/dsl-syntax
  .md` §15.10, §13; `docs/v5-design-decisions.md` §7.8, §7.16, §7.19).
  A `statuses:` entry may now be a bare, unnamed sub-array holding a
  contiguous run of the entries already legal elsewhere in the array
  (`status:`/`review:`/`environment:`, unchanged); the loader gains
  three checks with no exact precedent in the closed sets §13 already
  validates — a sub-array nested inside a sub-array is a load error
  (this pass's own grammar is flat, deliberately, see below); a
  sub-array must hold exactly one entry whose `status:` is a
  non-critique agent-balled system status (`generation`, `retro`,
  `setup`, `merge` — §15.1's own `ball` column, `critique` excluded for
  the reason §15.5 already excludes it from standing alone), zero or
  two-or-more being a load error naming the count found; and a
  queue-shaped anchor (`flow:`/`blocks:`) may not sit inside one. A
  `review:` entry with no declared `throwback:` of its own now
  defaults to its citing sub-array's one non-critique entry rather than
  being an outstanding declaration gap — computed at throwback time
  from the loaded bundle, never stored, the same posture `ready_scopes`
  and staleness already take. `throwback:` itself is unchanged in
  shape, reach and runtime semantics: the same bounded allow-list of
  legal decline exits the command edge already enforces
  (`Catapult.Engine.Aggregate`'s `DeclineGate` clause, ORC-34;
  `systems/dashboard.md`'s own ORC-75 entry), not a single value the
  derivation's default is swapped out for.

  **What this retires in role, not in size:** before this pass, an
  *undeclared* `throwback:` (`[]`, §15.4's own default) left a gate
  with zero legal exits — an unreachable gate, not a feature — so
  every declared gate in `bundles/default-flow/gates/**` names one
  today out of necessity, not preference. After this pass, an author
  may omit `throwback:` wherever the derivation already picks the sole
  node they want, and the field remains exactly as before for every
  other case: naming a target *outside* the citing sub-array
  (`ux-review`'s own `throwback: [pending]`, reaching past its
  sub-array to `pending`, which the derivation — confined to the citing
  sub-array — was never going to reach), or naming more than one legal
  exit alongside whatever the derivation would pick
  (`engineering-review`'s own `throwback: [generation, ux-review]`:
  `generation` is the derived default, `ux-review` is a second exit the
  single-valued derivation could not itself offer). Neither is a
  counterexample this pass overlooked; both are the field's existing
  multi-target shape doing what it always did. §15.1's fixed vocabulary
  loses none of its three jobs (gates/environments/critique position
  against it, chain tiers bind to it, cutover re-resolution anchors on
  it) — only the middle job's throwback-target role, which this
  section's derivation now shares with it rather than depending on it
  exclusively for the empty-list case.

  **Not decided by this pass, named rather than glossed over:** nested
  sub-arrays (a homonym risk against `container`-skeleton nesting,
  §15.6, this pass's own open question); a queue-shaped anchor inside a
  sub-array, which is what folding `setup`/`retro` into `milestone`'s
  own array would actually require — refused at load for now because
  it reaches a dispatch question (`systems/delivery.md`'s own open
  item) this pass does not touch; and a throwback from a gate sitting
  outside every sub-array, targeting into one. **Not built as part of
  this pass**, the same boundary every ORC-105 pass above already
  draws: the loader changes this entry describes are `lib/catapult/dsl
  /workflow.ex`'s (today's `gate_throwback_problems/2` computes
  "earlier in the flat array," which this pass's derivation replaces
  for the default case) — dev's diff against this record, not design's.

## Initial vs target

Initial (Phase 3): core vocabulary, loader, design-dialect extension
set (delivery annotations arrive with delivery). Target: full
extension registry with delivery + runtime dialects registered;
bundle-diff support for the registry's handle machinery.

## Depends on

substrate. Content it loads lives in platform_content.
