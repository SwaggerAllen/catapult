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

## Initial vs target

Initial (Phase 3): event log, reducer for the design dialect's event
set, core projections, scheduler + sweeper. Target: flow instances,
staleness cascades, snapshots, replay tooling surfaced in the
dashboard.

## Depends on

substrate, foundation (EventStore infra), core_dsl (bundle semantics
the reducer is generic over).
