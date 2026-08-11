---
paths:
  - lib/catapult/harness/**
  - test/catapult/harness/**
---

# harness

The prompt-iteration harness (v5 §10.2): SiegeEngine's cohort
machinery re-platformed. Cohorts (stratified sampling under the
upstream-only-axes rule), fresh-vs-review iteration modes, score
aggregation from the review grammar plus structural metrics
(grammar-parse rate, cardinality violations), and comparison against
baselines pinned in the registry.

## Standing decisions

- **Sampler axes come from upstream of the iterated tier, never
  from its outputs** (SiegeEngine's hard-won rule, kept): an axis
  derived from the target tier's own output collapses to one bucket
  on never-generated candidates and the sampler degenerates to
  alphabetical fill.
- **Fresh-mode wipes are destructive by design and say so** — "what
  does the new prompt produce on a clean slate" is only meaningful
  on a clean slate; off-campaign content is named collateral, not a
  surprise.
- **Budget-capped by construction**: harness runs go through the llm
  component's metering; a run without a cap is a config error, not a
  choice.
- **Harnessability is a property of the runtime abstractions** —
  anything with declared nodes, scopes, grammars, reviewers. The
  app-facing mode is a consequence, not a second product.

## Initial vs target

Initial (Phase 6, pullable to 5): cohorts + scoring + baselines over
the design dialect, offline mode via the fake. Target: app-facing
mode over the runtime dialect (timing open, v5 §8).

## Depends on

engine, generation, llm, registry (baseline artifacts).
