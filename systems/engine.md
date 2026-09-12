---
paths:
  - lib/catapult/engine/**
  - test/catapult/engine/**
  - priv/repo/migrations/**
---

# engine

The reactive core: the Commanded application, per-project aggregates
and the event log, the reducer, the universal projections (nodes,
edges, fragments, drafts, reviews, ready_scopes, staleness, flows),
the reactive scheduler with its sweeper, and replay/rebuild. The
first consumer of the ES store family (v5 §2.4) — its purity floors
and `events/0` registry are proven here before any target app uses
them.

## #1 Standing decisions

- **#2 The log is the source of truth; projections are derived and
  disposable.** Rebuild-from-zero byte-identity is a standing test:
  replaying the full log into fresh projections must equal
  incremental state, always. This is also the
  recovery mechanism — no projection surgery, ever.
- **#3 The scheduler is state-driven, not event-driven**:
  readiness is a query against current projections, so the same
  query answers "ready now" and "ready at sequence T," and there is
  no in-memory pending-set to corrupt. Fast path via PubSub;
  sweeper as the convergence floor.
- **#4 "Write the ready_scopes row" (the scheduler's rule 3) is a PubSub
  broadcast, never a table write** — the same "never materialized"
  standing decision below applies to the scheduler's own output, not
  only to the query it wraps. On each trigger the scheduler re-runs
  `Catapult.Engine.Projections.ReadyScopes.ready/3` (rules 1 and 2)
  for the tiers the trigger could have affected and broadcasts the
  resulting `(tier, scope)` pairs on `engine:ready_scopes:<project_id>`
  (naming spine, `Catapult.Engine.Topics`, conventions §3). The
  scheduler holds no memory of what it last broadcast — diffing
  against a remembered ready-set to announce only deltas would be
  exactly the in-memory pending-set the state-driven doctrine refuses
  to grow, so it re-announces liberally instead: every event that
  could plausibly move readiness (draft committed, draft approved,
  bundle flipped) re-triggers the query and the broadcast fires
  unconditionally on that trigger, whether or not the ready set
  actually changed. The payload is a hint, never an authority: a
  consumer re-validates before acting on it (§7.1's validate-or-revert
  discipline, applied to an internal signal the same as an external
  one), which is also why the broadcast needs no de-duplication of its
  own — whatever a consumer does with a ready pair is idempotent on
  its own side regardless of how many times the pair gets announced.
- **#5 The scheduler dispatches to no component by name.**
- **#6 Review-tier dispatch is a second, simpler readiness rule, not an
  extension of the context-walk one.** `ReadyScopes.ready/3` filters
  review tiers out entirely (`generation_tier?/1`) because §7.19
  already settled their dispatch: fired one cycle after the tier they
  review commits, unconditionally — no context walk of their own to
  gate on. Left unaddressed, that exclusion would make review dispatch
  bypass `ready_scopes` altogether, which is exactly the "nothing else
  initiates work" invariant this ticket exists to hold. The
  scheduler's enumeration therefore carries two rules feeding one
  signal: a tier's own context-walk readiness for generation tiers, and
  "the reviewed tier's current draft has no review yet" (already
  answerable via `Store.reviews_for_draft/1`) for review tiers — both
  land on the same broadcast, so a consumer never has to know which
  rule produced a given pair.
- **#7 `scope_filter` is evaluated where readiness is, and answers a
  different question than the context walk does.** A node failing its
  tier's `scope_filter` is not a candidate at all — it never appears in
  enumeration, which is distinct from appearing and being not-yet-ready.
  Evaluation is a new engine-side predicate evaluator, beside
  `ContextResolver` and built on the same `Store` edge/node primitives,
  because a `scope_filter` predicate (`has_edge`, `count`, `exists`,
  `all`/`any`, `reaches`) needs live graph state the same way a context
  walk does. Built as the shared home for the predicate language's
  other three slots (`cardinality.when`, an edge `constraint`, a flow
  `completion`, `dsl-syntax.md` §8) when their own tickets land, not a
  one-off for this slot alone.
- **#8 `input.<role>` and `input.*` resolve to `{:ok, []}`, always — never
  a real target, never `{:error, :unsupported}`** (ORC-107, closing the
  gap `systems/generation.md`'s ORC-10 entry names). `ContextResolver.resolve/2`
  gives `:input` its own clause rather than folding it into a shared
  `when source in [:input, :ticket]` guard with `:ticket`, because the
  two sources are unsupported for different reasons — `:ticket` stays
  `{:error, :unsupported}`, v5 §7.11's Phase 7. `:input` covers both the `role` and the wildcard
  forms identically: neither is a graph walk (an input document is
  pinned prose, not a node with a tier, a status, or edges — the
  intake entry below is where the pinned content actually lives and
  how a prompt reads it), so `ContextResolver` — whose whole job is
  walking *declared node/edge instances* — has nothing to resolve
  either form against and says so the same way for both.
- **#9 The empty list is the whole mechanism, not a placeholder for one.**
  `ReadyScopes.walk_ready?/2` and `.walk_report/2`, and `Staleness .walk_stales?/2`, fold `{:ok,
  targets}` generically — `Enum.all?(targets, &(&1.status == :approved))` on an empty list is
  vacuously true, `Enum.any?(targets, &target_newer?/2)` on an empty list is vacuously false. Neither
  module carries a line for this: an `input.<role>` walk is therefore *structurally* incapable of
  blocking readiness or reporting staleness, which is dsl-syntax.md §7's "a role with no documents
  never blocks readiness" and v5 §1.1's "an input-doc edit... stales nothing" — both already true of
  every `{:ok, []}` regardless of source, so neither invariant needs a bespoke branch written *for*
  it.
- **#10 Consequence for `explain/2`:** an `input.<role>` walk resolves satisfied with zero targets,
  the same shape a fully-satisfied ordinary walk has, so `Enum.reject(& &1.satisfied)` drops it from
  `blocking` entirely — it carries no `reason: :unsupported`. Only `ticket.<source>` walks do.
  `screens/explain-why.md` and its storybook fixture show the same (ORC-107).
- **#11 Explain-why is `ReadyScopes`'s own second query, not a parallel
  implementation.** "What is blocking this scope"
  (`systems/dashboard.md`'s naming) reuses `candidates/2` and the same
  per-walk resolution `ready?/2` already does, replacing the boolean
  fold with a structured report: which context-walk entry is unmet,
  and for each of its resolved targets, its current status. Built
  beside readiness because both read the same candidate/target
  machinery — a second traversal implementation is the drift risk, not
  the convenience.
- **#12 Navigation edges get no second check in the engine.** `Catapult.Dsl.Chain` already refuses
  to load a context walk that traverses a `navigation: true` edge (dsl-syntax.md §4, §13) — the
  readiness and explain-why queries walk only what the loader already proved is readiness-bearing, and
  add no redundant edge-kind filter of their own.
- **#13 Creation is not dispatchability, and the engine needs no new node
  status to hold that line.** `Reducer.apply_mint/2` already lands a
  minted child at `status: :absent` the moment its parent's draft names
  it (v5 §7.10's "children are created when the plan node names them"),
  and an `:absent` node's readiness is exactly its declared `context:`,
  evaluated the same as any other node's — nothing about having just
  been minted makes it a special case. A bundle wanting a child gated
  on its parent's workflow gates points that child tier's context at a
  walk the parent's review/approval flow actually resolves through
  (the node's own `:approved` status, set only once its review tier's
  chain-axis pass lands); the gating is therefore a bundle-content
  decision, not an engine mechanism, and no `:pre_queue` node status is
  introduced to duplicate what the context walk already expresses.
  §7.2's child-blocks-parent (completion) and any future
  `openBlockerFor`-style check are delivery's concerns over the ticket
  tree, not this system's over the node graph, and the readiness query
  never treats a node's children as a precondition of that node's own
  readiness — only its declared `context:` is.

- **#14 A join-target tier mints straight to `:approved`, and the mint- time default is what changes
  — readiness needed no new rule** (ORC-117).
- **#15 The fix is where the node is minted, not where readiness is read.**
  `Catapult.Engine.Reducer.apply_mint/2` does not hardcode `status: :absent`; the mint entry itself
  carries the status to write — `:approved` when the target tier declares no `draft:`, `:absent`
  otherwise — and the reducer copies it onto `Store .mint_node/1` unchanged, the same "copy, never
  derive" shape every other reducer branch follows. `Node.status` keeps its three values — `:absent`,
  `:drafted`, `:approved` — no fourth value for "synthesized, never reviewed." A join target's
  `:approved` is a deliberate reuse of the readiness-only reading of that atom ("this node satisfies
  anything walking toward it"), not a claim that a human or a draft was ever approved, and it is not
  split into a fourth status to make the name more honest.
- **#16 What a reader makes of that value is a separate question from what the mint writes.**
  `status: :approved` at mint time answers "does this node itself have anything left to review" —
  correctly, since a join target never does — but a reader walking onto it is asking a different
  question, "has the content behind this node settled," and the two coincide only once the draft that
  minted the node is itself approved. So `walk_ready?/2` and `explain/2`'s `walk_report/2` resolve a
  target through `settled?/2` (below) rather than testing `status` directly, and the "is this target's
  tier a join target" check lives in exactly one place, shared by `ready?/2`'s boolean fold and
  `explain/2`'s structured one — never folded independently into each, which would be two computations
  of one fact.
- **#17 Where the value is computed: the command edge, not the reducer.**
  `Catapult.Generation.Extraction.mints/4` resolves the target tier's full declaration (via `chain`)
  to build each mint entry's `tier`/`scope_key`/`edge_name` — the same lookup that has
  `chain.tiers[instance.target].draft` in hand carries one more field on the entry it returns,
  threaded unchanged through `Catapult.Engine .Commands.CommitDraft`'s `mints:` and onto
  `DraftCommitted`'s own `mint()` type.
- **#18 The same default reaches `policy`, and staleness needs no change.**
  `sysarch_policy`/`comparch_policy`/`non_goals_policy`
  (`systems/platform_content.md#15`'s split of the former single
  `policy.yaml`) are each `generator: synthesis` with no `draft:`,
  structurally identical to `comp`/`subcomp`/`resp`, so each gets the
  identical mint-time `:approved`.

- **#19 A node's readiness-effective status is resolved, not read bare —
  a join target defers to whichever node minted it, recursively**
  (ORC-235). `walk_ready?/2` and `explain/2`'s
  `walk_report/2` do not test `target.status == :approved` directly;
  both call one shared resolver — call it `settled?/2` here,
  named for the concept rather than committing dev to a literal
  function name — that both fold generically over a walk's
  targets:

  - a target whose tier declares a `draft:` (`chain.tiers[target.tier]
    .draft != nil`) is `settled?` exactly when `target.status ==
    :approved` — the ordinary review/approval path;
  - a target whose tier declares no `draft:` and is not `generator:
    supplied` (a join target fanned out by some other node's
    `DraftCommitted`) is `settled?` exactly when its minting parent is
    `settled?` — `Store.get_node(project_id, target.parent_node_id)`,
    recursed through the same predicate. `apply_mint/2` writes
    `parent_node_id: event.node_id` (the committing node, i.e. the
    minting parent) for every mint, and a `per(X)` node's own
    `parent_node_id` is its `per`-parent for the identical
    reason (`Reducer.apply/2`'s `DraftCommitted` clause,
    `parent_node_id: event.parent_node_id`) — the recursion reads a
    field the reducer already writes, on both sides, and needs no
    column. A node reaching this branch with `parent_node_id
    == nil` is a data-integrity error to surface, not a signal to read
    as settled — every fanout mint writes this field, so its absence
    here means the mint itself is broken, not that the node has
    nothing to wait on;
  - a target whose tier declares `generator: supplied` (`design_system`
    is `bundles/default`'s only instance today) is `settled?`
    unconditionally, the moment the node exists at all — keyed on the
    tier's own declaration rather than on `parent_node_id == nil`, so
    a genuine join target that somehow reached the store with no
    parent recorded falls into the error case above instead of reading
    as settled by coincidence. A supplied tier is pinned complete at
    intake (v5 §1.1, §5.4) with nothing upstream in the generation
    chain that produced it and could still revise it — the join-target
    recursion above exists because a join target's content traces back
    to a draft that may not yet be approved, and a supplied node has no
    draft anywhere in its history to be unapproved.
- **#20 Unchanged by the resolver:** `Node.status`'s three values, the mint-time write itself
  (`:approved` for a `draft:`-less tier, ORC-117 above), and `ContextResolver.resolve/2` — a walk
  resolves to exactly the targets it always did; only how a resolved target is judged `settled?`
  differs.

- **#21 `all.<tier>` is satisfied only once `<tier>`'s own population is exhausted, not merely once
  every node that happens to exist already is approved** (ORC-235). `ContextResolver.resolve/2`'s
  `source: :all` clause returns every currently-`Store .list_nodes/2` node of `<tier>`, but
  `ReadyScopes` does not fold that list alone with `Enum.all?/2`; empty is satisfied only when
  emptiness is known to be final, which `Enum.all?([], _)` cannot tell from "nothing has minted or
  drafted here yet." A tier's population is exhausted — call it `drained?/1`, the same naming register
  as `settled?/2` above — when no further node of that tier will ever appear *and* nothing that
  already exists is still pending. The recursion below folds over the same closed `scope:` vocabulary
  `candidates/3` already switches on, but its two recursive branches (`per(X)`, `child_of(X)`)
  test that definition differently, because the two node kinds come into existence at different
  points.

  - `singleton` with `generator: supplied` (`design_system` is
    `bundles/default`'s only instance today): drained unconditionally,
    from the moment the project exists — a supplied tier's population
    is fixed at intake, before the chain ever dispatches a single tier,
    so there is no "not yet" state between zero and its final count for
    this recursion to distinguish. A project supplying no document
    tagged `design_system` mints none (`design_system.yaml`'s own
    header — the same optionality every `input.<role>` carries), and
    that zero is final the instant the project exists, not
    provisional on anything the chain does later;
  - `singleton` with a `generator: llm` draft dispatched through the
    chain itself — exactly the tiers that are both `scope: singleton`
    and `generator: llm` (`feature_expansion`, `non_goals`,
    `frontend_sysarch`; `ref` is `scope: reference`, not `singleton`,
    below, so it is not in this bucket): `Sweeper.dispatchable?/1`
    matches each of the three on its `draft:`/`generator: "llm"` pair
    exactly like any other chain-dispatched tier, and the engine's
    `{:singleton}` scope holds exactly one row per project per tier
    (`candidates/3`'s `scope_key: %{}`, the `unique_index` on
    `(project_id, tier, scope_key)`): drained once its one node exists
    and is `settled?` — never vacuously, because such a tier's count is
    exactly one once the chain reaches it, never legitimately zero;
  - `reference` (`ref` is `bundles/default`'s only instance, `docs
    /dsl-syntax.md` §3.1, ORC-236): never drained. An indefinite,
    write-path-created pool cannot tell "no more will ever be written"
    from "none exist yet" the way every branch above can — there is no
    upstream tier whose own exhaustion would settle the question, and
    no chain event marks the pool complete. Rather than leave that
    recursion hang the first time anything asks, `dsl-syntax.md` §13
    refuses two things at load time instead: an `all.<tier>` walk
    targeting a `reference`-scope tier, and a non-zero cardinality `min`
    on the side of an edge instance that names one (below) — nothing in
    `bundles/default` needs either (every `ref` read is a named
    `reference`/`fulfills` citation resolved by id, never a population
    walk, and every `→ ref` instance's cardinality is `{min: 0}` on both
    ends), so both refusals cost no shipped content and this branch of
    `drained?/1` is never actually called;
  - `per(X)`: drained once X is drained *and* every node `Store
    .list_nodes(X)` names (trustworthy as the final list only because X
    is already confirmed drained) has its corresponding `per(X)` node
    `settled?` — and a corresponding node with no stored row at all
    reads as not settled, the same "hasn't drafted yet" case the
    driving-tier check above exists to catch, not a gap the clause
    forgets to answer;
  - `child_of(X)` (the one tier a `type: fanout` edge instance
    targets — `Catapult.Dsl.Chain.fanout_drivers/2` filters
    `chain.edges` to `type == "fanout"` and `instance.target == tier`
    to give the driver, and this projection's own `child_of(X)` clause
    calls it rather than keeping a second copy of the same recursion;
    `core_dsl.md#45` is what makes that set a single tier rather than
    merely usually one): drained once `X` is drained *and* every row
    already at
    `<tier>` is `settled?` — a fanout mint runs exactly once,
    synchronously with its source's own `DraftCommitted` (regeneration
    is chosen, not triggered, `docs/v5-design-decisions.md`), so once
    the one possible minting source has committed and been approved,
    no further instance of `<tier>` will ever appear and the current
    list is final, whatever its length. The second conjunct costs
    nothing at the twelve `child_of` tiers that are join targets
    (`comp`, `comparch_policy`, `journey`, `non_goals_policy`, `resp`,
    `screen`, `screen_coll`, `screen_subcomp`, `subcomp`,
    `sysarch_policy`, `ui_coll`, `ui_subcomp`), whose rows are
    `:approved` from mint and whose `settled?` already defers to the
    very `X` this branch checks. It is load-bearing at the
    thirteenth: `vocab` is the one `child_of` tier in `bundles/default`
    carrying a `draft:` of its own, so its rows mint `:absent` and stay
    pending until drafted and approved — without the conjunct,
    `drained?(vocab)` would read true the instant `feature_expansion`
    is approved and every vocab entry is still undrafted, which is "no
    further node will appear" without "nothing existing is still
    pending."
- **#22 Termination is a property of `bundles/default`'s own scope graph today, not one the loader
  enforces.** `per(X)`/`child_of(X)` references are declared over tier *names*, not edge
  instances: `Chain.build`'s acyclicity check (`lib/catapult/dsl/chain.ex`) walks `edges:` instances
  only, and `scope_problems/1` checks only that a scope names a tier the bundle actually declares —
  nothing at load time rejects a bundle declaring `A per(B)` and `B per(A)`, which would recurse
  `drained?` forever the first time either tier's readiness is asked for. `per(X)`/`child_of(X)`
  are the only cases that recurse at all — every `singleton` tier is a base case for this recursion,
  whatever its own `drained?` branch decides.
- **#23 Order is derived from the graph `context:`/`scope:` declare, never from a declared tier
  sequence.**
- **#24 `drained?` delivers the ordering half of the Scope section's purpose, not the
  reading-real-APIs half.**

- **#25 A minted node's `fields` are written at mint time, copied from the
  mint entry unchanged — the identical "copy, never derive" shape
  ORC-117 already established for `status`** (ORC-236).
  `apply_mint/2` threads `mint.status` from `Extraction.mints/4`'s own
  entry onto `Store.mint_node/1` without the reducer deriving anything;
  the mint entry also carries `fields:` — every
  `mint.<name>`/`mint.parent.<name>` value `Extraction.mints/4`
  resolved at the command edge (`docs/dsl-syntax.md` §3,
  `systems/core_dsl.md`'s ORC-236 entry) — and `apply_mint/2` copies it
  onto the same call, alongside `status`. No reducer branch derives
  them and the purity floor is not exposed: the values are computed,
  purity-floor-clean, before the event is dispatched, the same
  guarantee `mint.status` relies on.
- **#26 `settled?/2`'s `generator: supplied` clause widens to `generator: reference`,
  unconditionally, for the identical reason** (ORC-236; the three-way match above).
- **#27 Cardinality and instance-level `graph_constraint` are evaluated once the edge's own bound
  side is drained — except a `max` bound, which needs no such gate and is evaluated as soon as it can
  be violated — and a violation is a reported, non-blocking finding — never a retried draft and never
  a blocking gate** (ORC-236).
- **#28 A declared edge now resolves to the node it names, closing the
  chain this ticket's own audit found empty — from two independent
  directions, not one fix gating the other.** Every `<arch> → ref`
  citation is extracted (`systems/generation.md`'s ORC-235 entry: nine
  instances satisfy the source-identity gate); what resolves them is
  `ref`'s `scope: reference` (above) — a `ref` node's `scope_key` is
  `%{"id" => <the id the write path assigned>}`, the exact shape a
  `<reference target="...">` citation looks up, so
  `resolve_target/3`'s `Store.get_node_by_scope(project_id,
  target_tier, %{"id" => value})` lookup succeeds for all nine. Under
  `scope: singleton`, `ref`'s `scope_key` was the single flat `%{}`
  every node of a `scope: singleton` tier shares, and every one of the
  nine extracted citations resolved to nothing. Separately,
  `source_ref:`/`target_ref:` extraction
  (`systems/core_dsl.md`'s ORC-236 entry) extracts the seventeen
  `dependency` and non-`ref` `reference`/`fulfills` instances. Sixteen
  of their targets (`comp`, `resp`, `journey`, `screen`, `subcomp`,
  `ui_coll`, `ui_subcomp`, `screen_coll`, `screen_subcomp`) carry a
  correctly id-shaped `scope_key` from their own ordinary fanout mint,
  so those sixteen resolve by the same `%{"id" => value}` lookup the
  moment they are extracted, with no dependency on `ref`'s scope at
  all. The seventeenth, `ui_coll →
  design_system`, does not: `design_system` is `scope: singleton`, not
  fanout-minted, and its one node's `scope_key` is the flat `%{}` every
  `scope: singleton` tier shares — an id lookup against it can never
  match. That instance resolves through the `scope: singleton` endpoint
  locator instead (`docs/dsl-syntax.md` §4.2), which is
  `resolve_target/3`'s second clause: a `scope: singleton` target
  resolves by `Store.get_node_by_scope(project_id, target_tier, %{})`,
  no id involved, selected by the tier's own declared scope rather than
  by an attribute value. `Extraction.references/5` carries the
  `source_ref:`/`target_ref:` locator resolution itself
  (`systems/generation.md`), not only better-shaped inputs.
  `apply_declared_edge/2` applies whichever edge list it is handed and
  does no locating of its own.

- **#29 A fanned-out child cannot leave its parent's workflow-axis sub-array, and this is a
  consequence of readiness already gating, not a new rule for this system to enforce** (ORC-115,
  design pass — stated as an invariant `docs/dsl-syntax.md` §15.10's sub-array grouping and ORC-116's
  own subflow-navigation design both lean on).

- **#30 Sweeper cadence defaults to 30s, `tunable`** (v5 §7.10's bindings surface, same mechanism as
  every other marked threshold) — enough headroom that a burst of events doesn't turn the convergence
  floor into a second fast path, short enough that a lost PubSub message (process crash, netsplit) is
  invisible within one dispatch cycle in practice. **`staleClaimGrace` (§7.16's still-open item) is
  not this constant** — it measures ticket-claim staleness on the delivery/ tracker side
  (`max(Run.EndedAt, StateSince)`), a different clock for a different job, noted so the two are not
  conflated by a reader reaching for "the scheduler's timer" and finding two candidates. §7.16's item
  is open independently of this constant. **A tick walks its projects serially, not fanned out.**
- **#31 The sweeper is a distinct registered process and declares `:singleton` placement, the same
  kind `engine_projector` already uses** (v5 §2.5). The fast path is not a second process to place:
  "on each trigger the scheduler re-runs `ReadyScopes.ready/3` ... and broadcasts" (above) rides
  inside `Catapult.Engine.Projector.handle/2`, which already runs cluster-wide singleton by
  construction (a Commanded event handler subscription is consumed once, in order, or replay
  guarantees break) — so placement is only ever a question about the timer loop.
- **#32 A node id is a per-project slug, not globally unique** (ORC-87).

- **#33 Every engine table keys by `(project_id, id)` — and so does every *secondary* unique index
  on it, which is the half that does not follow from the first.**

- **#34 Purity floors are absolute in this system**: no clocks,
  randomness, or generated ids in aggregate/reducer/projection code;
  inject at the command edge. Enforced by the substrate's call-graph
  audit check, which this system is the reason to build.
- **#35 `ready_scopes` is the plane's dispatch source** (v5 §1.2's
  inversion) — the engine writes it; generation and delivery consume
  it; nothing else initiates work.
- **#36 Events are versioned and upcast on read** (v5 §2.4): shapes are
  immutable contracts; changes are new versions with pure upcasters
  registered beside the reducer; the log is never rewritten; replay
  fixtures retain every historical shape. Built into the ES family
  from the first event, because retrofit means a broken replay.
- **#37 Every atom an engine event carries needs a `JsonDecoder` on read, and the class is exactly
  four events today, not one** (ORC-226; the crash that found it: `Catapult.Engine.Projector` raising
  `Ecto.ChangeError` on `ReviewWritten.kind` and taking the reference instance down with it — a
  `Commanded.Event.Handler` with no `error/3` stops on the first bad event, permanently, since it
  re-reads the same event on every boot). `Catapult.Engine.EventStore` sets
  `Commanded.Serialization.JsonSerializer` deliberately (its own moduledoc: it round-trips atom-keyed
  struct fields, which the library's default serializer does not attempt); `deserialize/2` rebuilds
  the event via `struct/2` and then always runs `Commanded.Serialization.JsonDecoder.decode/1` on the
  result — the same mandatory second step `Catapult.Delivery.ContainerLifecycle` and
  `Catapult.Delivery.FeatureLifecycle` already implement for their own persisted state (ORC-120).
- **#38 The class, over every event this doc's file map owns:** four events carry a value the
  reducer passes unchanged into a `Store` call backed by an `Ecto.Enum` column — `ReviewWritten.kind`
  (`Store.Review.kind`), `ActiveBundleFlipped.axis` (`Store.ActiveBundleVersion.axis`),
  `FindingAdjudicated.disposition` (`Store.ContainerFinding.disposition`), and `DraftCommitted
  .mints[].status`/`.edge_type` and `.edges[].type` (`Store.Node .status`, `Store.Edge.type`), the
  last landing through `Reducer .apply_mint/2`'s and `.apply_declared_edge/2`'s own pass-through
  `status:`/`type:` assignments. Every other atom- or `DateTime`-typed field on an engine event either
  never reaches a `Store` call at all (`DraftCommitted.committed_at` is read off the event but never
  forwarded to `insert_draft/1`; `CommentPosted.posted_at` and `RunFailed.occurred_at` fold through
  `apply/2` clauses that write no projection row, by design, above) or is a plain string end to end
  (every `reason`, every `gate`, every `type_name`) — this is the whole set for atom- and
  `DateTime`-typed fields, not a sample of it.
- **#39 The fix is one shared helper, not four bespoke decoders, and it resolves each value against
  the legal set `Ecto.Enum.values/2` returns rather than against the runtime atom table — which an
  event module's own compiled form does not populate with its legal values.**
- **#40 An unrecognised value never raises inside `decode/1`, and the mechanism that guarantees it
  leaves no ordering hazard for a dev to get backwards.** `WireDecoding` does not call
  `String.to_existing_atom/1` on the wire string as an independent second step — it matches the wire
  string against the atoms `Ecto.Enum.values/2` already returned (comparing each to
  `Atom.to_string/1`) and substitutes the matching atom it already holds. There is no separate lookup
  that could run before the `values/2` call and reintroduce the `ArgumentError` measured above: the
  only atoms `decode/1` can ever produce are the ones `values/2` just handed back, already resolved,
  so there is no ordering for a later change to invert. When no match exists, `decode /1` leaves that
  field's value as the wire string, unchanged, rather than raising — the struct then reaches the
  `Store` call it always would have, meets the same uncasted `Ecto.Changeset.change/2` every field in
  this class already goes through, and fails as `Ecto.ChangeError` at the one site `Projector`'s
  `error/3` (`:stop`, below) already governs.
- **#41 `Projector` keeps Commanded's default `error/3` (`:stop`), unchanged — a decision, not an
  oversight.**
- **#42 The round-trip gap closes in the one test that reaches the real serializer.**
  `config/test.exs`'s `Commanded.EventStore.Adapters.InMemory` performs no serialization at all, so
  the default suite is structurally incapable of exercising any `JsonDecoder`, this class or the next
  one. `test/catapult/engine/event_store_test.exs` — the one test already reaching the real,
  Postgres-backed adapter — carries one case per event in the class above, each asserting the decoded
  struct's atom-typed field is an atom, not the string `Jason` would otherwise leave it as, plus one
  case, on any single field in the class, asserting that an unrecognised value comes back as the wire
  string unchanged rather than raising inside `decode/1` — the fallback stated above, exercised rather
  than only asserted in prose. `FlowCompleted`'s two-binary case remains: it proves the migration and
  the adapter wiring, which is a different and still- needed fact from the one the new cases prove.
- **#43 The reducer resolves bundle semantics per event, from the log — never from whatever
  `core_dsl` currently has loaded.** The active bundle can flip mid-log, on either axis (v5 §6/§7.19;
  `core_dsl.md`'s cutover decision), and rebuild-from-zero must equal incremental state *always*, a
  flip included. A reducer that asks "what bundle is loaded right now" would apply today's semantics
  to yesterday's events on rebuild and diverge from what actually happened. So the flip events fold
  into their own small per-axis projection — current bundle version, and the sequence it became
  current, two rows per project — and the reducer consults that projection, in log order, exactly like
  every other event; it never reads `core_dsl`'s loaded state mid-fold. This is also the engine-side
  half of the join `core_dsl.md` already promises delivery's Phase 7 re-resolution (a blocked ticket's
  status history against the bundle-version timeline): the timeline is this projection, so delivery
  reads it rather than re-deriving one of its own.
- **#44 Staleness is a projection, never stored state** (v5 §7.11): a
  node is stale when its committed content predates the inputs its
  context walk reads — computed from the log on demand, consumed by
  flow walks and the plane's out-of-band ticket filing. No stale
  flag is ever written, and no pending work attaches to nodes;
  pending work is always a ticket.
- **#45 A review tier needs no staleness treatment — but this does not
  close v5 §7.16's open item, which names a different object.** §7.16
  asks what a passed *workflow* gate pins ("Approval is a status, and
  review states are declared"); `dsl-syntax.md` §3.3 (ORC-84)'s
  `reviews: <tier>` is the chain axis, and §7.19 draws the line
  explicitly: a review tier is dispatched immediately after the
  generation tier it reviews, one cycle, and "has no throwback
  semantics: there is no passed gate downstream of it to reopen." A
  review tier also declares no `draft:` and no committed artifact, so
  there is nothing for §7.11's staleness derivation to anchor on even
  if it wanted to run. So a review tier is simply never consulted by
  the derivation, in either direction — not stale, not pinned, not
  reopened, and no "approved version" field is ever needed for one.
  §7.16's item stays open (restored at `v5-design-decisions.md`
  §7.16): a workflow gate is declared delivery-bundle vocabulary, not
  an engine node, so what it pins is delivery's to design when
  workflow gates land (`systems/delivery.md`'s Phase 7), over
  whatever this system's node/staleness projections already expose —
  not this ticket's to answer.
- **#46 Snapshot cadence and stream partitioning carry the v4 defaults forward, unmoved.** Stream
  partitioning: one EventStore stream per project, the Commanded aggregate identity being the project
  id (v4 §C.3) — already implied by "per-project aggregates" above, stated explicitly here because the
  ticket asked; both axes' events land in the same project stream; a project has one aggregate, not
  two. Snapshot cadence: every 10,000 events per project.

- **#47 Container and workflow-axis lifecycle events land on the same
  single per-project aggregate, not a second one** (ORC-104;
  `docs/dsl-syntax.md` §15.6-§15.8, `docs/v5-design-decisions.md`
  §7.8). A container instance's
  mint, its activation, each move of its current queue — forward past
  a resolved gate, or backward on a step's own outcome (a decline, from
  a `critique` entry's own agent run, landing on the generation entry
  it pairs with, or from a human at a gate, landing per its
  `throwback:` — one mechanism per §7.19, not two) or an explicit
  author transition, never on a queue's population refilling (§15.8)
  — a carried finding's filing or decline, and a milestone's flag-set
  flip are none of them derivable
  from anything already in the log: nobody else records "this
  milestone instance now exists" the way nobody else records "this
  draft was approved." They are original protocol facts, the identical
  shape `OpenFlow`/`CommitDraft`/`ApproveDraft` already are, and "a
  project has one aggregate, not two" (above) already answers where
  they land — `Catapult.Engine.Aggregate`, dispatched through the same
  `Catapult.Engine.Router`, in the same per-project stream every
  chain-axis event already writes to. New command/event modules join
  the existing set under this doc's own file map
  (`lib/catapult/engine/commands/**`, `lib/catapult/engine/events/**`),
  not a parallel set delivery owns: a second Commanded aggregate
  identified by `project_id` would be the second aggregate this doc
  already refuses, and command modules living under delivery's own map
  while dispatched through this system's router would point the
  dependency the wrong way — `systems/delivery.md`'s own "Depends on"
  already runs delivery → engine, never the reverse. Command
  validation — a queue-advance naming a declared anchor, a `blocks:`
  relation (`singleton:` declares no lifetime bound — retired at
  ORC-148, `systems/core_dsl.md` — so there is no fourth check here) —
  reads the loaded
  `Catapult.Dsl.Workflow.t()` the identical way the reducer already
  resolves bundle semantics from the log rather than from whatever
  `core_dsl` currently has loaded (above); this system already depends
  on core_dsl for exactly this, so no new dependency edge is needed.
- **#48 This is the first command edge into this aggregate that isn't this system's own.** Deciding
  *when* a queue has emptied or a `blocks:` sibling has cleared, and issuing the command, is
  `systems/delivery.md`'s new queue dispatcher; this system only validates and records what it's told,
  exactly as "engine is state of record, delivery is the protocol interpreting it" already reads in
  that doc.

- **#49 Membership is derived by reference, never a stored list — the
  queue-as-query principle applied one level up** (ORC-104;
  ORC-105's grammar, `dsl-syntax.md` §15.6-§15.7,
  `docs/v5-design-decisions.md` §7.8's "containers and projects alike
  keep references to their work items even once archived"). A
  container's access path to its own work is answerable from each work
  item's own `container_id` — set once, at open, the same way
  `project_id` already is — filtered to this container instance, with
  no resolution predicate to make it look like a queue's population
  query. Archiving a work item is policy, decided at
  `systems/delivery.md`, and never touches this column, so the
  reference survives archival for free: no membership list to keep in
  sync, and nothing here reopens `ready_scopes`'s own "never
  materialized" reasoning by writing a bucket for a different query
  that reasoning already refused a bucket for. A new projection reads
  current queue position per container instance in the same shape the
  ninth projection already gives current bundle version — one row per
  instance, current queue and the sequence it became current — since
  "which instance is minted vs. which is active" (`dsl-syntax.md`
  §15.8) is exactly that same two-fact shape, mint recorded once and
  activation a later, separate write to the same row.
- **#50 Membership is a version bump on the opening event, not a new table.** `container_id` and
  `queue` are set once, at open — which means they are fields on the event that opens a work item, so
  `Catapult.Engine.Events.FlowOpened` is version 2 and `FlowOpenedV1` joins `ReviewWrittenV1` as a
  frozen historical shape with an upcaster (v5 §2.4). The upcast fills both with `nil` rather than
  backfilling a guess: a version-1 event was written before containers existed, so the work item it
  opened was genuinely a member of nothing, and a guessed container would have made an unowned work
  item silently count into some queue's population — the one failure the queue-as-query has no way to
  notice.

- **#51 `CommentPosted` (v1, explicit) is a new `events/0` entry, and a
  human review comment is an original protocol fact on this same
  aggregate, not a second one** (ORC-34). It joins
  `DraftApproved`/`FindingAdjudicated` on the identical ground "a
  project has one aggregate, not two" already gives: nobody else in
  the log records that a human left this comment on this node's
  `body_sha`, so it cannot be derived, and it lands through the
  existing `Catapult.Engine.Router` in the same per-project stream.
  `Catapult.Engine.Commands.PostComment` carries `project_id`,
  `node_id`, `body_sha`, `locator` (nullable — see below), `author_id`,
  `body`, `posted_at` (supplied by the caller, per this system's own
  purity floor — never generated in the aggregate); `CommentPosted`
  mirrors it. Validation rejects a `body_sha` that doesn't match the
  node's currently committed draft, the same stale-view rejection
  every other command on a surface we own already gives (`systems
  /delivery.md`'s point-of-action rule) — a comment posted against a
  view the author hadn't refreshed fails here rather than silently
  attaching to the wrong version. **No `kind`/`author_kind` field:**
  nothing in Phase 4 posts a machine comment through this event — the
  chain's own auto-review is `ReviewWritten`, a distinct record with
  its own `kind: :ai | :human` — so `CommentPosted` is human-authored
  by construction and stays that way until something actually needs to
  post through it, the same "don't validate a scenario that can't
  happen" discipline this codebase already keeps elsewhere. This is
  what ORC-31's author-identity filter exists to reconstruct on a
  surface we don't own; on a surface we do, the identical outcome
  falls out of never having built a channel two kinds of author could
  write through in the first place. **Two reviewers commenting
  concurrently need no new mechanism**: this command carries no
  `expected_version` invariant of its own to protect (it appends a
  fact, it doesn't compare-and-swap a mutable one), so the ordinary
  case is Commanded's own optimistic-concurrency retry on the
  aggregate stream — the identical primitive §7.16 already names for
  human-vs-human races generally, not a second one built for comments.
  **The sentence locator is nullable, and is always null in Phase 4**:
  `docs/ui-spec.md` §5 stages per-sentence anchoring in `document
  -review` at v2; v1 (Phase 4's own) has no diff producing one yet.
  Nothing below reads `locator` to decide what to fold in, only to
  decide how to render an entry once folded — so v5 §7.4's per-span
  bucket key degenerates to per-node today (there is exactly one
  committed body per node to comment on) and activates for free,
  unchanged, the day v2's anchoring ships a real one.

- **#52 Harvesting is a query against this log, not a second table — the identical shape
  `Catapult.Engine.Projections.RunFailures` already established for a different derived fact,
  corrected onto here after design review found the first draft's cache reopened the exact
  silent-failure risk it claimed to close** (ORC-34).

  - `DraftCommitted` as the boundary: `GateDeclined` at T1 resets
    validation's window; a comment lands at T2, mid-regeneration;
    `DraftCommitted` at T3 resets *this* projection's window,
    discarding T2 before it ever rendered; `GateDeclined` again at T4
    passes validation (T2 postdates T1) and dispatches a regeneration
    whose `feedback` folds since T3 and sees nothing — burning the
    exact dispatch this entry exists to prevent, and losing T2
    outright in the process, since no later window ever folds back
    across T3 to find it. So `DraftCommitted` plays no role in either
    fold: a comment posted while a regeneration is in flight is not
    discarded by that regeneration's own commit.
  - "The resolution before the most recent one," unfiltered by gate,
    as the boundary: it infers the boundary from *position* in the
    global resolution sequence, which is wrong the moment a workflow
    declares more than one gate, and the shipped `feature.yaml`
    (`bundles/default-flow
    /types/feature.yaml`) declares two, `ux-review` then
    `engineering-review`, run in sequence over the same single
    pre-gate `generation` status, with `engineering-review`'s own
    `throwback: [generation, ux-review]` making a
    decline-to-`ux-review`-then-decline-again-at-`engineering-review`
    path ordinary rather than contrived. `GateDeclined` on
    `engineering-review` at T1 resets *validation's* window for that
    gate; a comment lands at T2; `GateApproved` on `ux-review` at T3
    is a resolution too, but not one naming `engineering-review`;
    `GateDeclined` on `engineering-review` again at T4 passes
    validation (the last resolution *naming* `engineering-review` is
    T1, and T2 postdates it) — but "the resolution before the most
    recent one," unfiltered, is T3, so the render folds since T3 and
    misses T2.

  - **Validation reads the aggregate's own state — no store read,
    because none is needed.** The aggregate keeps the "minimal state
    needed to reject a malformed sequence" for containers and nodes
    (its own moduledoc), and the same shape for gates: a project-wide
    comment counter, bumped by one on every `CommentPosted` it
    applies, and a per-gate mark of that counter's value as of each
    gate's last `GateApproved`/`GateDeclined`, recorded when `apply/2`
    folds that event. `DeclineGate`'s `execute/2` rejects unless the
    current counter is past the mark recorded for `cmd.gate` —
    answered by reading `state`, one of `execute/2`'s own two
    arguments. There is no
    `GateComments.any_since_last_resolution?/2` computing the same
    predicate by reading the log: a second copy of that fact standing beside the
    aggregate's own is the exact two-windows-that-can-disagree shape
    above — one predicate, and the aggregate is where it lives.
  - **`since_sequence` rides on the command.** `Commands.DeclineGate`
    carries a `since_sequence` field, computed by whatever constructs
    the command — the same command-edge boundary `posted_at` already
    crosses on `PostComment`, for the identical reason: an aggregate
    that computed it would be reading the store, and one that derived
    it from its own local counter would still be manufacturing an event
    field the moduledoc requires already be present on the command. The
    caller reads `GateComments.last_resolution_sequence(project_id,
    gate)` — a plain query, fine outside the aggregate — before
    dispatch; `execute/2` copies `cmd.since_sequence` onto the emitted
    `GateDeclined` unchanged, the same copy `CommentPosted` makes of
    `posted_at`.
  - **A caller-supplied boundary that has gone slightly stale is safe
    in the one direction that matters.** If a comment lands between the
    caller's read and the aggregate processing the command,
    `since_sequence` undercounts how recent the true boundary is — but
    undercounting only makes `CommentFeedback` fold from *earlier*,
    including comments already answered, never *later*, so the failure
    mode is extra context, not a blank render. A stale command racing
    an actual resolution of the *same* gate is the one case that could
    go the other way, and it cannot reach the aggregate:
    `DeclineGate`'s `expected_version` (§7.16's optimistic concurrency)
    rejects it outright, and the ordinary retry re-reads
    `GateComments.last_resolution_sequence/2` before trying again — the
    identical mechanism this doc already names for two humans commenting
    concurrently.

  Delivery reads this the same way it reads `engine_flows` and the
  ninth projection — through a query, never a second copy of the log's
  own facts; there is exactly one description of this mechanism, here,
  and `systems/delivery.md`'s entry points at it rather than restating
  it.
- **#53 The reset boundary is the resolution naming the gate, stamped on the `GateDeclined` that
  used it — never `DraftCommitted`, and never a position inferred from the global resolution
  sequence.** `CommentFeedback.since_last_resolution(project_id, node_id)` reads the most recent
  `GateApproved`/`GateDeclined` event in the project's log, unfiltered by which gate it names — Phase
  4's single pre-gate `generation` status is what makes "whichever gate" safe here — and if that event
  is a `GateDeclined`, folds every `CommentPosted` for `node_id` seen after its stamped
  `since_sequence`; if it is a `GateApproved`, or no resolution has happened yet, `feedback` is empty.
  "Consumed" means "rendered into every regeneration dispatched before the next resolution naming this
  gate, and gone the moment that resolution lands" — not "discarded by an unrelated draft commit," and
  not "discarded by an unrelated gate's own approval" either.
- **#54 Where the boundary is computed: the command edge, never `execute/2`.**

- **#55 A workflow gate's sign-off is two new commands landing on this aggregate, closing the
  mechanism `systems/delivery.md`'s ORC-32 entry left as "a later increment"** (ORC-34; the write path
  lands here rather than in Phase 7 because `docs/ui-spec.md` §2 rule 2 refuses a screen —
  `document-review`, ORC-75 — inventing protocol vocabulary the platform doesn't have, so
  `PostComment` and a decline command must exist before that screen can). `Catapult.Engine
  .Commands.ApproveGate{project_id, flow_id, gate, actor_id}` → `GateApproved`, and
  `Commands.DeclineGate{project_id, flow_id, gate, throwback_to, since_sequence, actor_id}` →
  `GateDeclined`, both v1, `since_sequence` caller-supplied per the harvesting entry above, both keyed
  by the `(project_id, flow_id)` composite `systems/delivery.md`'s own ORC-32 entry establishes for
  this aggregate's process-manager consumer (ORC-87). **`gate`/`throwback_to` legality — is `gate` a
  key of `workflow.gates`, is `throwback_to` earlier in the citing type's own effective sequence (the
  "earlier in the array" test `Catapult.Dsl.Workflow`'s own `gate_throwback_problems/2` runs at load
  time for a *declared* `throwback:` value, reused at the command edge as a runtime check, since
  ORC-115 makes the declared `throwback:` a single-target override on the derived default rather than
  the bound on legality, `docs/dsl-syntax.md` §15.10, §15.4) — is the command edge's to check, not
  `execute/2`'s**: the container commands this entry points to as precedent validate bundle content at
  their own dispatcher, `Catapult.Delivery.ContainerLifecycle`, and reject in `execute/2` only against
  the aggregate's own pure state — this aggregate's own moduledoc states that split ("never against
  bundle content, which the command edge already validated before dispatch") and `execute/2` loading a
  workflow bundle to check it directly would be exactly the impure read the harvesting entry above
  rules out for `since_sequence`, on the identical file this entry itself is recorded in. Whatever
  constructs `ApproveGate`/`DeclineGate` — ORC-75's screen — validates `gate` and `throwback_to` the
  same way `ContainerLifecycle` validates `MintContainer`/`AdvanceContainerQueue`, before dispatch.
  **A decline requires at least one comment; there is no free-text override.** `docs/ui-spec.md`
  §3.2's own `document -review` action set is "approve / throw back," target chosen from the gate's
  own declared `throwback:` when it names one, its derived default otherwise, or the earlier-prefix
  picker for anything else (ORC-115, `docs/dsl-syntax.md` §15.4) — no reason field — so the screen
  this command answers to specs exactly the simpler rule: `DeclineGate` is rejected outright,
  synchronously, at the point of action, when the aggregate's own comment counter has not advanced
  past the mark it recorded for `gate` at that gate's last resolution — pure aggregate state, no store
  read; the harvesting entry above has the mechanism and the reason it is not
  `GateComments.any_since_last_resolution?/2`, a store read `execute/2` may not make. `since_sequence`
  on the emitted `GateDeclined` is `cmd.since_sequence`, copied rather than computed, for the
  identical reason — the caller populates it from `GateComments .last_resolution_sequence(project_id,
  gate)` before dispatch, and the same entry covers why that stays safe even when the read has gone
  slightly stale by the time the aggregate processes the command. **Project-wide, not flow-scoped, on
  purpose**: `CommentPosted` carries no `flow_id`, and `systems/delivery.md`'s own `FeaturePublisher`
  entry already leans on "nothing yet opens two flows concurrently on one project" to resolve a flow
  from a bare `project_id`; this reuses that exact standing simplification rather than inventing a
  second one, and carries the identical Phase 7 revisit condition — multiple concurrent flows per
  project need `CommentPosted` to carry `flow_id` too, not a new check here. **This is a rejection the
  aggregate makes, not the view**: `docs/ui-spec.md` §2 rule 1 and this doc's own "the rejection lands
  at the point of action" already rule out a UI-side check as the arbiter for any command on a surface
  we own; a decline attempt with no comments yet is simply invalid input to `DeclineGate`; ORC-75's
  screen surfaces that rejection synchronously, the same as any other compare-and-swap failure, but
  does not perform it.

- **#56 `prior_review` needs a new `Store.reviews_for_node/2`, project-
  scoped per ORC-87 from the start — not the existing `reviews_for_draft
  /1` the pre-review draft leaned on, which answers a different
  question and stays exactly as bare-id as it already was, a real gap
  ORC-87's own audit missed** (ORC-34; the "audit's first pass missed
  it" pattern this doc's own ORC-87 entry records for `engine_drafts`'
  second key, here at a call site rather than an index).
  `reviews_for_draft(draft_id)` stays, bare id and all, because the
  review-tier dispatch rule above needs exactly what it
  answers — does *this* draft have a review yet — and threading
  `project_id` through it is real but separate cleanup. What
  `prior_review` needs is a different query `reviews_for_draft/1`
  cannot answer — "the same slot doing different jobs," with one of
  the two jobs otherwise left blank: reading by
  `draft_id` returns nothing until *this* draft has been reviewed,
  which is always true for a freshly regenerated draft and for the
  review tier about to review it for the first time — exactly the case
  where "what I said last time" is the whole point. `Store
  .reviews_for_node(project_id, node_id)` joins `engine_reviews` to
  `engine_drafts` on `project_id` **and** `draft_id`/`id` together —
  carrying `project_id` on both sides of the join predicate itself,
  not just in the function's own arguments, which is the exact spot
  the ORC-87 gap named above is actually won or lost — filters
  `engine_drafts.node_id`, and orders by `inserted_at` descending,
  project-scoped from the moment it's written rather than retrofitted.
  Both the
  regenerating generation tier and the review tier re-run after it read
  the same most-recent row — the node's last review, whichever draft it
  landed against — which is never empty once the node has been reviewed
  once, on either caller. A node never yet reviewed still renders
  `prior_review` blank via Solid's own unset-is-empty behavior.
  **The row carries `body_sha`** (`Store.Review` already has
  the field — `write_review`/`ReviewWritten` set it from the draft they
  reviewed) **and `reviews_for_node/2` renders it**, so a prompt reading
  `prior_review` can tell whether the review it sees applies to the
  node's current committed body or a superseded one; without it,
  nothing distinguished "what I said about the body you're now
  regenerating from" from "what I said about a body two commits ago,"
  which the deliberate cross-draft read above makes possible
  (`feedback`'s own entries carry the same kind of
  provenance — `posted_at` against the log's own ordering).

- **#57 `ApproveGate`/`DeclineGate` carried no compare-and-swap, which is a defect against §7.16's
  own rule, not an open question — found reading the code against the rule, not filed as a finding by
  either of the two tickets that already dispatch these commands** (ORC-114; two compares, because
  there are two distinct staleness questions — the second is below).

  The aggregate gains two project-wide fields beside `comment_count`/
  `gate_marks` above, on the identical simplification those two already
  state and revisit-condition: **`gate_resolutions: %{String.t() =>
  :approved | :declined}`**, absent key meaning "open." `execute/2` for
  `ApproveGate`/`DeclineGate` rejects when `cmd.gate` is already a key —
  `{:error, {:engine_gate_already_resolved, gate: cmd.gate, disposition:
  existing}}`, the same "name the value, not the actor" level of detail
  `:engine_container_queue_conflict` already gives (a screen wanting who
  reads the log the same way `document-review`'s own conflict rendering
  already would). `apply/2` for `GateApproved`/`GateDeclined` sets the
  key to the disposition; `apply/2` for `DraftCommitted` clears the
  whole map — a fresh commit reopens every gate, the identical fact
  `Catapult.Delivery.FeatureLifecycle.Projection.commit/2` already
  encodes on the delivery side (below), tracked here independently and
  for the same reason the container's own copy of `queue` is: "this
  copy exists only so `execute/2` can reject without a read." Project-
  wide rather than flow-scoped is the same call `CommentPosted` above
  already made and for the same reason — `DraftCommitted` carries no
  `flow_id`, "nothing yet opens two flows concurrently on one project"
  is exactly as true here as it was there, and the identical Phase 7
  revisit condition applies: multiple concurrent flows need this keyed
  by `{flow_id, gate}`, not a new mechanism.
- **#58 The shape to copy is already in this file.** `AdvanceContainerQueue` matches `%{state:
  :active, queue: current} when current == cmd.from_queue` and carries `from_queue` on the command for
  the identical reason §7.16 gives: first writer wins, a stale `from` is rejected rather than applied.
- **#59 The compare token is status, not version — §7.16's "compare token: version, not status"
  item, settled in favor of the recorded rule by the first mechanism the item is about.**
  `gate_resolutions` is a named-value compare (`:approved | :declined | absent`), the same
  status-shaped kind `AdvanceContainerQueue`'s `queue` already is, not the aggregate's Commanded
  stream version — following "Author's call: the rule as stated compares on status" (§7.16) and the
  precedent already in this file, over the ABA risk the item itself names and leaves open.
- **#60 The second compare is the one already in this file: `PostComment`'s own `body_sha` compare,
  on the same two commands.** `ApproveGate`/ `DeclineGate` carry `node_id` and `body_sha`, the
  identical pair `PostComment` already carries and for the identical reason — `execute/2` rejects when
  `cmd.body_sha` doesn't match `nodes[cmd .node_id].body_sha`, the same per-node value
  `DraftCommitted`'s own `apply/2` already maintains (that's what makes `PostComment`'s existing check
  possible with no new aggregate state): `{:error, {:engine_stale_gate_resolution, node_id:
  cmd.node_id, current: current, got: cmd.body_sha}}`, `:engine_stale_comment`'s own shape reused
  rather than invented. This runs beside `gate_resolutions`, not instead of it — the two guard
  different failures: `gate_resolutions` rejects a second writer racing the first on one still-open
  resolution, `body_sha` rejects a resolution whose view is a body the aggregate has already moved
  past, resolved or not. Which `node_id`: Phase 4's own shipped `feature.yaml` runs exactly one
  `generation` status ahead of its gates (already named above), so the command edge —
  `document-review`, ORC-75 — has exactly one node to read `body_sha` off; the general
  node(s)-per-gate mapping stays open, as the rest of this entry leaves it, not a second deferral.
- **#61 Verify by breaking it, per orchestration's own rule for a guard rather than a feature**: two
  probes, not one. Revert `gate_resolutions`' compare and watch a regression test exercising two
  racing `ApproveGate`s (or an `ApproveGate` racing a `DeclineGate`) fail; separately, revert the
  `body_sha` compare and watch a test exercising decline → regenerate → stale approve fail — the exact
  sequence the second axis above walks. Read each failure, put each compare back, record both probes
  in the commit message; the expectation travels with the decision rather than being invented at
  review time.

- **#62 Unblocking a limit-class failure gains a real command — a human action, not only a
  regeneration retry** (ORC-114, design pass).

  `Catapult.Engine.Commands.ResumeFlow{project_id, flow_id, to,
  actor_id}` → `Catapult.Engine.Events.FlowResumed{project_id, flow_id,
  to, actor_id}`, both v1, dispatched through the same router and
  landing on the same per-project aggregate as every other command
  here — an original protocol fact ("a human chose to resume this
  ticket at this position") nobody else in the log records, the
  identical ground `GateDeclined`/`CommentPosted` already stand on.
  `to` is the chosen return position (`Sequence.position()`-shaped,
  `systems/delivery.md`); validating it against the effective-sequence
  prefix up to and including the ticket's own `blocked_origin` — "never
  forward" (`docs/ui-spec.md` §6) — is the command edge's job, the
  identical division `gate`/`throwback_to` already draw: bundle- and
  projection-derived content is checked before dispatch, never inside
  `execute/2`.

  `Catapult.Engine.Router` gains `ResumeFlow` in its dispatch list,
  beside `ApproveGate`/`DeclineGate`, with the same comment marking it
  part of this ticket's edge. Role authorization (does this `actor_id`
  own the blocked ticket's origin status) is left exactly where every
  other gate-adjacent command already leaves it — identity's, Phase 7.
- **#63 The compare-and-swap is the same mechanism as the gate fix above, scaled down further: a
  gate has one precondition; being blocked has one too.** The aggregate gains a third project-wide
  field, `blocked: boolean`, `false` by default. `apply/2` for `RunFailed` sets it `true` —
  unconditional, since every `RunFailed` this system's own event already is limit-class by
  construction (its moduledoc: "a dispatched agent run failed on a limit-class error"), so there is no
  second failure class to distinguish here the way there was for a gate's disposition. `apply/2` for
  `FlowResumed` and for `DraftCommitted` both set it `false` — a retry and a human resume clear the
  same fact, the identical pair `Projection.commit/2` already clears on the delivery side. `execute/2`
  for `ResumeFlow` rejects unless `blocked == true`: `{:error, {:engine_flow_not_blocked, flow_id:
  cmd.flow_id}}` — a stale resume attempt (someone else already resumed it, or a retry already landed)
  reads identically to "never was blocked," which is enough for the rejection to be correct without
  the aggregate having to retain who resolved it, the same level of detail the gate fix settled on
  above. Project-wide, not flow-scoped, for the identical reason and the identical Phase 7 revisit
  condition as `gate_resolutions` and `comment_count` before it: `RunFailed` carries no `flow_id`
  either.

- **#64 `ApproveDraft`/`DiscardDraft` gain a dispatcher and the identical
  compare-and-swap `ApproveGate`/`DeclineGate` needed** (ORC-229).
  Both commands were registered and validated but had no
  production caller anywhere in `lib/**`: `Catapult.Delivery
  .FeatureLifecycle`'s `GateApproved`/`GateDeclined` handling
  (`systems/delivery.md`) already advances a ticket's projected status,
  but neither event ever touched `Node.status`, so a node reached
  `:drafted` and stayed there and `ReadyScopes.ready/3`'s
  `Enum.all?(targets, &(&1.status == :approved))` never turned true for
  anything downstream of it (dsl-syntax.md §7). The fix is at the
  dispatch side, not the read side — the identical shape ORC-117's
  join-target fix above takes. A process manager,
  `Catapult.Delivery.DraftResolution` (`systems/delivery.md`, below),
  reacts to `GateApproved`/`GateDeclined` and dispatches
  `ApproveDraft`/`DiscardDraft` against the flow's own reviewed node —
  Phase 4's standing "one node per flow" simplification
  (above, and `systems/delivery.md`'s ORC-34 entry). Both events' own
  `actor_id` threads onto the resulting
  command unchanged, so `DraftApproved`/`DraftDiscarded` carry who
  acted the same way `ApproveGate` already does — v5 §7.19's "who
  approved is answerable from the object" holds for a draft the
  identical way it already holds for a gate.
- **#65 Approve only when the resolving gate is the review group's own last one; decline discards
  unconditionally.** A gate's own citing sub-array (dsl-syntax.md §15.10) may hold more than one
  `review:` entry ahead of `checks` — `feature.yaml` ships two, `ux-review` then `engineering-review`,
  both reviewing the same single node (Phase 4's own mapping, above) — and marking the node
  `:approved` the moment the first of them passes would let a downstream context walk dispatch before
  the ticket's own required second sign-off ever ran, which is not what "readiness requires all
  targets ready" is supposed to mean. So `ApproveDraft` dispatches only when `GateApproved`'s own
  forward advance leaves the citing sub-array — the identical `leaves_group` computation
  `Catapult.Dsl.Workflow .throwback_target_details/3` already derives for a throwback target
  (`lib/catapult/dsl/workflow.ex`), read here in the forward direction instead; an earlier gate's
  approval only advances the ticket's own projected status. A decline is not the same shape: every
  `review:` entry in a `generation`/`critique`/ review group falls back to the same leading `pending`
  (§15.10, the rule `screens/document-review.md` cites), so any `GateDeclined` against the node
  dispatches `DiscardDraft` unconditionally — there is no partial-decline case where the draft should
  survive.
- **#66 `DraftDiscarded` resets the node to `:absent`, not a fourth status.** `Node.status` keeps
  the same three values ORC-117 fixed it at — `Reducer.apply(%DraftDiscarded{}, _)` clears the
  projection's `current_draft_id`/`body_sha` alongside `set_draft_status(:discarded)`, and writes
  `status: :absent`, the identical value a never-drafted node carries. This is the whole mechanism for
  "how a decline reopens a node for regeneration" (above): `ReadyScopes.ready/3`'s own candidate
  filter reads `node.status == :absent` and needs no change, the same "write the correct value at the
  transition, not a new branch at the read" precedent ORC-117 set. The aggregate's own in-memory
  `pending_draft_id` is cleared on `DraftDiscarded` the same way; the projection's reset is its
  equivalent.
- **#67 `ApproveDraft`/`DiscardDraft` carry the compare-and-swap §7.16's own rule requires, the same
  one ORC-114 gives `ApproveGate`/`DeclineGate`.** Without it, `execute/2` for both commands would
  read no aggregate state at all and emit unconditionally on a replay or a duplicate dispatch — moot
  while nothing dispatches them, live the moment a process manager does, since a process manager's own
  event handler can itself be replayed. Both take `PostComment`'s own shape:
  `execute(%__MODULE__{nodes: nodes}, %ApproveDraft{} = cmd)` rejects unless
  `nodes[cmd.node_id].pending_draft_id == cmd.draft_id` — `{:error, {:engine_stale_draft_resolution,
  node_id:, current:, got:}}` otherwise, `:engine_stale_gate_resolution`'s own shape reused rather
  than invented — and `DiscardDraft` takes the identical guard. A duplicate dispatch of either command
  against a node already moved past that draft (approved, discarded, or superseded by a fresh commit)
  is a rejection, not a second event.
- **#68 The review score stays parked.** Nothing here reads `ReviewWritten.score` —
  `docs/dsl-syntax.md` §15.10's "a parked scheduler item, §7.19, not bundle content" stands, and
  `ApproveDraft` dispatches only off a human's `GateApproved`, never off a review tier's own automated
  pass.

## #69 Initial vs target

Initial (Phase 3): event log, reducer for the design dialect's event
set, core projections — including the active-bundle-version
projection above, decided now though no cutover exists yet to
exercise it — scheduler + sweeper, and the EventStore infrastructure
migration this needs to run at all. That migration's path,
`priv/repo/migrations_infra/**`, is `systems/foundation.md`'s mapped
file, not this doc's (this doc's own map above stops at
`lib/catapult/engine/**` and `test/catapult/engine/**`) — the need is
engine's, the file is foundation's, so this ticket carries
`system:foundation` alongside `system:engine`, matching
`foundation.md`'s own Initial-vs-target note that the migration lands
"with engine." Target: flow instances, staleness provenance,
snapshots, replay tooling surfaced in the dashboard.

**The engine's own store tables live at `priv/repo/migrations/**`**,
added to this doc's file map by the same ticket. Distinct from
`priv/repo/migrations_infra/**` (foundation's, for EventStore/Oban):
these are ordinary per-store domain tables (`engine_nodes`,
`engine_edges`, ... — conventions §6), and `priv/repo/migrations` is
Ecto's own default path, so nothing but foundation's is under
`_infra`. `staleness` and `ready_scopes` are deliberately absent from
that migration and from any table: both are pure queries
(`Catapult.Engine.Projections.Staleness`/`.ReadyScopes`), never
materialized, per this doc's own standing decision above.

## #70 Depends on

substrate, foundation (EventStore infra), core_dsl (bundle semantics
the reducer is generic over).
