---
paths:
  - lib/catapult/delivery/**
  - test/catapult/delivery/**
---

# delivery

The protocol plane: the Tracker, Host, and Deploy ports with real
adapters (Linear, GitHub, health-endpoint deploy detection) and
in-memory fakes — orchestration's port architecture re-expressed in
Elixir — plus, over them, the v5 §7 machinery in two stages: first
the **authoring loop** (Phase 4: feature-ticket lifecycle projection,
gate states, feature-branch PR management, decline harvesting), later
the full two-grain delivery (spawn at Building, child lifecycle,
mutex, dispatch, reconciliation, the validation loop, escalations,
milestones with the `:live` boundary step, the maintenance watcher).

## Standing decisions

- **Ports with fakes, exactly like the Go pipeline** — the fake ships
  with the port; the sim-style test ring runs the whole protocol
  offline. This is the porting model (v5 §7.13): snapshot→actions
  purity maps near-1:1 onto a Commanded process manager.
- **Linear is a projection; the event log is the authority** (v5
  §7.1). Human actions arrive as commands; validate-or-revert, with
  the plane's record as ground truth. No plane behavior may depend
  on tracker state it didn't project.
- **Every comment the plane relies on carries a fixed marker**
  (orchestration §9's rule, kept verbatim): counts and resumes
  parse markers, never prose.
- **The authoring loop is a strict subset, not a fork**: Phase 4
  ships the gate/PR/harvest slice of the same modules the full
  machinery grows into; no throwaway scaffolding that Phase 7
  rewrites.

## Initial vs target

Initial (Phase 4): ports + fakes; feature lifecycle through the two
gates; PR + harvesting; state projection to Linear. Target
(Phase 7): the whole of v5 §7, including the delivery-DSL extension
registered with core_dsl.

## Depends on

substrate, engine (state of record), generation (the chain whose
progress it projects). Req for the Linear/GitHub clients.
