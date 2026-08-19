---
paths:
  - lib/catapult/engine/**
  - test/catapult/engine/**
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
- **A passed review gate's pin is the ordinary staleness rule applied
  to the review node itself — closing v5 §7.16's open item.**
  `dsl-syntax.md` §3.3 (ORC-84) settled the grammar half: a review is
  a tier (`reviews: <tier>`), 1:1 with the tier it reviews, its own
  `context:` load-time-checked equal to the reviewed tier's. That
  equality *is* the pin — a review node reads exactly the inputs its
  reviewed tier does, so it is one more node under the rule above:
  stale precisely when the tier it reviews would be, with no separate
  "approved version" field ever recorded or compared. §7.19's
  all-reopen-on-throwback reads this derivation directly rather than
  diffing stored approval state. Recorded here because engine is
  where the derivation actually runs; `v5-design-decisions.md` §7.16
  is amended alongside this doc to stop calling it open.
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
exercise it — scheduler + sweeper. Target: flow instances, staleness
provenance, snapshots, replay tooling surfaced in the dashboard.

## Depends on

substrate, foundation (EventStore infra), core_dsl (bundle semantics
the reducer is generic over).
