---
paths:
  - components/llm/**
---

# llm

The LLM adapter component (v5 §10.1 layer 1), shipped to target apps
and consumed first by the plane's own generation: the provider
behaviour with real and deterministic-fake implementations,
model-tier routing, the metering/cost ledger with caps and circuit
breaker, the three-way failure taxonomy (refusal → editable;
transport → retryable; schema-invalid → cancel), and
generation-failures-as-domain-read-models.

## Standing decisions

- **Every model call in any Catapult-adjacent codebase goes through
  this behaviour** (conventions §11). The adapter carries the fakes,
  metering, routing, and taxonomy; a bypassed call has none of them.
- **The deterministic fake is a first-class implementation, not a
  test double**: shaped output per requested schema, stable under a
  seed, shipped with the component. It is the precondition for
  no-network CI in every LLM-using app (v5 §2.8).
- **Failures are data, not exceptions** (v5 §10.1): the taxonomy is
  the contract; consumers pattern-match. Generation failures never
  reach crash reporting.
- **The serial-pipeline pattern lives here**: enqueue-on-completion
  chains with log-derived progress — pausable, resumable, identical
  inline in tests (absorbed from Polyphony).

## Initial vs target

Initial (Phase 3): provider behaviour, Anthropic adapter, fake,
basic routing + metering. Target: cost ledger with caps/breaker,
per-tier effort routing (bundle-declared, v5 §B.2.4), published on
the release train.

## Depends on

substrate. Req as the HTTP client.
