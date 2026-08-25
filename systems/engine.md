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

  **`engine_drafts` carries the same class of second key, and this
  audit's first pass missed it** — corrected here rather than left to
  stand: `engine_drafts_one_pending_per_node` is a partial unique
  index on bare `node_id` (`where: status = 'pending'`), enforcing "at
  most one pending draft per node" project-globally rather than per
  project, the identical shape to the `engine_edges` gap above. Two
  projects each minting a node with the same id, each calling
  `Store.insert_draft/1` to open a pending draft for it: the first
  succeeds, the second raises `Ecto.ConstraintError` on this index,
  unhandled — worse than the `engine_edges` case, because
  `insert_draft/1`'s `on_conflict: :nothing` names
  `conflict_target: [:project_id, :id]` as its arbiter, which
  suppresses conflict on the primary key alone and does nothing for a
  separate unique index the same insert also violates. Widened to
  `(project_id, node_id)` in the same migration, same shape as the
  edges fix. The audit that closes this section is per-table, not
  per-index: every non-project-scoped unique index has to be found,
  and `engine_edges` and `engine_fragments` being checked first did
  not mean the remaining five tables carried none — `engine_drafts`
  did.

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

- **Container and workflow-axis lifecycle events land on the same
  single per-project aggregate, not a second one** (ORC-104, design
  pass; `docs/dsl-syntax.md` §15.6-§15.8, `docs/v5-design-decisions.md`
  §7.8, settling what `systems/delivery.md`'s three ORC-105 entries
  left as "not yet built... this system owns"). A container instance's
  mint, its activation, each move of its current queue — forward past
  a resolved gate, or backward when a queue's population refills or a
  cited gate throws back (§15.8) — a carried finding's filing or
  decline, and a milestone's flag-set flip are none of them derivable
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
  validation — a singleton queue's lifetime bound, a queue-advance
  naming a declared anchor, a `blocks:` relation — reads the loaded
  `Catapult.Dsl.Workflow.t()` the identical way the reducer already
  resolves bundle semantics from the log rather than from whatever
  `core_dsl` currently has loaded (above); this system already depends
  on core_dsl for exactly this, so no new dependency edge is needed.

  **This is the first command edge into this aggregate that isn't this
  system's own.** Deciding *when* a queue has emptied or a `blocks:`
  sibling has cleared, and issuing the command, is
  `systems/delivery.md`'s new queue dispatcher; this system only
  validates and records what it's told, exactly as "engine is state of
  record, delivery is the protocol interpreting it" already reads in
  that doc. The split is not new in kind, only new in direction — every
  writer into this aggregate so far has been this system's own command
  edge, not another system's process manager. It does not reopen "the
  scheduler dispatches to no component by name," several bullets up:
  that invariant is scoped to the chain-axis generation signal
  (`ready_scopes`) specifically, and stands exactly as written — a
  queue's resolved `flow:` that turns out to open ordinary ticket work
  still dispatches through the existing `OpenFlow` path, driven by
  nothing but `ready_scopes`, unchanged.

- **Membership is derived by reference, never a stored list — the
  queue-as-query principle applied one level up** (ORC-104, design
  pass; ORC-105's grammar, `dsl-syntax.md` §15.6-§15.7,
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

  **The dev pass found membership needed a version bump, not a new
  table, and that is worth recording where the upcasting discipline
  is.** `container_id` and `queue` are set once, at open — which means
  they are fields on the event that opens a work item, so
  `Catapult.Engine.Events.FlowOpened` is version 2 and
  `FlowOpenedV1` joins `ReviewWrittenV1` as a frozen historical shape
  with an upcaster (v5 §2.4). The upcast fills both with `nil` rather
  than backfilling a guess: a version-1 event was written before
  containers existed, so the work item it opened was genuinely a member
  of nothing, and a guessed container would have made an unowned work
  item silently count into some queue's population — the one failure
  the queue-as-query has no way to notice.

- **`CommentPosted` (v1, explicit) is a new `events/0` entry, and a
  human review comment is an original protocol fact on this same
  aggregate, not a second one** (ORC-34, design pass, revised on
  design review — the FeedbackBucket cache the first draft proposed is
  gone; see the correction below for why). It joins
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

- **Harvesting is a query against this log, not a second table — the
  identical shape `Catapult.Engine.Projections.RunFailures` already
  established for a different derived fact, corrected onto here after
  design review found the first draft's cache reopened the exact
  silent-failure risk it claimed to close** (ORC-34, design pass,
  design-review correction). The reopened risk, named precisely: a
  cache table is written asynchronously by whatever process reacts to
  a decline, while the *sweeper* that would dispatch a regeneration is
  timer-driven and reads readiness from projections the same reducer
  updates independently (`Catapult.Generation.Sweeper`) — nothing
  orders the two, so a sweep tick landing between "the gate declined"
  and "the cache row landed" dispatches with a blank `feedback`,
  indistinguishable from a genuine zero-comment case at render time.
  That is exactly the ambiguity this ticket's own record says must be
  resolved before dispatch, and a cache cannot resolve it — only
  removing the asynchronous write can. `Catapult.Engine.Projections
  .CommentFeedback.since_last_resolution(project_id, node_id)` reads
  `Commanded.EventStore.stream_forward/2` directly, the same call
  `RunFailures.count_since_commit/2` already makes, and is a
  synchronous read of the log itself, not a projection anything writes
  ahead of time — so there is no ordering gap for a sweep tick to land
  in, whatever the reset boundary turns out to be.

  **The reset boundary is not `DraftCommitted`, on a second design-
  review finding this pass corrects: that boundary and
  `GateComments.any_since_last_resolution?/2`'s boundary, below, are
  different queries that can each pass while the other sees something
  different, which reopens the same blank-vs-zero ambiguity one level
  in** (ORC-34, design pass, second design-review correction). A
  concrete case second review gave: `GateDeclined` at T1 resets
  validation's window; a comment lands at T2, mid-regeneration;
  `DraftCommitted` at T3 reset *this* projection's window on the old
  design, discarding T2 before it ever rendered; `GateDeclined` again
  at T4 passes validation (T2 postdates T1) and dispatches a
  regeneration whose `feedback` folds since T3 and sees nothing —
  burning the exact dispatch this ticket exists to prevent, and losing
  T2 outright in the process, since no later window ever folds back
  across T3 to find it. The fix makes both queries the same shape:
  this fold resets at **the gate resolution before the most recent
  one** — the second-most-recent `GateApproved`/`GateDeclined` event in
  the project's log, unfiltered by which `gate` it names, or the start
  of the log if fewer than two resolutions have happened yet — then
  appends every `CommentPosted` for `node_id` seen since. Not filtering
  by `gate` looks like a difference from `GateComments`'s own fold,
  which does take a `gate` parameter below, but Phase 4's own
  single-gate `feature.yaml` makes it a difference with no effect: with
  exactly one gate declared, every `GateApproved`/`GateDeclined` in the
  project necessarily names it, so folding all resolutions and folding
  only the ones naming that one gate select the identical events. This
  leans on the same thing "Phase 4 needs no general node(s)-per-gate
  answer" already leans on elsewhere in this entry — the day a second
  gate exists, this fold has to learn which gate covers `node_id` and
  filter on it too, the same day `GateComments` would have to learn the
  same mapping to stay a validation for the *right* gate rather than
  any gate; neither is owed that answer by this ticket. Read at render time,
  after the triggering `GateDeclined` is already the log's most recent
  resolution, "the resolution before the most recent one" is exactly
  the boundary `GateComments` checked *before* that `GateDeclined` was
  appended, so the two windows are the same window by construction,
  not by two independently-written queries agreeing today and drifting
  tomorrow. Walked through the case above: at T4, this fold's boundary
  is T1 (the resolution before T4), so it sees T2 — the comment that
  actually justified the decline — and does not see whatever comments
  led to the T1 decline, already rendered into the regeneration T1
  dispatched. `DraftCommitted` plays no role in this fold at all; a
  comment posted while a regeneration is in flight is no longer
  discarded by that regeneration's own commit, which is the same
  scenario stated as a separate risk and closed by the same fix rather
  than a second one. "Consumed" now means "rendered into every
  regeneration dispatched before the next resolution, and gone the
  moment that resolution lands" — not "discarded by an unrelated
  draft commit."

  Delivery reads this the same way it already reads `engine_flows` and
  the ninth projection — through a query, never a second copy of the
  log's own facts — which is what the pre-review draft's own text
  claimed while contradicting it with a cache in the same commit;
  there is now exactly one description of this mechanism, here, and
  `systems/delivery.md`'s entry points at it rather than restating it.

- **A workflow gate's sign-off is two new commands landing on this
  aggregate, closing the mechanism `systems/delivery.md`'s ORC-32
  entry left as "a later increment"** (ORC-34, design pass, scope
  correction: the ticket's own write path, deferred once to Phase 7,
  turns out to be this ticket's because `docs/ui-spec.md` §2 rule 2
  refuses a screen — `document-review`, ORC-75 — inventing protocol
  vocabulary the platform doesn't have yet, and neither `PostComment`
  nor a decline command exists before this pass). `Catapult.Engine
  .Commands.ApproveGate{project_id, flow_id, gate, actor_id}` →
  `GateApproved`, and `Commands.DeclineGate{project_id, flow_id, gate,
  throwback_to, actor_id}` → `GateDeclined`, both v1, both keyed by the
  `(project_id, flow_id)` composite `systems/delivery.md`'s own ORC-32
  entry already establishes for this aggregate's process-manager
  consumer (ORC-87). Validation reads the loaded `Catapult.Dsl
  .Workflow.t()` the same way this doc's ORC-104 entry already does for
  container commands: `gate` must be a key of `workflow.gates`, and for
  `DeclineGate`, `throwback_to` must be a member of that gate's own
  `throwback` list (`Catapult.Dsl.Gate.throwback` — a member is always
  load-time-resolvable per `Catapult.Dsl.Workflow`'s own
  `gate_throwback_problems/2`, but a garbage value on the command still
  needs rejecting here, at the aggregate, since the loader never sees
  this command). **A decline requires at least one comment; there is
  no free-text override.** `docs/ui-spec.md` §3.2's own `document
  -review` action set is "approve / throw back, with the throwback
  target chosen from the declared exits" — no reason field — so the
  simpler of the two fixes design review posed for the ticket's own
  zero-comment open question is also the one the screen this ticket
  answers to actually specs: `DeclineGate` is rejected outright,
  synchronously, at the point of action, when `Catapult.Engine
  .Projections.GateComments.any_since_last_resolution?(project_id,
  gate)` is false — the identical `RunFailures`-shaped fold, reset at
  this project's most recent `GateApproved`/`GateDeclined` naming this
  `gate` (or at the log's start, if neither has happened yet) and
  incremented at each `CommentPosted` since, project-wide. **Project-
  wide, not flow-scoped, on purpose**: `CommentPosted` carries no
  `flow_id`, and `systems/delivery.md`'s own `FeaturePublisher` entry
  already leans on "nothing yet opens two flows concurrently on one
  project" to resolve a flow from a bare `project_id`; this reuses that
  exact standing simplification rather than inventing a second one, and
  carries the identical Phase 7 revisit condition — multiple concurrent
  flows per project need `CommentPosted` to carry `flow_id` too, not a
  new check here. **This is a rejection the aggregate makes, not the
  view**: `docs/ui-spec.md` §2 rule 1 and this doc's own "the rejection
  lands at the point of action" already rule out a UI-side check as the
  arbiter for any command on a surface we own; a decline attempt with
  no comments yet is simply invalid input to `DeclineGate`; the screen
  a future ticket builds surfaces that rejection synchronously, the
  same as any other compare-and-swap failure, but does not perform it.
  **What this does not pin: §7.16's "what a passed gate pins" stays
  exactly as open as it already was.** Neither event carries a
  `body_sha` or any other content-identity field — they record only
  enough for a ticket's projected status to move, forward or to a named
  throwback target, and for the comment-count check above to run; they
  are not a second attempt at the staleness-of-a-passed-gate question
  `systems/delivery.md`'s ORC-32 entry and this section's own §7.16
  bullet already leave to Phase 7. Which node(s) a given gate reviews —
  the general question behind "does what this gate approved still
  match what's downstream of it" — is likewise untouched; Phase 4's own
  shipped `feature.yaml` runs exactly one `generation` status ahead of
  its gates, so nothing here needs the general answer to work today.
  Role authorization (does this `actor_id` hold `gate.role`) is left
  exactly where §7.16 already leaves grant evaluation — identity's, a
  Phase 7 component — recorded the same way `actor_id` rides
  unvalidated on `DraftApproved` today. **How a decline reopens a node
  for regeneration is still not built here.** `GateDeclined` moves the
  ticket's own projected status (`systems/delivery.md`, below); which
  chain-axis node(s) that throwback makes eligible for `ready_scopes`
  again is the same still-open §7.19 mechanism this ticket inherited
  rather than closed — this entry only guarantees that whenever ORC-9's
  executor does re-dispatch, `feedback` is already correct by
  construction: `CommentFeedback.since_last_resolution/2`'s reset
  boundary is the same "resolution before the most recent one" this
  bullet's own comment-count check reads, so the window that let a
  decline happen is the identical window the regeneration it triggers
  renders, independent of what triggers the re-dispatch or how long
  the sweeper takes to notice.

- **`prior_review` needs a new `Store.reviews_for_node/2`, project-
  scoped per ORC-87 from the start — not the existing `reviews_for_draft
  /1` the pre-review draft leaned on, which answers a different
  question and stays exactly as bare-id as it already was, a real gap
  ORC-87's own audit missed** (ORC-34, design pass, design-review
  finding; the "audit's first pass missed it" pattern this doc's own
  ORC-87 entry already used once for `engine_drafts`' second key,
  applied here to a call site rather than an index).
  `reviews_for_draft(draft_id)` stays, bare id and all, because the
  review-tier dispatch rule above needs exactly what it already
  answers — does *this* draft have a review yet — and threading
  `project_id` through it is real but separate cleanup this ticket
  notes without taking (dev's, the same way every other decision in
  this doc is). What `prior_review` needs is a different query
  `reviews_for_draft/1` cannot answer, which is the ticket's own "the
  same slot doing different jobs" question the pre-review draft pinned
  without noticing it left one of the two jobs blank: reading by
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
  `prior_review` blank via Solid's own unset-is-empty behavior,
  unchanged. **The row carries `body_sha`** (`Store.Review` already has
  the field — `write_review`/`ReviewWritten` set it from the draft they
  reviewed) **and `reviews_for_node/2` renders it**, so a prompt reading
  `prior_review` can tell whether the review it sees applies to the
  node's current committed body or a superseded one; without it,
  nothing distinguished "what I said about the body you're now
  regenerating from" from "what I said about a body two commits ago,"
  which the deliberate cross-draft read above makes possible for the
  first time (`feedback`'s own entries carry the same kind of
  provenance — `posted_at` against the log's own ordering).

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
