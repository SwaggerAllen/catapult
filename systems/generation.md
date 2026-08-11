---
paths:
  - lib/catapult/generation/**
  - test/catapult/generation/**
---

# generation

The plane's design-dialect execution: Oban workers that take a ready
`(tier, scope)` from the engine's `ready_scopes`, evaluate context
walks, render the Liquid prompt, call the llm component, validate
output against the tier's grammar (via core_dsl), and dispatch the
commit command to the engine. The plane-side half of v5 §10.1's
layer 2; the app-facing runtime dialect is a later extraction
(components/runtime, Phase 8) that must not fork this logic.

## Standing decisions

- **Generation workers hold no state and make no decisions**: what
  to generate comes from `ready_scopes`; what to render comes from
  the bundle; whether output is acceptable comes from the grammar.
  A worker is replay-safe glue (v5 §2.6) — if a worker needs
  memory, the design is wrong somewhere upstream.
- **Validation failure is feedback, not error** (v4 §A.1.3 carried
  forward): a grammar-invalid generation retries with the error as
  feedback per the llm taxonomy, bounded; a half-committed state is
  impossible because commit-time validation gates the event.
- **Same renderer for generation and review** (the per-tier triad
  invariant, SiegeEngine's rule): the reviewer sees exactly the
  generator's context plus the draft. Enforced by sharing the
  context-assembly code path, not by convention.

## Initial vs target

Initial (Phase 3): design-dialect worker loop for the upstream
tiers, offline against the fake, live against Anthropic. Target:
review passes, regen-with-feedback threading, thinking-effort
routing, extraction seam for the runtime dialect kept clean.

## Depends on

engine (ready_scopes, commands), core_dsl (grammars, walks), llm,
platform_content (the prompts).
