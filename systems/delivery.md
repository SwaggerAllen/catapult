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

**There is no Tracker port, and no tracker adapter is ever built**
(v5 §7.17). Ticket state is ours; the work surface is ours
(`docs/ui-spec.md`). The only outward-facing tracker interface is a
**mirror** — an outbound projection of top-level tickets only, for
teams reporting into a larger org's system, with no inbound write
path (`docs/non-goals.md`) — and it is a product feature, not a
dependency of the loop.

**There is no tracker cutover, because there is nothing to cut over
from.**
The reversal landed before any tracker integration was written, so
the plane never acquires one. Orchestration builds Catapult and
orchestration uses Linear; that is a different system running a
different loop, and it is unaffected by anything here. Catapult the
platform does not talk to Linear at all.

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
- **The host port's second operation resets a bound repo's fixture
  content; it does not touch generated artifacts** (ORC-10). A bound
  repo has to carry a `workflow_dispatch` file before GitHub will
  accept a dispatch to it at all, and no role in this pipeline has a
  route to author a file inside a *different* repository — that repo
  is out of every agent's reach by construction, not by refusal. So
  the plane writes it there instead: the toy seed's per-role input
  documents and `.github/workflows/catapult-dispatch.yml` live as
  fixtures in *this* repo, reviewed like any other file, and `reset`
  overwrites the bound repo's contents from them. `HostPort` gains
  this as a second callback alongside `dispatch_run/1`, and the fake
  implements it too, so the offline chain test exercises the same
  reset path rather than a live-only mechanism — the same "fake is
  scope, not test scaffolding" rule `systems/generation.md` states for
  the dispatch call. What reset does *not* do: generated artifacts
  still land only through `Dispatch`'s result-report path into the
  plane's own store, never written to the bound repo, and reset does
  not make `input.<role>` resolve — that's intake, Phase 5, ORC-12
  (`docs/non-goals.md`'s ORC-10 entry). What it buys today is an
  author and a rebuild path for a fixture repo, not test determinism
  or seeded generation content.
- **`DELIVERY_GITHUB_TOKEN` gains `Contents: read and write`, pulled
  forward rather than newly spent** (ORC-10). Phase 4's
  feature-lifecycle PR management already needs contents-write on a
  bound repo regardless of this ticket; reset draws on that same
  grant early instead of inventing a second one. The grant is global —
  one config value, not one per project binding — so it reaches every
  bound repo the moment it's set. Acceptable for a test repo the
  author owns; not fixed here. `lib/catapult/delivery.ex`'s own config
  comment already names the GitHub App installation token as the
  shape that scopes this per-repo, and that stays the answer — ORC-10
  doesn't owe it.
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
- **Blocked-ticket re-resolution across a workflow cutover is
  delivery's join, over engine's projection** (v5 §7.19; `core_dsl
  .md`'s §6 cutover). When a bundle flip retires the workflow
  sequence a blocked ticket's origin status belonged to, delivery
  re-resolves it: (a) the most recent status the ticket held that
  still exists in the new sequence, failing that (b) the status after
  the most recent *system status* it reached. (b) always terminates —
  system statuses are platform-fixed, the one part of a ticket's
  history no bundle change can delete. The join reads two logs and
  owns only one of them: the ticket's own status history is delivery's
  projection, and the active-bundle-version timeline is
  `systems/engine.md`'s ninth projection (current version + the
  sequence it became current, two rows per project) — delivery reads
  that rather than re-deriving its own copy, on the same boundary as
  everywhere else in this doc (engine is state of record, delivery is
  the protocol interpreting it). Target (Phase 7), alongside the rest
  of the workflow-bundle machinery this needs to have a subject at
  all — there is no declared workflow sequence to cut over from
  before then.
- **No boundary ticket, generalized: containers carry their own
  progress, and the project is a container too** (ORC-105, design
  pass, superseding ORC-103's own unmerged milestone-only version of
  this entry; `docs/v5-design-decisions.md` §7.8;
  `docs/dsl-syntax.md` §15.6-§15.8). A container's status is which of
  its declared queues is current; a queue is a derived query, never a
  stored bucket, so there is no per-queue pending set for this system
  to own the way `ready_scopes` is engine's. Two relations this
  system dispatches against, both new: a queue's `flow:` target is
  ordinary ticket-type dispatch (no new mechanism — a `retro` or
  `setup` ticket opens a flow instance exactly like any other type);
  a queue's `blocks:` relation to a sibling queue holds that sibling's
  entry open while the blocking queue carries unresolved work items —
  the general form of what used to be a single hard-coded
  boundary-blocking rule, now one relation the dispatcher reads
  wherever a workflow bundle declares it, milestone `main`→`retro`
  included. **The pause has no separate mechanism to build**: an
  `Urgent` ticket dispatches regardless of which queue a container
  currently sits in (`docs/v5-design-decisions.md` §7.3, §7.10), which
  falls out of ordinary priority dispatch rather than needing a
  ticket-carried flag against its milestone the way ORC-103's draft
  required. Storage for "which queue is a given container currently
  at," the `blocks:`-aware dispatcher, the `:live`-gates-`retro`
  interlock (§2.8), and the scan/setup/retro machinery itself are
  Target (Phase 7), filed as ORC-104 and blocked on this record; this
  entry is the shape it builds against.

## Initial vs target

Initial (Phase 4): the host port + fakes; feature lifecycle through
the two gates; PR + harvesting; lifecycle projected into the plane's
own read models, which the work surface renders — there is no third
party in this path. **Narrowed at ORC-9**: the host port's
dispatch-facing slice — context-fetch, result-report, OIDC
validation, run correlation, and its in-memory fake — lands in Phase
3 with the generation executor (`systems/generation.md`), ahead of
the rest of this system. It is one seam with two consumers arriving
at different times, not two ports: the slice generation needs now is
a subset of the same host port this doc already claims, not a
parallel one this ticket invents. The handler logic for that slice —
OIDC validation, run correlation, context/result payloads — lives
under this doc's own file map; **what serves it does not**
(`systems/foundation.md`'s design review finding): the endpoint rides
a second path on foundation's existing health listener, reached
through an `api_surface/0` declaration rather than a router of this
system's own, because the general composed router waits for
dashboard's Phase 4/7 web layer. **Narrowed again at ORC-10**: the
repo-reset operation above, and the `Contents: read and write` grant
it draws on, land with it — a second sliver of Phase 4's host port
pulled into Phase 3 for the same reason the first one was, because the
milestone boundary test needs it now. Feature-lifecycle PR management
and decline harvesting proper are unaffected and still open at Phase
4. Target
(Phase 7): the whole of v5 §7,
including the delivery-DSL extension registered with core_dsl, the
declared review sequences and environments of §7.19, and the outbound
mirror in place of the Linear adapter.

## Depends on

substrate, engine (state of record), foundation (serves the
dispatch-facing host port endpoint on its listener), generation (the
chain whose progress it projects), core_dsl (the workflow bundle's
declared statuses and environments, v5 §7.18-§7.19), dashboard (the
work surface — a hard dependency, since nothing else renders the
loop). Req for the GitHub client.
