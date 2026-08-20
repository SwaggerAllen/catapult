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

## Standing decisions

- **The log is the source of truth; projections are derived and
  disposable.** Rebuild-from-zero byte-identity is a standing test
  (v4 §A.3.2 carried forward): replaying the full log into fresh
  projections must equal incremental state, always. This is also the
  recovery mechanism — no projection surgery, ever.
- **The scheduler is state-driven, not event-driven** (v4 §A.2.7):
  readiness is a query against current projections, so the same
  query answers "ready now" and "ready at sequence T," and there is
  no in-memory pending-set to corrupt. Fast path via PubSub;
  sweeper as the convergence floor.
- **"Write the ready_scopes row" (v4 §A.2.7's rule 3) is a PubSub
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
- **The scheduler dispatches to no component by name.** Generation and
  delivery both land after this ticket in the build order
  (`docs/build-plan.md` Phase 3/4), so the scheduler cannot call an
  enqueue function that doesn't exist yet and must not be built to
  assume one particular shape for a consumer that hasn't landed.
  "The engine writes it; generation and delivery consume it" (below)
  is a claim about which side owns the *readiness signal* — engine,
  exclusively, which is what makes "nothing else initiates work" true
  — not about the engine performing generation's or delivery's own
  outbox insert. When each consumer lands, its own ticket names the
  cross-component edge, and conventions §7's pattern ("insert the job
  through the target's exported enqueue function inside the local
  transaction") applies on *its* side of the subscription, not this
  one's.
- **Review-tier dispatch is a second, simpler readiness rule, not an
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
- **`scope_filter` is evaluated where readiness is, and answers a
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
- **Explain-why is `ReadyScopes`'s own second query, not a parallel
  implementation.** "What is blocking this scope"
  (`systems/dashboard.md`'s naming) reuses `candidates/2` and the same
  per-walk resolution `ready?/2` already does, replacing the boolean
  fold with a structured report: which context-walk entry is unmet,
  and for each of its resolved targets, its current status. Built
  beside readiness because both read the same candidate/target
  machinery — a second traversal implementation is the drift risk, not
  the convenience.
- **Navigation edges get no second check in the engine.**
  `Catapult.Dsl.Chain` already refuses to load a context walk that
  traverses a `navigation: true` edge (dsl-syntax.md §4, §13) — the
  readiness and explain-why queries walk only what the loader already
  proved is readiness-bearing, and add no redundant edge-kind filter of
  their own. Restated here because a query written defensively
  (checking a property its input already guarantees) is exactly the
  kind of drift-prone duplication `core_dsl.md`'s "all validation at
  load time where possible" standing decision exists to prevent.
- **Creation is not dispatchability, and the engine needs no new node
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
- **Sweeper cadence defaults to 30s, `tunable`** (v5 §7.10's bindings
  surface, same mechanism as every other marked threshold) — enough
  headroom that a burst of events doesn't turn the convergence floor
  into a second fast path, short enough that a lost PubSub message
  (process crash, netsplit) is invisible within one dispatch cycle in
  practice. **`staleClaimGrace` (§7.16's still-open item) is not this
  constant** — it measures ticket-claim staleness on the delivery/
  tracker side (`max(Run.EndedAt, StateSince)`), a different clock for
  a different job, noted so the two are not conflated by a later pass
  reaching for "the scheduler's timer" and finding two candidates.
  §7.16's item stands exactly as recorded; nothing here resolves it.
  **A tick walks its projects serially, not fanned out.** `Catapult
  .Repo`'s pool is a shared, finite budget, not this ticket's alone to
  spend — SETUP.md §2 sizes it (`FOUNDATION_POOL_SIZE=4`) against the
  projector's writes, Oban's workers as queues land, the health check,
  *and* this sweep together, on the one reference cluster this code
  deploys to. `Task.async_stream`'s default width
  (`System.schedulers_online`) is the idiomatic move and the wrong one
  here: on a run of any real size it alone can reach for more
  connections than the pool holds, ahead of a request the pool exists
  to serve. One project at a time keeps a tick's own footprint at a
  single checked-out connection regardless of how many projects exist,
  which is affordable at 30s cadence because a readiness query is
  cheap and the floor's whole job is convergence, not speed. Revisit
  condition: a measured tick duration exceeding the cadence at real
  project counts — the fix then is a bounded width stated as a number
  here, never the default.
- **The sweeper is a distinct registered process and declares
  `:singleton` placement, the same kind `engine_projector` already
  uses** (v5 §2.5) — not, as first sketched, `:local`. The fast path
  is not a second process to place: "on each trigger the scheduler
  re-runs `ReadyScopes.ready/3` ... and broadcasts" (above) rides
  inside `Catapult.Engine.Projector.handle/2`, which already runs
  cluster-wide singleton by construction (a Commanded event handler
  subscription is consumed once, in order, or replay guarantees break)
  — so the fast path was never a placement question and this bullet is
  only ever about the timer loop. `:local` was argued on
  redundant-computation grounds alone (a stateless read costs cycles,
  not correctness, if every node repeats it) without pricing what
  "every node" costs against a pool sized in the single digits: a
  rolling deploy runs two full instances briefly, and `:local` turns
  one sweep into two, against the same budget the paragraph above
  already spends down to one connection per tick. `:singleton` removes
  the doubling by construction — one sweeper cluster-wide, like the
  projector beside it — rather than accepting it and arguing the size
  is fine; the two processes now share one placement rule for one
  reason (each must run exactly once, not once per node) instead of
  each defending a different number. Registered via `processes/0`
  like any other named process.
- **Every table in the engine store keys by `(project_id, id)`, not
  `id` alone** — a decision this ticket settles rather than hands
  back, because `ReadyScopes.ready(chain, project_id, tier)` is the
  first thing to query `engine_nodes` *by project*, and the answer
  changes which index shape is even correct. ORC-6's migration fixed
  the id column's *type* at `:string` rather than `:binary_id`
  deliberately, to leave the id *scheme* open ("a deterministic,
  content-addressed slug is an equally legal id") — but it fixed the
  *primary key* to `id` alone in the same migration, which only one of
  the two legal schemes actually supports. A caller-supplied string
  being unique across every project the plane will ever build is not a
  constraint anyone picks on purpose; `scope_key` and `handle` are
  already how a node is addressed *within* a project
  (`dsl-syntax.md` §3), and nothing about the command edge or a
  bundle's own vocabulary promises more than that. The evidence
  agrees: four `async: true` test modules deadlocked on shared bare
  ids (`"sysarch"`, `"comp1"`, `"n1"`) before this pass, on nothing
  more than ordinary human-readable names two authors independently
  reached for; the fix that landed (per-module id prefixing) makes the
  suite pass without saying whether two real projects can collide the
  same way, because it works around the schema rather than correcting
  it.

  So the key moves to `(project_id, id)`, and `engine_nodes
  .parent_node_id`'s self-reference becomes a composite foreign key
  against the same pair. The same shape recurs on every sibling table
  this migration created (`engine_edges`, `engine_fragments`,
  `engine_drafts`, `engine_reviews`, `engine_flows`,
  `engine_active_bundle_versions`): each keys by a caller-supplied
  `id` alone today (an edge's `"fulfills|comp|resp"`, a draft's
  `"draft-comp1-1"`, a bundle flip's `event.flip_id`), built the same
  way from the same project-scoped vocabulary, so each carries the
  identical collision risk whether or not a test has tripped over it
  yet. `engine_edges`, `engine_fragments`, `engine_drafts` and
  `engine_flows` each hold a `references(:engine_nodes, ...)` on a
  single column (source/target, owner/author, node_id, entry_node_id);
  `engine_reviews` holds one on `engine_drafts.id` instead. Every one
  of those stops being a legal foreign key the moment the table it
  points at gains a key column — so a fix confined to `engine_nodes`
  alone does not migrate cleanly: it composite-keys the whole store in
  one migration, or the foreign keys don't resolve. This is not a
  broadening of this ticket's scope: `priv/repo/migrations/**` is
  already this doc's mapped path (ORC-6) and every one of these
  tables is already this ticket's file to touch — it is what
  "composite key" turns out to mean once the foreign keys are followed
  to their source. Writing the migration and updating every call site
  that reads a node by id alone (`Store.get_node/1` included) is
  dev's, as with every decision in this doc; this pass settles the
  shape, not the diff.

  **Confirmed (ORC-87): the id is a per-project slug, not globally
  unique by construction.** The alternative was still live going into
  this ticket — ORC-6 fixed the id column's type at `:string`
  specifically to leave either scheme legal, and no command edge has
  landed yet to mint one over the other. Nothing since has weakened
  the case above, and the evidence sharpens it: the deadlock this
  pass was filed about was not a test artifact but ordinary bundle
  authoring — two independently-written test modules each reaching
  for `"sysarch"`, `"comp1"`, `"n1"` on nothing more than a plausible
  name, exactly as a bundle's own tier/scope vocabulary would.
  `scope_key` and `handle` are already how a node is addressed
  *within* a project (`dsl-syntax.md` §3); a globally-unique scheme
  would have to either reopen the UUID door ORC-6 deliberately left
  shut, for no gain the DSL asks for, or lean on bundle authors to
  hand-prefix every id with the project — a convention nothing
  enforces, and the evidence above is two authors already not
  following it by default. Per-project slugs, kept.

  **Composite primary keys are necessary and not sufficient — a
  second class of key, not the primary key, is not project-scoped
  either, and the migration above does not touch it.** `engine_edges`
  carries its own idempotency key distinct from its primary key: the
  unique index `(edge_name, source_node_id, target_node_id)` that
  `Store.insert_edge/1` upserts against
  (`conflict_target: [:edge_name, :source_node_id, :target_node_id]`),
  there so a replayed `produces:` edge lands the same row rather than
  a duplicate. It carries no `project_id` column. Two projects each
  declaring an edge under the same name between two identically
  spelled node ids — plausible now, since ids are project-scoped
  slugs rather than globally unique ones — collide on this index:
  project B's edge is either rejected on the unique constraint, or,
  since the upsert is `on_conflict: :nothing`, silently dropped as an
  apparent replay of project A's, leaving project B's graph missing an
  edge with no error anywhere. This index becomes `(project_id,
  edge_name, source_node_id, target_node_id)` in the same migration
  that composite-keys the table. `engine_fragments` needs no
  equivalent fix: it carries no separate unique index today —
  `Store.insert_fragment/1` upserts on its own `id`
  (`conflict_target: :id`, built the same `owner_node_id|kind
  |author_node_id` way an edge's id is built from
  `edge_name|source|target`) — so folding `project_id` into that same
  column's primary key, which the migration above already does for
  every table, closes this table's gap for free; there is no second
  index here to widen.

  **The call sites this migration strands, and the shape of their
  fix.** This ticket's own list — `Store.get_node/1`,
  `Store.edges_from/2`, `Store.approve_node/1`,
  `ContextResolver.landings/2`, `PredicateEvaluator.walk/2` and
  `.bfs/4` — is not quite complete: `ContextResolver.parent_of/1`,
  `Store.edges_to/2`, `Store.edges_from/1` (the unrestricted-reaches
  arity) and `PredicateEvaluator.outgoing/2` read `engine_nodes` or
  `engine_edges` by bare id the same way and are strung through the
  same callers, so the fix is one shape applied consistently rather
  than a list to work through case by case. None of it is a fresh
  design question: every caller already holds a `project_id` in
  scope — the reducer's `event.project_id` on every branch
  (`DraftApproved` included), and every `ContextResolver`/
  `PredicateEvaluator` entry point anchored on a `Node.t()` that
  already carries its own `project_id`. So: thread the caller's
  already-available `project_id` into each `Store` function above and
  scope its query by it — no new lookup, nothing that isn't already
  sitting in the caller's hand — and update `engine_edges`'
  `conflict_target` to match the widened index. Dev's, per this doc's
  standing practice; recorded here so the shape is settled before the
  diff, not discovered mid-diff. (`lib/catapult/engine.ex`, the
  component root, calls none of this directly and needs no change for
  this fix — checked, not assumed, since that file sits outside this
  doc's own path glob and outside `systems/README.md`'s unowned list,
  a gap this ticket flagged without closing.)

  **Retire the per-module test id namespacing once this lands.** The
  `@ns`/`nid/1` prefixing in `context_resolver_test.exs`,
  `ready_scopes_test.exs`, `staleness_test.exs` and
  `reducer_test.exs` — added to stop an `async: true` cross-module
  deadlock on shared bare ids — exists only because ids collide
  across modules standing in for projects the same way two real
  projects would collide. A composite `(project_id, id)` key (and,
  for `engine_edges`, the widened unique index above) makes two test
  modules' identical bare ids exactly as safe as two projects' would
  be, which is the property this whole entry exists to guarantee, so
  the workaround has no remaining reason to exist. Dev's diff removes
  it in the same change: a workaround left standing after its cause
  is fixed reads as a rule to the next author, not as history.
- **Purity floors are absolute in this system**: no clocks,
  randomness, or generated ids in aggregate/reducer/projection code;
  inject at the command edge. Enforced by the substrate's call-graph
  audit check, which this system is the reason to build.
- **`ready_scopes` is the plane's dispatch source** (v5 §1.2's
  inversion) — the engine writes it; generation and delivery consume
  it; nothing else initiates work.
- **Events are versioned and upcast on read** (v5 §2.4): shapes are
  immutable contracts; changes are new versions with pure upcasters
  registered beside the reducer; the log is never rewritten; replay
  fixtures retain every historical shape. Built into the ES family
  from the first event, because retrofit means a broken replay.
- **The reducer resolves bundle semantics per event, from the log —
  never from whatever `core_dsl` currently has loaded.** The active
  bundle can flip mid-log, on either axis (v5 §6/§7.19;
  `core_dsl.md`'s cutover decision), and rebuild-from-zero must equal
  incremental state *always*, a flip included. A reducer that asks
  "what bundle is loaded right now" would apply today's semantics to
  yesterday's events on rebuild and diverge from what actually
  happened. So the flip events fold into their own small per-axis
  projection — current bundle version, and the sequence it became
  current, two rows per project — and the reducer consults that
  projection, in log order, exactly like every other event; it never
  reads `core_dsl`'s loaded state mid-fold. This is also the
  engine-side half of the join `core_dsl.md` already promises
  delivery's Phase 7 re-resolution (a blocked ticket's status history
  against the bundle-version timeline): the timeline is this
  projection, so delivery reads it rather than re-deriving one of its
  own. Built in from Phase 3 on the `events/0` precedent above: the
  discipline costs nothing before a cutover exists and is a broken
  replay to retrofit after one has landed. **A ninth projection, not
  a port** — the intro paragraph names eight; this one exists because
  the other eight can't be replayed correctly across a bundle flip
  without it, not because the ticket asked for it by name.
- **Staleness is a projection, never stored state** (v5 §7.11): a
  node is stale when its committed content predates the inputs its
  context walk reads — computed from the log on demand, consumed by
  flow walks and the plane's out-of-band ticket filing. No stale
  flag is ever written, and no pending work attaches to nodes;
  pending work is always a ticket.
- **A review tier needs no staleness treatment — but this does not
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
- **Snapshot cadence and stream partitioning carry the v4 defaults
  forward, unmoved.** Stream partitioning: one EventStore stream per
  project, the Commanded aggregate identity being the project id (v4
  §C.3) — already implied by "per-project aggregates" above, stated
  explicitly here because the ticket asked; both axes' events land in
  the same project stream; a project has one aggregate, not two.
  Snapshot cadence: every 10,000 events per project (v4 §A.3.6).
  Neither is built in Phase 3 (snapshots stay Target, below), but the
  value is decided now rather than left for whoever builds them —
  snapshots are disposable projections like any other (v5 §8's
  cold-storage rider agrees), so a wrong cadence costs a resweep, not
  a migration, and there is no reason to leave it unstated in the
  meantime. Revisit condition: measured per-project event volume
  disagreeing with v4's assumption enough to matter — nothing has run
  long enough yet to measure it.

## Initial vs target

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

**ORC-6's own diff stops short of the scheduler and sweeper**, despite
both being named Initial above. The ticket's own scope paragraph
enumerates "the Commanded application, per-project aggregates and the
event log, the reducer generic over bundle semantics, and the
universal projections" and names none of the reactive-runtime pieces;
`ready_scopes` and staleness land as this ticket's `Catapult.Engine
.Projections.ReadyScopes`/`.Staleness` — pure queries against current
projections, exactly the "state-driven" shape the scheduler standing
decision above describes — so a later ticket's scheduler process has
something to call rather than something to build from scratch. Filed
here rather than silently: this is a deviation from this doc's own
Initial line, argued for in ORC-6's hand-back.

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

## Depends on

substrate, foundation (EventStore infra), core_dsl (bundle semantics
the reducer is generic over).
