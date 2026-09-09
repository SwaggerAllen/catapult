---
paths:
  - packages/client-ts/**
---

# client_ts

`platform-client-ts` (v5 §5.6): the TypeScript client corpus for
React-target projects — the client twin of the substrate. Slots:
client store convention (retraction-capable), optional persisted
outbox, import-boundary lint, composed client root with the
init/restore/flush lifecycle contract (URL-as-view-state included),
the typed realtime client (topic families, cursor classes, catch-up,
retraction), client-side audit, SSR/hydration boundary guidance, and
WASM-external consumption.

## #1 Standing decisions

- **#2 Slots are declared capabilities, not mandates** (v5 §5.6); the
  audit checks what a project declares. Forced by Polyphony's
  no-client-held-unsaved-work standing decision — the platform does
  not overrule argued project decisions by default.
- **#3 A platform-layer deliverable, seeded by its first two consumers**
  (author call): Haven (stress case) and Polyphony (median case)
  drive the slot contents; nothing lands in the corpus without a
  consumer.
- **#4 Generated clients are the only door to the backend** — the
  OpenAPI client and the typed channel client; a hand-written fetch
  is the client-side sibling of a bypassed LLM call.

## #5 Initial vs target

Initial: empty — this system exists as a file-map claim and a slot
list until the React pass (Phase 7). Target: the corpus published
per release train, consumed by Polyphony's rebuild (Phase 8).

## #6 Depends on

Contract artifacts from delivery/api-surface machinery; WASM
externals via the registry.
