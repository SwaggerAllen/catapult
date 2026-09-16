---
paths:
  - lib/catapult/delivery.ex
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
the validation loop, escalations, milestones with the `:live`-gated
`retro` entry (ORC-105), the maintenance watcher).

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

**Children spawn when the plan node names them, not at a status
transition** (v5 §7.10): a depth-scoped gate sitting before the
child's own existence is unclaimable unless it exists by then.
Creation is not dispatchability — early children sit pre-queue until
the parent's design gates pass. **Architecture's own fan-out
recurses the identical rule one level further, settled at ORC-151's
third design review** (below): sysarch, each comparch and each
subcomparch spawns its own ticket the same way, rather than
generating as scope-runs inside one ticket.

## #1 Standing decisions

- **#2 `HostPort.request`'s `credential_name` widens to the bindings
  tunable's full ordered pair** (ORC-215): the single-credential shape
  was ORC-9's workaround for a runner harness that failed over on any
  non-zero exit; `systems/generation.md`'s own entry retires the
  workaround now that Catapult's own harness classifies limit-class
  failures itself, and `HostPort.Actions.dispatch_run/1` sends the
  pair whole.
- **#3 Ports with fakes, exactly like the Go pipeline** — the fake ships
  with the port; the sim-style test ring runs the whole protocol
  offline. This is the porting model (v5 §7.13): snapshot→actions
  purity maps near-1:1 onto a Commanded process manager.
- **#4 The host port's second operation resets a bound repo's fixture content; it does
  not touch generated artifacts** (ORC-10). A bound repo has to carry a
  `workflow_dispatch` file before GitHub will accept a dispatch to it at all, and no
  role in this pipeline has a route to author a file inside a *different* repository —
  that repo is out of every agent's reach by construction, not by refusal. So the plane
  writes it there instead: a seed's per-role input documents and the workflow file it
  pushes to `.github/workflows/catapult-dispatch.yml` live as fixtures in *this* repo,
  reviewed like any other file, and `reset` overwrites the bound repo's contents from
  them. **The workflow file is one fixture shared by every seed**, at
  `test/catapult/generation/fixtures/catapult-dispatch.yml` rather than inside either
  raft's own directory beside it: `Catapult .ToySeed.reset_files/0` and
  `Catapult.TodoAppSeed.reset_files/0` push the same file to the same path in the same
  bound repo, so a per-seed copy would leave whichever seed provisioned last silently
  deciding which harness that repo carried (the fixture's own header records this).
  `HostPort` gains this as a second callback alongside `dispatch_run/1`, and the fake
  implements it too, so the offline chain test exercises the same reset path rather than
  a live-only mechanism — the same "fake is scope, not test scaffolding" rule
  `systems/generation.md` states for the dispatch call. What reset does *not* do:
  generated artifacts still land only through `Dispatch`'s result-report path into the
  plane's own store, never written to the bound repo, and reset does not make
  `input.<role>` resolve — that is intake (Phase 5, ORC-107, this doc's own ORC-107
  entry below; `systems/generation.md` carries what that means for assertions).
- **#5 `DELIVERY_GITHUB_TOKEN` gains `Contents: read and write`, pulled forward rather
  than newly spent** (ORC-10). Phase 4's feature-lifecycle PR management already needs
  contents-write on a bound repo regardless of this ticket; reset draws on that same
  grant early instead of inventing a second one. The grant is global — one config value,
  not one per project binding — so it reaches every bound repo the moment it's set.
- **#6 The raft is pinned as a copy in this system's own store, discovered from a
  registered directory in the bound repo, and never read again after intake** (ORC-107,
  v5 §1.1). A registered path and a pinned copy are two different jobs, not one choice
  between alternatives: a registered path is how intake *finds* the raft; a pinned copy
  is what a render-time walk actually reads.
- **#7 Storage**: `Catapult.Delivery.Store.InputDocument` (new,
  `delivery_input_documents`), the same shape `DraftBody` already established for the
  identical problem one tier over — a Liquid variable needs a stable string and the
  thing underneath is allowed to keep moving. Keyed `(project_id, role, filename)`;
  `content` is the verbatim copy a walk reads; `source_ref` is the commit SHA intake
  read it at, carried for provenance only and never dereferenced again — resolving a
  later walk *from* `source_ref` would be exactly the live re-read v5 §1.1 refuses, just
  one hop removed. Exposed at the boundary the same way `get_draft_body/2`/
  `put_draft_body/4` are: `Catapult.Delivery.get_input_documents/2` (a role's pinned
  documents), `Catapult.Delivery.get_raft/1` (every pinned document, for the wildcard),
  `Catapult.Delivery .pin_input_documents/3` (intake's own write, below).
- **#8 Discovery**: a fixed platform-wide path, `docs/raft/` in the bound repo — not a
  per-project setting, on the same footing `reset_repo`'s own workflow-dispatch file
  already stands on (a bound repo carries fixed plane-required paths; nothing here makes
  this one configurable that wasn't already). Every file directly under it is one input
  document, and the filename minus its extension is the role tag — no manifest, no
  per-role declaration anywhere, which is `chain.md` #19's `input.<role>` with no
  closed registry to violate, carried into storage rather than contradicted by it: a
  project tagging a document is a project naming a file.
- **#9 An extension-stem collision under one role is legal and ordered.**
  `InputDocument`'s key — `(project_id, role, filename)` — already stores more than one
  filename per role; nothing about the schema forces one-to-one. Discovery bounds what
  "sharing a role" can actually mean, though: filename-stem-is-role means the only way
  two files land under one role is the same stem with a different extension —
  `project_doc.md` and `project_doc.txt` both tagging `project_doc` — never an arbitrary
  number of unrelated documents filed under one tag by any naming a person would choose.
  In practice a project keeps one file per role; the rule is narrower than general
  per-role multiplicity — only that the extension-stem collision is not rejected,
  merged, or deduplicated, since nothing about it is wrong. Both read paths query rather
  than promise an order, though, and both feed a concatenated-string render
  (`systems/generation.md`'s entry): `get_input_documents/2` returns every row pinned
  under the role for `input.<role>`, `get_raft/1` returns every row pinned under the
  project for the `raft` wildcard (`chain.md` #19), and an unspecified order on
  either would let two renders of the same frozen pin disagree — the exact instability
  the freeze in v5 §1.1 exists to prevent. Both queries carry **`ORDER BY filename`**:
  it costs nothing (the row count sharing a role is one in the overwhelmingly common
  case) and makes the render reproducible.
- **#10 Reading it**: `HostPort` gains a fourth read-shaped operation,
  `read_directory/3` (`project_id`, `ref`, `path`) :: `{:ok, %{filename => content}}`,
  landing in `HostPort.Actions` and `HostPort.Fake` in the same change — the rule every
  operation on this port already follows. Unlike `reset_repo/2`'s own
  default-branch-only shape (the defect ORC-33 found and fixed for a different
  operation), `read_directory/3` takes an explicit `ref`: intake pins against a commit a
  caller names, not whatever the default branch happens to be the moment it runs.
- **#11 The intake pass**: one function, called at most once per project — given a
  `project_id` and a `ref`, it calls `read_directory/3` against the registered path and
  writes every file it gets back through `pin_input_documents/3`. "At most once" is not
  a convention, it is the entire mechanism behind v5 §1.1's "frozen at intake": there is
  exactly one legal call, so there is no second read to diverge from the first. What
  decides *when* that call happens — a project's creation or scaffold flow — is not
  intake's concern: a caller already holding a `project_id` and a `ref` is assumed, the
  same boundary Phase 5's own exit criterion draws (scaffolding its seed raft, whatever
  it is, needs exactly those two facts supplied, regardless of how a real project's
  author eventually supplies them).
- **#12 Ruled out**: reading the raft from anywhere other than the bound repo — a
  dashboard upload, a second config channel for pasted-in prose.
- **#13 The frozen-edit notice is narrower here than v5 §1.1 describes.** §1.1's
  Triage notice needs something to *file a ticket* the moment a diff lands under a
  registered input path — the base-check sweep — and ticket-filing is Phase 7's: the
  same validation-loop/ reconciliation machinery `ticket.<source>` itself waits on (v5
  §7.11), which also carries the sweep's other two triggers, the out-of-band-bug half
  and the doc-reconciliation half (`docs/v5-design-decisions.md` §7.3's entry points).
  What intake supplies toward it is the one fact a Phase-7 sweep would otherwise have
  nowhere to get: the registered raft path, recorded per project by intake (above), is
  already the thing "a diff under a registered input path" means — the sweep reads that
  fact rather than re-deriving it. Filing the notice itself rides Phase 7's
  reconciliation machinery alongside the sweep's other two triggers, rather than a
  bespoke ticket-filer built now and rehomed later.
- **#14 Ticket state is a projection; the event log is the authority**
  (v5 §7.1). Unchanged by owning the tracker — if anything sharpened,
  since the surface and the authority now agree. Human actions arrive
  as commands the plane validates: on a surface we own the rejection
  lands at the point of action (§7.16's compare-and-swap); through
  Linear it degrades to validate-or-revert, because Linear applies
  last-write-wins and tells nobody. No plane behavior may depend on
  tracker state it didn't project.
- **#15 Plane-authored annotations are records with kinds on surfaces we
  own** (v5 §7.17, `docs/ui-spec.md`); the fixed-marker rule is
  retired there. Markers existed because an external tracker had
  nowhere to put
  typed data, so protocol state rode in prose behind a prefix and
  counts and resumes parsed it. Owning the tracker removes the
  premise: **plane-authored annotations are records with kinds**, and
  nothing parses prose to find them. The rule survives verbatim on
  surfaces we do not own — GitHub PR comments — where the original
  reason still holds, and orchestration keeps it wholesale since it
  has no store of its own.
- **#16 Intent → idempotent effect → observed completion** (v5 §7.1):
  no external effect shares a transaction with an event. Outbound
  acts record intent, execute via outbox workers, and complete only
  on the world's confirmation (webhook/sweep). Effect-without-record
  heals by re-observation; intent-without-effect is visible and
  escalates. The log never says "done" on the plane's own word.
- **#17 The authoring loop is a strict subset, not a fork**: Phase 4
  ships the gate/PR/harvest slice of the same modules the full
  machinery grows into; no throwaway scaffolding that Phase 7
  rewrites.
- **#18 Blocked-ticket re-resolution across a workflow cutover is delivery's join,
  over engine's projection** (v5 §7.19; `core_dsl .md`'s §6 cutover). When a bundle flip
  retires the workflow sequence a blocked ticket's origin status belonged to, delivery
  re-resolves it: (a) the most recent status the ticket held that still exists in the
  new sequence, failing that (b) the status after the most recent *system status* it
  reached. (b) always terminates — system statuses are platform-fixed, the one part of a
  ticket's history no bundle change can delete. The join reads two logs and owns only
  one of them: the ticket's own status history is delivery's projection, and the
  active-bundle-version timeline is `systems/engine.md`'s ninth projection (current
  version + the sequence it became current, two rows per project) — delivery reads that
  rather than re-deriving its own copy, on the same boundary as everywhere else in this
  doc (engine is state of record, delivery is the protocol interpreting it).
- **#19 No boundary ticket, generalized: containers and the project alike carry their
  own progress — but the project is not a container** (ORC-105;
  `docs/v5-design-decisions.md` §7.8; `workflow.md` #16, #30). A container's
  or a project's status is which of its declared queues is current; a queue is a derived
  query, never a stored bucket, so there is no per-queue pending set for this system to
  own the way `ready_scopes` is engine's. Two relations this system dispatches against:
  a queue's `flow:` target resolves against a work-item-type registry shared by
  container and plain-type declarations alike (`workflow.md` #9) — no new
  dispatch mechanism whichever it resolves to, a `retro` or `setup` ticket opening a
  flow instance exactly like any other type, `setup` dispatching as its own anchor
  entry, first in the newly minted container's own sequence, never a value carried on
  the parent's dispatching entry, so the two never need to be the same declaration; a
  queue's `blocks:` relation to a sibling queue in the same declaration guards *entry
  into* that sibling while the blocking queue carries unresolved work items, checked
  once at the transition rather than held continuously (the `blocks:` entry below) — one
  relation the dispatcher reads wherever a workflow bundle declares it, milestone
  `main`→`retro` included, rather than a single hard-coded boundary-blocking rule. **The
  pause has no separate mechanism to build**: an `Urgent` ticket dispatches regardless
  of which queue a container or the project currently sits in
  (`docs/v5-design-decisions.md` §7.3, §7.10), which falls out of ordinary priority
  dispatch rather than needing a ticket-carried flag against its milestone. Where each
  piece lives: storage for "which queue a given container or the project is currently
  at" is `engine_containers.current_queue`/`current_queue_sequence`
  (`lib/catapult/engine/store/container.ex`); the `blocks:`-aware dispatcher is
  `Catapult.Delivery.ContainerLifecycle` (below); and the declaration-graph acyclicity
  check that bounds nesting (`systems/core_dsl.md` #15) is
  `Catapult.Dsl.Workflow.declaration_graph_problems/1`, skeleton-agnostic (ORC-148).
  There is no separate scan/setup/retro machinery: `setup`/`retro` fold directly into
  `milestone`'s own array as inline agent-balled entries, with no separate scan step
  (ORC-148, below).
- **#20 Mint is not activation, and this system's dispatcher is the one
  that has to hold the two apart** (ORC-105; `workflow.md`
  #19; `docs/v5-design-decisions.md` §7.8). A container instance can
  exist — created by business logic or a person, accepting groomed
  work into its own future queues — before its parent's own position
  ever reaches it; only reaching it makes it *active*, and only
  becoming active runs its `setup` entry's `flow:`. Mint and
  activation are not one event ("dispatch mints one instance and
  starts that instance at its own `setup` entry"; "minted one at a
  time as the prior one closes"), because of the case this system
  explicitly wants: grooming next milestone's `prep` during this
  milestone's own `main`. The storage distinguishing "instances that
  exist" from "the instance that is current" is
  `Catapult.Delivery.ContainerLifecycle`'s own `state` field
  (`:minted | :active | :closed`), and a gate's throwback is a human's
  `AdvanceContainerQueue` with `reason: :throwback`, checked against
  `ContainerLifecycle.Sequence.earlier?/4` — the live half of the
  check the loader can only make statically. A container's position
  moves backward on a gate's own throwback: a container's anchor
  entries carry gates and environments (`workflow.md` #5, #19,
  #34), so they have a `throwback:` of their own to honor. A
  queue un-resolving when its population refills is *not* a backward
  move (ORC-148's `blocks:` entries below). A milestone sign-off gate
  between `main` and `retro` can throw back to `main`, and this
  system's dispatcher honors that path exactly this way.
- **#21 A fifth ORC-105 pass gave the dispatcher a cardinality bound to respect and
  closed a hole in the loader's own acyclicity check that this system's dispatcher would
  otherwise have inherited** (`systems/core_dsl.md` #15;
  `docs/v5-design-decisions.md` §7.8). `milestone`'s `setup` and `retro` queues are
  declared `singleton: true` — a bound the loader cannot check (a queue's population is
  live ticket state) and that is therefore this system's own dispatcher's job; what the
  bound means — at most one work item ever assigned, never 0-or-1 unresolved at a time —
  is the entry below. Separately, the declaration-graph acyclicity check (above) has to
  treat a skeleton-less type — the project included — as a graph node, not only a
  `container`-skeleton type: a node set limited to `container`-skeleton types excludes
  the exact edge a project/container cycle runs on (`milestone.main` → `flow: project`,
  `project.build-out` → `flow: milestone`), and a loader built that way lets the cycle
  through. `Catapult.Dsl.Workflow.declaration_graph_nodes/1` is explicitly
  skeleton-agnostic (ORC-148), so a project/container cycle on that edge is caught by
  `DslGraph.acyclic?/1`.
- **#22 A sixth ORC-105 pass corrected the fifth pass's own singleton
  reading and gave this system's dispatcher a fact to check that the
  loader cannot: which type a fresh project actually starts from**
  (`workflow.md` #2; `docs/
  v5-design-decisions.md` §7.8). `singleton:` bounds a queue to at
  most one work item **ever assigned**, not 0-or-1 unresolved at any
  moment — a queue whose sole work item has reached `terminal` is
  *closed*, not empty-with-room, so this system's dispatcher rejects a
  second assignment outright rather than admitting it and filing
  `Blocked`, once one work item has ever been assigned to a singleton
  queue; "admit and file `Blocked`" and "reject outright" dispatch
  differently on the same input. Separately, `entry:` on a workflow
  bundle's own `bundle.yaml` names the type onboarding dispatches a
  fresh project from — this system reads it rather than inferring a
  starting point from which declaration looks project-shaped, an
  inference the loader never checks. Neither rule changes this
  system's shape, only what its dispatcher and its onboarding path
  each read and enforce. The singleton-lifetime rejection is
  superseded rather than built (ORC-148, below). The `entry:` read is
  built at load time — `Catapult.Dsl.Manifest` reads it off
  `bundle.yaml` and `Workflow.entry_problems/2` validates it resolves
  to a declaration-graph root — and an onboarding path dispatching a
  fresh project from it is Target (Phase 7), unticketed.
- **#23 ORC-115 (design pass, corrected on two later design reviews) gives
  this system's dispatcher a derived throwback default and names,
  without yet answering, whether a container instance can be a
  dispatch target in its own right** (`workflow.md` #6, #34,
  #35; `docs/v5-design-decisions.md` §7.8, §7.16, §7.19; answered at
  ORC-148, below). The dispatcher's own throwback handling resolves
  every decline's *legality* the same way, regardless of declaration —
  checked against "earlier in the citing type's own effective
  sequence" (identical to how the dispatcher already has to honor a
  Blocked-return); a gate's declared `throwback:` bounds nothing here,
  because `DeclineGate` enforces no allow-list at the command edge and
  a bounded allow-list would be a claim with nothing behind it. What a
  gate's declared `throwback:` supplies is a *landing point* — a
  single optional status: the dispatcher reads it when the gate names
  one, and falls back otherwise to the citing sub-array's own earliest
  entry as the one-click default — its own leading `pending`, when the
  sub-array has one (every generation-shaped sub-array does,
  `docs/dsl-syntax.md` §13's tightened check), its own
  non-review-shaped agent-balled entry directly otherwise — either way
  computed from the loaded workflow bundle at throwback time, never
  stored. This is the same shape `flow:` resolution and the
  singleton-lifetime check above already take (read the bundle, don't
  cache a derived fact). A gate sitting first in its own sub-array, or
  in no sub-array at all, has no earlier entry there to fall back to,
  so the dispatcher derives no default for it and the gate must
  declare `throwback:` explicitly (ORC-181, `docs/dsl-syntax.md`
  §15.4, §13, §15.10).
- **#24 A container instance is an agent dispatch target on the identical footing as a
  ticket instance (ORC-148).** Dispatching from a work item with a queue and one without
  were never different operations, only different status flows attached to the same
  mechanism (`workflow.md` #4, `docs/v5-design-decisions.md` §7.8) — the queue
  was never what made something a dispatch target, so this system does not need a
  container-shaped answer distinct from the ticket-shaped one it already has. With
  `setup` and `retro` inline (ORC-148, below), `setup`/`retro` dispatch
  (`Catapult.Delivery.ContainerLifecycle.open_inline/3`) by minting a synthetic
  per-entry flow (`ContainerLifecycle.Ids.work_item_id/3`, keyed on
  `project_id`/`container_id`/queue, not the container's own id) and routing it through
  the ordinary ticket-shaped branch/PR/ file-map/`DispatchRun` path — sufficient for
  what dispatches, since each inline entry gets its own PR rather than needing to share
  the container's: `lib/catapult/delivery/dispatch.ex`'s `HostPort.request` carries no
  branch or file-map field, and `store/dispatch_run.ex` keys on `flow_id`, never a
  container id.
- **#25 ORC-148 (design pass) retires `singleton:` and the fold that motivated it,
  closing the open question the two bullets above left standing** (`workflow.md`
  #16, #17, #19; `docs/v5-design-decisions.md` §7.8).
- **#26 A design review on ORC-148 changed the shape of this system's own
  `blocks:`-aware dispatcher work, filed above**
  (`workflow.md` #18; `docs/v5-design-decisions.md`
  §7.8). `blocks:` is an entry guard, checked once, at the transition
  into the entry it guards, never rechecked against the same occupancy
  — not a standing hold this system's dispatcher recomputes for as
  long as the guarded entry carries unresolved work. Concretely, this
  system's dispatcher evaluates a `blocks:` condition exactly once, at
  the moment a container's position would advance into the guarded
  entry — never as a periodic or event-driven recheck against an
  already-active entry, which is what would let a queue refilling
  mid-`retro` pull the container back out of it. That states what the
  guard is not — a standing recheck against an entry already entered —
  not how the dispatcher decides when to attempt the entry in the
  first place: `ContainerLifecycle` (the process manager named below)
  is an ordinary event-subscribed process manager, not a poll loop. It
  re-evaluates a guarded entry's eligibility on every engine event
  that could change the answer — most often, a work item the blocking
  queue counted resolving out of it — and the moment a `blocks:`
  condition reads clear, it is this same dispatcher, not a human
  action, that issues the advance command. A container never sits
  fully unblocked waiting to be asked forward; "checked once, at the
  transition" is what each of those event-triggered attempts does, not
  a claim that the dispatcher looks only a single time over the
  container's whole life. The entry guard lives in
  `Catapult.Delivery.ContainerLifecycle`: `forward_or_open/3` returns
  `[]` on `{:held, _holders}`.
  Separately, reaching `terminal` has a guard this system's dispatcher
  enforces unconditionally, regardless of implementation — every one
  of a container's own queues holding no unresolved work — never
  narrower than whatever `blocks:` relations a bundle happened to
  author, so a queue nobody named in any `blocks:` list still cannot
  be closed over on the way to `terminal`. Neither rule adds a loader
  check (`workflow.md` #8 is unaffected by the terminal guard,
  and the entry-guard reading is a semantics rule on a check that
  already exists). The terminal guard's enforcement is the `close/2`
  precondition the bullet below states, landed with the
  `next_commands/2` change that retired the backward move (ORC-177).
- **#27 A third design review on ORC-148 found the `blocks:` inversion above left a
  contradiction standing: a container's position still moved backward on a queue
  refilling, restated rather than removed — and a fourth found the third's own fix
  over-corrected** (`workflow.md` #26, #34; `docs/v5-design-decisions.md` §7.8). A
  queue un-resolving is not one of the ways a container's position moves backward —
  it would be the identical defect the bullet above retired from `blocks:` itself,
  reappearing one level up. **This system's dispatcher never moves a container's
  position backward because a queue refilled.** "An authored transition" alone would
  rule out more than it should: a `critique` entry's own decline is automatic, with no
  author in it, and `docs/v5-design-decisions.md` §7.19 requires it be structurally
  identical to a human decline at a gate. **What moves position backward is a step's own
  outcome — a decline, whether a `critique` entry's own agent run issues it (landing
  back on the generation entry it pairs with) or a human issues it at a gate (landing
  per its declared or derived `throwback:`) — or an explicit author transition** —
  concretely, returning a milestone from `retro` to `main`, which `ContainerLifecycle`
  never performs on its own. Forward advance into a guard-cleared entry stays this
  system's dispatcher's to make automatically, the moment the guard reads clear (the
  bullet above); a decline's backward move is likewise this system's dispatcher's to
  apply the moment it is issued, agent or human; the `retro` → `main` return alone is
  the author's own action, taken once `retro`'s own sub-array — its agent step and the
  human gates around it — has run to completion, not the instant `retro`'s output lands
  back in `main` and un-resolves it.

  **What replaces the walk** — two questions, both closed by record
  already settled rather than by new mechanism (`workflow.md`
  #16, #19).

  The terminal guard is enforced at `close/2`, as a second precondition
  beside the one it already carries, every finding adjudicated — the
  flag-set flip beside it is what a close emits, never a condition on
  whether it happens. Before proposing composition or dispatching
  `CloseContainer`, the dispatcher checks every `{:queue, entry}`
  `Sequence.steps/2` returns for which `Status.queue_shaped?/1` holds —
  every entry carrying a `flow:`, whether it nests a child
  container or holds ordinary ticket work, which is every declared
  queue proper — against `ContainerQueues.resolution/3`. Any that
  answers `:open` or `{:held, _}` refuses the close exactly the way an
  unadjudicated finding already does: logged, `[]` returned,
  re-evaluated on the next relevant event rather than polled. The
  check runs over the type's whole declared array, never scoped to
  entries behind `current` — the concrete shape of the terminal guard's "unconditional,
  reaches every queue-shaped anchor... whether or not any of them is
  also named in some other entry's `blocks:`": a queue long past
  `current` and named in no `blocks:` list is checked identically to
  one immediately behind it. `setup` and `retro` — the non-queue-shaped,
  `flow:`-less inline dispatch points `Status.queue_shaped?/1` already
  excludes — need no place in this check: `ContainerQueues.admits?/3`
  bounds each to at most one assignment ever, so once resolved neither
  can un-resolve, which is exactly why that guard text names
  "every queue-shaped anchor" rather than every positioned entry.

  No new loader check, no new event, no new command: a precondition on an existing
  dispatch, the identical shape the finding-adjudication check already is.
- **#28 ORC-31 (design pass) extends the Host port's operation vocabulary
  for feature-lifecycle PR management and decline harvesting** —
  branch, PR-open, merge-forward, merge, review-comment read, marker-
  comment write, PR-label set, and check-status read, plus a diff
  read for reconciliation. Each is traced to the protocol clause it
  serves rather than to what GitHub happens to expose (v5 §7.17's
  first discipline): branch/PR-open/merge-forward/merge cover §7.5's
  topology (child PR → feature branch, feature PR → main; merge-
  forward absorbs drift continuously and surfaces a conflict as a
  real signal, never a silent resolution); PR-label set is how the
  plane marks `ci:docs`/`ci:code` for §7.7's job selection; check-
  status read answers back keyed to head SHA regardless of base
  branch, exactly as §7.7 requires; review-comment read and marker-
  comment write are §7.4's harvesting split, and they are two
  different GitHub comment kinds by design, not by convention —
  review-comment read pulls line-anchored review comments (the
  harvesting source), marker-comment write posts plane-authored,
  issue-level PR comments (bounces, findings). Keeping them on
  separate GitHub APIs is necessary but not, on its own, sufficient
  for telling human feedback from machine feedback — see the
  correction below. Diff read is this ticket's
  own restated invariant (conventions §11): the port moves refs and
  reads diffs, it never checks out. As with every earlier operation
  on this port, each lands in `HostPort.Actions` and `HostPort.Fake`
  in the same change — never one ahead of the other.
- **#29 Author-review correction: harvesting classification filters by author
  identity, not by endpoint alone — a revision to §7.4's classification mechanism for
  the GitHub-PR surface, not an application of it** (ORC-31). "Arrived via the
  review-comment endpoint" is not sufficient to call a comment human, and §7.4 does not
  hold unchanged on this surface: §7.4's rule covers *any* machine, because its premise
  is that machines mark, while endpoint-of-origin covers only *our* machine. Every
  third-party actor with review access — a GitHub App, a linter, a review bot, Claude
  Code's own inline review comments — posts through the identical review-comment
  endpoint a human uses; under endpoint-alone classification those harvest as human
  declines and thread into regeneration as author feedback, silently. **Revision:**
  review-comment read filters its results by author identity before anything is treated
  as harvestable — `performed_via_github_app` is reliable for GitHub-App-authored
  comments, `user.type == "Bot"` is reliable for bot accounts, and either excludes a
  comment from the human bucket. **Residual, named rather than hidden:** a bot
  authenticating with a human's personal access token is indistinguishable from that
  human at the API; nothing here closes that gap, and no fix is known.
- **#30 List-shaped read operations page to exhaustion; neither asserts a
  bound it hasn't measured** (ORC-31, design pass, author-review
  correction). `review-comment read` and `check-status read` are both
  list reads with no natural cap — a contested review on a real gate
  decline is not a handful of comments. This project has already
  shipped the single-page version of this defect once, in the sibling
  adapter: ORC-101 (Triage) found the Go pipeline's
  `internal/host/github/github.go` `ListAgentRuns` reading exactly one
  `per_page=100` page with no filter, on the reasoning "anything past
  100 runs ago is not it" — reasoning that turned out wrong under
  sweep noise. `HostPort.Actions` follows GitHub's pagination (the
  `Link` header / cursor) to exhaustion for both operations rather
  than reading one page and assuming the rest doesn't matter;
  `HostPort.Fake` mirrors the same contract — its fixtures include a
  multi-page case for each, not only a single-page one — so the
  offline sim ring can catch a caller that assumes one page is
  everything. No cap is imposed at this layer; a rate/cost bound, if
  one turns out to be needed, is a dispatch-budget decision (v5
  §7.12.1), not a silent truncation here.
- **#31 The marker vocabulary is a typed module, scoped to GitHub PR comments only**
  (ORC-31; extends the marker-retirement bullet above rather than reopening it).
  `HostPort.Marker` (naming follows `HostPort.Actions`/`HostPort.Fake`'s own pattern)
  holds a closed enum of kinds, each with a render function producing the exact comment
  body and a parse function reading one back — `{:ok, {kind, payload}} | :not_a_marker`
  — so no call site builds a marker string by interpolation and no call site greps a
  comment body for a substring. **`parse/1`'s named caller: marker-comment write's own
  idempotency check.** Before posting a new bounce, the plane lists the PR's existing
  issue-level comments and parses each with this function to check whether the
  scope-violation marker for this gate decline is already there, so a re-triggered
  decline path (a retry, a resumed pass) doesn't post a second `Ready for rework`
  comment. This is a read of the plane's own issue-level comments and is not the
  harvesting read — `parse/1` never sees a line-anchored review comment, and
  harvesting's classification (the author-identity entry above) never calls it. Phase 4
  needs exactly one kind to start: the scope-violation bounce already named in §7.5 ("a
  plane-authored marker comment naming the paths, `Ready for rework`"). Later kinds —
  §7.11's findings marker, §7.14's bug-intake sequence stamp — join the same closed enum
  when their phase needs them; they are not invented ad hoc at whichever call site first
  wants one. This module governs the write side only. **The read side needs no parser of
  its own only because the plane never authors a line-anchored review comment — an
  invariant to keep, not a free property.**
- **#32 The Fake's forge state lives in a per-test supervised process, not a Store
  table** (ORC-31). `dispatch_run` is not the precedent it looks like:
  `delivery_dispatch_runs` is written by the *real* adapter as well as the fake —
  `HostPort.Actions` opens that record on every live dispatch, because it is production
  state the plane genuinely keeps. Branches, PRs, comments and check runs have no
  production writer at all; GitHub holds them and the real adapter only ever reads them
  back, so Store tables for those would exist solely for the fake, inside the plane's
  production schema, with nothing in production ever writing a row. The one thing a
  Store table would have bought — sandbox safety under `mix test`'s async runs — needs
  no schema: a per-test process is isolated by construction, and with no database
  involved there is no sandbox to need. `HostPort.Fake` gains a GenServer per test
  (started and stopped with the test, like any other test-owned process in this
  codebase) holding branches, PRs, comments and check runs in memory, keyed to that
  process — not a Store table.
- **#33 No HTTP-mock-server-based fake** (ORC-31, design pass; refusal,
  scope: system:delivery). The Actions adapter's own code path could
  run unmodified against a stub GitHub server (Bypass, a cassette
  replay of the REST API), and that will look like the easier fake to
  write. Refused: it fakes the vendor's transport, not the protocol —
  the exact property v5 §7.17's second discipline names ("the fake is
  written against the protocol rather than mirroring the adapter"),
  and an HTTP-level stub would quietly start requiring GitHub's own
  URL shape, pagination and rate-limit behavior to keep the fake
  alive, which is the coupling the fake exists to avoid. `HostPort
  .Fake` stays a plain Elixir implementation of the behaviour with no
  HTTP dependency at all.
- **#34 The sim-style test ring drives a full branch → PR → comment →
  harvest → merge-forward → merge scenario through `HostPort.Fake`
  alone, with no network** (ORC-31, design pass). It lives beside the
  rest of this system's suite, under this doc's own file map
  (`test/catapult/delivery/`) — no separate ring or `live` directory,
  the same reasoning `systems/foundation.md`'s live suite already
  gives for a different tag. It carries no `:live` tag
  itself: nothing in it crosses a real network boundary, so the ring
  is an ordinary async suite member, not a live one. Populating this
  ring is scope, not scaffolding — the same standing principle
  `systems/generation.md` states for the dispatch fake — because it
  is what lets protocol work on branches, PRs and harvesting continue
  to be exercised, and continue to be provably correct, on a day
  GitHub itself is down.
- **#35 The feature-ticket lifecycle is a Commanded process manager,
  `Catapult.Delivery.FeatureLifecycle`, reading engine's own events — not a second
  engine aggregate** (ORC-32, design pass; v5 §7.13's porting-model citation,
  "snapshot→actions purity maps near-1:1 onto a Commanded process manager," is this
  component). It is `application: Catapult.Engine.Application`-subscribed, the same
  application `Catapult.Engine.Router` already names, because the events it reacts to
  (`FlowOpened`, `DraftCommitted`, `DraftApproved`, …) are engine's own. **Checked, not
  assumed: this does not reproduce the compile-connected edge
  `Catapult.Engine.Application`'s own moduledoc warns a router macro creates.**
- **#36 Identity is the pair `(project_id, flow_id)`, composited into one
  process-manager identity — never a bare id** (ORC-32, design pass;
  ORC-87). A ticket IS a flow instance (v5 §7.10, "opening a ticket IS
  opening a flow instance"); `FlowOpened` and `engine_flows` already
  carry and key by `(project_id, id)`, for the exact reason
  `systems/engine.md`'s ORC-87 entry keys every other engine store
  table the same way — a caller-supplied id is a per-project slug, not
  globally unique, and `systems/engine.md`'s own evidence is that two
  independently-written authors reach for the identical plausible one.
  A process-manager instance started from `interested?(%FlowOpened{
  project_id: p, flow_id: f})` on bare `f` alone repeats that bug one
  layer up. `interested?/1` returns `{:start, "#{p}:#{f}"}` (or an
  equivalent unambiguous composite — the exact separator is dev's),
  and every later clause matching this project's other engine events
  derives the same pair from the event's own `project_id` plus
  whichever id names the ticket's entry node or flow.
- **#37 The loaded workflow is a parameter, never resolved — the same
  shape `ReadyScopes.ready/3` and `Scheduler.trigger/2` already take a
  loaded `Chain.t()` in** (ORC-32, design pass).
  `Store.current_bundle_version(project_id, :workflow, at_sequence)`
  reads the ninth projection (`systems/engine.md`), but nothing mints
  a `projects` row or a `FlipActiveBundle` event on the `:workflow`
  axis today, so a resolver built now would be built against a shape
  the bindings work (v5 §7.10 — "not urgent to build... cheap and
  high-value when it lands") is free to draw differently once it
  exists. Whatever calls into this process manager's callbacks
  supplies the already-loaded `Catapult.Dsl.Workflow.t()` — gates,
  environments, critique — the identical calling convention
  `ReadyScopes`/`Scheduler` already establish for the chain axis, so
  the two axes' consumers read alike.
- **#38 Reachability, settled: `checks` is this phase's last reachable
  position; `merge`, `deploy`, `validating` and `terminal` arrive with
  Phase 7** (ORC-32; `workflow.md` #10). The kinds themselves
  are never in question — `Catapult.Dsl.SystemStatus`'s closed table
  fixes them all up front, so nothing here adds or removes one. What
  is open is which of them this process manager's own callbacks ever
  route a ticket into. `merge`/`deploy` are reconciliation and
  publish outcomes and `validating` is §7.11's post-deploy repair
  loop, which needs a deploy, which needs `merge` — each sits behind
  Phase 7's child lifecycle/mutex/dispatch/reconciliation machinery.
  So this process manager's `interested?`/`handle` pair is total over
  `pending → generation → [critique] → [gate] → … → checks` and
  *recognizes* the later kinds without ever driving a ticket into them
  — a bundle declaring gates or environments after `deploy` still
  loads and validates (`workflow.md` #5, #12), unaffected. A ticket reaching `checks`
  sits there under this phase; what moves it again is Phase 7's own
  dispatcher.

  **`checks` can recur, once per generation-shaped sub-array (`workflow.md` #6,
  #7) — the boundary is the last such occurrence in the type's own array that
  precedes the array's own `merge` entry, not the first** (ORC-182).

  **The last-occurrence boundary reaches a second gap, in
  `Projection.passable?/2`.** With exactly two clauses — `kind in
  [:pending, :generation, :critique]`, and a gate — and `resting/3`
  never testing the sequence's own last entry, a first-occurrence
  `checks` (always last, on the shipped bundle) never hits the missing
  clause: `take_through_boundary/1`'s first-occurrence anchor was
  load-bearing for this too. Moving the boundary to the last
  occurrence makes every earlier `checks` — and, on §15.2's shape,
  `design`, `architecture`, `implementation`, and every `reconcile`
  ahead of the final `checks` — a *non-last* position `resting/3` does
  test, raising `FunctionClauseError` out of a clause list never asked
  to answer for them. Two answers were coherent; the rule is:

  - `design`, `architecture` and `implementation` are generation-shaped
    the identical way `generation` already is (`dsl-syntax.md` §13,
    §15.1) and this projection draws no distinction between the four
    anywhere else (`Sequence.to_position/1` maps all of them through
    the same `{:kind, atom}` shape) — the clause's `kind in [...]`
    list names all four, not `generation` alone.
  - `checks` and `reconcile` stay unpassable **at every occurrence,
    not only the last.** This projection has no event reporting a
    checks run's own outcome or a reconcile's own join independently
    of a fresh `DraftCommitted`/`RunFailed` (`FeatureLifecycle`'s own
    `interested?` list, which is the whole of what this process
    manager observes), so nothing here can tell an intermediate
    `checks` or `reconcile` apart from the boundary one the paragraph
    above already covers. `passable?/2` carries a catch-all clause
    answering `false` for every kind not named in the bullet above,
    and every `checks`/`reconcile` occurrence renders and rests
    exactly like the boundary always has. Consequence: a ticket
    resting at a non-final `checks` or `reconcile` does not advance
    into that phase's own `critique`/gates under today's event
    vocabulary — real on §15.2's documented shape, not on the shipped
    bundle. Giving this phase a signal for an intermediate checks or
    reconcile outcome is new Phase 4 advancement behaviour, a design
    of its own; it is unbuilt.
- **#39 A third gap, in `resting/3` itself, surfaces only against a recurring boundary
  kind.** `resting/3` found "not yet passable" by walking `Sequence.positions/2`'s list
  with `Enum.find (positions, last, &(&1 != last and not passable?(&1, state)))` —
  excluding the sequence's own last entry by comparing *values*, not index. Once
  `{:kind, :checks}` legitimately recurs (above), every earlier occurrence shares that
  value with `last` and the `!= last` guard excludes all of them alongside the true
  final one — silently, since `passable?/2` is never even called on them. The walk sails
  straight past every non-final `checks` instead of resting there, contradicting "every
  checks/reconcile occurrence renders and rests exactly like the boundary always has"
  two paragraphs above. The walk pairs each position with its index and excludes by
  `index != last_index` instead of by value.
- **#40 The label owner, settled: the work surface renders; this projection never
  does** (ORC-32, design pass, closing this ticket's other open question). The
  projection carries exactly what `Catapult.Dsl.SystemStatus.kind()` and the loaded
  workflow's own gate/environment `name:` already give — `:generation`,
  `"engineering-review"` — never a rendered string.
- **#41 Gate skip-on-no-diff and the entry-tier rule are both read off
  machinery this projection already depends on, not new engine
  mechanism** (ORC-32, design pass). A gate is offered to the human
  only once its own reviewed scope has committed something new since
  the ticket last stood at it — `DraftCommitted`'s own `tier`/
  `body_sha` already say whether a tier the gate reviews produced
  anything this cycle, the identical content-identity §7.11's
  staleness derivation already reads (`systems/engine.md`: "Staleness
  is a projection, never stored state"). A gate whose scope committed
  nothing — never dispatched (the entry-tier rule, §7.3, skipped it
  outright) or regenerated byte-identical — auto-advances rather than
  asking; "an author gate that asks nothing teaches the author to stop
  reading them" is the reason, not a new invariant. Entry tier itself
  is read once, at `FlowOpened` (the flow's own `ticket: {entry:
  <tier>, ...}` declaration, v5 §7.10), and narrows which
  `generation`/gate pairs `interested?` ever considers reachable for
  that instance — every kind before the entry tier's own status is
  simply never a candidate, the same "nothing to review is
  orchestration's decisionless pass generalized" framing §7.3 already
  gives it.
- **#42 Blocked carries no new mechanism either** (ORC-32, design pass). `:blocked` is
  one of the twenty fixed kinds (`Catapult.Dsl.SystemStatus`) with `ball: :varies`; this
  process manager enters it as any other transition, and the flavor label plus origin
  are read the same way v5 §7.19 already settles for the platform generally — off the
  ticket's own projected history, never stamped onto a comment (this doc's
  marker-retirement bullet above already retires stamping "for surfaces we own").
- **#43 What advancing past a gate on a human's word dispatches to stays open,
  unchanged by this ticket** (ORC-32). v5 §7.16 already names this open — "Approval is a
  status... the mechanism is a later increment, and a sizeable one" — and the process
  manager above covers only the transitions engine's own events already drive (dispatch,
  commit, skip-on-no-diff). Which aggregate a human's sign-off command validates against
  under §7.16's optimistic concurrency is `Catapult.Engine.Aggregate` — `ApproveGate`/
  `DeclineGate`, `systems/engine.md`'s own entry (ORC-34) — the narrow half.
- **#44 What advancing past a gate dispatches to includes an engine-side consequence,
  sized to exactly Phase 4's own scope (ORC-229).** `ApproveDraft`/`DiscardDraft`
  (`systems/engine.md`'s own entry, `Catapult.Delivery.DraftResolution` below) is the
  "later increment, and a sizeable one" v5 §7.16 named for turning a passed gate into an
  engine-recognized approval.

- **#45 The storage question the three entries above leave open is
  engine's, not this system's — corrected here rather than left to
  read as a contradiction** (ORC-104;
  `systems/engine.md`'s own entry). The storage distinguishing
  "instances that exist" from "the instance that is current" is not a
  second store this system keeps: a container
  instance's mint, its activation and every move of its current queue
  are original protocol facts with nowhere else to be authoritative,
  and `systems/engine.md`'s "a project has one aggregate, not two"
  already settles where an original fact about a project lands —
  `Catapult.Engine.Aggregate`, the same one every chain-axis event
  already writes to, never a second aggregate or a delivery-owned
  table standing in for one. What this system owns is the *dispatcher*
  — deciding when a queue has emptied of unresolved work, when a
  `blocks:` sibling has cleared, and when the container's own position
  reaches an inline agent-balled entry (`retro`/`setup`, ORC-148) and
  it may be dispatched — and
  issuing the resulting command into engine's aggregate; engine
  validates and records it, and its projection is what this
  system's dispatcher reads back, keeping no second copy of its own.
  This system's own store keeps nothing about container position that
  engine's projection doesn't already hold.

- **#46 The dispatcher is a new process manager, `Catapult
  .Delivery.ContainerLifecycle`, built beside `FeatureLifecycle` on the
  identical `application: Catapult.Engine.Application`-subscribed
  shape — and the first of this system's process managers that writes
  back, not only reads** (ORC-104). Every other process manager
  this system ships (`FeatureLifecycle`, ORC-32) only
  projects engine's events into this system's own read models; this
  one also issues commands into `Catapult.Engine.Aggregate` once its
  own dispatch conditions are met — the split `systems/engine.md`'s
  entry states from the other side.
- **#47 It dispatches through `Catapult.Engine.Router` itself rather than returning
  commands for Commanded to route.** A process manager ordinarily returns commands and
  its `application:` routes them; that is not available here, because
  `Catapult.Engine.Application` deliberately does not compose the router (keeping it off
  the compile-connected graph — that module's own moduledoc carries the reason). A
  returned command is therefore an *unregistered* command and Commanded stops the
  manager. Two consequences are load-bearing rather than incidental: the dispatch must
  be `consistency: :eventual`, since a strongly consistent dispatch from inside a
  strongly consistent handler waits for that handler to catch up with itself; and a
  rejected command must be absorbed rather than fatal, because the rejections this
  design produces on purpose — a stale `from_queue` losing its compare-and-swap, a
  re-mint of an instance that already exists — are the manager re-deriving a decision
  already made, and Commanded's default is to stop on them. The convergence loop is the
  resulting events coming back around to the same manager. Dispatch stays uniform per
  `workflow.md` #9: whatever a queue's resolved `flow:` turns out to be, this
  process manager treats identically — a `ticket`-skeleton resolution opens an ordinary
  flow instance through the existing `OpenFlow` path (unchanged, still driven only by
  `ready_scopes` on the chain-axis side), a `container`-skeleton or skeleton-less
  resolution issues a mint command instead — never branching on anything the queue entry
  itself declares, only on what the resolved declaration contains. `retro` and `setup`
  are not special-cased here either: each is an ordinary declared queue entry whose
  `flow:` names an ordinary chain-bundle flow, dispatched the same way any other queue's
  `flow:` is (`docs/v5-design-decisions.md` §7.8).

- **#48 A process manager's own persisted state is bound by the identical JSON round
  trip its events already are — settled as a standing rule, not just fixed on the one
  instance that crashed** (ORC-120, bug).
  `Commanded.ProcessManagers.ProcessManagerInstance` calls `persist_state/2` after every
  handled event, unconditionally, which serializes the manager's own struct through the
  identical `Commanded.Serialization.JsonSerializer` `config/*.exs` already names for
  the event store — the same encoder every event struct here already carries `@derive
  Jason.Encoder` for, and the same one `Catapult.Engine.Events.FlowResumed`'s own
  moduledoc already documents refusing a bare `Sequence.position()` tuple over, for the
  reason recorded there: `Jason` has no `Encoder` for a raw tuple, so a struct carrying
  one crashes real persistence on the first write, not on `mix test` — the suite's
  `InMemory` adapter (`config/test.exs`) never round-trips state through JSON at all, so
  this class of defect is invisible to the default suite by construction, on any process
  manager, indefinitely.

- **#49 Every carried finding leaves adjudicated, enforced as the container's own
  close — not a check keyed to the queue name `retro`, and not a separate check bolted
  on afterward** (ORC-104, ORC-148). `retro` is an ordinary agent-balled entry directly
  in `milestone`'s own array (`workflow.md` #19) — dispatched against
  the milestone container instance itself, a legal dispatch target on the identical
  footing as a ticket (`v5-design-decisions.md` §7.8) — never a separately minted ticket
  or a `flow:` of its own. Its dispatched run reads the findings this milestone carried
  and, for each, either opens it under its own key (an ordinary flow instance, through
  the same uniform dispatch above) or writes a decline with its reason — an engine
  event, `FindingAdjudicated`, on the milestone container instance's own aggregate. The
  container does not advance past `retro` while any finding it carries lacks one of
  those two outcomes — because an unadjudicated finding is exactly that, unresolved work
  this container is still holding — but the check is attached to the container's own
  close, not to a queue recognized by the name `retro`: naming the queue would mean the
  dispatcher branching on the word `retro`, which is the implicit anchor meaning
  `workflow.md` #4 refuses (`skeleton:` names the shape; nothing in the loader
  branches on a type's own name) and which `workflow.md` #10's admission rule is
  written to keep out of plane logic.

- **#50 The aggregated flag set flips through the ordinary intent → idempotent effect
  → observed completion discipline (§7.1), because a flag flip is an external effect
  exactly like a GitHub call** (ORC-104, design pass; v5 §2.10, §7.8). `retro`'s
  dispatched run computes the union of `feature_flags/0`-registered flags across this
  milestone's member features (membership read off `systems/engine .md`'s new
  by-reference projection) once the container is otherwise ready to advance past it —
  after the `:live` gate has cleared (already enforced structurally: a red `:live`
  verdict counts as `main` still carrying unresolved work, so `main`'s declared `blocks:
  [retro]` keeps `retro` from being *entered* at all until it clears, `workflow.md` #18's
  entry-guard reading — `retro` never begins mid-red, so nothing has to hold its result
  back after the fact) and the author's own manual pass. The flip is not a
  plane-internal event alone: it is a `FunWithFlags`-backed enable call, so it follows
  the outbox discipline every other outbound act in this system already does — a
  `FlagSetFlipRequested` intent event, an outbox worker performing the enable calls, and
  a `FlagSetFlipped` completion event once the world confirms.

- **#51 Composition proposes and never commits, and proposes off the structured
  signals this system already keeps rather than reproducing orchestration's flat backlog
  view** (ORC-104, design pass). `setup`'s dispatched run — forward-looking, dispatched
  the same uniform way any other agent-balled entry is — computes candidates for the
  next container's `prep` from this system's own backlog/gating projection and writes
  them to a new, purely computed proposal read-model; nothing here creates a real
  ticket. Committing a proposal into an actual `prep` entry is an ordinary ticket-open
  action, an author's to take, unchanged by this ticket and out of its scope (explicitly
  named as such in the ticket record) — the milestone screen that will render this
  proposal list is dashboard v3's, later.

- **#52 ORC-33 (design pass) finds ORC-31's own operation vocabulary short
  one shape, and this is that shape named rather than patched
  silently.** Branch/PR-open/merge-forward/merge/labels/checks/diff
  (`HostPort`'s ORC-31 bullet above) cover topology, CI signaling and
  reconciliation, but nothing in that list writes *content* onto an
  arbitrary ref. `reset_repo/2` looks adjacent and isn't: its own
  moduledoc already restricts it to fixture content, and
  `HostPort.Actions.reset_repo/2` takes no branch argument at all;
  every `put_file/2` call resolves against the repo's default branch
  through GitHub's plain `contents/:path` endpoint, with no `ref`
  query parameter. Pushing a committed draft's body onto a
  feature branch that is very much not the default branch needs a
  real branch parameter, so `HostPort` carries two further callbacks
  rather than reusing that one: `commit_files(project_id, branch,
  files, message)` — a per-file Contents-API shape (read the blob sha
  if the file exists, PUT with it if so; `reset_repo/2` rides a single
  Git Data commit instead, this doc's ORC-228 entry below), which
  `commit_files/4` keeps since every call pushes exactly one file and
  its round-trip count never grows — generalized with an explicit
  `branch:` ref and a caller-supplied commit message, since
  `"catapult: reset fixture"` is `reset_repo/2`'s own message and
  wrong for everything else — and `update_pr_body(project_id,
  pr_number, body)`, a PATCH needed because pushing a draft is the
  first operation that edits a PR after opening it. Both land in
  `HostPort.Actions` and `HostPort.Fake` together, the same rule every
  earlier operation on this port already follows.

- **#53 The write side is a new process manager, `Catapult.Delivery
  .FeaturePublisher`, not a wing bolted onto `FeatureLifecycle`.** Both are
  `application: Catapult.Engine.Application`-subscribed to the identical events
  (`FlowOpened`, `DraftCommitted`) and identified the same composite way (`project_id <>
  ":" <> flow_id`, ORC-87) `FeatureLifecycle` already establishes — reused, not
  reinvented, for the same Phase-4 reason `FeatureLifecycle`'s own moduledoc names:
  nothing yet opens two flows concurrently on one project, so resolving "the flow" from
  a bare `project_id` is correct today. What is not reused is the module.

- **#54 Trigger timing, settled: the branch and the PR open together, on the flow's
  first successful `DraftCommitted`** — closing the ticket's own open question.
- **#55 The branch name is `feature/<slug>-<flow_id>`** (ORC-33) — the id for
  uniqueness, the slug for what a branch list otherwise cannot show. A title slug cannot
  *be* the identity, for the collision reason `systems/engine.md`'s own ORC-87 entry
  gives for every per-project id this system handles: two independently-authored flows
  can share a plausible title. That argues for keeping `flow_id` in the name, not for
  dropping a slug a human could otherwise read. The slug is read once, off the flow's
  own ticket title at `FlowOpened` — the same declaration entry-tier already reads
  (`ticket: {entry: <tier>, ...}`, above) — lowercased, non-alphanumeric runs collapsed
  to one `-`, truncated to a fixed length. It is never re-read: the branch name, slug
  included, is read back off the same `FeaturePublication` row named below rather than
  recomputed, so a title edited after the fact can't disagree with what GitHub already
  holds — which is what answers the rename worry, using machinery this bullet already
  has rather than avoiding the slug to dodge it. `FeaturePublisher` records
  `branch_name` and `pr_number` on its own row the moment both calls succeed
  (`Catapult.Delivery.Store .FeaturePublication`, `delivery_feature_publications`,
  composite-keyed `(project_id, id)` exactly as `Store.FeatureLifecycle` already is) — a
  re-observed `DraftCommitted` for a flow that already has a row skips straight to the
  push below.

- **#56 Every push is tracked for idempotency in this system's own store,
  never as a new engine event.** The tempting shape borrows
  `FlagSetFlipRequested`/`FlagSetFlipped`'s intent → effect →
  completion pair wholesale, and that's the wrong precedent here. A
  flag flip is a fact the *container itself* holds (§7.8's "features
  merge dark... the milestone lights up together" is real aggregate
  state), so its completion belongs on `Catapult.Engine.Aggregate`,
  where every other original fact about a container already lands
  (`systems/engine.md`'s "a project has one aggregate, not two").
  Whether a given node's committed body has been pushed onto a git ref
  is not a fact anything in engine's own domain reasons about — nothing
  in `ready_scopes`, dispatch or the lifecycle projection reads it back
  — so it is `delivery_dispatch_runs`'s category of fact, not
  `FlagSetFlipped`'s: bookkeeping this system's own outbound act keeps
  for its own retry logic, with no consumer on the other side of the
  aggregate boundary. `Catapult.Delivery.Store.ArtifactPush`
  (`delivery_artifact_pushes`, keyed `(project_id, node_id)`) records
  `tier`, `scope_key`, `path`, `body_sha` and `pushed_at` once
  `commit_files/4` returns `:ok`. The Contents API is idempotent per
  path regardless (the blob-sha-then-PUT shape `commit_files/4` uses;
  `reset_repo/2` rides a single Git Data commit instead, ORC-228), so
  a lost row costs a redundant PUT, never a wrong one — the row exists
  to skip the call, not to guarantee the correctness of one that runs
  twice.

- **#57 The repo-relative path a committed body writes to is a named placeholder, not
  a settled convention** — `.catapult/artifacts/<tier>/<node_id>.xml`, the raw,
  schema-validated body `CommitPath` already grammar-checked, written verbatim.

- **#58 The PR body is regenerated whole on every push, never appended to** — reading
  back `Catapult.Delivery.Store.ArtifactPush`'s own rows for the flow rather than
  re-deriving the set from engine's nodes (`Engine.Store.list_nodes/2` is scoped per
  tier, and this system already keeps the exact join it would take to reconstruct the
  set by hand). One line per row — tier, scope, path — links the reader into the diff by
  path rather than restating its content; a full rewrite means a re-processed event or a
  retried push can never leave a duplicate or a stale line the way an append-only body
  would.

- **#59 Correction: the feature PR's diff is not the review surface the ticket's own
  argument says it is.** `docs/v5-design-decisions.md` §7.4's already-live text (the
  "Reversed at §7.17" passage, which predates this ticket and which this ticket's own
  record does not cite) splits artifact feedback by kind: prose reviews natively, at
  sentence granularity; only code review stays line-anchored in a PR. Every tier Phase
  4's chain produces is prose (`comparch`, `sysarch`, `impl`, `feature_expansion`,
  `vocab` — XML-in, schema-validated, never a line of application code), so the surface
  a human actually reads at `Product review`/`Architecture review` is dashboard's native
  review screen, once dashboard builds it (already a hard dependency of this whole
  system — "Depends on" below) — not this PR. What the ticket record calls "the point"
  survives with a narrower job: the PR stays the versioning, CI (§7.7's
  `ci:docs`/`ci:code` labels) and child-base surface §7.5 already names, and its body is
  a navigation aid for whoever does open it, not the mechanism gate-entry depends on.

- **#60 Two consequences of the correction above, named rather than left
  for the next pass to guess at (ORC-33, design pass, author
  review).** First: **ORC-31's author-identity filter is not
  orphaned by this correction — it is early.** The doc/code split
  settles *which surface* each artifact kind reviews on; it does not
  retire either surface's own machinery. The filter's consumer is
  line-anchored *code* review, which arrives with child PRs in Phase
  7, not with a prose-only feature PR — so "the PR is not the review
  surface" does not mean the filter has no consumer. The filter and
  its residual (a PAT-authenticated bot indistinguishable from the
  human it authenticates as) stay exactly as recorded above, waiting
  on Phase 7 rather than dead. Second: **`ORC-34` ("Harvest declines
  from PR review into regeneration feedback") is scoped by the
  split.** Phase 4's declines are prose declines, read from the native
  review surface (`docs/ui-spec.md`, once UI v1 builds it) rather than
  from PR review comments — the PR-harvesting half its title names is
  the code path, and arrives later with the same Phase-7 child PRs the
  first consequence names.
- **#61 The ordering fact the correction above states in passing is worth its own
  line: Phase 4's gates are unreadable by a human until ORC-75 (UI v1) ships the native
  review screen** (ORC-33, design pass, author review) — a real intra-milestone
  dependency, not an aside. `FeaturePublisher` and every gate behind
  `Catapult.Delivery.FeatureLifecycle`'s projection can be built and can fire without
  ORC-75; nothing here waits on it mechanically.
- **#62 Merging stays out of this ticket's reach, unchanged from the standing
  reachability record above.** `FeaturePublisher` calls `create_branch/3`, `open_pr/2`
  and the two operations this ticket adds; it never calls `merge_pr/3`.

- **#63 ORC-34 (design pass) narrows its own ticket's premise before designing
  anything: Phase 4's harvest source is `document-review`, not this system's GitHub
  PR.**

- **#64 Design review threw the first draft back: it kept no second copy
  of the mechanism in name while building one in fact, and it deferred
  the write path this scope actually needs.** A
  `Catapult.Delivery.Store.FeedbackBucket` cache beside
  `CommentPosted` on `Catapult.Engine.Aggregate` is a second engine
  projection whatever it is called — and a cache whose writer
  (whatever reacts to a decline) races the timer-driven sweeper that
  reads readiness, reopening the very silent-blank ambiguity the
  ticket exists to close — so there is none. The decline trigger,
  arriving as a command like any other author action and validated
  the same way, is not deferrable to §7.16's later gate-sign-off
  increment: `docs/ui-spec.md` §2 rule 2 refuses `document-review`
  (ORC-75) inventing a comment or a decline command the protocol
  doesn't have, so ORC-75 cannot design its screen until this ticket
  lands the vocabulary. The full mechanism — `CommentPosted`,
  `CommentFeedback`, `ApproveGate`/`DeclineGate`, `GateComments`, all
  four log-derived, none of them a second store — is recorded once, in
  `systems/engine.md`'s own entries, since that is where the
  aggregate, the commands and the event log they read all already
  live; this doc points at it rather than restating it.

- **#65 This system's job is the two reads and the one write the mechanism above
  doesn't itself perform: rendering, and moving a ticket's projected status.**
  `Catapult.Generation.ContextAssembly` reads
  `Engine.Projections.CommentFeedback.since_last_resolution/2` and
  `Engine.Store.reviews_for_node/2` directly at render time (`systems/generation.md`'s
  own entry) — this system supplies neither; there is no delivery-owned copy of
  `feedback` or `prior_review` for either ticket's premise to have gotten wrong this
  time. What this system does own: `Catapult.Delivery.FeatureLifecycle` gains two more
  `interested?`/`handle` clauses, `GateApproved` and `GateDeclined`
  (`systems/engine.md`), the same process manager ORC-32 already built to project every
  other engine event this ticket's status tracks. `GateApproved` advances the ticket to
  the next entry in its type's own `statuses:` array after the gate's position (a lookup
  against the loaded `Catapult.Dsl.Workflow.t()` this process manager already threads
  through, per ORC-32's own entry above); `GateDeclined` moves it straight to
  `throwback_to` — no lookup needed, the event already names the resolved target,
  guaranteed reachable by the command edge's own "earlier in the citing type's own
  array" check before dispatch — the identical predicate `Catapult.Dsl.Workflow
  .gate_throwback_problems/2` already runs at load time against a *declared*
  `throwback:` (unaffected by ORC-115's narrowing of that field to a single target,
  `workflow.md` #34), reused at the command edge as a second, runtime instance
  of the same check against whatever the human actually picked — declared override,
  derived default, or an earlier-prefix choice alike (`workflow.md` #6, #34).

- **#66 Draft approval/discard is a second write-side process manager, not
  a third `FeatureLifecycle` clause** (ORC-229; `systems/engine.md`'s
  own `ApproveDraft`/`DiscardDraft` entry). `FeatureLifecycle`
  dispatches no commands, ever — projection only, behaviorally,
  precisely so a fault in a *write* triggered off engine's events
  never risks the read model every status column and every gate
  already depends on — and dispatching `ApproveDraft`/`DiscardDraft`
  back into the engine on `GateApproved`/`GateDeclined` is exactly
  such a write, with the identical replay hazard `FeaturePublisher`'s
  own split already exists to avoid: a process manager's `handle/2`
  re-runs on every rebuild, and a second write-triggering handler on
  the instance that already owns the read model is the wrong instinct
  to build on even though `systems/engine.md`'s own compare-and-swap
  makes a replayed dispatch a rejection rather than a duplicate event.
  `Catapult.Delivery.DraftResolution` is the process manager:
  identical subscription and identification shape to
  `FeatureLifecycle`/`FeaturePublisher` (`application: Catapult.Engine
  .Application`, `project_id <> ":" <> flow_id`, ORC-87) — and,
  because neither `GateApproved` nor `GateDeclined` carries a node id,
  and `Catapult.Engine.Store.Flow` has no node column to look one up
  from, a third `interested?` clause on `FlowOpened`, identical in
  shape to `FeatureLifecycle`'s own, starts each instance holding
  `entry_node_id` in its own state rather than deriving a node from the
  resolving event. `handle/2` for `GateApproved`/`GateDeclined` then
  calls `Catapult.Engine.Store.get_node(pm.project_id,
  pm.entry_node_id)` — not to find the node, which the held state
  already names, but to read `Node.current_draft_id`, the value that
  becomes the resulting `ApproveDraft`/`DiscardDraft`'s own `draft_id`;
  `systems/engine.md`'s own compare-and-swap is what makes
  populating a command from a projection read safe rather than a race.
  Nothing this process manager decides is read off `FeatureLifecycle`'s
  own projection, for the identical resilience reason `FeaturePublisher`
  doesn't read it either: a stalled sibling must not stall this one.
- **#67 Whether a `GateApproved` approves the draft is computed independently of
  `FeatureLifecycle`'s own status advance, from the same loaded
  `Catapult.Dsl.Workflow.t()`, not read off it.**

- **#68 A decline with no comments is refused before it becomes an event,
  by the aggregate, not by a screen** (ORC-34). Having "the UI" fail
  validation would put a protocol invariant in the view layer, which
  this doc's own point-of-action rule rules out for every other
  command on a surface we own (this doc, above: "the rejection lands
  at the point of action"), and `docs/ui-spec.md` §2 rule 1 says the
  same thing from the screen's own side ("no screen is a second write
  path"). `Catapult.Engine.Commands.DeclineGate` is what actually
  rejects it — `systems/engine.md`'s own entry has the check (the
  aggregate's own per-gate comment-count state, not a projection read
  off `GateComments.any_since_last_resolution?/2`, since the
  aggregate's own purity floor forbids `execute/2` reading the log)
  and the reason a real comment is required rather than a free-text
  override: `docs/ui-spec.md` §3.2 already specs `document-review`'s
  throwback action with a target and nothing else, no reason field, so
  requiring a comment rather than inventing one is the simpler fix and
  the one the screen this ticket answers to already assumes. Whatever
  screen ORC-75 builds surfaces that rejection synchronously — the
  same compare-and-swap conflict rendering `docs/ui-spec.md` §3.1
  already specs for a stale transition — but does not perform the
  check itself.

- **#69 Cross-scope comment routing is named, not built — nothing in
  Phase 4 exercises it yet** (ORC-34, design pass). v5 §7.4's
  "comments at the wrong altitude are routed, not honored" example is
  a parent-ticket comment about a child's internals; Phase 4 has one
  open flow with many nodes and no child tickets
  (`systems/delivery.md`'s Phase 7 fanout), so there is no altitude
  for a comment to be wrong at yet beyond node-vs-node inside one
  ticket — and even that is a human correcting their own lane, not the
  machine inferring one: the plane makes no model calls
  (conventions §11), so nothing here reads a comment's prose to
  decide it belongs elsewhere. `CommentPosted`'s `node_id` is
  reassignable by an explicit author action recorded as an ordinary
  edit to that fact, never a plane-side inference; harvesting always
  reads a comment's current `node_id`, whatever it was posted against
  first. Real cross-ticket routing waits for Phase 7's child tickets to
  exist at all.

- **#70 A screen needing a concept the protocol lacks is a protocol change first,
  never a field added at the edge** (`docs/ui-spec.md` §2 rule 2).
- **#71 Draft body history is one previous, not a log.** What the per-sentence diff
  needs, checked against what `document-review` does with it, is the prior committed
  body and the current one — never a second-oldest, since a fresh visit always starts
  from the latest committed body. So `put_draft_body/4` shifts rather than appends.
- **#72 The ticket-listing query is delivery's; the screens are dashboard's.**
  `Store.tickets_for_project/1` answers what `board`'s lanes and `my-queue`'s action
  kinds both need in one project-scoped read. `my-queue` is cross-project by design, and
  satisfies ORC-87/ORC-35's "every query carries a project id" by fanning this query out
  once per project the actor has standing in — the rule forbids a projectless read, not
  a screen showing more than one project's rows.
- **#73 A ticket's title or argument is bundle content, not a plane mechanism**
  (`chain.md` #12, #32, `systems/platform_content.md`). The work surface reads
  `fields["argument"]` off the node at a flow's own `entry_node_id`, and renders blank
  until bundle content supplies one.
- **#74 What a passed gate pins is no longer open here.** It was §7.16's standing
  question and the reason gate events carry no `body_sha`; `workflow.md` #36
  answers it structurally (ORC-115), so a surface needing gate staleness derives it
  there rather than reintroducing a pinned field on the event.

- **#75 ORC-151 (design pass) retires the one named exception
  `inline_dispatch_point?/1` has carried since ORC-148, by removing what made it
  necessary** (`workflow.md` #10, #13; `docs/v5-design-decisions.md` §7.5,
  §7.19). `merge`'s own `ball` is `plane`, not `agent` — the mechanical join into the
  parent branch, effected by the plane once the `reconcile` kind approves, barring a
  conflict — so `merge` leaves the agent-balled set this function filters over entirely.
  `inline_dispatch_point?/1`'s `not queue_shaped? and non_critique_agent_step? and
  status != "merge"` simplifies to "agent-balled and not review-shaped": the `status !=
  "merge"` clause has nothing left to do, since `merge` is no longer a candidate the
  first two clauses would admit.

- **#76 A third design review on this same ticket adds two facts this
  system's own dispatcher will carry, past what the pass above scoped
  as "not this pass's to build"** (`docs/dsl-syntax.md` §15.1, §15.11;
  `docs/v5-design-decisions.md` §7.2, §7.10, §7.15, §7.19). First,
  architecture's own fan-out (sysarch/comparch/subcomparch) spawns a
  ticket per tree level, the identical spawn rule this system states
  for a feature's component and subcomponent children (above,
  "children spawn when the plan node names them, not at a status
  transition"; `v5-design-decisions.md` §7.15 states the same rule) —
  recursed one level further. Second, a non-root instance's
  own `merge` is triggered by its parent, not by its own dispatch:
  entering `reconcile` is a precondition gated on every blocking
  child's own subflow having finished (`v5-design-decisions.md` §7.2's
  child-blocks-parent, read on entry rather than only on completion),
  and reaching it is what fires the mechanical merge for every child
  now ready — the identical `plane`-balled merge effect named above,
  triggered from the parent's transition rather than the child's own.
  `Catapult.Delivery.ContainerLifecycle`'s own entry-guard (its
  `blocks:` rule, ORC-148, above) is the nearest existing shape a
  dispatcher implementation extends, not a new concept this system
  invents; there is no `fanout` status (`workflow.md` #10) —
  `Catapult.Delivery.FeatureLifecycle.Sequence` described it as
  vestigial, and nothing ever dispatched from it, so its absence needs
  no mechanism here. **Phase 7's:** the tree-spawn recursion into
  architecture, and the parent-triggered merge cascade, alongside
  reconciliation itself (above).

- **#77 A fourth design review on this same ticket names two facts this system's own
  dispatcher will carry that the third pass's own worked example got wrong, past what
  either pass scoped as "not this pass's to build"** (`docs/dsl-syntax.md` §13, §15.1,
  §15.2, §15.11; `docs/v5-design-decisions.md` §7.6, §7.19). First, **the tickets
  architecture's own fan-out spawns run a second, distinct type from the feature ticket
  itself, not the feature's own array at a deeper tree position** — the feature ticket
  dispatches through `types/feature.yaml` (design → architecture → implementation →
  merge, one instance ever); a comparch or subcomparch ticket dispatches through a
  second declared type with no `design` phase of its own, recurring per tree level,
  which is `v5-design-decisions.md` §7.6's "Child" lifecycle. This system's own
  type-registry lookup (above, "the loaded workflow is a parameter, never resolved")
  already resolves whichever type a spawn names, so the fact that a spawned child names
  a *different* type from its parent's own is not a new capability this system needs to
  grow — it is a fact about which type a spawn cites, `bundles/**` content against this
  record. Second, **`implementation` is a real dispatch phase, a kind of its own in the
  fixed vocabulary alongside `design`/`architecture`, not a vestigial `checks`
  occurrence** (`dsl-syntax.md` §15.1; "Reachability, settled", above, ORC-32) — a
  ticket's own code generation dispatches at `status: implementation` the identical way
  its own architecture phase dispatches at `status: architecture`, both inline
  agent-balled entries this process manager's existing uniform dispatch already reaches,
  needing no new branch — `implementation` sits in `SystemStatus`'s own union.

- **#78 ORC-155 (design pass) gives `Sequence.resolve_position/3` a disjointness check
  it has been trusting rather than enforcing, and gives every `position()` a namespaced
  identity beyond kind or gate name alone** (`dsl-syntax.md` §13, §15.1, §15.4, §15.12;
  `v5-design-decisions.md` §7.19).
- **#79 Separately, and for the reason `CatapultWeb.Live.Positions`' own moduledoc
  already gives** — a card, a rail entry, a `throwback:` and a `blocks:` reference all
  name a position that may recur (three `pending`, three `checks`, two `reconcile` in
  `dsl-syntax.md` §15.2's `types/feature.yaml` worked example alone) — **a bare
  `position()` is no longer a sufficient identity on its own.** `<anchor>.<name>`
  (§15.12) is the qualified form; this system's own `status_kind`/`status_gate`
  projection columns (`Store.tickets_for_project/1`) are unaffected in shape — a gate's
  name was always its whole identity, and a status's kind is still what every downstream
  branch here reads — and gain a `name` column beside `status_kind`, read for display
  and reference resolution only, never atomized. `Positions.key/1`'s own round-trip
  encoding needs the qualifying anchor to stay a *stable* encoding once two occurrences
  of one kind can appear in the same effective sequence, which ORC-116 needs
  (`docs/ui-spec.md` §2 rule 2: that ticket cannot introduce the vocabulary it needs to
  render subflows as groupings, only consume what this one defines). **Where each
  lives:** `resolve_position/3`'s own disjointness check and the namespace/uniqueness
  checks are `lib/catapult/dsl/**`'s (core_dsl's entry, above); the projection column is
  this system's, and `Positions`' own encoding change is dashboard's.

- **#80 ORC-116 widens to give `ContainerLifecycle.Sequence` the identical namespace
  awareness the entry above gave this system's ticket-axis positions**
  (`docs/dsl-syntax.md` §15.2, §15.12) — the container axis has the identical gap, and a
  bundle shaped to avoid recurring names only dodges it.
- **#81 The fix mirrors the ticket-axis one rather than inventing a second mechanism,
  and the data it needs is on `Type`, not on `Status`.** `%Catapult.Dsl.Type{}` already
  carries `groups: [Range.t()]` — one `Range` per sub-array, over `statuses` — beside
  `statuses` itself (its own moduledoc: "`groups` holds one `Range` per sub-array over
  that sequence"); a group has no identity of its own beyond that span and the anchor
  sitting inside it (`workflow.md` #6). `steps/2` reads only
  `%Type{statuses: statuses}` and drops `groups` on the pattern match — the field is
  not missing there, it is discarded. The lookup reads `groups` alongside `statuses`
  to resolve a qualified `<anchor>.<name>` identity the same way the loader does;
  `next_step/3`, `step/3` and `earlier?/4` compare against that qualified identity
  instead of the bare name `name/1` returns, and a caller naming an unambiguous
  (non-recurring) position resolves exactly as a bare name always did.
- **#82 One hazard the fix has to hold, not create: `groups`' ranges index into
  `statuses`, and `steps/2`'s output does not share that indexing.** `to_step/1` returns
  `nil` for an `environment:` entry and `steps/2` rejects every `nil`, so a step's
  position in `steps/2`'s output is only the same as its index in `statuses` when no
  `environment:` entry sits ahead of it. §15.10 admits an `environment:` wherever a
  `review:` is legal — inside a sub-array, not only after one — so a lookup that walks
  `groups`' `Range`s against `statuses` directly (never against the filtered `steps/2`
  list) holds regardless; one that reuses `steps/2`'s existing index space would break
  silently, off by one, the day a bundle puts an `environment:` ahead of a group.
- **#83 The qualified lookup resolves against `Type`'s own data, not `Status`'s.**
  `ContainerLifecycle.Sequence.next_step/3`, `step/3` and `earlier?/4` resolve against
  `identified_steps/2`'s namespace-qualified identity — `type.statuses`, walked at its
  own true index and paired with `Type.namespaced_positions/1`'s own `canonical` field,
  never `steps/2`'s already-filtered list. A bare, ambiguous argument resolves to
  nothing rather than to the wrong occurrence.

- **#84 ORC-171 gives runtime position-tracking, on both axes, the
  identical canonical identity ORC-116 gave `Sequence`'s own lookups**
  (`docs/dsl-syntax.md` §15.2, §15.12).
- **#85 Container axis.** `Catapult.Delivery.ContainerLifecycle`'s dispatcher carries
  `Type.namespaced_positions/1`'s own `canonical` identity throughout, never
  `Sequence.name/1`'s display label: `container.current_queue` is populated with it,
  every comparison against it — `forward_or_open/3`, `resolve_and_open/4`, `forward/3`
  included — reads that same qualified value, and `forward/3` passes it into
  `Sequence`'s lookups rather than `Sequence.steps/2`'s bare list. `Sequence.name/1`
  stays what it already is, a display label, never an identity.
- **#86 Ticket axis, the identical shape.** `FeatureLifecycle .Sequence.position/0`
  and `Projection`'s `passed`, `blocked_from` and `pinned_to` carry the same canonical
  identity rather than `Status.name/1`'s bare one. `Projection.to_wire/1`/`from_wire/1`
  (ORC-120) carry the qualifying anchor as a third field beside `kind` and `gate`, the
  same way `passed`'s own flattened records already do.
- **#87 An inline dispatch point's own two synthesized entries carry the identical
  field, set to `nil`.**
- **#88 A record written before this ticket decodes with no anchor, and that decodes
  correctly, with no backfill.** `Projection.from_wire/1` reads its new
  `blocked_from_anchor`/`pinned_to_anchor` fields with a tolerant default rather than
  the dot access the existing `_kind`/ `_gate` pairs use, because every
  `Commanded.ProcessManagers .ProcessManagerInstance` snapshot committed before this
  ticket predates the field entirely, and `from_wire/1` runs on exactly such a snapshot
  on every process restart. A missing anchor decodes as `nil` — the unqualified identity
  that position always was, since no bundle recurred a bare name before this ticket
  landed.
- **#89 The kind/gate discrimination is unaffected in shape, the same way the
  loader-level fix above left `status_kind`/`status_gate` unaffected.** A position is
  still either a kind or a gate — `position_columns/1` and `Store`'s two display columns
  keep reading exactly that — with the qualifying anchor consulted only where recurrence
  needs telling apart.
- **#90 The loader is not where this closes, and no load-time warning is the decision
  here.** §15.12's own uniqueness-within-a-namespace check already refuses the one shape
  that is actually a grammar error; two occurrences of one kind in two distinct
  namespaces are legal DSL, correctly so — recurrence across sub-arrays is exactly what
  namespacing exists to permit.

- **#91 ORC-176 (design pass) gives `Sequence.positions/2` a way to place an inline
  dispatch point's own flow, closing a gap ORC-148 opened when it folded `setup`/`retro`
  into `milestone`'s own array with no backing `types/<name>.yaml` for either**
  (`workflow.md` #19). `ContainerLifecycle.open_inline/3` opens such
  a flow with `flow_name: entry.status` — the entry's own literal name, since an inline
  entry carries no `flow:` for `flow_name` to resolve through a declared type instead
  (that function's own moduledoc comment). `FeatureLifecycle` subscribes to every
  `FlowOpened` uniformly, with no filter for a container-owned or inline-dispatched
  flow, and hands that same `flow_name` to `Sequence.positions/2` to place it.
- **#92 The fix is the discipline `ContainerLifecycle.inline_dispatch_point?/1`
  already keeps, extended to this module rather than duplicated by name.**
  `positions/2`, when `flow_name` fails to resolve in `workflow.types`, asks whether
  `flow_name` itself names one of the closed system-status kinds
  `Status.non_review_shaped_agent_step?/1` admits (`SystemStatus.agent_balled?/1` and
  not `SystemStatus.review_shaped?/1`) — the identical test that already decides whether
  `ContainerLifecycle` opens this flow inline in the first place, read directly rather
  than re-derived. If so, the flow's own effective sequence is fixed rather than
  resolved from any declared array: `[{:kind, :pending}, {:kind, <kind>}]` — the same
  "immediately preceded by its own pending, as that entry's sub-array head" shape §15.1
  already gives every generation-shaped entry — and nothing after it, for the reason
  named above: an inline dispatch point has no `checks`/`reconcile`/`merge`/`deploy`
  position to place it at. **A `flow_name` naming neither a declared type nor one of
  these closed kinds is still the authoring bug `warn_unplaceable/3` describes** — a
  chain's `ticket:` face citing a label no declared type actually carries — and keeps
  logging it; the warning's trigger narrows rather than disappears, since it was a false
  positive for exactly these two flows and no others.

- **#93 ORC-198 (design pass) corrects three `FeatureLifecycle.Sequence` call sites,
  carrying four instances of the same bug between them, that stayed keyed on the
  reference-ambiguity test after `systems/core_dsl.md`'s own ORC-198 entry splits it
  from the runtime-collision one ORC-155's `name:` made distinct** (this system's own
  ORC-171 entry, above; `docs/dsl-syntax.md` §15.12).

  All four read `kind_ambiguous`.

- **#94 ORC-202 (author decision) settles what a recurring kind is
  disambiguated *by*, and the qualifier reads `qualified` rather than
  `namespace` in consequence** (`docs/dsl-syntax.md` §15.12). The rule:
  **a kind may recur freely; a *name* may not.** §15.12 already says
  so — "two `critique` entries in one array, three `pending` entries,
  or two `checks` entries" are legal and `name:` is what tells them
  apart — and its uniqueness check binds names within a namespace,
  never kinds. Two `review`-kind statuses in one sub-array are the
  ordinary case this permits, not an edge one.

  `qualified` is the field that identifies an occurrence uniquely, by
  construction: `<anchor>.<name>` inside a sub-array, the bare name
  outside one, over names §15.12 already forces to be unique within
  their namespace. `Sequence.qualifier/1` is the one place that choice
  is made, and `annotate/4`, `resolve_kind_reference/3` and
  `find_kind_entry/3` all read it, so the qualifier a position is
  stored with and the qualifier a lookup matches against cannot drift
  apart. `kind_ambiguous` still decides *whether* a qualifier is
  needed; only what it holds has changed. Nothing persists the field —
  no event and no projection column carries it — so it is computed
  identity throughout, and changing what it holds needs no migration.
- **#95 Test projects are a recorded kind with a lifecycle, from the
  first project-level record this plane has** (ORC-216).
  `delivery_projects` is the first `projects` entity in this store:
  before it, nothing needed to ask "does this project id mean
  anything beyond a binding" (`ProjectBinding`'s own moduledoc). The
  milestone boundary's live suite does: it needs to mint a project,
  hold one aside for a debugging session to inspect after a failure,
  and reclaim it afterward, and doing that downstream of `Store
  .list_project_ids/0` with an ad hoc filter would mean every future
  project-scoped sweep re-deriving or missing the same rule.
  `delivery_projects` (`Catapult.Delivery.Store.Project`) is the
  record — `project_id` primary key, `test_project_state` nullable
  (`:provisioning | :active | :released | :deleted`). A project is a
  test project iff the field is set; nothing here adds a second `kind`
  column to say so a second way, because the one bit the nullable
  field carries is the whole of what "is this a test project" means
  today, and a project no test flow ever minted gets no row here at
  all rather than a row reading some `:ordinary` placeholder no code
  reads yet.
- **#96 The record carries one more column, `stub_mode` (boolean, not null, default
  `true`; ORC-223)** — whether a test project is a test project and whether its
  dispatches skip the model are two different questions, and collapsing them into one,
  off `test_project_state`'s presence alone, would stub the Phase-5 proof run along with
  the toy chain. `systems/generation.md`'s ORC-223 entry states the policy this column
  exists to carry and who sets it to what.
- **#97 At most one active-or-provisioning, by construction of the mint operation, not
  a checked constraint.** `Store.mint_test_project/2` performs both halves of
  "provisioning a new one releases whichever was active or still provisioning" — flip
  every row currently `:active` or `:provisioning` to `:released`, insert the new row
  `:provisioning` (promoted to `:active` only once `reset_and_intake /2` succeeds —
  ORC-224, below) — before either half is visible to a second reader, so no window
  exists where two rows read `:active` at once, and none where a row a crashed
  provisioning attempt stranded at `:provisioning` survives a fresh mint unreleased
  (ORC-224, below, states the failure shape this reclaims).
- **#98 `:deleted` is terminal and the row survives it.** Deleting a test project
  purges every row keyed by this `project_id` in every delivery-owned table — all eight
  key by `project_id`: `delivery_project_bindings`, `delivery_dispatch_runs`,
  `delivery_input_documents`, `delivery_draft_bodies`, `delivery_feature_lifecycles`,
  `delivery_feature_publications`, `delivery_container_proposals`,
  `delivery_artifact_pushes` — and then sets `test_project_state: :deleted` on the one
  row that is *not* purged: `delivery_projects`'s own, kept as a tombstone so a project
  id is never reused and a `:deleted` project reads differently from one that never
  existed. **What this does not purge**: `engine_nodes`, `engine_flows`, every other
  engine-owned projection table, and the project's own EventStore stream — engine's file
  map — and "the log is the source of truth; projections are derived and disposable"
  (`systems/engine.md`) means those rows cost storage rather than correctness by
  staying.
- **#99 One authenticated provisioning surface, three operations, a
  bearer secret rather than OIDC** (ORC-216). Provision
  (mint a test project, bind it to `catapult-test`, reset the bound
  repo's fixture content, intake the raft at the ref reset produced —
  below), release, and a read of a scope's most recent dispatch run —
  all three behind one secret, `DELIVERY_PROVISIONING_TOKEN`,
  declared exactly like `DELIVERY_GITHUB_TOKEN` above (no default,
  `secret: true`, so a build missing it fails at boot naming it, and
  `SETUP.md`'s required-env manifest carries the line) and compared
  constant-time (`Plug.Crypto.secure_compare/2`, a dependency this
  tree already carries via `:plug`).

  These three routes register through `api_surface/0` exactly like
  `fetch_context/2` and `report_result/2` do, and reach the world
  through the identical `Catapult.Foundation.DispatchPlug` path
  dispatch (`systems/foundation.md`) — a third, fourth and fifth path
  on the one listener, alongside `fetch_context/2` and
  `report_result/2`, not a second listener.
- **#100 `reset_repo/2` widens to report the ref it produced** (ORC-216; `HostPort`,
  `HostPort.Actions` and `HostPort.Fake` in the same change, per this doc's own standing
  rule on this port). It returns `{:ok, ref}` rather than bare `:ok` — the default
  branch's head commit SHA once `files` lands, in `HostPort .Actions` (the sha of the
  single Git Data commit its final ref update produces — ORC-228, below), and a
  synthesized one in `HostPort.Fake`, the identical `"fake-sha-..."` shape `Forge`'s own
  `head_sha/1` already generates for a branch head — `reset_repo/2`'s own Fake
  implementation only logs, and synthesizes this ref, nothing more. The contract is
  `{:ok, ref}` in either adapter, whatever produces the sha.
- **#101 What "the plane recorded it" resolves to, concretely: `DispatchRun` gains
  `outcome` and `credential_used`.** The exit criterion asks the live suite to assert
  success, a `credential_used`, and the committed draft, and none of the three durably
  exists on any row today — `ResultHandler.payload()`'s `status` and `credential_used`
  reach `Dispatch.simulate_result/2` and stop there, because nothing before this ticket
  has had a reason to read either back later. `complete_dispatch_run/2` widens to accept
  and store both alongside the coarse `:completed`/`:failed` it already writes
  (unchanged — `:completed` still covers a recorded limit-class/other failure exactly as
  today; `systems/generation.md`'s failover entry depends on that reading holding); the
  terminal-status read surfaces `status`, `outcome`, `credential_used`, `node_id` and
  the node's own `body_sha` (a plain cross-system read through to `Catapult.Engine
  .Store`, the same shape `current_open_flow_id/1` above already uses) — a non-nil
  `body_sha` is what "the committed draft" resolves to, and it is `engine_nodes`'s own
  column, written only by `CommitDraft` landing on `Catapult.Engine.Aggregate` and
  projected from the `DraftCommitted` it emits.
- **#102 How far the toy chain runs before release is settled: quiescence on
  a project-wide run enumeration, not a depth cap** (ORC-225, off the
  run-26 incident `systems/generation.md`'s fixture-coverage and
  typed-failure entries close — run 26 was green with four of its five
  dispatched runs red, because nothing asserted on the other four).
  `Provisioning` has a fourth read beside `provision/1`, `release/2`
  and `status/3`: `Provisioning.runs(conn, project_id)`, reachable at
  `GET /dispatch/test-project/:project_id/runs`, backed by
  `Store.dispatch_runs_for_project/1` — every `DispatchRun` row for
  `project_id`, any tier, oldest first, the same shape
  `dispatch_runs_for_flow/2` already gives one `flow_id`'s rows, minus
  the `flow_id` filter. Each row normalizes exactly like `status/3`'s
  own single-tier read (`status`, `outcome`, `credential_used`,
  `node_id`, `body_sha`) plus the two fields a single-tier caller
  already knows without asking and an enumerating caller does not:
  `tier` and `root_tag`.

  A read gains no route by existing — the route needs four sites: the `Provisioning`
  function and the `Store` query above, plus a `defexport` and an `api_surface/0` entry.

  The live test polls this read on its existing `@poll_interval`,
  alongside the terminal-status poll it already runs, until it reports
  no outstanding work.

  **`remaining` (ORC-230) answers "is there anything left to do", not only "have these
  runs finished".** A fixed poll count, or a bare check that the run-id set has stopped
  changing, both answer that question wrong the same way: a node that has become ready
  but has not yet been dispatched carries no `DispatchRun` row for either check to see,
  so it reads identically to "nothing left." `runs/2`'s response is `%{runs: [...],
  remaining: integer}` rather than a bare array, where `remaining` is the plane's own
  current answer, read at the moment of the call, off **both** readiness reads
  `Catapult.Generation.Sweeper` itself dispatches from (`sweep_tiers/2`,
  `lib/catapult/generation/sweeper.ex`) rather than one of the two:
  `Catapult.Engine.Projections.ReadyScopes.ready/3` (generation-tier readiness — the
  context-walk rule) **and** `ReadyScopes.ready_review/3` (review-tier readiness — "the
  reviewed tier's current draft has no review yet," a separate rule no generation-side
  filter covers), each joined against `Store.list_nodes/2` for nodes with no terminal
  `DispatchRun` yet, plus any run already in flight, summed.

  **`Catapult.Generation.Quiescence` has no caller and is gone.**

  **Per-run duration comes free of the same widening.**
  `Store.DispatchRun` already carries `timestamps(type:
  :utc_datetime_usec, updated_at: :updated_at)`, which
  `normalize_run/1` otherwise never reads. Each run in the response
  carries `duration_ms` — `DateTime.diff/3` between `updated_at` and
  `inserted_at`, in milliseconds. That is dispatch-to-terminal, not
  per-phase, since `updated_at` bumps on every status transition and a
  per-phase figure would need columns this record does not add; it is
  what turns a flaky boundary run into something measurable rather than
  something re-run by hand — `systems/generation.md`'s entry is where
  that measurement gets used.

  Once `remaining` reaches zero, the test asserts every run observed so
  far individually (`outcome == success`, a non-empty
  `credential_used`, a non-nil `body_sha`) — the same three assertions
  `@entry_tier` alone carried before, closing exactly the gap run 26
  exposed, where four red runs and one green one read as a green suite
  because nothing polled the other four. `systems/generation.md`'s
  ORC-230 entry states what the test does once `remaining` first
  reaches zero: call `approve_drafts/2` and keep going, rather than
  stop.

  No new dispatch mechanism: this reuses `Catapult.Generation.Sweeper`
  exactly as it runs — "let the sweeper dispatch whatever is ready" is
  the whole mechanism, and a narrower "dispatch exactly one scope"
  mode is not built, for this or any other caller.
- **#103 Quiescence is bounded by the raft's cascade depth, not by an approval that
  never comes (ORC-230).** Without an external actor resolving approvals in an
  unattended run, `ApproveDraft` — dispatched only by
  `Catapult.Delivery.DraftResolution` in reaction to a human's `GateApproved`
  (`systems/engine.md`'s ORC-229 entry) — never fires, and every tier whose readiness
  runs through a `self.parent`-style walk requiring `:approved` (most of
  `bundles/default/tiers/*.yaml`) stays permanently unready — the sweeper alone reaches
  only the tiers whose full `context:` resolves vacuously regardless of any node's
  approval status, a fixed and small set. `Provisioning.approve_drafts/2`, below,
  dispatches `ApproveDraft` directly, bypassing `DraftResolution`'s own `GateApproved`
  reaction entirely rather than triggering it, so a toy-seed project's quiescence is
  bounded only by however deep the raft's own downward-cascade graph goes.
  `systems/generation.md`'s own entry states what the live suite's poll loop does with
  that reach: the boundary suite (tag `:live`) walks all of it, every run — there is no
  shallower suite and no round cap.
- **#104 `Provisioning.approve_drafts/2` is the external actor an unattended
  run needs, dispatching `ApproveDraft` directly rather than through a
  ticket's own gate** (ORC-230 — the other half of ORC-229's
  mechanism). Reachable at `POST
  /dispatch/test-project/:project_id/approve-drafts`, it loads the
  chain the same way `Catapult.Generation.Sweeper`,
  `Catapult.Generation.DispatchWorker` and `Catapult.Generation
  .CommitPath` already do — `Dsl.load(Config.fetch!(:generation,
  :bundles_root))` (`sweeper.ex:79`, `dispatch_worker.ex:56`,
  `commit_path.ex:158`), reading the configured bundles root rather
  than a literal path this operation would otherwise have to invent
  — and for every tier in it calls `Store.list_nodes/2`
  — the identical per-tier read `Sweeper` and this doc's own widened
  `remaining` (above) already make — collecting every node whose
  `status` is `:drafted`. For each, it dispatches
  `Catapult.Engine.Commands.ApproveDraft{project_id, node_id: node.id,
  draft_id: node.current_draft_id, actor_id: "live-suite"}` and returns
  the count it approved, so a caller can tell "something moved" from
  "nothing left to approve."
- **#105 With no ticket and no gate, one call against a drafted node is itself the
  approval, not a step toward one** — there is no two-approve-calls-per-ticket nuance,
  and `systems/generation.md`'s entry states the assertion built on that.
- **#106 `actor_id` is a literal, not a call to `CatapultWeb.Live .Actor.id/0`.** That
  module's own moduledoc scopes it to "every write dispatched from this system's
  screens" — a stand-in for Phase 4's one human author until identity exists.
  `approve_drafts/2` dispatches from a boundary surface no screen renders, and reusing
  `"author"` here would erase the one distinction this actor exists to keep visible:
  that an unattended run approved its own drafts. `"live-suite"` is declared in
  `Catapult.Delivery.Provisioning` itself — the one call site a later automated caller
  extends rather than duplicates.
- **#107 Approves; never discards.** An unattended walk only ever needs to advance —
  this actor's job is keeping the walk moving, not judging output, so it never
  dispatches `DiscardDraft`. A ticket teaching the live suite to exercise a discard path
  is free to add one; this operation doesn't build the half it doesn't use.
- **#108 Approval is unconditional, not driven by a stubbed review score.**
  Threshold-based gating stays parked as a scheduler item rather than bundle content
  (`docs/v5-design-decisions.md` §7.19); driving `ApproveDraft` off `WriteReview`'s own
  `score` would unpark that decision as a side effect of making a test run, rather than
  through a design of its own. `approve_drafts/2` reads no review body and no score — it
  approves every node it finds `:drafted`, unconditionally, so the parked decision stays
  parked.
- **#109 Not gated on `stub_mode`.** `stub_mode` (the entry above) is a per-*dispatch*
  input deciding whether a runner calls a model; whether a draft gets approved is a
  plane-side write this operation performs on its caller's own schedule, regardless of
  any individual dispatch's `stub_mode` — so no flag threads the two together, and a
  live suite one day driving a real, non-stub dispatch through this same operation costs
  nothing extra to support.
- **#110 The suite polls this surface; a push transport is a design of its own.**
- **#111 The in-flight guard's query lives on `Store`, beside the table it
  reads** (ORC-223 — `systems/generation.md`'s companion entry states
  why the guard exists and how its cutoff was chosen). No new column
  and no new table: `delivery_dispatch_runs` already carries
  everything the check needs (`project_id`, `tier`, `scope_key`,
  `status`, `inserted_at`). `Store.in_flight_dispatch?/4` takes
  `project_id`, `tier`, `scope_key` and a cutoff timestamp the caller
  computes — `DispatchWorker`'s own `Config.fetch!(:generation,
  :clock)` — and passes in as plain data, the same shape every other
  cross-boundary `Store` call here already takes (ids and values in,
  never a module), and answers whether a row matching all
  three with `status` in `:dispatched`/`:context_fetched` and
  `inserted_at` at or after that cutoff exists.
  `Catapult.Delivery.in_flight_dispatch?/4` is the boundary export
  `DispatchWorker` actually calls. An index on
  `(project_id, tier, scope_key, status)` is what keeps the lookup as
  cheap as `get_node_by_scope/3`'s own on `engine_nodes` — the
  `(project_id, node_id)` index on this table doesn't cover it, since
  the guard runs before a node id is ever resolved.
- **#112 `HostPort.request` gains `stub_mode`, threaded straight through to
  the dispatch input — no new operation** (ORC-223,
  `systems/generation.md`'s companion entry states the policy).
  `ContextAssembly.build/4` sets it from `Catapult.Delivery
  .stub_mode?/1`, the boundary export over the per-project
  `stub_mode` column above; `HostPort.Actions.dispatch_run/1` sends it
  as the `workflow_dispatch` input's third field, stringified exactly
  like `credential_order` already is (GitHub's own inputs are strings
  regardless of the workflow's declared `type:`). Fixture push gets the
  same treatment `reset_repo/2`'s `files` map already gives every other
  pushed path: `ToySeed.reset_files/0` pushes each fixture's *content*
  under a repo-relative path keyed by that fixture's own `root_tag` —
  not its checked-in filename (`systems/generation.md`'s companion
  entry gives the full mapping and naming rule) — under a fixed
  namespace, `.catapult-stub/<root_tag>.xml`, chosen for being
  unambiguously not under `docs/raft/**`, the one directory
  `read_directory/3` ever walks.
- **#113 A test project is unsweepable from the moment it is minted, not only once
  released or deleted — closing the window `provision/1` left open between minting a row
  and finishing the writes that describe it** (ORC-224).

  `test_project_state` has a fourth value, `:provisioning` —
  "minted, not yet safe to dispatch against." `mint_test_project/2`
  sets it instead of `:active`; `provision/1` calls
  `Store.activate_test_project/1` once `reset_and_intake/2` returns
  `{:ok, ref}` — the same point it already returns the 200 response
  from (this module's own moduledoc). `activate_test_project/1`
  matches `project_id` **and** `test_project_state == :provisioning`,
  never `project_id` alone: a transition names the state it transitions
  *from*, the same guard shape `release_test_project/1` already carries
  for the same reason, so a retried or duplicated `provision/1` call
  finds the row already `:released` or `:deleted` and no-ops rather
  than reviving a terminal project. (Belt-and-braces, since the entry
  above records that this operation is never called concurrently
  against the same row: matching `project_id` alone would also resurrect
  a row a concurrent mint had already flipped to `:released`, which is
  the same hazard the "no window where two rows read `:active` at once"
  invariant above exists to keep to one writer at a time — but not the
  scenario this guard is here for.) `sweepable_project?/1` answers
  `false` for
  `:provisioning` exactly as it already does for `:released` and
  `:deleted` (`systems/generation.md`'s companion entry states the
  policy); the no-row default is unchanged (`true` — an ordinary,
  non-test project) — the new value is a row, not an absence, so the
  reading it protects never sees it.
- **#114 Two widenings, not one, because `reset_and_intake/2` fails in two shapes and
  one caller only catches one of them.** A returned `{:error, reason}` still runs
  `provision/1`'s existing failure branch, which calls `release_test_project/1`
  unconditionally on the row it just minted (this doc's own entry above: "a project that
  fails to reset or intake is released rather than left dangling `:active`") — every
  such failure happens before promotion, so `release_test_project/1` matches `[:active,
  :provisioning]`, not `:active` alone.
- **#115 `:released` cannot double as this state**, for two reasons this doc's own
  `list_released_test_projects/0` and `release_test_project/1` already give the shape
  of: a `:provisioning` row reading `:released` would let a concurrent `provision/1`
  call's reclaim step (`list_released_test_projects/0` → `delete_test_project /1`)
  delete the project out from under its own in-flight reset, and
  `release_test_project/1`'s own no-op-outside-`:active` guard would silently stop the
  failure path above from working the moment `:active` stopped being the state a fresh
  mint starts in.
- **#116 `reset_repo/2`'s fixture write moves off one commit per file onto GitHub's
  Git Data API — two commits per reset and a fixed call count, whatever the file count**
  (ORC-228).
- **#117 The workflow file stays on its Contents PUT, unconditionally — run 27 is the
  measurement.** `ToySeed.reset_files/0` writes
  `.github/workflows/catapult-dispatch.yml` into the same map as everything else, and
  `SETUP.md` §2 already records that GitHub refuses a `PUT …/contents/{path}` under
  `.github/workflows/` to a token holding Contents without Workflows —
  `DELIVERY_GITHUB_TOKEN` holds both, so that specific refusal never reaches this token,
  and its Contents PUT against that path succeeds: run 27's own commit history
  (`SwaggerAllen/catapult-test`) has it landing at 2026-09-05 21:59:08, on this token,
  on this repo. Whether GitHub's Git Data `PATCH …/git/refs` applies the same
  workflow-scope check a Contents PUT does is therefore beside the point: nothing here
  needs that fact, because the Contents PUT is proven to work and costs two of the seven
  calls above (a blob-sha `GET …/contents/{path}` plus the `PUT`) regardless of what the
  tree write does. The rule is unconditional rather than branching on an unmeasured
  GitHub behavior: every file **except** the workflow file rides the tree commit; the
  workflow file always rides its Contents PUT, issued *before* the tree write rather
  than after, so the tree commit — which the ref update, last of the seven calls, moves
  the branch to — is the branch's actual head and the sha `reset_repo/2` returns, rather
  than the workflow commit trailing behind it. No probe against `catapult-test` is
  needed for this.
- **#118 `@request_timeout` stays at 30s in both live tests**
  (`toy_seed_chain_live_test.exs`, `todo_app_proof_live_test.exs`).
- **#119 `commit_files/4` does not move to the Git Data shape.** Its one caller,
  `FeaturePublishWorker`, pushes a single `%{path => body}` map per call
  (`feature_publish_worker.ex:193`) — the per-file loop it runs already costs one round
  trip per call, not one per fixture set, so nothing there times out and nothing there
  grows with `@root_tag_fixtures`. Moving it buys no live-suite headroom; the
  write-count problem is `reset_repo/2`'s alone. It keeps its per-file Contents-API
  shape (read the blob sha, PUT with it) — its own shape, not shared with
  `reset_repo/2`.
- **#120 Concurrent per-file writes are ruled out, not just left unchosen — on an
  inferred rather than a measured GitHub behavior, named as such rather than dressed as
  settled fact.**
- **#121 `HostPort` and `HostPort.Fake` are unaffected.** This port's standing rule is
  that every *operation* lands in `HostPort`, `HostPort.Actions` and `HostPort.Fake`
  together (this doc's Reading-it and ORC-31 entries) — it binds when an operation is
  added, and this change adds none: `reset_repo/2`'s callback signature and its `{:ok,
  ref}` contract are exactly what they were. `HostPort.Fake.reset_repo/2` already
  synthesizes its ref through `Forge.head_sha/1` and reaches no network (ORC-216's own
  entry above), so it has nothing to change either way.
- **#122 `SETUP.md` §2's derived-scope bullets for `DELIVERY_GITHUB_TOKEN` name
  endpoints, not intent.** Its Contents-permission bullet lists `GET
  …/git/commits/{sha}`, `POST …/git/trees` and `POST …/git/commits` beside the `GET
  …/git/ref/heads/{ref}` and `POST …/git/refs` entries already there, and `PATCH
  …/git/refs/heads/{branch}` joins the same bullet — Contents alone, since the workflow
  file never touches the Git Data path and so needs nothing beyond the Contents scope
  this token already holds.

## #123 Initial vs target

Initial (Phase 4): the host port + fakes; feature lifecycle through
the two gates; PR + harvesting; lifecycle projected into the plane's
own read models, which the work surface renders — there is no third
party in this path. **Narrowed at ORC-104**: the container/queue
machinery above — the dispatcher, mint vs. activation, the
`blocks:`-aware completion check, dispatch onto an inline agent-balled
entry (`setup`/`retro`, ORC-148 — `singleton:`'s own rejection check
is retired rather than built, above), findings adjudication and the
aggregated flag flip — lands in Phase 4 too, ahead of the rest of
Phase 7's two-grain delivery machinery (child lifecycle, mutex,
dispatch, reconciliation, escalations, the maintenance watcher), for
the reason the ticket record gives: no ticket before Phase 7 otherwise
demonstrates the authoring loop closes over a container rather than
remaining a claim about individual tickets. `workflow.md`'s
grammar itself — the `types/<name>.yaml`/`gates/`/`environments/`
loader, the declaration-graph acyclicity check, the `blocks:`
structural acceptance — is `systems/core_dsl.md`'s own file map
(`lib/catapult/dsl/**`) and
lands with this same ticket; no file-map change is needed for either
half. **Corrected here, on author review: the touch is core_dsl +
engine + this system + `platform_content`, not three.** The shipped
`bundles/default-flow` predates every ORC-105 grammar pass —
`bundle.yaml` carries no `entry:`, its gates and environments still
carry the retired `after:` field, and `gates/ux-review.yaml` throws
back to `queue`, a name this same ticket's dev pass retires — so
landing `workflow.md`'s loader without migrating that content in the
identical change fails every workflow bundle's load, before anything
else this ticket builds ever runs. `bundles/**` is
`platform_content`'s own file map (unchanged, no map edit needed there
either);
`systems/platform_content.md` records what the migration must carry,
so dev has an argued shape rather than a blank file to guess at. The
touch is four systems, not three; the mutex label set grows to
match.

**Narrowed at ORC-9**: the host port's
dispatch-facing slice — context-fetch, result-report, OIDC
validation, run correlation, and its in-memory fake — lands in Phase
3 with the generation executor (`systems/generation.md`), ahead of
the rest of this system. It is one seam with two consumers arriving
at different times, not two ports: the slice generation needs now is
a subset of the same host port this doc already claims, not a
parallel one this ticket invents. The handler logic for that slice —
OIDC validation, run correlation, context/result payloads — lives
under this doc's own file map; **what serves it does not**
(`systems/foundation.md`'s dispatch-facing endpoint entry): the endpoint rides
a second path on foundation's existing health listener, reached
through an `api_surface/0` declaration rather than a router of this
system's own, because the general composed router waits for
dashboard's Phase 4/7 web layer. **Narrowed again at ORC-10**: the
repo-reset operation above, and the `Contents: read and write` grant
it draws on, land with it — a second sliver of Phase 4's host port
pulled into Phase 3 for the same reason the first one was, because the
milestone boundary test needs it now. **ORC-31 (design pass) records
the shape of the rest of Phase 4's host port** — the operation
vocabulary, the marker-vocabulary module and the sim-style test ring,
above — ahead of the dev pass that builds it. **ORC-31's dev pass
lands that shape**: the operation vocabulary in both `HostPort
.Actions` and `HostPort.Fake`, `HostPort.Marker`, and the offline sim
ring. **ORC-32 (design pass) records the shape of lifecycle projection
proper** — the process manager and its standing decisions, above —
ahead of the dev pass that builds it. It covers `queue` through
`fanout` (Building) only; wiring the host port's own operations (a
bounce, a merge-forward, a merge) into that projection, and everything
from `checks` onward, stays open at Phase 4 and is no ticket's yet.
**ORC-33 (design pass) records the shape of the last unbuilt slice of
Phase 4's PR management** — `FeaturePublisher`, the two host-port
operations it needs and the standing decisions above — ahead of the
dev pass that builds it. It covers creating the feature branch and its
single PR and keeping both current as the flow's own drafts commit;
wiring a bounce, a merge-forward or a merge into any of this stays
exactly as open as ORC-32 already left it — no ticket's yet, and
`checks` onward is still Phase 7's.
**ORC-34 (design pass) records the shape of Phase 4's decline-harvesting
slice, and — on design review, widened rather than left as scoped —
the gate sign-off/decline command mechanism itself** —
`CommentPosted`, `CommentFeedback`, `ApproveGate`/`DeclineGate`,
`GateComments` (all `systems/engine.md`'s), and `FeatureLifecycle`'s
two new `interested?` clauses (above) — ahead of the dev pass that
builds it, and corrects its own ticket record's premise twice: the
harvest is `document-review`'s native comments, not `HostPort`'s PR
review comments, which stay Phase 7's exactly as ORC-31/ORC-33 already
built them; and the gate command deferred to "§7.16's later increment"
on the first pass turns out to be this ticket's, because `docs/
ui-spec.md` §2 rule 2 refuses `document-review` (ORC-75) inventing
that vocabulary itself. What still does not cover: `document-review`
the screen (`docs/ui-spec.md`, ORC-75, blocked on this ticket reaching
`Merged` for exactly that reason) and §7.16's general "what a passed
gate pins," which `systems/engine.md`'s own entry names as untouched
by the mechanism above.
Target
(Phase 7): the whole of v5 §7,
including the declared review sequences and environments of §7.19 and
the outbound mirror in place of the Linear adapter. The reserved
grammar this phase gives a consumer to, all of it parsed and checked
at load already (`core_dsl` #43): `enforcement:` on a tier and
`consistency:` on an edge (`chain.md` #16, #25); the ticket
skeleton's relative order enforced against dispatch, a gate's
`escalation`, and `environment:` entries with every environment key
(`workflow.md` #12, #32, #38). What does *not* arrive with it is a
tier-side annotation block: the cross-axis binding is the workflow's,
and a tier carries no delivery key at all (`bundle.md` #11).

## #124 Depends on

substrate, engine (state of record), foundation (serves the
dispatch-facing host port endpoint on its listener), generation (the
chain whose progress it projects), core_dsl (the workflow bundle's
declared statuses and environments, v5 §7.18-§7.19), dashboard (the
work surface — a hard dependency, since nothing else renders the
loop; concretely **ORC-75, UI v1** — until it ships the native review
screen, Phase 4's gates have no surface a human can act on, per the
ORC-33 entry above). Req for the GitHub client.
