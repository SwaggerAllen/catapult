---
paths:
  - lib/catapult/delivery/**
  - test/catapult/delivery/**
---

# delivery

The protocol plane: the Host and Deploy ports with real adapters
(GitHub, health-endpoint deploy detection) and in-memory fakes —
orchestration's port architecture re-expressed in Elixir — plus, over
them, the v5 §7 machinery in two stages: first the **authoring loop**
(Phase 4: feature-ticket lifecycle projection, gate states,
feature-branch PR management, decline harvesting), later the full
two-grain delivery (child lifecycle, mutex, dispatch, reconciliation,
the validation loop, escalations, milestones with the `:live`
boundary step, the maintenance watcher).

**The Tracker is no longer one of the ports** (v5 §7.17): ticket
state is ours, and what remains outward-facing is a **mirror**
adapter — an outbound projection of top-level tickets only, for teams
reporting into a larger org's system, with no inbound write path
(`docs/non-goals.md`). Delivery runs against Linear until the native
work surface lands at UI v1 (`docs/ui-spec.md` §5), so the Linear
adapter is real work with a stated end date rather than a permanent
port.

**Children spawn when the plan node names them, not at Building**
(v5 §7.10): a depth-scoped gate sitting before Building is
unclaimable unless its children exist by then. Creation is not
dispatchability — early children sit pre-queue until the parent's
design gates pass.

## Standing decisions

- **Ports with fakes, exactly like the Go pipeline** — the fake ships
  with the port; the sim-style test ring runs the whole protocol
  offline. This is the porting model (v5 §7.13): snapshot→actions
  purity maps near-1:1 onto a Commanded process manager.
- **Ticket state is a projection; the event log is the authority**
  (v5 §7.1). Unchanged by owning the tracker — if anything sharpened,
  since the surface and the authority now agree. Human actions arrive
  as commands the plane validates: on a surface we own the rejection
  lands at the point of action (§7.16's compare-and-swap); through
  Linear it degrades to validate-or-revert, because Linear applies
  last-write-wins and tells nobody. No plane behavior may depend on
  tracker state it didn't project.
- ~~**Every comment the plane relies on carries a fixed marker.**~~
  **Retired for surfaces we own** (v5 §7.17, `docs/ui-spec.md`).
  Markers existed because an external tracker had nowhere to put
  typed data, so protocol state rode in prose behind a prefix and
  counts and resumes parsed it. Owning the tracker removes the
  premise: **plane-authored annotations are records with kinds**, and
  nothing parses prose to find them. The rule survives verbatim on
  surfaces we do not own — GitHub PR comments — where the original
  reason still holds, and orchestration keeps it wholesale since it
  has no store of its own.
- **Intent → idempotent effect → observed completion** (v5 §7.1):
  no external effect shares a transaction with an event. Outbound
  acts record intent, execute via outbox workers, and complete only
  on the world's confirmation (webhook/sweep). Effect-without-record
  heals by re-observation; intent-without-effect is visible and
  escalates. The log never says "done" on the plane's own word.
- **The authoring loop is a strict subset, not a fork**: Phase 4
  ships the gate/PR/harvest slice of the same modules the full
  machinery grows into; no throwaway scaffolding that Phase 7
  rewrites.

## Initial vs target

Initial (Phase 4): ports + fakes; feature lifecycle through the two
gates; PR + harvesting; state projection to Linear, which is the
interim surface until UI v1. Target (Phase 7): the whole of v5 §7,
including the delivery-DSL extension registered with core_dsl, the
declared review sequences and environments of §7.19, and the outbound
mirror in place of the Linear adapter.

## Depends on

substrate, engine (state of record), generation (the chain whose
progress it projects), core_dsl (the workflow bundle's declared
statuses and environments, v5 §7.18-§7.19), dashboard (the work
surface, once UI v1 lands). Req for the GitHub client and, while it
lasts, the Linear one.
