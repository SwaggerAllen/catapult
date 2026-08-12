---
paths:
  - lib/catapult/generation/**
  - test/catapult/generation/**
---

# generation

The plane's design-dialect coordination — **agents end-to-end (v5
§1.2): the plane never generates, it dispatches**. This system takes
ready `(tier, scope)` pairs from `ready_scopes`, evaluates context
walks and renders the Liquid prompt, dispatches an agent run via the
delivery system's host port, serves the rendered context to the
runner-side harness, and validates the committed body against the
tier's grammar (via core_dsl) when the agent reports. The app-facing
runtime dialect (components/runtime, Phase 8) shares the rendering
and validation logic and must not fork it.

## Standing decisions

- **The plane holds no working copies and makes no model calls.**
  The runner's checkout is the working copy; bodies reach the plane
  as commits to read at a SHA, never as files on its disk. The
  in-plane persistence class (branch management, working trees,
  ephemeral-disk writes) is deleted by construction.
- **Dispatch coordination holds no state and makes no decisions**:
  what to generate comes from `ready_scopes`; what to render comes
  from the bundle; whether output is acceptable comes from the
  grammar. If coordination needs memory, the design is wrong
  somewhere upstream.
- **Validation failure is feedback, not error** (v4 §A.1.3 carried
  forward): a grammar-invalid commit returns a typed error the agent
  retries with, bounded; a half-committed state is impossible
  because commit-time validation gates the event.
- **Same renderer for generation and review** (the per-tier triad
  invariant, SiegeEngine's rule): the reviewer sees exactly the
  generator's context plus the draft. Enforced by sharing the
  context-assembly code path, not by convention.
- **Latency scales the pool, never the architecture**: slow
  generation means an autoscaling worker pool pulling from the
  queue — generation never moves in-plane.
- **The execution substrate is an adapter behind the host port**
  (v5 §7.12.1, §8): Actions (the default) and the worker pool (BYO
  cluster canonically, managed opt-in) are two adapters over one
  runner-harness contract — fetch rendered context, run agent,
  commit, report. The contract is the invariant; nothing outside
  the Actions adapter may assume Actions. The dispatch-concurrency
  cap is a per-instance `tunable` in plane state, never a config
  constant — scheduler backpressure and hosted tiering share it.

## Initial vs target

Initial (Phase 3): readiness-driven dispatch for the upstream tiers,
offline against the agent-port fake (canned bodies through the real
commit path), live against dispatched runs on Actions. Target:
review passes, regen-with-feedback threading, executor-profile
routing, the shared seam with the runtime dialect kept clean.

## Depends on

engine (ready_scopes, commands), core_dsl (grammars, walks),
delivery (host port, dispatch, run correlation),
platform_content (the prompts).
