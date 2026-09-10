---
paths:
  - components/llm/**
---

# llm

The LLM adapter component (v5 §10.1 layer 1), shipped to target apps
via the generation runtime — **not consumed by the plane**: Catapult
is agents end-to-end (v5 §1.2) and its chain never makes a
synchronous completion call. The component: the provider behaviour
with real and deterministic-fake implementations, model-tier
routing, the metering/cost ledger with caps and circuit breaker, the
three-way failure taxonomy (refusal → editable; transport →
retryable; schema-invalid → cancel), and
generation-failures-as-domain-read-models.

## #1 Standing decisions

- **#2 Every model call in any Catapult-adjacent codebase goes through
  this behaviour** (conventions §11). The adapter carries the fakes,
  metering, routing, and taxonomy; a bypassed call has none of them.
- **#3 The deterministic fake is a first-class implementation, not a
  test double**: shaped output per requested schema, stable under a
  seed, shipped with the component. It is the precondition for
  no-network CI in every LLM-using app (v5 §2.8).
- **#4 Failures are data, not exceptions** (v5 §10.1): the taxonomy is
  the contract; consumers pattern-match. Generation failures never
  reach crash reporting.
- **#5 The serial-pipeline pattern lives here**: enqueue-on-completion
  chains with log-derived progress — pausable, resumable, identical
  inline in tests (absorbed from Polyphony).

## #6 Initial vs target

Initial: **nothing until Phase 8** — the component is built with its
first real consumer (the runtime dialect; Polyphony's beat loop).
The contract is settled now (v5 §10.1: synchronous completions only;
agent-in-environment runs are dispatch machinery, never adapters) so
the runtime's design is stable; construction waits. Target: provider
behaviour, Anthropic adapter, deterministic fake, routing,
metering/caps, published on the release train.

## #7 Depends on

substrate. Req as the HTTP client.
