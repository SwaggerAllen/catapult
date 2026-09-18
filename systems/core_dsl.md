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
files → validated union, single directory per bundle — no `extends:`
layering, `bundle.md` #7), and the **extension registry** (v5 §9)
through which platform extensions add annotation namespaces,
declaration kinds, generator types, context-source kinds, and audit
profiles.

## #1 Standing decisions

- **#2 The core is frozen; growth happens in extensions** (v5 §9).
  A change to core vocabulary is a platform-versioned event with a
  migration story; an extension is an entry. When in doubt, it's an
  extension.
- **#3 No bundle-side code, ever.** Bundles declare instances against
  installed-extension vocabulary; the predicate language stays
  non-Turing-complete (v5 §6). This is a correctness property the
  scheduler and audit lean on, not a style choice.
- **#4 All validation at load time where possible**: type-level
  acyclicity (libgraph), cross-references, cardinality shapes,
  extension schemas. A bundle that loads is a bundle the engine can
  run; instance-level checks (dependency cycles) run at projection
  time.
- **#5 Destructive bundle change over a populated graph is a cutover,
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
- **#6 Grammar machinery lives here** (validators derived from bundle
  declarations); engine and generation call it. One validator source
  because commit-time rejection (engine) and pre-flight validation
  (generation, CLI later) must agree byte-for-byte.
- **#7 `catapult.yaml` is the loader's, not the bundle's** (`bundle.md`
  #2). It names one bundle per axis and nothing else — it is what the
  loader reads to find `bundles/` in the first place, not content the
  loader validates against a bundle schema. That makes it this system's
  file, same as any other loader input, and distinct from `bundles/**`'s
  content, which `platform_content` owns.
- **#8 Four core-grammar growth events landed directly, not through the
  extension registry** (ORC-84): a fourth scope kind, `cascade_visit`
  (`chain.md` #6 — one node per node a flow's own cascade walk visits, for a
  planning tier, engine-minted rather than fanout-minted); a context walk's
  hop chain lengthened from exactly one to any number, plus a `~` suffix
  reversing a hop (`chain.md` #19 — walker matches the edge's `target`
  instead of its `source`); a new context-walk source,
  `all.<tier>.<projection>` (#19 — every declared instance of a tier, no
  edge); and edges gaining an `instances:` list, several source/target
  sites sharing one name and mechanism (`chain.md` #27).
- **#9 A fifth core-grammar growth event, same daylight, same ticket**
  (ORC-84, author decision revising `docs/v5-design-decisions.md` §7.19): a
  tier declaration gains `reviews: <tier>` (retired by #45), marking it a
  review tier for the named tier rather than a generation tier of its own.
  Unlike the four above, this isn't a new scope kind, edge form, or
  context-walk source — it's a new relation *between two tier declarations*:
  `reviews:` fixes the declaring tier's scope and cardinality to the named
  tier's, 1:1, without restating `scope:`, and it obligates a load-time check
  with no precedent in the closed sets the load rules already validate — that the
  review tier's own `context:` names the same set of walks as the reviewed
  tier's `context:`.
- **#10 Depth's grammar generalizes to a pair, and a new declarable form
  configures `critique`'s participation** (ORC-92; `workflow.md` #26, #33;
  `docs/v5-design-decisions.md` §7.19 — both grammar sections' own shape
  changed again at ORC-105, below, without disturbing this decision). Two
  changes land together: `depth:`'s shape check widens from "non-negative
  integer" to "non-negative integer, or a list of exactly two" —
  `Catapult.Dsl.Gate.parse_depth/2` and `Catapult.Dsl.Environment`'s own copy
  both need the second clause, and the load rules gain a shape check validating
  all three depth sites the same way — and the loader gains a new, singular,
  non-globbed declaration kind: `critique.yaml` at a workflow bundle's root,
  structural-parsing-only in the same shape `Gate` and `Environment` already
  use (unknown keys rejected, `depth:` defaulting to `0`), with no other
  fields — no `after:`, no `role:`, nothing that would make it look like a
  review-status declaration, because it configures a fixed kind rather than
  declaring one (`workflow.md` #10's line stays exactly as strict).
- **#11 Not built: a named-pass selector for the `[first, rest]` pair.**
  `first`/`rest` are positional, never a name a bundle chooses (`scaffold`,
  `refactor_flow`) — a chain has no vocabulary for its own flows on the
  workflow axis to begin with (v5 §7.18), and inventing one here to save a
  pair's two positions a name would be the identical cross-axis leak the axis
  split already forbids everywhere else.
- **#12 `Chain.t()` carries its resolved `predicates.yaml` map forward**
  (ORC-8, named here because the reactive scheduler is the first
  runtime consumer). `Chain.build/3` already resolves and validates
  every named predicate a bundle's four slots (`scope_filter`,
  `cardinality.when`, an edge `constraint`, a flow `completion`,
  `chain.md` #37) reference — then discards the map once load-time
  validation passes. Nothing downstream can evaluate a `scope_filter`
  reference against live graph state without it; re-parsing
  `predicates.yaml` independently would double-implement this system's
  own load path and risk drifting from what the loader actually
  validated. The fix is a field, not a second reader: `Chain.t()` gains
  `predicates: %{String.t() => Predicate.t()}`, populated from the
  value `build/3` already computes. `systems/engine.md` records the
  runtime-evaluator decision this field exists to serve.
- **#13 A project's queue sequence and a container's are two declaration
  shapes, not one shape parameterized by kind, and work-item types are now a
  registry** (ORC-105; `docs/v5-design-decisions.md` §7.8).

- **#14 A fourth ORC-105 pass unified `queues/project.yaml`, `queues/
  containers/<name>.yaml` and `types/<name>.yaml` into one declaration shape,
  retired `after:`, and moved `critique.yaml`/`gates/`/ `environments/`
  positioning inline** (supersedes the three-file-shape entry above;
  `workflow.md` #4, #5, #32; `docs/v5-design-decisions.md` §7.8, §7.18,
  §7.19). Every declaration is `types/<name>.yaml`: `type:` names it,
  `skeleton:` picks `ticket`, `container` or `none` (`workflow.md` #12 and
  #16's per-skeleton fixed backbones), and `statuses:` is one ordered array holding both the
  skeleton's own anchors and whatever gates (`review:`), environments
  (`environment:`) or `critique` entries the author interleaves among them —
  position is the array index, full stop; no declaration in this grammar
  carries an `after:` field, on a gate or an environment either.
  `gates/<gate>.yaml` and `environments/<env>.yaml` still exist as named,
  reusable declarations (role, throwback, escalation, depth; promotion,
  lifetime) — what moved out of them is only position, since a citing type's
  own array now says where each one runs, and two types may run the same gate
  in different relative order without either being wrong. `critique.yaml` is
  retired outright (superseding ORC-92's form, `docs/v5-design-decisions.md`
  §7.19): a `critique` entry must sit immediately after a `generation` entry
  in the same array, which is also the load-time reason a `container`- or
  `none`-skeleton type can never declare one — it has no `generation` anchor
  to pair with. The loader gains three checks with no exact precedent in the
  closed sets the load rules already validate: a `statuses:` entry must carry exactly
  one of `status:`/`review:`/`environment:`; `flow:`/`blocks:` are legal only
  on a queue-shaped `status:` entry (a container's five anchors, or any entry
  in a `none`-skeleton type); and a `ticket`-skeleton type's array must
  contain `pending` (first), `generation`/`checks`/`merge`/`deploy` (each at
  least once, in that relative order, `generation`/`merge` may recur) and
  `terminal` (last). **`extends:` is chain-axis only:** a workflow bundle
  carries no `extends:` field at all, since v5 §3.1's fork-tailor-merge
  lifecycle — already the model for bundles and policy packs generally — is
  the one a workflow bundle was always shaped for, not a runtime-composed
  layer (`bundle.md` #7).

- **#15 A fifth ORC-105 pass corrected two errors the fourth pass's own
  three-valued `skeleton:` field had baked in, and added one field**
  (`workflow.md` #4, #30; `docs/v5-design-decisions.md` §7.8).
  `skeleton:` is optional rather than `ticket | container | none` — a
  type declaring neither has no anchors at all, and there is no "at
  most one loaded `skeleton: none` declaration" check: rootness is a
  node nothing else's `flow:` targets, derived from the declaration
  graph the loader already builds, never a value a second check has to
  police. **The declaration-graph acyclicity check's node set is any
  type with a queue-shaped anchor** — `container`-skeleton or
  skeleton-less alike — and a `flow:` naming a skeleton-less type is
  legal. Admitting only `container`-skeleton types as nodes excludes
  every `flow:` edge *into* a skeleton-less type by construction and
  leaves a real cycle undetected (`milestone.main` naming `flow:
  project` alongside `project.build-out` naming `flow: milestone`).
  **Gates and environments are legal on skeleton-less types too** —
  that a project needs no re-resolution anchor is an argument about
  anchors, not about what its array may contain, and the governing
  rule never claimed otherwise. **New: `singleton: true` on a
  queue-shaped anchor entry**, bounding a queue to at most one work
  item over its lifetime for plane code to address directly
  (`milestone`'s `setup` and `retro` are the motivating declarations)
  — not a load-time check (assignment history is live state), and the
  loader's job stops at accepting the field; a second assignment to a
  singleton queue is dispatch behavior, not a grammar concern, and
  what that bound means is the entry below's — a lifetime bound and a
  "files `Blocked`" response disagree with each other. The dispatcher,
  the sweep, the scan/setup/retro machinery, and the singleton-queue
  rejection check are ORC-104's.

- **#16 A sixth ORC-105 pass named the plane's entry point explicitly and
  corrected `singleton:`'s own semantics, both gaps the fifth pass's own
  record left open** (`workflow.md` #2, #30; `docs/v5-design-decisions.md`
  §7.8). Derived rootness answers "is this type a root," never "which root
  does the plane dispatch a fresh project from" — a bundle declaring `epic`
  without nesting it under anything else already has two roots, so "the
  project is a project by convention" names nothing the loader can check.
  `entry:`, a required key on a workflow bundle's own `bundle.yaml`, names
  that type instead, checked at load the same way `role_holders:` and
  `mirror_mapping:` are checked when supplied: the name resolves, the
  resolved type carries a queue-shaped anchor, and it is a root in the
  declaration graph.

- **#17 ORC-115 (design pass, corrected on two later design reviews)
  narrows `throwback:` to a single-target escape hatch and gives a
  `statuses:` array a grouping construct the fourth ORC-105 pass's
  unification didn't have** (`workflow.md` #6, #34;
  `docs/v5-design-decisions.md` §7.8, §7.16, §7.19). A `statuses:`
  entry may be a bare, unnamed sub-array holding a contiguous run of
  the entries already legal elsewhere in the array
  (`status:`/`review:`/`environment:`, unchanged); the loader gains
  three checks with no exact precedent in the closed sets the load rules
  already validate — a sub-array nested inside a sub-array is a load error
  (the grammar is flat, deliberately, see below); a sub-array must
  hold exactly one entry whose `status:` is a non-review-shaped
  agent-balled system status (`generation`, `design`, `architecture`,
  `implementation`, `retro` or `setup` — `workflow.md` #10's
  agent-balled shapes minus `critique` and `reconcile`, both
  review-shaped and excluded for the reason #26 already excludes
  `critique` from standing alone; `merge` is not a candidate either, its own `ball` having
  moved from `agent` to `plane`, ORC-151), zero or two-or-more being
  a load error naming the count found; and a queue-shaped anchor
  (`flow:`/`blocks:`) may not sit inside one. A `review:` entry's
  decline defaults to its citing sub-array's own earliest entry — its
  own leading `pending`, when the sub-array has one (every
  generation-shaped sub-array does), its own
  non-review-shaped entry directly otherwise — computed at throwback
  time from the loaded bundle, never stored, the same posture
  `ready_scopes` and staleness already take. A gate sitting first in
  its own sub-array, or in no sub-array at all, has no earlier entry
  there to fall back to, so this derivation gives it no default and
  it must declare `throwback:` explicitly (ORC-181; superseded by
  #45's sixth change, which lets an ungrouped gate have no throwback
  at all).
- **#18 A decline's legal targets are never narrower than
  `docs/v5-design-decisions.md` §7.19's own Blocked-return rule — any earlier
  status in the ticket's effective sequence — and no bundle-declared list
  bounds them.**
- **#19 `throwback:` narrows to a single optional status rather than
  retiring.** Unbounded legality removes only one of `throwback:`'s two jobs.
  It bounded legality, and that job is gone. It also named a decline's
  *landing point* — the one-click action a bare decline takes — and that job
  is untouched: the sub-array's own earliest entry — its own leading
  `pending` for a generation-shaped group — is the derived default, and
  `throwback:` is what a gate declares instead, for the gate that wants a
  different one.

- **#20 ORC-148 (design pass) reverses the fourth pass's own governing
  sentence — a skeleton fixes a required backbone, never an exclusive
  membership — and retires `singleton:` outright** (`workflow.md` #12,
  #16; `docs/v5-design-decisions.md` §7.8; `systems/delivery.md`). "A
  container is any work item whose skeleton has queues, a ticket is
  any work item whose skeleton has a generation" (`workflow.md` #4's
  own sentence) is not an *exclusive* membership rule, and the loader read
  it as one: `Catapult.Dsl.Workflow .container_shape_problems/2`
  required a `container`-skeleton type's array to hold *exactly* its
  five fixed anchors, nothing else, and `Status.parse/4`'s
  `queue_shaped?` — whether `flow:`/`blocks:` (and, until it retired,
  `singleton:`) are legal on a given entry — was computed once per
  type from `skeleton:` alone. Nothing in this section's own prose
  ever argued for that exclusivity; it was the three-file format's
  residue, the same kind of accidental coupling the one-file
  unification above removes from everywhere else. **The check keys on
  the entry's own name and content, not on the type's `skeleton:`:**
  `flow:`/`blocks:` are legal on a *population anchor*
  (`prep`/`main`/`cleanup`, or any entry in a skeleton-less type's
  array) and illegal on the fixed agent/world kinds (`pending`,
  `generation`, `critique`, `checks`, `merge`, `deploy`, `setup`,
  `retro`, `terminal`), whichever type's array either sits in; the
  declaration-graph node set and `entry:`'s own check both key on
  "does this type's array hold a population anchor at all" rather than
  on "is this type's `skeleton:` `container` or absent." A
  `container`-skeleton type's required backbone (its five anchors,
  each at least once, in order) and a `ticket`-skeleton type's are
  exactly as fixed as before; what they do not do is cap what else a
  declaring bundle may additionally interleave from the shared
  vocabulary. **This is what lets `setup` and `retro` fold inline:**
  each is an ordinary agent-balled entry directly in `milestone`'s own
  array — `retro` grouped with the sign-off gates around it in a
  sub-array (`workflow.md` #6, the shape ORC-115 named and left unreachable,
  above), `setup` needing no group at all — dispatched by
  `milestone`'s own chain-bundle tiers exactly as a `generation` entry
  dispatches by a ticket-skeleton type's, with no `flow:` and no
  separately minted child. `types/setup.yaml` and `types/retro.yaml`
  are deleted rather than kept as dispatch targets (`bundles/**`).
  **`singleton: true` retires rather than narrows**, because the
  cardinality it bounded stops existing: it closed a *queue* to a
  second assignment once populated, and `setup`/`retro` stop being
  queues the moment they have no `flow:` to nest a child through —
  there is exactly one `milestone` instance and exactly one array
  position each occupies, which is the "at most one, ever" property
  with nothing left for a field to declare. **A container instance is
  an agent dispatch target** — the question ORC-115 left open, settled
  the same direction as the rest of this reversal: dispatching from a
  work item with a queue and one without were never different
  operations, only different status flows attached to the identical
  mechanism (`docs/v5-design-decisions.md` §7.8,
  `systems/delivery.md`). The loader carries it across
  `lib/catapult/dsl/status.ex`, `type.ex` and `workflow.ex`;
  `bundles/default-flow/**` is the folded result; and the
  dispatcher/executor half is `systems/delivery.md`'s, against its own
  Target list.

- **#21 ORC-151 (design pass) splits the fixed vocabulary's `merge` kind
  in two, naming the review it always implied** (`workflow.md` #10,
  #13; `docs/v5-design-decisions.md` §7.5, §7.19). `merge` carried two
  jobs at once — reading a produced PR against its own argument, and
  mechanically joining it into the parent branch — and
  `Catapult.Dsl.SystemStatus.agent_steps/0` has carried `:reconcile`
  since Phase 3 with no matching `phase:` to declare it against.
  `reconcile` joins the fixed table as the second **review-shaped**
  kind alongside `critique` (the parallel category to
  "generation-shaped"), agent-balled and required — stated
  positionally, not per skeleton — wherever a `merge` entry appears: a
  `merge` entry must be preceded, earlier in the same array, by a
  `reconcile` entry, `container`-skeleton arrays included (a
  skeleton-keyed statement leaves a gap: the retired spec's
  `milestone.yaml` example ran `setup` and `retro` each through a bare
  `checks → merge → deploy`, merging unread), never opt-in the way
  `critique` is, since no ticket merges without having been read
  against its own argument first. `reconcile` may also recur, the way
  a generation-shaped entry and `merge` already could — the retired
  spec's own worked example carries two, one closing the architecture
  phase's own join and one closing implementation. `merge`'s own
  `ball` changes from `agent` to `plane`: mechanical, effected by the
  plane once `reconcile` approves, barring a conflict (which routes to
  `Blocked` the ordinary way). This is also what lets
  `Catapult.Delivery .ContainerLifecycle.inline_dispatch_point?/1`
  stop excluding `merge` by name — a name check inside a module whose
  own moduledoc asserts it branches on no status name: the predicate
  is "agent-balled and not review-shaped," which excludes `merge`
  because it is no longer agent-balled, needing no name check. The
  sub-array anchor rule (`workflow.md` #6) generalizes the identical way:
  "non-critique agent-balled" becomes "non-review-shaped
  agent-balled," admitting any number of `reconcile` entries alongside
  `critique` ones without counting toward the sub-array's required-one
  anchor. **Gate scope is derived from position relative to the
  nearest `reconcile` before it** — a gate earlier than every
  `reconcile` in a type's own array approves the citing tier's own
  artifact; one sitting after a `reconcile` approves what that
  `reconcile` has already joined and, per the entry below, already
  **merged** in from every child beneath it, superseded again by a
  later `reconcile` if one follows — closing a gap
  `v5-design-decisions.md` §7.16 left open (what a gate scoped to a
  join, rather than to one generation's own sub-array, approves), with
  no new field: computed from array position, the identical "derive,
  don't declare" posture `throwback:`'s own default already takes.
  **No `docs/non-goals.md` entry**: growing this closed table is
  covered by that file's existing admission rule without amendment,
  the same non-entry `design`/`architecture` got at ORC-148. The
  loader carries it in `lib/catapult/dsl/system_status .ex`'s
  `@statuses` table and `generation_shaped?/1`'s sibling,
  `status.ex`'s `non_critique_agent_step?/1` rename and
  generalization, and `workflow.ex`'s backbone and sub-array checks
  widening to include `reconcile` and the merge-preceded-by-reconcile
  positional check; `bundles/**` declares it; the dispatcher change is
  `systems/delivery.md`'s, against its own Target list.

- **#22 A third design review on this same ticket retires `fanout` from the
  fixed table, moves architecture's own fan-out onto the ticket tree, and
  makes `merge` implicit outside the root** (`workflow.md` #10, #28;
  `docs/v5-design-decisions.md` §7.10, §7.15, §7.19). Three changes:
  **`fanout` retires**, its only remaining job (marking a feature's own wait
  before its implementation-phase `reconcile`) a dispatch precondition rather
  than a status of its own — the edge type of the identical name
  (`Catapult.Dsl.Edge`'s `@types`, node-id minting) is untouched.
  **Architecture's own fan-out — sysarch, each comparch, each subcomparch —
  dispatches through its own ticket instance of the one declared type,
  spawned when the plan names it** (the existing child-spawn rule,
  `v5-design-decisions.md` §7.10, applied recursively) **rather than as
  `depth:`-filtered scope-runs inside one ticket**, which could never give a
  subcomparch `critique` its own bounce (a ticket has one status at a time,
  so one ticket's one `critique` visit throws the whole tree back).
  `reconcile` carries no `depth:`: whether an instance runs its own join is a
  fact about that instance's own children, never a declared ceiling.
  **`merge` is depth-0 by rule and fires only at the root** — every
  `ticket`-skeleton type still declares exactly one, reconcile-preceded,
  load-checked unchanged; a non-root instance's own copy of that declaration
  never reaches it by its own dispatch, and instead merges when its parent
  enters `reconcile` (`v5-design-decisions.md` §7.2's child-blocks-parent,
  read as a precondition on entry and, symmetrically, as the merge trigger).

- **#23 A fourth design review on ORC-151 fixes five worked-example defects
  the third pass's own draft left standing, and settles two questions it left
  open** (`docs/v5-design-decisions.md` §7.6, §7.10, §7.19).
  **`implementation` joins the fixed table as a third named generation kind**
  — a tier's code cannot dispatch through a bare second `checks`, because
  `checks` is world-balled CI against produced work, never a generation run;
  deliberately gateless in the shipped default (the touchpoint budget
  calibrates two author gates, `v5-design-decisions.md` §7.10, and a third
  keyed to implementation is that entry's own named exception, not the
  ordinary case). **`pending` recurs, once per generation-shaped entry's own
  sub-array**, tightening "somewhere earlier in the array" — with `fanout`
  retired, `pending` is the only plane-balled wait position left, and a
  shared leading `pending` licensing several sub-arrays at once leaves later
  ones with nowhere to queue; throwback's own derived default (`workflow.md`
  #34) falls
  back to a generation-shaped sub-array's own leading `pending` rather than
  straight to its agent step, matching the repair-loop mapping (`Ready for
  rework`/`Reworking`) rather than skipping the queued wait. **A declared
  gate may be cited twice within one type's own array**, the analogue of
  `critique`'s existing citing-it-more-than-once precedent, extended from a
  system status to a named declaration — `architecture-review`, cited once
  before a `reconcile` and once after, is the exercised case. **Two type
  declarations, not one array depth-filtered**: the feature ticket itself
  cannot be "one declared type… once per node" at its own depth 0, because
  `design` has no `depth:` field to make it no-op below the root the way a
  gate or `critique` can — so the feature's own type and the type
  architecture's recursive fan-out spawns are two separate declarations; this
  is `v5-design-decisions.md` §7.6's "Child" lifecycle, not that document's
  own feature lifecycle depth-filtered. Two comment/naming rules with no
  structural consequence: children merge at their *parent's* `reconcile`,
  never at their *own* dispatch of `merge`, and the worked example's `merge`
  comment says so; and the gate is `architecture-review`, not
  `comparch-review`, since naming a gate for the tier it reviews is the
  implicit-anchor-meaning defect #11 exists to keep out, and its own two
  positions already derive their different scopes from where they sit, not
  from a second name.

- **#24 A sixth design review on ORC-151 closes one gap the fifth pass's
  own fix left open** (`workflow.md` #26;
  `docs/v5-design-decisions.md` §7.19). `critique`'s load-time
  adjacency rule — "immediately after a generation-shaped entry, or
  immediately after that entry's own `checks`, never before it" — is
  stated at five sites, and all five carry the identical `checks`
  caveat: the retired spec's load checklist, its own rule statement,
  the container/ticket-skeleton interleaving passage, the
  `skeleton:`-decoupling section's own "critique's admission" bullet,
  and the project-level widening passage. A worked example reordered to the amended rule is,
  read against any one of those sites without the caveat, a load
  error. The rule belongs in the rule statement itself, not in a
  second worked-example paragraph beside it claiming the rule above
  already says it (`workflow.md` #26 states it once). A rule with three or more statements in this
  document (critique adjacency, `pending` precedence, the
  depth-bearing sites, the generation-shaped kind list) is edited at
  every statement in the same pass that changes any one of them, not
  just the site a review happens to quote: six consecutive rounds on
  ORC-151 each corrected one statement and left a sibling statement
  stale — `merge`, the reconcile count, `checks`'s position, the
  child lifecycle, `pending`, and `critique`'s own adjacency rule
  against itself. The loader's widened critique-adjacency check is
  the entry below's.

- **#25 A fifth design review on ORC-151 fixes three defects the fourth
  pass's own worked examples and lifecycle mapping left standing**
  (`workflow.md` #26, #28; `docs/v5-design-decisions.md` §7.19).
  **`checks` sits between a generation-shaped entry and the
  `critique` that reviews it**, not after it, and never behind the
  human gate. `critique`'s own load-time adjacency rule (`workflow.md` #26)
  admits an intervening `checks` ("immediately after a
  generation-shaped entry, or immediately after that entry's own
  `checks`, never before it"), and both worked examples
  (`types/feature.yaml`, `types/component.yaml`) carry that order —
  one `checks` per generation-shaped sub-array, always ahead of its
  `critique`. **The retired spec's own lifecycle mapping carries three `Todo`s
  and three `Checks`, matching `feature.yaml`'s three
  generation-shaped sub-arrays** — a single occurrence of each is the
  `pending`-once-per-sub-array rule violated, stated as a
  tracker lifecycle rather than a load error. The mapping and the
  worked example describe one type and are edited together: five
  consecutive corrections had fixed one and left the other
  disagreeing (`merge`, the reconcile count, `checks`'s position, the
  child lifecycle, `pending`). **A `reconcile` entry is declared once
  for the type, unconditionally, like every other entry** — what
  varies per instance is whether its own *effective sequence* selects
  anything from it, exactly the "derive, don't declare" framing this
  same section already gives `depth:` itself; nothing removes the
  entry from a per-instance copy of the array, so the worked-example
  comments describe it the way `depth:`'s own filtering is described,
  never as "present iff this instance has children." The loader's
  widened critique-adjacency check rides the entries above's loader
  work.

- **#26 ORC-155 (design pass) gives a `status:` entry a bundle-authored
  `name:` distinct from its kind, and namespaces a position by the
  sub-array it sits in** (`workflow.md` #7, #8;
  `docs/v5-design-decisions.md` §7.19). Without it a recurring kind —
  a `critique` and a `checks` once per group — is addressable only by
  kind, which a card, a rail entry, a
  `throwback:` or a `blocks:` reference all need to name
  unambiguously and cannot: `CatapultWeb.Live.Positions.key/1`
  round-trips exactly the `{:kind, atom} | {:gate, name}` pair the
  projection stores, with no way to say *which* `pending`. `name:`
  answers it without growing the closed kind table (`workflow.md` #10) a
  fourth time for a need no chain lifecycle actually has (the identical
  reasoning #30 already gives for `design`/`architecture`/`implementation` not
  needing a fifth or sixth member): a position's identity is
  `<anchor>.<name>`, the sub-array's own one non-review-shaped
  agent-balled entry supplying the anchor (`workflow.md` #6, #7), bare at the top
  level, one level of qualification only. **This retires the "same
  declared gate cited twice" pattern (`workflow.md` #32, above)**: two citations
  landing in the same sub-array collide under the
  uniqueness-within-a-namespace check, and a citation told apart from
  its sibling only by which side of a `reconcile` it falls on is
  exactly the second qualification level the grammar refuses.
  `architecture-review`, cited twice in `feature.yaml` and again in
  `component.yaml`, is the exercised case; the citation
  scoped to what `reconcile` has joined is a gate of its own,
  `architecture-synthesis-review`, in both worked examples — the two
  already reviewed different things and say so by name, rather than
  by which side of a join they happen to sit on. **Also: a load-time
  check that no declared gate name collides with any addressable
  status name** — safe by construction while status names were
  platform-fixed kinds, not once a bundle can author one. The loader
  carries it in `lib/catapult/dsl/status.ex`'s known-key list and its
  `depth:` gate, keyed on kind rather than on the parsed name string
  now that the two can differ, and `workflow.ex`'s
  namespace/uniqueness and gate-disjointness checks;
  `system_status.ex` is unaffected, since every predicate it exports
  already reads kind. The projection column
  (`Catapult.Delivery.Store.tickets_for_project/1` gains a name column
  beside `status_kind`) and `CatapultWeb.Live.Positions`' own
  round-trip encoding, extended to carry the qualifying anchor, are
  the consumers.

- **#27 A design review on ORC-148 corrected two things the pass above got
  wrong and settled one it had left implicit** (`workflow.md` #8, #18;
  `docs/v5-design-decisions.md` §7.8). `milestone.yaml`'s `main
  blocks: [retro]` beside a `retro` folded inline with no `flow:`
  cannot load under a `blocks:` check that requires its target to be a
  population anchor, which an inline `retro` is not. **`blocks:` is an
  entry guard, checked once at the transition it guards, never a
  standing hold a projection recomputes** — `Q1 blocks: [Q2]` means
  `Q2` cannot be *entered* while `Q1` still carries unresolved work,
  checked exactly once, not continuously for as long as `Q2` runs. A
  standing-hold reading carries a real defect: a queue refilling while
  the guarded entry was already mid-run pulls the container back out
  of it, and `retro`'s own output landing back in `main` would make a
  completion-hold `blocks:` interrupt `retro` with its own result.
  **Reaching `terminal` has an unconditional, undeclarable guard** —
  every one of a container's own queues holding no unresolved work —
  separate from whatever `blocks:` a bundle authors, so a queue nobody
  thought to name in some other entry's `blocks:` list cannot be
  quietly closed over on the way to `terminal`; this system's
  dispatcher enforces it, the loader checks nothing new.
  **`generation`'s closed vocabulary carries two further named kinds,
  `design` and `architecture`**, both generation-shaped everywhere
  `generation` itself is checked (backbone membership,
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
  entry it lands on. `lib/catapult/dsl/status.ex`, `workflow.ex` and
  `system_status.ex` carry it: the `blocks:` check, the
  `design`/`architecture` kinds in `SystemStatus`'s own union, and the
  dispatcher reading a transition-time check rather than a
  standing-hold projection.

- **#28 ORC-198 (design pass) splits `Type.namespaced_positions/1`'s one
  ambiguity computation into two, because ORC-155's own `name:` is exactly
  what makes them able to disagree** (`workflow.md` #7, #8).

  The two sets are not one a subset of the other, so neither is safe
  to derive from the other: `status: pending` in one sub-array beside
  `status: checks, name: pending` in another recur on bare with
  **distinct** kinds — a real reference ambiguity (`blocks: [pending]`
  cannot pick one), no runtime collision at all, since the two resolve
  to different `position()` shapes. The two namespaces are what makes
  that bundle legal to write at all: `workflow.md` #7's uniqueness check
  ("Names are unique within their own namespace — the top-level array,
  and each sub-array") refuses the same pair sharing one namespace at
  load, so the case worth modelling here is only ever the one that
  spans two. Two distinct-`name:` `status: pending` entries
  are the opposite — no reference ambiguity, each name resolves to
  exactly one entry — but a real runtime collision. `bare`/`qualified`/
  `canonical` keep meaning exactly what ORC-155 gave them, unchanged,
  since `resolve_reference/2` and `earlier_names/2` are correctly keyed
  on bare already. `namespaced_entry()` gains a second, independent
  field, `kind_ambiguous: boolean()` — true when this entry's own kind
  (`status:`/`review:`/`environment:` value, never `name:`) recurs
  elsewhere in the type's own array — for the runtime-collision
  question alone. `Catapult.Dsl.Type` carries the field, and every
  runtime-facing consumer reads it in place of the reused
  `canonical == bare` test — `systems/delivery.md`'s own ORC-198 entry
  names the three call sites.

- **#29 `extends:` retires from the DSL entirely — a chain bundle becomes
  a single directory of authored content, forked and tailored the way
  a workflow bundle has been since ORC-105's fourth pass** (ORC-153;
  `docs/v5-design-decisions.md` §5.5, §6, §7.18;
  `bundle.md` #5, #7). `Catapult.Dsl.Manifest` drops `extends:` — an
  unknown key, rejected at load on either bundle kind, the same as a
  workflow bundle's manifest already rejects it. `Catapult.Dsl
  .Extends` (`chain/3`, cycle detection, the cross-axis kind check,
  base-first ordering, `resolve_files/2`, `fragment_vocabulary/1`,
  `load_layers/2`) goes with it; `Catapult.Dsl.Grammar` and
  `Catapult.Generation.ContextAssembly`, which resolved schema and
  prompt paths through `load_layers/2`, become single-directory
  lookups instead, and `Catapult.Dsl.Chain`'s own internal layering
  goes with the module that supplied it. **The bundle-relative
  content-path traversal guard is not layering and does not go with
  it**: whatever replaces `resolve_content_path/2` in the
  single-directory lookup still expands both sides of a
  `prompt:`/`grammar:` path and refuses any candidate escaping its own
  bundle — the guard exists because that path is bundle-authored
  content, a fact independent of whether a second layer sits
  underneath to escape into.

- **#30 `design_system` settles as a new generator type, `supplied`,
  reusing neither `external` nor a `ref`** (ORC-110;
  `docs/v5-design-decisions.md` §5.4). §5.4's own phrasing — "an external or
  vendored node like any §3.2 external" — reads as behavior parity, not
  mechanism reuse, once weighed against what `external` actually is:
  registry-resolved content, `package:`- addressed, staleness a version bump
  the registry publishes (v5 §3.2, `chain.md` #39).

  The new type: `generator: supplied`, `source: input.<role>`. Content
  is the raft document(s) pinned under that role at intake, copied into
  the node's committed body directly — the same "extracted, not
  authored twice" shape `external` already uses for registry content
  (§3.2), just sourced from the project's own frozen raft instead. No
  `draft:`, no prompt, no review: there is nothing here an LLM authors
  or a human gates a second time, because the gate already happened at
  intake (v5 §1.1's freeze) — sharper than `journey`/`screen`'s reason
  for carrying no review tier of their own
  (`systems/platform_content.md`'s ORC-109 entry, a projection with
  nothing of its own for a review to read), since here there is no
  draft in the first place.
  `design_system` itself mints directly from the pinned raft artifact
  rather than by a fanout edge — no `child_of(X)` to declare, the same
  shape `ref` already has and for the same reason (`tiers/ref.yaml`'s
  own comment: nothing mints it and it mints nothing) — and mints
  **at most one**: a role with no pinned document mints no node at
  all, the same optionality every
  `input.<role>` carries (v5 §1.1: a role "never blocks readiness"),
  and the UI tiers derive primitives normally rather than failing
  closed.

  `design_system` joins `project_doc`, `mocks`, `non_goals` as platform
  input-tag vocabulary (`chain.md` #19) — a fourth role, admitted the
  same way the other three were, by a shipped tier reading it (ORC-107's
  admission rule) — but read through a `supplied` generator's `source:`
  field rather than a `context: input.<role>` walk: the role-tagging
  mechanism is shared across all four roles, the consumption path is
  not, because `design_system` has no prompt for `ContextAssembly` to
  render a variable into (unlike `mocks`, which does —
  `systems/platform_content.md`'s ORC-110 entry).
- **#31 This entry declares the `design_system` tier itself**, not only its
  node kind: `design_system`, `generator: supplied`, `source:
  input.design_system`, no scope parent (mints directly from the pinned raft
  artifact, the same shape `ref` has, per above) and mints at most one.
- **#32 The `ui_coll → design_system` dependency edge is `ui_coll`'s side
  of the relationship, not this entry's.** It belongs to whichever tier
  declares `ui_coll` and its dependency list, and nothing here depends on it:
  a `design_system` node mints and holds content whether or not anything
  declares a dependency on it.

- **#33 A `declared_in` path's element and attribute segments join the
  cross-references the loader already checks at load time**
  (ORC-232, `chain.md` #32, sharpening this system's own
  "cross-references" bullet above). The retired spec's enumeration of what
  "every cross-reference resolves" already covers — edge endpoints,
  fragment kinds, prompt/schema paths, predicate names — named no
  check of a `declared_in` path's own segments against the schema of
  the tier it reads, and six wrong segments sat undetected across nine
  occurrences in the shipped bundle as a result
  (`systems/platform_content.md`'s ORC-232 entry: every one matched
  nothing in a committed body, silently, because
  `Extraction.descend/2` resolves a segment by exact string equality
  with no normalization). The loader now resolves a `declared_in`
  path's leading segment to the tier it names, reads that tier's own
  `draft.grammar` schema, and walks the remaining segments against it
  the same way `Extraction.descend/2` walks them against a committed
  body — refusing to load when a segment names no element or attribute
  the schema declares under that exact spelling, naming the edge, the
  instance and the offending segment.
- **#34 The walk follows a `type="Name"` reference into a complexType
  declared in the same schema file exactly as it follows an inline content
  model — this bundle's ordinary shape, not an edge case.**
- **#35 Two failure modes, kept apart.** A segment the check can resolve —
  whether inline or by following a same-file `type=` reference — and finds
  wrong is the class above — a load error. A segment the check cannot resolve
  at all, because the schema reaches it through a construct the check does
  not model (`xs:group`, `xs:extension`, a type defined in a schema the
  tier's own file imports rather than declares), is not an error: the check's
  own coverage gap is not the bundle author's defect, so an unresolvable
  segment passes through unverified rather than blocking the load. Only a
  segment the check positively resolves and finds wrong is this defect's
  class.
- **#36 Attribute segments are checked identically to element segments, not
  carved out.** `Extraction.attribute/2` resolves a trailing `.@attr` segment
  by the same exact-string comparison `Extraction.descend/2` uses for an
  element segment, so a typo in either position fails identically at runtime;
  the check reads both off the same schema walk rather than modeling elements
  and leaving attributes unchecked.

- **#37 A third-party-declared edge instance locates its non-`self`
  endpoint one of five ways, and only one of the five needs bundle
  content to say so** (ORC-236; `chain.md` #27, #32).
  `Extraction`'s own moduledoc names the gap and declines to guess at
  it: an instance whose `source` (or `target`) differs from
  the tier committing the draft that declares it needs "per-edge-type
  knowledge of that instance element's own shape... that the generic
  navigator cannot safely infer." Tracing every third-party-declared
  instance in `bundles/default` — seven `reference`/`fulfills`
  instances (`comp → resp`, `screen_coll → screen`, `journey →
  screen`, `resp → journey`, `resp → screen` and `screen_coll →
  journey`, plus `navigation`'s own `screen → screen` instance,
  `type: reference`, `source: screen`, declared in `screens`'s draft —
  `screens` never commits under the name `screen`, the identical
  unnamed-source shape the other six have) and ten `dependency`-typed
  instances (the six same-tier peer instances below, `ui_coll →
  design_system`, and three more `type: dependency` edges declared
  outside `dependency.yaml` — `calls`, `renders`, `uses_shapes`, all
  sourced from `frontend_sysarch`'s own draft) — finds that knowledge
  is inferable structurally for every one of the seven
  `reference`-typed instances and for four of the ten
  `dependency`-typed ones, which is why the mechanism is five locator
  kinds, not one: `self` (the committing tier), `self.parent` (the
  committing node's own `per(X)`/`child_of(X)` parent — the same owner
  vocabulary `produces:` uses, so there is one rather than two;
  `screen_coll →
  journey`'s and `ui_coll → design_system`'s own instances),
  `fanout(<edge>)` (the node minted by another edge's fanout instance
  whose own `declared_in` prefixes this instance's — `comp → resp`'s
  own instance, where `decomposition`'s `sysarch → comp` locus *is* the
  element `fulfills`'s own path continues past; the same match closes
  `calls`/`renders`/`uses_shapes`, whose `declared_in` each shares
  `frontend_sysarch`'s own `ui-collections.collection[]` or
  `screen-collections.collection[]` prefix with `decomposition`'s own
  `ui_coll`/`screen_coll` fanout instance), a `scope: singleton`
  endpoint (the endpoint's own tier holds at most one node project-wide,
  so no locator is needed to say which — `ui_coll → design_system`'s
  own target, `design_system` being `scope: singleton` (this system's
  own ORC-110 entry, above)), and an explicit path (the residual case,
  below). A side that resolves one of
  these four structural ways lets its *other* side default to the
  trailing `.@attr` segment of `declared_in` when it has one
  (`chain.md` #27) — which is why every `reference`-typed instance
  and four of the ten `dependency`-typed ones (`ui_coll →
  design_system`, `calls`, `renders`, `uses_shapes`) need no locator in
  bundle content at all: one side resolves structurally and the other
  takes the default.

  An explicit path (`@<attr>`, naming an attribute on `declared_in`'s
  own terminal element — a closed form, not a dotted element path as
  well, since the resolver implements only this one) is the fifth kind
  and the only one that needs bundle content, for the six `dependency`
  instances none of the four structural kinds can resolve:
  `comp ↔ comp`, `subcomp ↔ subcomp`,
  `ui_coll ↔ ui_coll`, `ui_subcomp ↔ ui_subcomp`, `screen_coll ↔
  screen_coll`, `screen_subcomp ↔ screen_subcomp` — each names two peer
  instances of the *same* tier off one element with no fanout locus in
  reach and no `self.parent` relationship either (`sysarch`, the
  `comp ↔ comp` instance's committing tier, is `per(requirements)`;
  neither `comp` endpoint is `requirements`), so both ends need a
  bundle-declared attribute name. **The loader does not attempt to
  infer a locator for this case** — a `source_ref:`/`target_ref:` left
  implicit where none of `self`/`self.parent`/`fanout(<edge>)`/a
  `scope: singleton` endpoint structurally match is a load error, not a
  guess, for the identical reason `Extraction`'s moduledoc gives for
  declining to guess: a wrong inference here fails
  silently (an empty walk that reads as "nothing to report" rather than
  "the bundle is broken"), which is worse than refusing to load. The
  same reasoning closes the vocabulary itself: a `source_ref:`/
  `target_ref:` naming anything outside the five kinds above — a dotted
  element path included — is a load error naming the instance and the
  offending value, and the `@<attr>` form's own attribute gets the
  identical ORC-232 declared_in/schema cross-validation described below,
  against the schema of whichever tier's draft `declared_in` resolves
  against.
- **#38 The ORC-232 declared_in/schema cross-validation widens to cover
  `fields:`/`produces:` `draft.<path>` sources, which have the identical
  defect already live in the shipped bundle** (ORC-236; `chain.md` #32).
  `mint.parent.<name>` reads a committing tier's own `fields:`/`produces:`
  values by name (below), so those sources get the same schema cross-check
  `declared_in` already gets — and `Extraction.text/2`'s exact-string match
  (no `_`↔`-` normalization, the same mechanism ORC-232's own entry names)
  fails silently on **21 of the bundle's 24 `produces:` entries**:
  `comparch.yaml`, `screen_collarch.yaml` and `ui_collarch.yaml` each declare
  all four of `authored: draft.technical_specification` /
  `draft.public_surface` / `draft .private_surface` / `draft.failure_surface`
  (four apiece), while `subcomparch.yaml`, `screen_subcomparch.yaml` and
  `ui_subcomparch.yaml` each declare three of the four — `technical
  _specification` / `public_surface` / `private_surface`, since that family
  produces no `failure_surface` fragment at all (three apiece) — for 3×4 +
  3×3 = 21.
- **#39 `type: policy_application` is not this mechanism, and gains none of
  it.** Its two instances' `declared_in` (`policy.structural`,
  `policy.required`) names a marker on the minting instance element
  itself, not a location in a *committed* draft body — there is no
  `references/5`-style extraction to locate a non-`self` endpoint for,
  because there is no second draft to read. It resolves the same way
  `mint.<name>`/`mint.parent.<name>` already do: engine-side, at the
  same moment and off the same element a fanout mint already walks.
  ORC-235's own entry (`systems/generation.md`) names this and the
  locator mechanism above as "two separate mechanisms, not one", and
  they are kept apart in the grammar the same way they stay apart in
  the extractor.
- **#40 `mint.parent.<name>` names the inherited half of a join-target
  tier's `mint.<name>` field source, spelled rather than left implicit**
  (ORC-236; `chain.md` #12).
- **#41 `design_system`'s `generator: supplied` mint is a scaffold-time
  write, not a swept dispatch.** `core_dsl.md`'s own ORC-110 entry (above)
  settles the tier's shape (mints at most one, directly from the pinned raft
  artifact, no fanout); *when* that mint happens is a separate question,
  since a `supplied` tier has no `context:` to gate readiness and no `draft:`
  for the sweeper's own `dispatchable?/1` to match. It happens once, at the
  same write that pins the raft (v5 §1.1's freeze) — a second engine write
  path alongside `DraftCommitted`'s own mint application, for a generator
  kind whose content is already final the moment the tier becomes reachable,
  never revisited by a later sweep tick.
- **#42 `.synthesis` retires from the context-walk projection vocabulary**
  (ORC-236; `chain.md` #19). No tier in `bundles/default` declares a
  walk targeting it, and `ContextAssembly.render_node/2` never
  implemented it — parsed, documented, never consumed on either side. A
  projection with no consumer is not designed; the word is out of the
  vocabulary instead, and nothing in `bundles/default` depends on it.
  `type: synthesis`, the edge type a `cascade_visit`-scoped planning
  tier's `plan_target`-style edges declare, is a different vocabulary
  word for a different thing and stays: `refactor_plan.yaml`,
  `upward_propagation_plan.yaml` and `downward_propagation_plan.yaml`
  all walk `self.plan_target -> <tier>.handle`, never `.synthesis`.

- **#45 The DSL redesign replaces the grammar the entries above
  describe, and the loader's shape with it.** The contract is
  `bundle.md`, `chain.md` and `workflow.md`, each rule carrying an id
  and, in its `.reasons.md` sibling, the argument for it.
  `bundles/default/chain.yaml` and `bundles/default-flow/workflow.yaml`
  are the default pair written in that grammar.
  Five changes, each naming the entries it supersedes:
  1. **Each axis is one declaration file.** `chain.yaml` carries every
     tier, edge, flow and predicate; `workflow.yaml` every type, gate
     and environment (`bundle.md` #3, #4). The per-file declaration
     kinds go, and the manifest with them. #7's `catapult.yaml` rule
     stands unchanged; #14's one-declaration-shape rule stands as one
     `types:` block rather than one file format across three
     directories; #29's "single directory of authored content"
     narrows to a single file plus the schemas and prompts that file
     names.
  2. **The cross-axis reference runs from the workflow.** A generation
     position names the tiers that run at it and a ticket type names
     the chain flows it serves (`workflow.md` #22, #40); nothing in
     `chain.yaml` names a position, a gate or a type. This reverses
     #11: the workflow now has vocabulary for the chain's flows, and
     the pairing is a load error rather than a convention.
  3. **A review and a reconcile are blocks on the tier they belong
     to** (`chain.md` #14, #15). #9's `reviews: <tier>` retires with
     the review tier itself, and so does the load rule checking that a
     review tier's walks match the reviewed tier's, which existed only
     because the copy existed.
  4. **`design`, `architecture` and `implementation` stop being
     kinds** and return as `name:` values on generation entries
     (`workflow.md` #10); the fixed table is the set of shapes plane
     logic branches on. The agent-balled kind enumerations in #17,
     #20, #23 and #27 shrink accordingly. `pending` leaves the table
     altogether — it is an engine flag every agent-balled position
     carries until an agent picks the work up, not an entry
     (`workflow.md` #25) — which supersedes the per-sub-array
     `pending` rules in #17, #19, #23, #25, #26 and #28.
  5. **A fact about one document is the schema's** (`bundle.md` #10):
     node identity, which elements are fields, and plain cardinality
     are annotations and occurrence bounds in the XSD, so the loader
     stops carrying rows nothing enforced. A join target declares
     `draft: none` rather than being recognised by the absence of a
     draft (`chain.md` #8), which is what #30 keyed its mint-time
     default on.
  6. **A gate outside a sub-array may carry no `throwback:` at all**
     (`workflow.md` #34, #35), the decline landing on a
     human-chosen earlier position instead. #17's and #19's rule that
     such a gate must declare one was in the contract and never in
     the loader, which tolerated nil throughout.

- **#ORC-249-1 `bundle.md` #14's acceptance test is a `Mix.Task`,
  `Mix.Tasks.Catapult.Bundle.Check`, filed at
  `lib/catapult/dsl/bundle_check.ex`.** Mix locates a task by module
  name, never by file path, so the path is free, and it sits inside
  this doc's own `lib/catapult/dsl/**` map rather than opening a second,
  unowned directory. It loads
  `bundles/default/chain.yaml` and `bundles/default-flow/workflow.yaml`
  through the ordinary loader path (`Catapult.Dsl.Loader.load_axes/5`),
  which exercises every load rule the two files are held to for free,
  and then measures both files' line counts against the bound
  `bundle.md` #14 states, failing over it. It is a built-in of the task
  itself, not a `Catapult.Audit.Check` (`systems/substrate.md`'s
  registry is `components/substrate`'s own gate suite, rooted at the
  working directory it runs from — a task here would need
  `system:substrate` in this ticket's mutex for a registry this task
  gains nothing from) and reimplements none of the load-time rules the
  loader already owns once it reads the grammar `docs/dsl/` states
  (`chain.md` #20, #21; `workflow.md` #22, #23, #40; `bundle.md` #11) —
  doing so here would be a second implementation of the same load
  rules, which is the drift this task exists to end rather than
  repeat.

  The module name sits in the `Mix.Tasks` namespace, which is neither
  of the root project's two Boundary boundaries (`Catapult`,
  `CatapultWeb`) — true at any file path, since Boundary classifies by
  module name and an unclassified module fails `mix compile
  --warnings-as-errors` outright (`"is not included in any boundary"`).
  It declares `use Boundary, classify_to: Catapult`, the mechanism
  Boundary reserves for mix tasks and protocol implementations for
  exactly this namespace mismatch. No `Catapult.Mix` sub-boundary: that
  shape exists to hold helper modules several tasks share, and this is
  the project's only task with no such helpers to hold.

## #43 Initial vs target

Initial (Phase 3): core vocabulary, loader, design-dialect extension
set. Target: the single-file loader for `chain.yaml` and
`workflow.yaml` (`bundle.md` #3, #4); full extension registry with
delivery + runtime dialects registered; bundle-diff support for the
registry's handle machinery.

The loader parses and checks reserved grammar now, so a bundle written
against it does not change shape when the consumer lands (`bundle.md`
intro). Each reserved construct and the ticket that will read it:

- **The flow engine** (engine#69): the `cascade_visit` scope, the
  `synthesis` edge type, `flows:` and every key inside it, a flow's
  `completion` predicate, the walk primitives, and the plan cascade's
  positions and derived context (`chain.md` #6, #26, #38, #40, #41).
- **Delivery Phase 7** (delivery#123): `enforcement:` on a tier,
  `consistency:` on an edge, the ticket skeleton's relative order
  enforced against dispatch, gate `escalation`, and `environment:`
  entries with every environment key (`chain.md` #16, #25;
  `workflow.md` #12, #38).
- **Generation** (generation#50) and **the LLM bindings** (llm#6):
  `executor:` profiles, routed by generation and bound by llm
  (`chain.md` #10).
- **The registry** (registry#7): `version` on either manifest, the
  `external`, `template`, `git_commit` and `webhook` generators,
  extension context-source kinds, and annotation namespaces
  (`chain.md` #39; `bundle.md` #5, #8).
- **Identity** (identity#6): a gate's `role` checked against the
  holders the identity component knows (`workflow.md` #32).
- **The commit path**: a `fanout` instance's `when:` predicate, and
  validation of a `template` generator's rendered body (`chain.md`
  #37, #39).
- **This doc**: the reference write path behind a supplied tier's
  `source: write` (`chain.md` #17).

## #44 Depends on

substrate. Content it loads lives in platform_content.
