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
  (`systems/generation.md` carries what that means for assertions). What it buys today is an
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
- **Plane-authored annotations are records with kinds on surfaces we
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
- **No boundary ticket, generalized: containers and the project alike
  carry their own progress — but the project is not a container**
  (ORC-105, design pass, superseding both ORC-103's own unmerged
  milestone-only version of this entry and this same ticket's own two
  earlier, since-reversed drafts — one that folded the project into
  the container shape, one that gave every queue entry a `flow:`/
  `opens:` pair; `docs/v5-design-decisions.md` §7.8; `docs/
  dsl-syntax.md` §15.6-§15.9). A container's or a project's status is
  which of its declared queues is current; a queue is a derived query,
  never a stored bucket, so there is no per-queue pending set for this
  system to own the way `ready_scopes` is engine's. Two relations this
  system dispatches against, both new: a queue's `flow:` target
  resolves against a work-item-type registry shared by container and
  plain-type declarations alike (`docs/dsl-syntax.md` §15.2, unified
  further at the fourth pass below) — no new
  dispatch mechanism whichever it resolves to, a `retro` or `setup`
  ticket opening a flow instance exactly like any other type, `setup`
  dispatching as its own anchor entry, first in the newly minted
  container's own sequence, never a value carried on the parent's
  dispatching entry, so the two never need to be the same declaration;
  a queue's `blocks:` relation to a sibling queue in the same
  declaration guards *entry into* that sibling while the blocking queue
  carries unresolved work items, checked once at the transition rather
  than held continuously (corrected to this reading at the design
  review below) — the general form of what used to be
  a single hard-coded boundary-blocking rule, now one relation the
  dispatcher reads wherever a workflow bundle declares it, milestone
  `main`→`retro` included. **The pause has no separate mechanism to
  build**: an `Urgent` ticket dispatches regardless of which queue a
  container or the project currently sits in
  (`docs/v5-design-decisions.md` §7.3, §7.10), which falls out of
  ordinary priority dispatch rather than needing a ticket-carried flag
  against its milestone the way ORC-103's draft required. Of the rest
  this entry named, three are built (ORC-175, design pass, checked
  against the tree): storage for "which queue a given container or the
  project is currently at" is `engine_containers.current_queue`/
  `current_queue_sequence` (`lib/catapult/engine/store/container.ex`);
  the `blocks:`-aware dispatcher is `Catapult.Delivery
  .ContainerLifecycle` (below); and the declaration-graph acyclicity
  check that bounds nesting (`docs/dsl-syntax.md` §13) is
  `Catapult.Dsl.Workflow.declaration_graph_problems/1`, already
  skeleton-agnostic per ORC-148. "The scan/setup/retro machinery
  itself" is superseded rather than built as this entry originally
  framed it: `setup`/`retro` fold directly into `milestone`'s own
  array as inline agent-balled entries, with no separate scan step
  (ORC-148, below). The `:live`-gates-`retro` interlock (§2.8) is the
  one item here still unbuilt — no `:live`-verdict signal exists
  anywhere in this system yet, and it needs the maintenance watcher
  this doc's own Initial-vs-target section still files to Phase 7 —
  and stays Target (Phase 7), unticketed.
- **Mint is not activation, and this system's dispatcher is the one
  that has to hold the two apart** (ORC-105's fourth pass, design
  pass; `docs/dsl-syntax.md` §15.8; `docs/v5-design-decisions.md`
  §7.8). A container instance can exist — created by business logic or
  a person, accepting groomed work into its own future queues — before
  its parent's own position ever reaches it; only reaching it makes it
  *active*, and only becoming active runs its `setup` entry's `flow:`.
  Two earlier framings of this same record had mint and activation as
  one event ("dispatch mints one instance and starts that instance at
  its own `setup` entry"; "minted one at a time as the prior one
  closes") and both are wrong for the case this system explicitly
  wants: grooming next milestone's `prep` during this milestone's own
  `main`. What this system owns is built (ORC-175, design pass,
  checked against the tree): the storage distinguishing "instances
  that exist" from "the instance that is current" is
  `Catapult.Delivery.ContainerLifecycle`'s own `state` field
  (`:minted | :active | :closed`), and a gate's throwback is a human's
  `AdvanceContainerQueue` with `reason: :throwback`, checked against
  `ContainerLifecycle.Sequence.earlier?/4` — the live half of the
  check the loader can only make statically. **This bullet originally read a
  container's position as moving backward two ways, the second being
  a gate's own throwback — a fifth-pass correction**, not a
  fourth-pass fact: the fourth pass's own "a container's anchor
  entries carry no gates, so they have no `throwback:` to borrow"
  stopped being true the moment gates and environments widened onto
  containers in the same pass that wrote it (`docs/dsl-syntax.md`
  §15.2, §15.4, §15.8). **The first of the two — a queue un-resolving
  when its population refills — is retired at ORC-148's third design
  review**; see that bullet below rather than treating it as this
  system's target behavior. A milestone sign-off gate between `main`
  and `retro` can throw back to `main` today, and this system's
  dispatcher honors that path exactly this way.
- **A fifth ORC-105 pass gave the dispatcher a cardinality bound to
  respect and closed a hole in the loader's own acyclicity check that
  this system's dispatcher would otherwise have inherited** (design
  pass; `docs/dsl-syntax.md` §15.6-§15.7; `docs/v5-design-decisions.md`
  §7.8). `milestone`'s `setup` and `retro` queues are declared
  `singleton: true` — bounded, this system's fifth-pass reading held,
  to 0 or 1 unresolved at a time — which is not something the loader
  can check (a queue's population is live ticket state) and is
  therefore this system's own dispatcher's job. **This reading was
  wrong, corrected at the sixth pass below** — see that bullet rather
  than treating "admitted and files `Blocked`" as this system's
  target behavior. Separately, the declaration-graph acyclicity check
  (above) now has to treat a skeleton-less type — the project
  included — as a graph node, not only a `container`-skeleton type:
  the fourth pass's narrower node set excluded the exact edge a
  project/container cycle runs on (`milestone.main` → `flow: project`,
  `project.build-out` → `flow: milestone`), so a loader built against
  the fourth pass's own record would have let that cycle through.
  Built, checked against the tree (ORC-175, design pass):
  `Catapult.Dsl.Workflow.declaration_graph_nodes/1` is explicitly
  skeleton-agnostic (ORC-148), so a project/container cycle on that
  edge is caught by `DslGraph.acyclic?/1` against the corrected node
  set, not the superseded one. Nothing in this system's own dispatch
  logic changes shape from the acyclicity correction — it is about
  what the loader accepts before this system ever sees a bundle.
- **A sixth ORC-105 pass corrected the fifth pass's own singleton
  reading and gave this system's dispatcher a fact to check that the
  loader cannot: which type a fresh project actually starts from**
  (design pass; `docs/dsl-syntax.md` §2, §13, §15.6-§15.7; `docs/
  v5-design-decisions.md` §7.8). `singleton:` bounds a queue to at
  most one work item **ever assigned**, not 0-or-1 unresolved at any
  moment — a queue whose sole work item has reached `terminal` is
  *closed*, not empty-with-room, so this system's dispatcher must
  reject a second assignment outright rather than admit it and file
  `Blocked`, once one work item has ever been assigned to a singleton
  queue. This is a real behavior change from the fifth pass's own
  record, not a rewording: "admit and file `Blocked`" and "reject
  outright" dispatch differently on the same input. Separately,
  `entry:` on a workflow bundle's own `bundle.yaml` names the type
  onboarding dispatches a fresh project from — this system reads it
  rather than inferring a starting point from which declaration looks
  project-shaped, the identical inference this record's own earlier
  passes leaned on informally without the loader ever having checked
  it. Neither correction changes this system's shape, only what its
  dispatcher and its onboarding path each read and enforce. Checked
  against the tree (ORC-175, design pass): the singleton-lifetime
  rejection this paragraph describes is retired rather than built,
  superseded before either half shipped (ORC-148, below). The `entry:`
  read is built at load time — `Catapult.Dsl.Manifest` reads it off
  `bundle.yaml` and `Workflow.entry_problems/2` validates it resolves
  to a declaration-graph root — but nothing yet dispatches a fresh
  project from it; wiring an onboarding path to that read stays Target
  (Phase 7), unticketed.
- **ORC-115 (design pass, corrected on two later design reviews) gives
  this system's dispatcher a derived throwback default and names,
  without yet answering, whether a container instance can be a
  dispatch target in its own right** (`docs/dsl-syntax.md` §15.4,
  §15.10; `docs/v5-design-decisions.md` §7.8, §7.16, §7.19; answered at
  ORC-148, below). The dispatcher's own
  throwback handling resolves every decline's *legality* the same way,
  regardless of declaration — checked against "earlier in the citing
  type's own effective sequence" (identical to how the dispatcher
  already has to honor a Blocked-return); a gate's declared
  `throwback:` bounds nothing here (second design review; the first
  pass's reading, that it stayed a bounded allow-list the command edge
  enforced, rested on a `DeclineGate` enforcement claim that isn't
  real). What a gate's declared `throwback:` still supplies is a
  *landing point* (third design review, narrowing the field to a
  single optional status rather than retiring it): the dispatcher reads
  it when the gate names one, and falls back otherwise to the citing
  sub-array's own earliest entry as the one-click default — its own
  leading `pending`, when the sub-array has one (every
  generation-shaped sub-array does, `docs/dsl-syntax.md` §13's
  tightened check), its own non-review-shaped agent-balled entry
  directly otherwise (a design-review correction, fourth pass, from
  resolving to that entry unconditionally) — either way computed from
  the loaded workflow bundle at throwback time, never stored. This is
  the same shape `flow:`
  resolution and the singleton-lifetime check above already take (read
  the bundle, don't cache a derived fact). A gate sitting first in its
  own sub-array, or in no sub-array at all, has no earlier entry there
  to fall back to, so the dispatcher derives no default for it and the
  gate must declare `throwback:` explicitly (ORC-181,
  `docs/dsl-syntax.md` §15.4, §13, §15.10).

  **This system's own open question — can a container instance be an
  agent dispatch target at all? — is answered at ORC-148: yes, on the
  identical footing as a ticket instance.** Dispatching from a work
  item with a queue and one without were never different operations,
  only different status flows attached to the same mechanism
  (`docs/dsl-syntax.md` §15.2, `docs/v5-design-decisions.md` §7.8) —
  the queue was never what made something a dispatch target, so this
  system does not need a container-shaped answer distinct from the
  ticket-shaped one it already has. Concretely, once `setup` and
  `retro` fold inline (built at ORC-148, below) this system's own
  Target build must still: point ORC-9's executor at the container
  instance's own branch and PR when the dispatch subject is a container
  rather than a ticket; give a container instance file-map paths of its
  own for the mutex mapping to key against, the identical shape a
  ticket's paths already take; and key `DispatchRun` on the container
  instance's id in that case rather than assuming a ticket id.
  **Neither ORC-104 nor ORC-148 built any of the three** (ORC-175,
  design pass): `setup`/`retro` dispatch today
  (`Catapult.Delivery.ContainerLifecycle.open_inline/3`) by minting a
  synthetic per-entry flow (`ContainerLifecycle.Ids.work_item_id/3`,
  keyed on `project_id`/`container_id`/queue, not the container's own
  id) and routing it through the ordinary ticket-shaped branch/PR/
  file-map/`DispatchRun` path instead — functionally sufficient for
  what dispatches today, since each inline entry gets its own PR
  rather than needing to share the container's, but not what this
  paragraph describes. `lib/catapult/delivery/dispatch.ex`'s
  `HostPort.request` still carries no branch or file-map field, and
  `store/dispatch_run.ex` keys on `flow_id`, never a container id. It
  also resolves what `main`'s `blocks: [retro]` (§15.7) means once
  `retro` is `milestone`'s own inline entry rather than a population of
  unresolved child tickets: `retro` cannot be *entered* while `main`'s
  own queue still carries unresolved work — the identical entry-guard
  test §15.7 states generally (corrected to this reading at the design
  review below), applied to a guarded entry that is not itself a
  queue. Target (Phase 7), unticketed: revisit when a container-owned
  dispatch identity — not today's per-entry synthetic flow — is
  actually needed.
- **ORC-148 (design pass) retires `singleton:` and the fold that
  motivated it, closing the open question the two bullets above left
  standing** (`docs/dsl-syntax.md` §13, §15.1, §15.2, §15.7, §15.10;
  `docs/v5-design-decisions.md` §7.8). The fifth/sixth-pass singleton
  reading above bounded a *queue's* lifetime cardinality — the
  mechanism `setup` and `retro` needed only because each was
  implemented as `flow:` naming a separately minted, ticket-skeleton
  child. Once `setup` and `retro` fold directly into `milestone`'s own
  array as ordinary agent-balled entries — no `flow:`, no minted
  child, `types/setup.yaml`/`types/retro.yaml` deleted — neither is a
  queue any more, so there is no cardinality left for a field to
  bound: "at most one, ever" falls out of there being exactly one
  `milestone` instance and exactly one array position each occupies.
  This system's dispatcher loses a check it was filed to build (the
  singleton-lifetime rejection, ORC-104's, retired rather than built)
  and gains the dispatch-target work named above in its place — a
  smaller Target list, not a larger one, since folding removes the
  separately-dispatched child the old shape needed a bound for.
- **A design review on ORC-148 changed the shape of this system's own
  `blocks:`-aware dispatcher work, filed above**
  (`docs/dsl-syntax.md` §13, §15.1, §15.7; `docs/v5-design-decisions.md`
  §7.8). The three bullets above described `blocks:` as a standing
  hold this system's dispatcher recomputes for as long as the guarded
  entry carries unresolved work — wrong, corrected in place above and
  restated here because it changes what this system builds: `blocks:`
  is an entry guard, checked once, at the transition into the entry it
  guards, never rechecked against the same occupancy. Concretely, this
  system's dispatcher evaluates a `blocks:` condition exactly once, at
  the moment a container's position would advance into the guarded
  entry — never as a periodic or event-driven recheck against an
  already-active entry, which is what let a queue refilling mid-`retro`
  pull the container back out of it under the retired reading. **This
  states what the guard is not — a standing recheck against an entry
  already entered — not how the dispatcher decides when to attempt the
  entry in the first place, which a further design review found this
  bullet left unanswered.** `ContainerLifecycle` (the process manager
  named below) is an ordinary event-subscribed process manager, not a
  poll loop: it re-evaluates a guarded entry's eligibility on every
  engine event that could change the answer — most often, a work item
  the blocking queue counted resolving out of it — and the moment a
  `blocks:` condition reads clear, it is this same dispatcher, not a
  human action, that issues the advance command. A container never
  sits fully unblocked waiting to be asked forward; "checked once, at
  the transition" is what each of those event-triggered attempts does,
  not a claim that the dispatcher looks only a single time over the
  container's whole life.
  Separately, reaching `terminal` gains a guard this system's dispatcher
  must enforce unconditionally — every one of a container's own queues
  holding no unresolved work — never narrower than whatever `blocks:`
  relations a bundle happened to author, so a queue nobody named in any
  `blocks:` list still cannot be closed over on the way to `terminal`.
  Neither correction adds a loader check (`docs/dsl-syntax.md` §13 is
  unaffected by the second one, and the first is a semantics correction
  to a check that already existed). The entry guard is built, in
  `Catapult.Delivery.ContainerLifecycle` (ORC-175, design pass, checked
  against the tree): `forward_or_open/3` returns `[]` on
  `{:held, _holders}`. The terminal guard is a rule this system's
  dispatcher must enforce regardless of implementation: every one of a
  container's own queues holds no unresolved work before `terminal`,
  unconditionally, never narrower than whatever `blocks:` relations a
  bundle happened to author. Its present enforcement is incidental to
  the same backward-move mechanism the bullet below settles
  (`next_commands/2`) — ORC-177's reconciliation
  covers this guard's implementation too, not only the backward move.
- **A third design review on ORC-148 found the `blocks:` inversion
  above left a contradiction standing: a container's position still
  moved backward on a queue refilling, restated rather than removed
  — and a fourth found the third's own fix over-corrected**
  (`docs/dsl-syntax.md` §15.8; `docs/v5-design-decisions.md` §7.8).
  §15.8's own "two ways a container's position moves backward" kept a
  queue un-resolving as one of them, un-gated — the identical defect
  the bullet above retired from `blocks:` itself, reappearing one
  level up. **Retired: this system's dispatcher never moves a
  container's position backward because a queue refilled.** The third
  review's own replacement named the surviving cause "an authored
  transition," which rules out more than it means to: a `critique`
  entry's own decline is automatic, with no author in it, and
  `docs/v5-design-decisions.md` §7.19 requires it be structurally
  identical to a human decline at a gate. **What moves position
  backward is a step's own outcome — a decline, whether a `critique`
  entry's own agent run issues it (landing back on the generation
  entry it pairs with) or a human issues it at a gate (landing per its
  declared or derived `throwback:`) — or an explicit author
  transition** — concretely, returning a milestone from `retro` to
  `main`, which `ContainerLifecycle` never performs on its own. Forward
  advance into a guard-cleared entry stays this system's dispatcher's
  to make automatically, the moment the guard reads clear (the bullet
  above, unaffected); a decline's backward move is likewise this
  system's dispatcher's to apply the moment it is issued, agent or
  human; the `retro` → `main` return alone is the author's own action,
  taken once `retro`'s own sub-array — its agent step and the human
  gates around it — has run to completion, not the instant `retro`'s
  output lands back in `main` and un-resolves it. This is also what
  keeps the `terminal` guard two bullets up reachable at all: the
  shipped `milestone`'s only throwback to `main` is `milestone-signoff`,
  sequenced *before* `retro` (`dsl-syntax.md` §15.10), so absent this
  manual return `retro` filing work into `main` would leave
  `cleanup`/`terminal` blocked with no declared path back.
  **Done, checked against the tree — ORC-177 (design pass; dev pass
  merged `27e0bff`).** The reconciliation the fourth-review correction
  above named landed across every site the retired reading reached:
  `Catapult.Delivery.ContainerLifecycle`'s `next_commands/2` no longer
  performs the retired pre-check (below); `container_queues.ex`'s
  resolution condition 1 cites the retirement directly rather than the
  reading it predated; and, in `container_queue_advanced.ex`, both the
  moduledoc and the `reason` type narrow to `:resolved | :throwback` —
  `:repopulated` is retired from each, and the moduledoc no longer
  gives a resolved queue un-resolving as this reason's own
  justification for existing. A third `reason` value, for the explicit
  author transition the fourth-review correction above names, is that
  mechanism's own vocabulary to add once it is built, not anticipated
  here. `container_lifecycle_test.exs`'s two tests that had asserted
  `reason: :repopulated` as the correct outcome were rewritten against
  whatever replaces the walk, below.

  **What replaces the walk, so "whatever replaces it" above is no
  longer open.** Two questions, both closed by record already settled
  rather than by new mechanism (`docs/dsl-syntax.md` §15.7, §15.8).

  Position needs no re-derivation, because there is nothing left to
  derive: §15.8's own third statement already retired position being a
  function of queue population at all. `next_commands/2` drops its
  `earliest_unresolved/4` pre-check outright — deleted, not repurposed
  — and dispatches straight to `forward_or_open/3` on every event. A
  container's position sits wherever the last forward advance or one
  of the two remaining backward-move causes (a step's own decline; the
  author's `retro` → `main` return) left it, and an earlier queue's
  population refilling changes nothing about it. That is the whole
  answer: it doesn't re-derive, and needing it to was the retired
  behavior.

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
  entries behind `current` — the concrete shape of §15.7's "unconditional,
  reaches every queue-shaped anchor... whether or not any of them is
  also named in some other entry's `blocks:`": a queue long past
  `current` and named in no `blocks:` list is checked identically to
  one immediately behind it. `setup` and `retro` — the non-queue-shaped,
  `flow:`-less inline dispatch points `Status.queue_shaped?/1` already
  excludes — need no place in this check: `ContainerQueues.admits?/3`
  bounds each to at most one assignment ever, so once resolved neither
  can un-resolve, which is exactly why §15.7's own guard text names
  "every queue-shaped anchor" rather than every positioned entry.

  No new loader check, no new event, no new command: a precondition on
  an existing dispatch, the identical shape the finding-adjudication
  check already is. `container_queues.ex`'s condition 1,
  `container_queue_advanced.ex`'s moduledoc and `reason` type, and the
  two `container_lifecycle_test.exs` tests named above are corrected
  against this replacement, not against a placeholder for it.
- **ORC-31 (design pass) extends the Host port's operation vocabulary
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
- **Author-review correction: harvesting classification filters by
  author identity, not by endpoint alone — a revision to §7.4's
  classification mechanism for the GitHub-PR surface, not an
  application of it** (ORC-31, design pass, second draft). The first
  draft treated "arrived via the review-comment endpoint" as
  sufficient to call a comment human, and presented that as §7.4
  holding unchanged. It doesn't hold as written: §7.4's rule covers
  *any* machine, because its premise is that machines mark, while
  endpoint-of-origin covers only *our* machine. Every third-party
  actor with review access — a GitHub App, a linter, a review bot,
  Claude Code's own inline review comments — posts through the
  identical review-comment endpoint a human uses; under
  endpoint-alone classification those harvest as human declines and
  thread into regeneration as author feedback, silently. **Revision:**
  review-comment read filters its results by author identity before
  anything is treated as harvestable — `performed_via_github_app` is
  reliable for GitHub-App-authored comments, `user.type == "Bot"` is
  reliable for bot accounts, and either excludes a comment from the
  human bucket. **Residual, named rather than hidden:** a bot
  authenticating with a human's personal access token is
  indistinguishable from that human at the API; nothing here closes
  that gap, and no fix is known. This is the strongest of the three
  mechanisms considered (markers, endpoint-alone, author-identity)
  because it needs no third party to cooperate with a convention it
  has never heard of — but it is a revision of §7.4's text ("anything
  unmarked... is human feedback") for the surface where we don't own
  the store, not a restatement of it. Markers are unchanged for *our*
  own machine (marker-comment write); author-identity filtering is
  what now stands in for "unmarked" on the review-comment side.
  **Placement correction (ORC-31, design pass, second author review):**
  the first draft of this correction recorded the revision here only,
  leaving `docs/v5-design-decisions.md` §7.4 still reading the
  superseded marker-only sentence — the source of truth disagreeing
  with the system doc about which rule is live. §7.4 now carries this
  mechanism, its reason and its residual directly; this bullet is the
  fuller argument the doc text points back to, not a second place the
  decision was made.
- **List-shaped read operations page to exhaustion; neither asserts a
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
- **The marker vocabulary is a typed module, scoped to GitHub PR
  comments only** (ORC-31, design pass; extends the marker-retirement
  bullet above rather than reopening it). `HostPort.Marker` (naming
  follows `HostPort.Actions`/`HostPort.Fake`'s own pattern) holds a
  closed enum of kinds, each with a render function producing the
  exact comment body and a parse function reading one back —
  `{:ok, {kind, payload}} | :not_a_marker` — so no call site builds a
  marker string by interpolation and no call site greps a comment
  body for a substring. **`parse/1`'s named caller (ORC-31, design
  pass, author-review addition): marker-comment write's own
  idempotency check.** Before posting a new bounce, the plane lists
  the PR's existing issue-level comments and parses each with this
  function to check whether the scope-violation marker for this gate
  decline is already there, so a re-triggered decline path (a retry,
  a resumed pass) doesn't post a second `Ready for rework` comment.
  This is a read of the plane's own issue-level comments and is not
  the harvesting read — `parse/1` never sees a line-anchored review
  comment, and harvesting's classification (the correction above)
  never calls it. Phase 4 needs exactly one kind to start: the
  scope-violation bounce already named in §7.5 ("a plane-authored
  marker comment naming the paths, `Ready for rework`"). Later kinds
  — §7.11's findings marker, §7.14's bug-intake sequence stamp — join
  the same closed enum when their phase needs them; they are not
  invented ad hoc at whichever call site first wants one. This module
  governs the write side only. **The read side needs no parser of its
  own only because the plane never authors a line-anchored review
  comment — an invariant to keep, not a free property, and it is
  recorded here so the next pass sees it before it breaks it** (ORC-31,
  design pass, author-review addition). Today that premise holds
  because no plane operation posts a line-anchored comment at all,
  which is what makes the property cost nothing rather than something
  enforced. If a later ticket adds one — a review-thread reply is an
  obvious want when declining a decline — that comment would arrive
  through the same review-comment endpoint the harvesting read
  otherwise treats as candidate human feedback, and it would harvest
  as feedback on its own author's comment with nothing here to catch
  it. Should that operation ever land, harvesting's read side needs
  the same author-identity filter the correction above puts on
  review-comment read generally — excluding the plane's own GitHub
  identity alongside third-party bots and Apps — not a return to
  string-parsing. Until then, "unmarked" means: arrived as a review
  comment, and not filtered out by the author-identity check above —
  not, as the first draft had it, simply "arrived as a review
  comment."
- **The Fake's forge state lives in a per-test supervised process, not
  a Store table** (ORC-31). `dispatch_run` is not the precedent it
  looks like: `delivery_dispatch_runs` is written by the *real*
  adapter as well as the fake — `HostPort.Actions` opens that record
  on every live dispatch, because it is production state the plane
  genuinely keeps. Branches, PRs, comments and check runs have no
  production writer at all; GitHub holds them and the real adapter
  only ever reads them back, so Store tables for those would exist
  solely for the fake, inside the plane's production schema, with
  nothing in production ever writing a row. The one thing a Store
  table would have bought — sandbox safety under `mix test`'s async
  runs — needs no schema: a per-test process is isolated by
  construction, and with no database involved there is no sandbox to
  need. `HostPort.Fake`
  gains a GenServer per test (started and stopped with the test, like
  any other test-owned process in this codebase) holding branches,
  PRs, comments and check runs in memory, keyed to that process — not
  a Store table. Store-backing forge state may still turn out to be
  the right call — the fake surviving a `Repo` restart, or the sim ring
  wanting to query forge state through the same surface as everything
  else, are real arguments for it — but that argument wasn't made here,
  so this entry doesn't make the decision on its behalf.
- **No HTTP-mock-server-based fake** (ORC-31, design pass; refusal,
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
- **The sim-style test ring drives a full branch → PR → comment →
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
- **The feature-ticket lifecycle is a Commanded process manager,
  `Catapult.Delivery.FeatureLifecycle`, reading engine's own events —
  not a second engine aggregate** (ORC-32, design pass; v5 §7.13's
  porting-model citation, "snapshot→actions purity maps near-1:1 onto
  a Commanded process manager," is this component). It is
  `application: Catapult.Engine.Application`-subscribed, the same
  application `Catapult.Engine.Router` already names, because the
  events it reacts to (`FlowOpened`, `DraftCommitted`, `DraftApproved`,
  …) are engine's own. **Checked, not assumed: this does not reproduce
  the compile-connected edge `Catapult.Engine.Application`'s own
  moduledoc warns a router macro creates.** A process manager probed
  against the real tree — `use Commanded.ProcessManagers.ProcessManager,
  application: Catapult.Engine.Application, name: "..."`, with
  `interested?/1` clauses matching real event structs (`FlowOpened`,
  `DraftCommitted`, `DraftApproved`) — compiles clean and leaves `mix
  xref graph --label compile-connected --fail-above 0` at its existing
  zero. The reason is the same one `Catapult.Engine.Router`'s own `use
  Commanded.Commands.Router, application: Catapult.Engine.Application`
  line already demonstrates coexisting with the gate: the edge that
  trips the ratchet is `Commanded.Commands.CompositeRouter.router/1`
  reading `__registered_commands__/0` off an already-aliased module at
  compile time (a macro call needing the callee compiled first), which
  neither `use ..., application: ...` nor ordinary struct
  pattern-matching in a function head triggers — those are `use`/export
  dependencies the tracer classifies as non-transitive, never
  compile-connected. No `Module.concat/1` escape is needed for the
  process manager itself. (Scratch-verified against this branch; the
  probe module itself was never committed, per DESIGN §5.)
- **Identity is the pair `(project_id, flow_id)`, composited into one
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
- **The loaded workflow is a parameter, never resolved — the same
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
- **Reachability, settled: `checks` is this phase's last reachable
  position; `merge`, `deploy`, `validating` and `terminal` arrive with
  Phase 7** (ORC-32, design pass, closing this ticket's own open
  question; restated here against the vocabulary as it now stands —
  `fanout` retired and the queue/pending rename and `:boundary`
  retirement both landed, `dsl-syntax.md` §15.1). The kinds themselves
  are never in question — `Catapult.Dsl.SystemStatus`'s closed table
  fixes them all up front, so nothing here adds or removes one. What
  is open is which of them this process manager's own callbacks ever
  route a ticket into. `merge`/`deploy` are reconciliation and
  publish outcomes and `validating` is §7.11's post-deploy repair
  loop, which needs a deploy, which needs `merge` — each sits behind
  the child lifecycle/mutex/dispatch/reconciliation machinery this
  ticket's own scope names as Phase 7's, not this one's. So this
  process manager's `interested?`/`handle` pair is total over
  `pending → generation → [critique] → [gate] → … → checks` and
  *recognizes* the later kinds without ever driving a ticket into them
  — a bundle declaring gates or environments after `deploy` still
  loads and validates today (§13), unaffected. A ticket reaching
  `checks` sits there under this phase; what moves it again is Phase
  7's own dispatcher.

  **`checks` can recur, once per generation-shaped sub-array
  (`dsl-syntax.md` §15.1, §15.11) — the boundary is the last such
  occurrence in the type's own array that precedes the array's own
  `merge` entry, not the first** (ORC-182, design pass). The shipped
  single-phase `feature.yaml` never exercised the difference — one
  `checks`, so first and last coincide — which is what let
  `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2`'s own
  `take_through_boundary/1` anchor on the first occurrence and still
  read correct. The multi-phase case is `dsl-syntax.md` §15.2's own
  revised `feature.yaml` worked example (three `checks`, one per
  design/architecture/implementation sub-array — the same count this
  doc's own ORC-155 entry, below, already names for that same
  declaration), corrected here from a design-review pass that first
  attributed it to §15.11's `component.yaml` instead: that example
  carries only two `checks` (architecture and implementation) and no
  `design` sub-array at all — §15.11's own prose is what rules `design`
  out there, since `design` and `product-review` are feature-only.
  Every one of §15.2's earlier `checks`/`critique`/gate cycles is
  ordinary reachable board structure, not Phase 7 machinery — only
  what follows the *final* `checks` (that sub-array's own `critique`,
  the type's trailing `reconcile`, `merge`, `deploy`, `terminal`) sits
  behind it. Anchoring on the first occurrence instead silently drops
  every position after it, however many phases and gates that is —
  not live against the shipped bundle today, so nothing has rendered
  wrong yet, but a landmine the moment a bundle ships §15.2's
  documented shape. Dev's diff against this record:
  `take_through_boundary/1` finds the *last* index carrying `{:kind,
  :checks}` ahead of `merge`, not the first.

  **That move exposes a second gap, in `Projection.passable?/2`,
  closed here rather than left for dev to guess at** (design review).
  `passable?/2` has exactly two clauses — `kind in [:pending,
  :generation, :critique]`, and a gate — and `resting/3` never tests
  the sequence's own last entry, which is the only reason a
  first-occurrence `checks` (always last, on the shipped bundle) has
  never hit the missing clause: `take_through_boundary/1`'s
  first-occurrence anchor was load-bearing for this too, unrecorded
  until now. Moving the boundary to the last occurrence makes every
  earlier `checks` — and, on §15.2's shape, `design`, `architecture`,
  `implementation`, and every `reconcile` ahead of the final `checks`
  — a *non-last* position `resting/3` does test, raising
  `FunctionClauseError` out of a clause list never asked to answer for
  them. Two answers were coherent and this record picks one rather
  than leaving both open:

  - `design`, `architecture` and `implementation` are generation-shaped
    the identical way `generation` already is (`dsl-syntax.md` §13,
    §15.1) and this projection draws no distinction between the four
    anywhere else (`Sequence.to_position/1` maps all of them through
    the same `{:kind, atom}` shape) — the existing clause's `kind in
    [...]` list widens to name all four, not `generation` alone.
  - `checks` and `reconcile` stay unpassable **at every occurrence,
    not only the last.** This projection has no event reporting a
    checks run's own outcome or a reconcile's own join independently
    of a fresh `DraftCommitted`/`RunFailed` (`FeatureLifecycle`'s own
    `interested?` list, which is the whole of what this process
    manager observes), so nothing here can tell an intermediate
    `checks` or `reconcile` apart from the boundary one the paragraph
    above already covers. `passable?/2` gains a catch-all clause
    answering `false` for every kind not named in the bullet above,
    and every `checks`/`reconcile` occurrence renders and rests
    exactly like the boundary always has. Consequence, named rather
    than left to be found as a stuck board card: a ticket resting at a
    non-final `checks` or `reconcile` does not advance into that
    phase's own `critique`/gates under today's event vocabulary —
    real on §15.2's documented shape, not on the shipped bundle.
    Giving this phase a signal for an intermediate checks or reconcile
    outcome is new Phase 4 advancement behaviour; it is unbuilt, and
    designing it is not this ticket's scope.

  **A third gap, in `resting/3` itself, surfaced only once the first
  two were fixed and tested against a recurring boundary kind** (dev
  pass, not caught by design review): `resting/3` found "not yet
  passable" by walking `Sequence.positions/2`'s list with `Enum.find
  (positions, last, &(&1 != last and not passable?(&1, state)))` —
  excluding the sequence's own last entry by comparing *values*, not
  index. Once `{:kind, :checks}` legitimately recurs (this record's own
  first bullet, above), every earlier occurrence shares that value with
  `last` and the `!= last` guard excludes all of them alongside the
  true final one — silently, since `passable?/2` is never even called
  on them. The walk sails straight past every non-final `checks`
  instead of resting there, contradicting "every checks/reconcile
  occurrence renders and rests exactly like the boundary always has"
  two paragraphs above. Fixed by pairing each position with its index
  and excluding by `index != last_index` instead of by value.
- **The label owner, settled: the work surface renders; this
  projection never does** (ORC-32, design pass, closing this ticket's
  other open question). The projection carries exactly what
  `Catapult.Dsl.SystemStatus.kind()` and the loaded workflow's own
  gate/environment `name:` already give — `:generation`,
  `"engineering-review"` — never a rendered string. Reasoned from
  §7.10's own store test (does changing it change what is generated,
  validated or enforced? no — a label is read, never branched on): a
  human-facing label is presentation, and belongs with "the work
  surface renders" (this doc's own opening paragraph), not with this
  projection and not with workflow-bundle content. `dsl-syntax.md`
  §15.1's table already fixes labels for the twenty platform-fixed
  kinds — `backlog`, `pending`, `generation`, `design`, `architecture`,
  `implementation`, `critique`, `checks`, `reconcile`, `merge`,
  `deploy`, `validating`, `blocked`, `stubbed`, `setup`, `prep`,
  `main`, `retro`, `cleanup`, `terminal` — across the two default
  lifecycles; a *declared* gate's or
  environment's own name (`ux-review`, `dev`) has no such table and
  needs one, but writing it is `systems/dashboard.md`'s decision when
  UI v1 renders this projection — out of this ticket's own declared
  scope ("the screens that render this, which are UI v1's") — not a
  new `label:` field on `Catapult.Dsl.Gate` (that would put a
  presentation fact in graph state, exactly what the store test rules
  out).
- **Gate skip-on-no-diff and the entry-tier rule are both read off
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
- **Blocked carries no new mechanism either** (ORC-32, design pass).
  `:blocked` is one of the twenty fixed kinds
  (`Catapult.Dsl.SystemStatus`) with `ball: :varies`; this process
  manager enters it as any other transition, and the flavor label plus
  origin are read the same way v5 §7.19 already settles for the
  platform generally — off the ticket's own projected history, never
  stamped onto a comment (this doc's marker-retirement bullet above
  already retires stamping "for surfaces we own"). Nothing here adds
  to that decision; it is named only so the process manager's own
  callbacks are read as an application of it rather than a fresh
  design.
- **What advancing past a gate on a human's word dispatches to stays
  open, unchanged by this ticket** (ORC-32, design pass). v5 §7.16
  already names this open — "Approval is a status... the mechanism is
  a later increment, and a sizeable one" — and this ticket's own scope
  ends at Building without needing to close it: the process manager
  above covers the transitions engine's own events already drive
  (dispatch, commit, skip-on-no-diff). Which aggregate a human's
  sign-off command validates against under §7.16's optimistic
  concurrency is left exactly where `systems/engine.md`'s own §7.16
  bullet already leaves it: "a workflow gate is declared
  delivery-bundle vocabulary, not an engine node, so what it pins is
  delivery's to design when workflow gates land
  (`systems/delivery.md`'s Phase 7)... not this ticket's to answer."
  That is engine's own file-map territory, and this doc does not
  reinterpret engine's "a project has one aggregate, not two" to
  settle it — the citation above already keeps §7.16 open on its own
  terms, without needing a second, narrower reading of a rule
  recorded in another system's file.

  **Amended at ORC-34: the aggregate question above is answered; the
  general §7.16 question it sits beside is not.** `Catapult.Engine
  .Aggregate` is what a human's sign-off command validates against —
  `ApproveGate`/`DeclineGate`, `systems/engine.md`'s own new entry —
  settling the narrow half this bullet named. What stays exactly as
  open as this bullet already left it: what a *passed* gate pins
  (§7.16's own still-open item), and which node(s) a gate spanning more
  than Phase 4's single pre-gate `generation` status would validate
  against. ORC-34 needed neither to close the mechanism it built.

- **The storage question the three entries above leave open is
  engine's, not this system's — corrected here rather than left to
  read as a contradiction** (ORC-104, design pass;
  `systems/engine.md`'s own new entry). "What this system owns, not
  yet built: the storage distinguishing 'instances that exist' from
  'the instance that is current'" read, at the sixth ORC-105 pass, as
  a second store this system would keep. It is not: a container
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
  validates and records it, and its new projection is what this
  system's dispatcher reads back, keeping no second copy of its own.
  This is a real correction to what the sixth pass wrote, not a
  rewording: this system's own store keeps nothing about container
  position that engine's projection doesn't already hold.

- **The dispatcher is a new process manager, `Catapult
  .Delivery.ContainerLifecycle`, built beside `FeatureLifecycle` on the
  identical `application: Catapult.Engine.Application`-subscribed
  shape — and the first of this system's process managers that writes
  back, not only reads** (ORC-104, design pass). Every process manager
  this system has shipped so far (`FeatureLifecycle`, ORC-32) only
  projects engine's events into this system's own read models; this
  one also issues commands into `Catapult.Engine.Aggregate` once its
  own dispatch conditions are met — the split `systems/engine.md`'s new
  entry states from the other side.

  **Amended at the dev pass: it dispatches through
  `Catapult.Engine.Router` itself rather than returning commands for
  Commanded to route.** A process manager ordinarily returns commands
  and its `application:` routes them; that is not available here,
  because `Catapult.Engine.Application` deliberately does not compose
  the router (keeping it off the compile-connected graph — that
  module's own moduledoc carries the reason). A returned command is
  therefore an *unregistered* command and Commanded stops the manager.
  Two consequences are load-bearing rather than incidental, and are
  recorded here so the next process manager that writes back does not
  rediscover them: the dispatch must be `consistency: :eventual`, since
  a strongly consistent dispatch from inside a strongly consistent
  handler waits for that handler to catch up with itself; and a
  rejected command must be absorbed rather than fatal, because the
  rejections this design produces on purpose — a stale `from_queue`
  losing its compare-and-swap, a re-mint of an instance that already
  exists — are the manager re-deriving a decision already made, and
  Commanded's default is to stop on them. The convergence loop is the
  resulting events coming back around to the same manager. Dispatch stays uniform per
  `dsl-syntax.md` §15.7: whatever a queue's resolved `flow:` turns out
  to be, this process manager treats identically — a `ticket`-skeleton
  resolution opens an ordinary flow instance through the existing
  `OpenFlow` path (unchanged, still driven only by `ready_scopes` on
  the chain-axis side), a `container`-skeleton or skeleton-less
  resolution issues a mint command instead — never branching on
  anything the queue entry itself declares, only on what the resolved
  declaration contains. `retro` and `setup` are not special-cased here
  either: each is an ordinary declared queue entry whose `flow:` names
  an ordinary chain-bundle flow, dispatched the same way any other
  queue's `flow:` is (`docs/v5-design-decisions.md` §7.8).

- **A process manager's own persisted state is bound by the identical
  JSON round trip its events already are — settled as a standing rule,
  not just fixed on the one instance that crashed** (ORC-120, bug,
  design pass). `Commanded.ProcessManagers.ProcessManagerInstance` calls
  `persist_state/2` after every handled event, unconditionally, which
  serializes the manager's own struct through the identical
  `Commanded.Serialization.JsonSerializer` `config/*.exs` already names
  for the event store — the same encoder every event struct here
  already carries `@derive Jason.Encoder` for, and the same one
  `Catapult.Engine.Events.FlowResumed`'s own moduledoc already
  documents refusing a bare `Sequence.position()` tuple over, for the
  reason recorded there: `Jason` has no `Encoder` for a raw tuple, so a
  struct carrying one crashes real persistence on the first write, not
  on `mix test` — the suite's `InMemory` adapter (`config/test.exs`)
  never round-trips state through JSON at all, so this class of defect
  is invisible to the default suite by construction, on any process
  manager, indefinitely. `Catapult.Delivery.FeatureLifecycle` is the
  instance this ticket found broken (no `@derive Jason.Encoder` on
  either itself or its nested `Projection`, and `Projection`'s
  `blocked_from`/`pinned_to`/`passed` all carry or key on raw
  `Sequence.position()` tuples), but the rule is general and already
  has a second instance in the identical repository state, found
  reading this ticket's own scope rather than by a separate look:
  `Catapult.Delivery.ContainerLifecycle` (ORC-104, above) carries no
  `@derive Jason.Encoder` either. **Both instances are this ticket's
  scope, not one filed and one fixed** — the two passes that found
  `ContainerLifecycle` each declined to touch it on the correct
  instinct that a ticket named `FeatureLifecycle` only, and the author
  then widened the ticket itself rather than leaving a second ticket to
  ship against a rule this doc had already written down one module
  over. `ContainerLifecycle` differs from `FeatureLifecycle` on both
  halves of the fix, which is why both are worth stating rather than
  assuming the same shape twice:
    * **Encode:** the missing `@derive Jason.Encoder`, and nothing
      more. `type_name` and `queue` are both `String.t() | nil` — no
      `Sequence.position()`-shaped field anywhere on this struct — so
      none of `blocked_from`/`pinned_to`/`passed`'s flattening work
      applies here.
    * **Decode:** a `JsonDecoder` implementation is still required,
      for a different reason than `FeatureLifecycle`'s. `state` is an
      atom (`:minted | :active | :closed`); `Jason` encodes `:minted`
      to `"minted"`, and `struct(module, data)` restores it as that
      bare string, in violation of the struct's own `@type` — the same
      reification gap named above for `FeatureLifecycle.projection`,
      just not previously turned on the atom next door.
    * **Latent, not live:** no `apply/2` or `handle/2` clause in
      `ContainerLifecycle` matches on `state:` — every head is
      `%__MODULE__{} = pm`, and the field is written but never
      matched (the one `state:` match in the file is on
      `Catapult.Engine.Store.Container`, a database row, a different
      struct). The drift is dormant today and goes live the first time
      a clause is added that matches on it — the reason to close it
      now rather than after it bites, and also why it is not itself
      gating.
  **The fix extends existing precedent rather than inventing a
  second one**:
  `FlowResumed` already answers a bare position field by flattening it
  to the two-nullable-strings shape `position_columns/1` (this doc's
  own store columns) already uses; `FeatureLifecycle`'s `blocked_from`
  and `pinned_to` take the same flattening. `passed` breaks new ground
  the existing precedent doesn't cover, and is named here so the next
  pass doesn't relitigate it: a JSON object's keys are always strings,
  so a map *keyed* on a position — not merely carrying one — cannot
  round-trip as a JSON object at all, flattened or not, and becomes a
  list of flattened `{position, signature}` records instead. Restoring
  either struct from a snapshot also needs a
  `Commanded.Serialization.JsonDecoder` implementation, which no event
  here has needed before now: `JsonSerializer.deserialize/2` calls
  `struct(module, data)` and only *then* the decoder protocol, so a
  nested struct field (`FeatureLifecycle.projection`) lands as a bare
  atom-keyed map, never reified, unless the protocol does it — the gap
  every event here has avoided simply by nesting no struct and needing
  no atom reconstructed. The decision is the shape; writing the
  encoder, the decoder and the flattening is dev's, same as always.

  **Both `Commanded` internals this entry rests on are confirmed
  against source, not restated on faith** (design review had flagged
  them as unread — deps are in fact vendored in this checkout).
  `ProcessManagerInstance`'s event-handling clause calls
  `persist_state(event_number, state)` unconditionally on every
  successful `mutate_state/2` — no flag, no opt-out
  (`deps/commanded/lib/commanded/process_managers/process_manager_instance.ex:257`).
  And `JsonSerializer.deserialize/2` really does build the struct
  before the decoder protocol runs, not after: `Jason.decode!/2 |>
  to_struct(type) |> JsonDecoder.decode()`, where `to_struct/2` is
  `struct(struct, data)`
  (`deps/commanded/lib/commanded/serialization/json_serializer.ex:33-41`).
  Both claims hold exactly as this entry and the ticket's own
  description already state them.

- **Every carried finding leaves adjudicated, enforced as the
  container's own close — not a check keyed to the queue name `retro`,
  and not a separate check bolted on afterward** (ORC-104, design pass;
  corrected to this shape at ORC-148's fold and its own design review,
  which retired the singleton-ticket `retro` this bullet originally
  described). `retro` is an ordinary agent-balled entry directly in
  `milestone`'s own array (`dsl-syntax.md` §15.1-§15.2, §15.10) —
  dispatched against the milestone container instance itself, a legal
  dispatch target on the identical footing as a ticket
  (`v5-design-decisions.md` §7.8) — never a separately minted ticket or
  a `flow:` of its own. Its dispatched run reads the findings this
  milestone carried and, for each, either opens it under its own key
  (an ordinary flow instance, through the same uniform dispatch above)
  or writes a decline with its reason — a new engine event,
  `FindingAdjudicated`, on the milestone container instance's own
  aggregate. The container does not advance past `retro` while any
  finding it carries lacks one of those two outcomes — because an
  unadjudicated finding is exactly that, unresolved work this container
  is still holding — but the check is attached to the container's own
  close, not to a queue recognized by the name `retro`: naming the
  queue would mean the dispatcher branching on the word `retro`, which
  is the implicit anchor meaning `dsl-syntax.md` §15.2 spent four
  passes removing ("nothing in the loader branches on any of the three
  words") and which §15.9's admission rule is written to keep out of
  plane logic. Attaching it to the close says the same thing about the
  same container without asking the grammar for a magic word, and says
  it about *every* container — including one whose author declared no
  backward-looking entry at all, which a `retro`-named check would have
  let close over its findings silently. This is not a `blocks:`
  relation either way (`dsl-syntax.md` §15.7's `blocks:` is an entry
  guard, checked once at transition, ORC-148 design review): nothing
  gates *entry into* `retro` on its own findings, since the findings
  are what `retro` itself produces and adjudicates after it has already
  begun. **In the shipped `milestone` type, `retro` is followed by
  `proposals-read`, then `cleanup`, `deploy` and `terminal` — no
  `checks`, `reconcile` or `merge` at all, a correction at ORC-155 to
  what this bullet said before it.** `retro` used to be followed by the
  identical checks/reconcile/merge/deploy sequence `setup` was also
  followed by (`reconcile` named at ORC-151; before that, the sequence
  read `checks`, `merge` and `deploy`, with the same reconciling
  judgment carried inside `merge` rather than named separately) — but
  that sequence closed a gap real only while `retro` merged something
  of its own. ORC-155 removes the gap along with its premise: `retro`
  produces no code, pushing its findings to `cleanup` rather than
  merging a docs-pruning draft directly, so there is nothing left for
  `checks`/`reconcile`/`merge` to check, join or land. The
  finding-adjudication close gate above is unaffected by any of this —
  it sits on `retro` itself, ahead of whatever follows it, never on
  `cleanup` — and neither is `setup`'s own identical shape: both agent
  steps drop the same three entries for the same reason, `setup` gaining
  a `kickoff-review` gate in their place (`dsl-syntax.md` §15.2, §15.12).

- **The aggregated flag set flips through the ordinary
  intent → idempotent effect → observed completion discipline (§7.1),
  because a flag flip is an external effect exactly like a GitHub call**
  (ORC-104, design pass; v5 §2.10, §7.8). `retro`'s dispatched run
  computes the union of `feature_flags/0`-registered flags across this
  milestone's member features (membership read off `systems/engine
  .md`'s new by-reference projection) once the container is otherwise
  ready to advance past it — after the `:live` gate has cleared (already
  enforced structurally: a red `:live` verdict counts as `main` still
  carrying unresolved work, so `main`'s declared `blocks: [retro]`
  keeps `retro` from being *entered* at all until it clears, §15.7's
  entry-guard reading — `retro` never begins mid-red, so nothing has to
  hold its result back after the fact) and the author's own manual
  pass. The
  flip is not a plane-internal event alone: it is a
  `FunWithFlags`-backed enable call, so it follows the outbox
  discipline every other outbound act in this system already does — a
  `FlagSetFlipRequested` intent event, an outbox worker performing the
  enable calls, and a `FlagSetFlipped` completion event once the world
  confirms. This is what makes "features merge dark as they complete;
  the milestone lights up together" (§7.8) real behavior rather than a
  grouping label on a query.

- **Composition proposes and never commits, and proposes off the
  structured signals this system already keeps rather than
  reproducing orchestration's flat backlog view** (ORC-104, design
  pass). `setup`'s dispatched run — forward-looking, dispatched the
  same uniform way any other agent-balled entry is — computes
  candidates for the next container's `prep` from this system's own
  backlog/gating projection and writes them to a new, purely computed proposal
  read-model; nothing here creates a real ticket. Committing a proposal
  into an actual `prep` entry is an ordinary ticket-open action, an
  author's to take, unchanged by this ticket and out of its scope
  (explicitly named as such in the ticket record) — the milestone
  screen that will render this proposal list is dashboard v3's, later.
  **The refusal this settles**: the tempting shape is the one
  orchestration shipped — a backlog view keyed on a work item's key,
  title, priority and gating state, which proposes a work item whose
  own description argues it isn't ready every close, because nothing
  in that view can see the argument. This system doesn't reproduce
  that gap. A work item already carries structured signals orchestration's
  flat view never had — `Stubbed` status (§7.6, "committed work
  deliberately waiting"), and any unresolved blocking edge or
  unmet context-walk dependency the engine already computes — and the
  proposal query filters against those before a candidate is ever
  written to the read-model, rather than surfacing every gating-state-
  eligible item and letting a human filter prose out of a description
  field by hand.

- **ORC-33 (design pass) finds ORC-31's own operation vocabulary short
  one shape, and this is that shape named rather than patched
  silently.** Branch/PR-open/merge-forward/merge/labels/checks/diff
  (`HostPort`'s ORC-31 bullet above) cover topology, CI signaling and
  reconciliation, but nothing in that list writes *content* onto an
  arbitrary ref. `reset_repo/2` looks adjacent and isn't: its own
  moduledoc already restricts it to fixture content, and — checked
  here rather than assumed — `HostPort.Actions.reset_repo/2` takes no
  branch argument at all; every `put_file/2` call resolves against the
  repo's default branch through GitHub's plain `contents/:path`
  endpoint, with no `ref` query parameter. Pushing a committed draft's
  body onto a feature branch that is very much not the default branch
  needs a real branch parameter, so this ticket adds two callbacks to
  `HostPort` rather than reusing that one: `commit_files(project_id,
  branch, files, message)` — the same per-file Contents-API shape
  `reset_repo/2` already established (read the blob sha if the file
  exists, PUT with it if so), generalized with an explicit `branch:`
  ref and a caller-supplied commit message, since `"catapult: reset
  fixture"` is `reset_repo/2`'s own message and wrong for everything
  else — and `update_pr_body(project_id, pr_number, body)`, a PATCH
  `HostPort` has never needed before now because nothing before this
  ticket edits a PR after opening it. Both land in `HostPort.Actions`
  and `HostPort.Fake` together, the same rule every earlier operation
  on this port already follows.

- **The write side is a new process manager, `Catapult.Delivery
  .FeaturePublisher`, not a wing bolted onto `FeatureLifecycle`.** Both
  are `application: Catapult.Engine.Application`-subscribed to the
  identical events (`FlowOpened`, `DraftCommitted`) and identified the
  same composite way (`project_id <> ":" <> flow_id`, ORC-87)
  `FeatureLifecycle` already establishes — reused, not reinvented, for
  the same Phase-4 reason `FeatureLifecycle`'s own moduledoc names:
  nothing yet opens two flows concurrently on one project, so
  resolving "the flow" from a bare `project_id` is correct today. What
  is not reused is the module. `FeatureLifecycle` is pure projection —
  the read side v5 §7.10 wants rendered without asking git anything —
  and wiring outbound GitHub calls into its own `handle/2` would mean a
  GitHub outage or a bad credential risking the one component every
  status column and every gate already depends on. Keeping them apart
  means a stalled `FeaturePublisher` leaves ticket status exactly as
  readable as it always was, which is the property worth the second
  module.

- **Trigger timing, settled: the branch and the PR open together, on
  the flow's first successful `DraftCommitted`** — closing the ticket's
  own open question. Neither named alternative survives on its own
  terms: opening at `FlowOpened` puts a PR up with no diff and nothing
  for CI to check, which is exactly the "sitting empty, notifying
  nobody" case the ticket record itself warns against; waiting for
  "the first gate" lets a flow commit several tiers' worth of drafts
  before anything is visible anywhere outside the plane's own store,
  which is worse than the empty-PR case it's meant to avoid, not
  better. The branch is created off `main`'s current head at that same
  moment rather than earlier — nothing exists yet to protect from
  drift before a first artifact lands, so an empty branch parked
  identically to `main` gives the merge-forward machinery nothing to
  do.

  **The branch name is `feature/<slug>-<flow_id>`** (ORC-33) — the id
  for uniqueness, the slug for what a branch list otherwise cannot
  show. A title slug cannot *be* the identity, for the collision
  reason `systems/engine.md`'s own ORC-87 entry gives for every
  per-project id this system handles: two independently-authored flows
  can share a plausible title. That argues for keeping `flow_id` in
  the name, not for dropping a slug a human could otherwise read. The
  slug is read once, off the flow's own ticket title at `FlowOpened` —
  the same declaration entry-tier already reads (`ticket: {entry:
  <tier>, ...}`, above) — lowercased, non-alphanumeric runs collapsed
  to one `-`, truncated to a fixed length. It is never re-read: the
  branch name, slug included, is read back off the same
  `FeaturePublication` row named below rather than recomputed, so a
  title edited after the fact can't disagree with what GitHub already
  holds — which is what answers the rename worry, using machinery this
  bullet already has rather than avoiding the slug to dodge it. `FeaturePublisher`
  records `branch_name` and `pr_number` on its
  own row the moment both calls succeed (`Catapult.Delivery.Store
  .FeaturePublication`, `delivery_feature_publications`,
  composite-keyed `(project_id, id)` exactly as `Store.FeatureLifecycle`
  already is) — a re-observed `DraftCommitted` for a flow that already
  has a row skips straight to the push below.

- **Every push is tracked for idempotency in this system's own store,
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
  path regardless (the same blob-sha-then-PUT shape `reset_repo/2`
  already relies on), so a lost row costs a redundant PUT, never a
  wrong one — the row exists to skip the call, not to guarantee the
  correctness of one that runs twice.

- **The repo-relative path a committed body writes to is a named
  placeholder, not a settled convention** —
  `.catapult/artifacts/<tier>/<node_id>.xml`, the raw, schema-validated
  body `CommitPath` already grammar-checked, written verbatim. No tier
  in `bundles/default/tiers/*.yaml` declares a target-repo location for
  its own draft — `draft:`'s `root_tag`/`grammar` name a validation
  contract, not a place in a shipped project's tree, and nothing else
  in `dsl-syntax.md` fills that gap either. Deciding the real one —
  whether a shipped project ever sees this XML at all, or whether a
  rendering step turns it into the kind of prose `systems/*.md` in
  *this* repo is, and where that step would live — is a bundle-grammar
  question (`core_dsl`/`platform_content`'s file maps), not this
  ticket's to answer by inventing an unreviewed `produces: path:`
  field. The namespaced placeholder keeps this ticket buildable without
  pre-empting that decision: nothing a hand-authored project file would
  ever be named collides with it, and every path is mechanically
  derivable from fields this system already has in hand (`tier`,
  `node_id`), no new lookup needed. Revisit condition: the day a tier
  declares where its own body belongs, this reads that instead of the
  placeholder — a one-function change here, not a new decision.

- **The PR body is regenerated whole on every push, never appended
  to** — reading back `Catapult.Delivery.Store.ArtifactPush`'s own rows
  for the flow rather than re-deriving the set from engine's nodes
  (`Engine.Store.list_nodes/2` is scoped per tier, and this system
  already keeps the exact join it would take to reconstruct the set by
  hand). One line per row — tier, scope, path — links the reader into
  the diff by path rather than restating its content; a full rewrite
  means a re-processed event or a retried push can never leave a
  duplicate or a stale line the way an append-only body would. This is
  the "table of contents... so the PR is readable without reading the
  diff" the ticket record asks for, on the reading corrected below of
  what reading it is actually for.

- **Correction: the feature PR's diff is not the review surface the
  ticket's own argument says it is.** `docs/v5-design-decisions.md`
  §7.4's already-live text (the "Reversed at §7.17" passage, which
  predates this ticket and which this ticket's own record does not
  cite) splits artifact feedback by kind: prose reviews natively, at
  sentence granularity; only code review stays line-anchored in a PR.
  Every tier Phase 4's chain produces is prose (`comparch`, `sysarch`,
  `impl`, `feature_expansion`, `vocab` — XML-in, schema-validated,
  never a line of application code), so the surface a human actually
  reads at `Product review`/`Architecture review` is dashboard's native
  review screen, once dashboard builds it (already a hard dependency of
  this whole system — "Depends on" below) — not this PR. What the
  ticket record calls "the point" survives with a narrower job: the PR
  stays the versioning, CI (§7.7's `ci:docs`/`ci:code` labels) and
  child-base surface §7.5 already names, and its body is a navigation
  aid for whoever does open it, not the mechanism gate-entry depends
  on. **This is load-bearing for why `FeaturePublisher` may safely lag
  `FeatureLifecycle` by however long an Oban retry takes**: a gate
  becomes visible off `FeatureLifecycle`'s own projection, which reads
  engine state directly and never waits on git; native review, when it
  lands, reads a committed body the identical way
  (`Delivery.get_draft_body/2`, already synchronous today). GitHub
  being slow, rate-limited or briefly down delays what the PR shows,
  never what the author is asked to act on.

- **Two consequences of the correction above, named rather than left
  for the next pass to guess at (ORC-33, design pass, author
  review).** First: **ORC-31's author-identity filter is not
  orphaned by this correction — it is early.** The doc/code split
  settles *which surface* each artifact kind reviews on; it does not
  retire either surface's own machinery. The filter's consumer is
  line-anchored *code* review, which arrives with child PRs in Phase
  7, not with this ticket's prose-only feature PR — reading "the PR
  is not the review surface" alone, without this line, invites a
  later pass to conclude the filter has no consumer and remove it.
  The filter and its residual (a PAT-authenticated bot indistinguishable
  from the human it authenticates as) stay exactly as recorded above,
  waiting on Phase 7 rather than dead. Second: **`ORC-34` ("Harvest
  declines from PR review into regeneration feedback"), which this
  ticket blocks, inherits a scope fact its own record doesn't carry
  yet.** Under the split, Phase 4's declines are prose declines,
  read from the native review surface (`docs/ui-spec.md`, once UI v1
  builds it) rather than from PR review comments — the PR-harvesting
  half its title names is the code path, and arrives later with the
  same Phase-7 child PRs the first consequence names. Neither point
  changes anything this ticket itself builds; both are recorded here
  because this correction is where the gap between the two first
  becomes visible.
- **The ordering fact the correction above states in passing is worth
  its own line: Phase 4's gates are unreadable by a human until
  ORC-75 (UI v1) ships the native review screen** (ORC-33, design
  pass, author review) — a real intra-milestone dependency, not an
  aside. `FeaturePublisher` and every gate behind
  `Catapult.Delivery.FeatureLifecycle`'s projection can be built and
  can fire without ORC-75; nothing here waits on it mechanically. But
  nobody can act on a `Product review`/`Architecture review` gate
  until ORC-75 exists, whatever this ticket does with the PR in the
  meantime — naming it here is what stops a reader concluding Phase 4
  ships a working review loop on its own. Already listed under
  "Depends on" below; this is that dependency's reason spelled out
  rather than left to "the work surface renders."
- **Merging stays out of this ticket's reach, unchanged from the
  standing reachability record above.** `FeaturePublisher` calls
  `create_branch/3`, `open_pr/2` and the two operations this ticket
  adds; it never calls `merge_pr/3`. "Reachability, settled" already
  leaves `merge` to Phase 7's own dispatcher — a publisher that
  squash-merged on its own initiative would be driving a ticket into a
  status this system's own lifecycle projection doesn't yet recognize
  reaching.

- **ORC-34 (design pass) narrows its own ticket's premise before
  designing anything: Phase 4's harvest source is `document-review`,
  not this system's GitHub PR.** The ticket record's own scope
  paragraph described the PR's line-anchored comments and a
  machine-vs-human author-identity filter as the thing to design
  against — the shape ORC-31/ORC-33 had already built, for a different
  phase, before this ticket's own design pass started. The ORC-33
  entry above already names the gap in as many words ("Phase 4's
  declines are prose declines, read from the native review surface...
  not from PR review comments"), and `docs/v5-design-decisions.md`
  §7.4 and `docs/ui-spec.md` §3.2 both settle the same split
  independently of this ticket. So the harvest designed below reads
  `document-review`'s own per-sentence comments, never `HostPort`'s
  `review-comment read` — that operation, its author-identity filter
  and its residual PAT gap stay exactly where ORC-31/ORC-33 left them,
  waiting on Phase 7's child PRs, untouched by anything below.

- **Design review threw the first draft back: it kept no second copy
  of the mechanism in name while building one in fact, and it deferred
  the write path this scope actually needs.** The first draft put
  `CommentPosted` on `Catapult.Engine.Aggregate` and then wrote
  `Catapult.Delivery.Store.FeedbackBucket`, a cache this doc's own text
  called "not a second engine projection" while being exactly that —
  and a cache whose writer (whatever reacts to a decline) races the
  timer-driven sweeper that reads readiness, reopening the very
  silent-blank ambiguity the ticket exists to close. Separately, this
  ticket's own scope paragraph opens with "the decline trigger,
  arriving as a command like any other author action and validated the
  same way" — deferred once, on the reasoning that §7.16's gate
  sign-off command was a later increment. It isn't, here: `docs/
  ui-spec.md` §2 rule 2 refuses `document-review` (ORC-75) inventing a
  comment or a decline command the protocol doesn't have, and neither
  exists before this pass, so ORC-75 cannot design its screen until
  this ticket lands the vocabulary. Everything below is corrected
  against both findings. The full mechanism — `CommentPosted`,
  `CommentFeedback`, `ApproveGate`/`DeclineGate`, `GateComments`, all
  four log-derived, none of them a second store — is recorded once, in
  `systems/engine.md`'s own new entries, since that is where the
  aggregate, the commands and the event log they read all already
  live; this doc points at it rather than restating it, which is the
  discipline the first draft's own text claimed and didn't follow.

- **This system's job is the two reads and the one write the
  mechanism above doesn't itself perform: rendering, and moving a
  ticket's projected status.** `Catapult.Generation.ContextAssembly`
  reads `Engine.Projections.CommentFeedback.since_last_resolution/2`
  and `Engine.Store.reviews_for_node/2` directly at render time
  (`systems/generation.md`'s own entry) — this system supplies neither;
  there is no delivery-owned copy of `feedback` or `prior_review` for
  either ticket's premise to have gotten wrong this time. What this
  system does own: `Catapult.Delivery.FeatureLifecycle` gains two more
  `interested?`/`handle` clauses, `GateApproved` and `GateDeclined`
  (`systems/engine.md`), the same process manager ORC-32 already built
  to project every other engine event this ticket's status tracks.
  `GateApproved` advances the ticket to the next entry in its type's
  own `statuses:` array after the gate's position (a lookup against the
  loaded `Catapult.Dsl.Workflow.t()` this process manager already
  threads through, per ORC-32's own entry above); `GateDeclined` moves
  it straight to `throwback_to` — no lookup needed, the event already
  names the resolved target, guaranteed reachable by the command edge's
  own "earlier in the citing type's own array" check before dispatch —
  the identical predicate `Catapult.Dsl.Workflow
  .gate_throwback_problems/2` already runs at load time against a
  *declared* `throwback:` (unaffected by ORC-115's narrowing of that
  field to a single target, `docs/dsl-syntax.md` §15.4), reused at the
  command edge as a second, runtime instance of the same check against
  whatever the human actually picked — declared override, derived
  default, or an earlier-prefix choice alike (`docs/dsl-syntax.md`
  §15.10). Neither clause is new mechanism beyond what this process
  manager already is;
  it is the increment ORC-32's own "what advancing past a gate
  dispatches to stays open" bullet named and deferred, closed here on
  the aggregate side `systems/engine.md` settles and amended into that
  bullet above.

- **A decline with no comments is refused before it becomes an event,
  by the aggregate, not by a screen** (ORC-34, design pass,
  design-review correction). The first draft answered the ticket's own
  "decline with no comments" open question by having "the UI" fail
  validation — which puts a protocol invariant in the view layer this
  doc's own point-of-action rule already rules out for every other
  command on a surface we own (this doc, above: "the rejection lands at
  the point of action"), and `docs/ui-spec.md` §2 rule 1 says the same
  thing from the screen's own side ("no screen is a second write
  path"). `Catapult.Engine.Commands.DeclineGate` is what actually
  rejects it — `systems/engine.md`'s own new entry has the check (the
  aggregate's own per-gate comment-count state, not a projection read —
  the fourth design-review correction relocated it there off
  `GateComments.any_since_last_resolution?/2`, since the aggregate's
  own purity floor forbids `execute/2` reading the log) and the reason a
  free-text override was rejected in favor of requiring a real comment:
  `docs/ui-spec.md` §3.2 already specs `document-review`'s throwback
  action with a target and nothing else, no reason field, so requiring
  a comment rather than inventing one is the simpler fix and the one
  the screen this ticket answers to already assumes. Whatever screen
  ORC-75 builds surfaces that rejection synchronously — the same
  compare-and-swap conflict rendering `docs/ui-spec.md` §3.1 already
  specs for a stale transition — but does not perform the check itself.

- **Cross-scope comment routing is named, not built — nothing in
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

- **A screen needing a concept the protocol lacks is a protocol change
  first, never a field added at the edge** (`docs/ui-spec.md` §2 rule
  2). ORC-75's dev pass filed six write/read gaps against a working
  surface with nowhere to read or write from; ORC-114 closed them
  together because they are that one rule applied six times. The
  shapes themselves live in the code they landed in —
  `Catapult.Delivery.Store` and `Catapult.Engine.Commands` each carry
  their own reasoning at the point it would be edited. What this doc
  keeps is the four decisions that bound future work rather than
  describe past work.

  **Draft body history is one previous, not a log.** What the
  per-sentence diff needs, checked against what `document-review` does
  with it, is the prior committed body and the current one — never a
  second-oldest, since a fresh visit always starts from the latest
  committed body. So `put_draft_body/4` shifts rather than appends. A
  need to diff against more than the immediately prior pass is a
  different and much larger storage decision, not an increment on this
  one.

  **The ticket-listing query is delivery's; the screens are
  dashboard's.** `Store.tickets_for_project/1` answers what `board`'s
  lanes and `my-queue`'s action kinds both need in one project-scoped
  read. `my-queue` is cross-project by design, and satisfies
  ORC-87/ORC-35's "every query carries a project id" by fanning this
  query out once per project the actor has standing in — the rule
  forbids a projectless read, not a screen showing more than one
  project's rows.

  **A ticket's title or argument is bundle content, not a plane
  mechanism** (`docs/dsl-syntax.md` §3, `systems/platform_content.md`).
  The work surface reads `fields["argument"]` off the node at a flow's
  own `entry_node_id`, and renders blank until bundle content supplies
  one.

  **What a passed gate pins is no longer open here.** It was §7.16's
  standing question and the reason gate events carry no `body_sha`;
  `docs/dsl-syntax.md` §15.10 answers it structurally (ORC-115), so a
  surface needing gate staleness derives it there rather than
  reintroducing a pinned field on the event.

- **ORC-151 (design pass) retires the one named exception
  `inline_dispatch_point?/1` has carried since ORC-148, by removing
  what made it necessary** (`docs/dsl-syntax.md` §15.1, §15.11;
  `docs/v5-design-decisions.md` §7.5, §7.19). `merge`'s own `ball`
  changes from `agent` to `plane` — the mechanical join into the
  parent branch, effected by the plane once the new `reconcile` kind
  approves, barring a conflict — so `merge` leaves the agent-balled set
  this function filters over entirely. `inline_dispatch_point?/1`'s
  `not queue_shaped? and non_critique_agent_step? and status !=
  "merge"` simplifies to "agent-balled and not review-shaped": the
  `status != "merge"` clause has nothing left to do, since `merge`
  is no longer a candidate the first two clauses would admit. This is
  the correction ORC-148's own dev pass named against itself — a
  module whose moduledoc asserts it branches on no status name,
  carrying one name check — closed by a grammar change rather than a
  code-only fix, because the exception was never this system's to
  invent: `merge` was agent-balled without being a dispatch point only
  because one kind was doing two jobs (`docs/v5-design-decisions.md`
  §7.19). **Reconciliation itself is not this pass's to build.**
  `reconcile` is agent-balled and dispatches like any other inline or
  chain-tier agent-balled entry — this system's existing uniform
  dispatch (`ContainerLifecycle.open_for/3`'s `cond`, and the ordinary
  `ready_scopes` path for a chain-tier `reconcile` on a ticket) needs
  no new branch to carry it, once the loader recognizes the kind — but
  what a `reconcile` agent run actually reads, writes and approves, and
  the mechanical merge effect `merge`'s own `plane` ball now implies,
  are Phase 7's, the same boundary every gate-mechanism entry above
  already draws. The loader changes named in `systems/core_dsl.md`'s
  own ORC-151 entry have landed, and `bundles/default-flow`'s
  `feature.yaml` and `seed.yaml` both declare `reconcile` against them.

- **A third design review on this same ticket adds two facts this
  system's own dispatcher will carry, past what the pass above scoped
  as "not this pass's to build"** (`docs/dsl-syntax.md` §15.1, §15.11;
  `docs/v5-design-decisions.md` §7.2, §7.10, §7.15, §7.19). First,
  architecture's own fan-out (sysarch/comparch/subcomparch) now spawns
  a ticket per tree level, the identical spawn rule this system already
  states for a feature's component and subcomponent children (above,
  "children spawn when the plan node names them, not at a status
  transition") — recursed one level further than this doc's own spawn
  discussion had needed to say so explicitly before now; a stale
  restatement of the pre-amendment "at `Building`" rule this same
  review found at `v5-design-decisions.md` §7.15 is corrected there,
  not here. Second, a non-root instance's
  own `merge` is triggered by its parent, not by its own dispatch:
  entering `reconcile` is a precondition gated on every blocking
  child's own subflow having finished (`v5-design-decisions.md` §7.2's
  child-blocks-parent, read on entry rather than only on completion),
  and reaching it is what fires the mechanical merge for every child
  now ready — the identical `plane`-balled merge effect named above,
  triggered from the parent's transition rather than the child's own.
  `Catapult.Delivery.ContainerLifecycle`'s own precedent for an
  entry-guard (its `blocks:` inversion, ORC-148, above) is the nearest
  existing shape a dispatcher implementation would extend, not a new
  concept this system invents; `fanout`'s own retirement (`dsl-syntax.md`
  §15.1) removes the status `Catapult.Delivery.FeatureLifecycle.Sequence`
  already described as vestigial, needing no further mechanism here
  since nothing ever dispatched from it. **Not built as part of this
  pass:**
  the tree-spawn recursion into architecture, and the parent-triggered
  merge cascade, both Phase 7's alongside everything the pass above
  already deferred.

- **A fourth design review on this same ticket names two facts this
  system's own dispatcher will carry that the third pass's own worked
  example got wrong, past what either pass scoped as "not this pass's
  to build"** (`docs/dsl-syntax.md` §13, §15.1, §15.2, §15.11;
  `docs/v5-design-decisions.md` §7.6, §7.19). First, **the tickets
  architecture's own fan-out spawns run a second, distinct type from
  the feature ticket itself, not the feature's own array at a deeper
  tree position** — the feature ticket dispatches through
  `types/feature.yaml` (design → architecture → implementation →
  merge, one instance ever); a comparch or subcomparch ticket
  dispatches through a second declared type with no `design` phase of
  its own, recurring per tree level, `v5-design-decisions.md` §7.6's
  "Child" lifecycle correctly read for the first time. This system's
  own type-registry lookup (above, "the loaded workflow is a
  parameter, never resolved") already resolves whichever type a spawn
  names, so the fact that a spawned child names a *different* type from
  its parent's own is not a new capability this system needs to grow —
  it is a fact about which type a spawn cites, `bundles/**` content
  against this record. Second, **`implementation` is now a real
  dispatch phase, not the vestigial `checks` occurrence the earlier
  finding at "Reachability, settled" (above, ORC-32) named before
  `design`/`architecture`/`implementation` joined the fixed vocabulary
  as kinds of their own** (`dsl-syntax.md` §15.1) — a ticket's own
  code generation dispatches at `status: implementation` the identical
  way its own architecture phase dispatches at `status: architecture`,
  both inline agent-balled entries this process manager's existing
  uniform dispatch already reaches, needing no new branch once the
  loader recognizes the kind, which it does — `implementation` sits in
  `SystemStatus`'s own union. The tree-spawn recursion and
  parent-triggered merge cascade named above, now spawning a second
  type rather than a depth-filtered instance of one, are Phase 7's:
  this system's dispatcher reaches them through the same uniform
  dispatch once that phase builds them.

- **ORC-155 (design pass) gives `Sequence.resolve_position/3` a
  disjointness check it has been trusting rather than enforcing, and
  gives every `position()` a namespaced identity beyond kind or gate
  name alone** (`dsl-syntax.md` §13, §15.1, §15.4, §15.12;
  `v5-design-decisions.md` §7.19). `resolve_position/3`'s own doc
  states plainly why membership in `workflow.gates` alone has always
  been enough to tell a gate from a status: "a gate name is never also
  a declared status kind (the two live in disjoint vocabularies)." That
  was true only because a status's whole identity was a platform-fixed
  kind no bundle could author; ORC-155 lets a bundle name a `status:`
  entry, and nothing before this pass stopped that name colliding with
  a declared gate. Left unchecked, a collision resolves to `{:gate,
  name}` unconditionally and a name matching neither raises inside
  `String.to_existing_atom` — both on the throwback path, both
  invisible until a decline actually fires. The load-time check
  `dsl-syntax.md` §15.12 adds closes this the same way every other gap
  in this class closes, at load rather than at the first decline that
  exercises it.

  **Separately, and for the reason `CatapultWeb.Live.Positions`' own
  moduledoc already gives** — a card, a rail entry, a `throwback:` and
  a `blocks:` reference all name a position that may recur (three
  `pending`, three `checks`, two `reconcile` in `dsl-syntax.md` §15.2's
  `types/feature.yaml` worked example alone) —
  **a bare `position()` is no longer a sufficient identity on its own.**
  `<anchor>.<name>` (§15.12) is the qualified form; this system's own
  `status_kind`/`status_gate` projection columns
  (`Store.tickets_for_project/1`) are unaffected in shape — a gate's
  name was always its whole identity, and a status's kind is still what
  every downstream branch here reads — and gain a `name` column beside
  `status_kind`, read for display and reference resolution only,
  never atomized. `Positions.key/1`'s own round-trip encoding needs the
  qualifying anchor to stay a *stable* encoding once two occurrences of
  one kind can appear in the same effective sequence, which ORC-116
  is why this matters now rather than later (`docs/ui-spec.md` §2 rule
  2: that ticket cannot introduce the vocabulary it needs to render
  subflows as groupings, only consume what this one defines). **Not
  built as part of this pass:** `resolve_position/3`'s own disjointness
  check and the namespace/uniqueness checks are `lib/catapult/dsl/**`'s
  (core_dsl's diff, above); the projection column, and `Positions`'
  own encoding change, are this system's and dashboard's, both dev's
  diff against this record, not design's.

- **ORC-116 widens to give `ContainerLifecycle.Sequence` the identical
  namespace awareness the entry above gave this system's ticket-axis
  positions** (`docs/dsl-syntax.md` §15.2, §15.12) — a design review on
  this ticket found the container axis had the identical gap and no
  fix, only a bundle shaped to dodge it. Before this fix,
  `Sequence.next_step/3` and `Sequence.earlier?/4` each resolved a
  position with `Enum.find_index/2` against the bare name
  `Sequence.name/1` returns — a `status:`'s own `status`, a `review:`'s
  own gate name — with no anchor concept at all, so two occurrences of
  one kind in a single container's array were not merely unlabeled the
  way a bare ticket-axis `position()` was before ORC-155; they were
  **indistinguishable to the lookup itself**, which resolved to
  whichever came first.

  **The fix mirrors the ticket-axis one rather than inventing a second
  mechanism, and the data it needs is on `Type`, not on `Status`.**
  `%Catapult.Dsl.Type{}` already carries `groups: [Range.t()]` — one
  `Range` per sub-array, over `statuses` — beside `statuses` itself
  (its own moduledoc: "`groups` holds one `Range` per sub-array over
  that sequence"); a group has no identity of its own beyond that span
  and the anchor sitting inside it (§15.10). `steps/2` reads only
  `%Type{statuses: statuses}` today and drops `groups` on the pattern
  match — the field is not missing, it is discarded. The fix reads
  `groups` alongside `statuses` to resolve a qualified `<anchor>.<name>`
  identity the same way the loader does; `next_step/3`, `step/3` and
  `earlier?/4` compare against that qualified identity instead of the
  bare name `name/1` returns today, and a caller naming an unambiguous
  (non-recurring) position keeps resolving exactly as before.

  **One hazard the fix has to hold, not create: `groups`' ranges index
  into `statuses`, and `steps/2`'s output does not share that
  indexing.** `to_step/1` returns `nil` for an `environment:` entry and
  `steps/2` rejects every `nil`, so a step's position in `steps/2`'s
  output is only the same as its index in `statuses` when no
  `environment:` entry sits ahead of it. §15.10 admits an
  `environment:` wherever a `review:` is legal — inside a sub-array,
  not only after one — so a fix that walks `groups`' `Range`s against
  `statuses` directly (never against the filtered `steps/2` list) holds
  regardless; one that reuses `steps/2`'s existing index space would
  break silently, off by one, the day a bundle puts an `environment:`
  ahead of a group. Latent today only because
  `bundles/default-flow/types/milestone.yaml` puts its `environment:
  prod` after both sub-arrays — worth recording here rather than left
  for the dev pass writing the fix to rediscover.

  **The qualified lookup resolves against `Type`'s own data, not
  `Status`'s.** `ContainerLifecycle.Sequence.next_step/3`, `step/3` and
  `earlier?/4` resolve against `identified_steps/2`'s namespace-qualified
  identity — `type.statuses`, walked at its own true index and paired
  with `Type.namespaced_positions/1`'s own `canonical` field, never
  `steps/2`'s already-filtered list. A bare, ambiguous argument resolves
  to nothing rather than to the wrong occurrence.
  `sequence_test.exs`'s "a bare name recurring across two sub-arrays"
  describe block exercises the lookup directly, against a synthetic
  recurring-name fixture, since no shipped bundle recurs a name after
  ORC-155. Threading that same qualified identity through every caller
  of these three lookups — so a qualified argument is what they are
  actually given, not only what they can accept — is the ORC-171 entry
  below.

- **ORC-171 gives runtime position-tracking, on both axes, the
  identical canonical identity ORC-116 gave `Sequence`'s own lookups**
  (`docs/dsl-syntax.md` §15.2, §15.12).

  **Container axis.** `Catapult.Delivery.ContainerLifecycle`'s
  dispatcher carries `Type.namespaced_positions/1`'s own `canonical`
  identity throughout, never `Sequence.name/1`'s display label:
  `container.current_queue` is populated with it, every comparison
  against it — `forward_or_open/3`, `resolve_and_open/4`, `forward/3`
  included — reads that same qualified value, and `forward/3` passes it
  into `Sequence`'s lookups rather than `Sequence.steps/2`'s bare list.
  `Sequence.name/1` stays what it already is, a display label, never an
  identity.

  **Ticket axis, the identical shape.** `FeatureLifecycle
  .Sequence.position/0` and `Projection`'s `passed`, `blocked_from` and
  `pinned_to` carry the same canonical identity rather than
  `Status.name/1`'s bare one. `Projection.to_wire/1`/`from_wire/1`
  (ORC-120) carry the qualifying anchor as a third field beside `kind`
  and `gate`, the same way `passed`'s own flattened records already do.
  `Projection` can answer which occurrence a resting ticket is actually
  at; retiring `CatapultWeb.Live.Positions.resting_key/2`'s own
  first-match, best-effort guess (`systems/dashboard.md`'s own ORC-116
  entry) on the strength of that is a dashboard-scoped pass's own
  decision, not this entry's — this ticket supplies the data such a
  pass would consume, nothing in `system:dashboard`.

  **An inline dispatch point's own two synthesized entries carry the
  identical field, set to `nil`.** `FeatureLifecycle.Sequence
  .annotated_positions/2`'s inline-dispatch fallback (this system's
  own ORC-176 entry, below) builds `setup`/`retro`'s fixed `pending`/
  kind pair by hand, with no declared type's `statuses:` array behind
  either entry — the same reason each already carries `group_key:
  nil`. `Type.namespaced_positions/1`'s own qualification is a
  property of a name's position inside a declared type's `statuses:`
  array; an entry with no such array behind it is bare by the
  identical rule §15.12 already states for anything outside a
  sub-array, and unambiguous besides — a synthesized two-entry list
  cannot recur a name against itself, and `setup`/`retro` are two
  distinct `FeatureLifecycle` process-manager instances
  (`ContainerLifecycle.open_inline/3` opens each as its own flow), so
  their two `pending`s are never compared inside one `Projection` the
  way `feature.yaml`'s own recurring group `pending`s are. So the
  canonical-identity field every other constructor of
  `annotated_position()` supplies is present on these two maps too,
  rather than the shape forking between callers — `annotated_positions
  /2` returns one shape regardless of which branch built it — carrying
  `nil`.

  **A record written before this ticket decodes with no anchor, and
  that decodes correctly, with no backfill.** `Projection.from_wire/1`
  reads its new `blocked_from_anchor`/`pinned_to_anchor` fields with a
  tolerant default rather than the dot access the existing `_kind`/
  `_gate` pairs use, because every `Commanded.ProcessManagers
  .ProcessManagerInstance` snapshot committed before this ticket
  predates the field entirely, and `from_wire/1` runs on exactly such a
  snapshot on every process restart. A missing anchor decodes as `nil`
  — the unqualified identity that position always was, since no bundle
  recurred a bare name before this ticket landed.

  **The kind/gate discrimination is unaffected in shape, the same way
  the loader-level fix above left `status_kind`/`status_gate`
  unaffected.** A position is still either a kind or a gate —
  `position_columns/1` and `Store`'s two display columns keep reading
  exactly that — with the qualifying anchor consulted only where
  recurrence needs telling apart.

  **Named, and outside this ticket's own reach: a human resuming to one
  specific occurrence of an ambiguous position.**
  `Catapult.Engine.Events.FlowResumed.to_kind`/`to_gate`
  (`system:engine`, outside this record's own file map) carries no
  qualifying field, so `unflatten_position/2` resolves a resume target
  correctly only for the unambiguous case — ORC-155's own "bare when
  unambiguous" rule already covers exactly that case elsewhere. Checked
  against `docs/non-goals.md`, since this decision's consequences reach
  `CatapultWeb.Live.Positions`; nothing there blocks it, and this entry
  touches neither `system:engine` nor `system:dashboard`.

  **The loader is not where this closes, and no load-time warning is
  the decision here.** §15.12's own uniqueness-within-a-namespace check
  already refuses the one shape that is actually a grammar error; two
  occurrences of one kind in two distinct namespaces are legal DSL,
  correctly so — recurrence across sub-arrays is exactly what
  namespacing exists to permit. Runtime position-tracking carrying the
  same canonical identity the loader already resolves against is what
  makes accepting such a bundle safe; a load-time warning would flag a
  legal shape instead.

  `bundles/default-flow/types/milestone.yaml`'s `retro` group carries
  its own leading `pending`, symmetric with `setup`'s
  (`docs/dsl-syntax.md` §15.2) — the canonical identity is what makes
  `setup.pending` and `retro.pending` distinct positions rather than one
  bare name arriving twice. Reverting that bundle to the symmetric
  shape and the plumbing above are one dev diff.

- **ORC-176 (design pass) gives `Sequence.positions/2` a way to place
  an inline dispatch point's own flow, closing a gap ORC-148 opened
  when it folded `setup`/`retro` into `milestone`'s own array with no
  backing `types/<name>.yaml` for either** (`dsl-syntax.md` §15.1,
  §15.7, §15.11). `ContainerLifecycle.open_inline/3` opens such a flow
  with `flow_name: entry.status` — the entry's own literal name, since
  an inline entry carries no `flow:` for `flow_name` to resolve through
  a declared type instead (that function's own moduledoc comment).
  `FeatureLifecycle` subscribes to every `FlowOpened` uniformly, with
  no filter for a container-owned or inline-dispatched flow, and hands
  that same `flow_name` to `Sequence.positions/2` to place it. Before
  this pass, `positions/2` only ever resolved a name against
  `workflow.types`; `setup` and `retro` never will resolve there again,
  by ORC-148's own design, so every setup/retro flow projected with
  `status_kind`/`status_gate` both `nil` — not a crash,
  `warn_unplaceable/3`'s own log line firing instead, but a real loss:
  `screens/board.md` renders `Sequence.positions/2` as a card's own
  lane set, and `Store.tickets_for_project/1` lists every open flow
  with no type filter at all, so a setup/retro card reached the board
  with no lane to sit in. **The title this ticket arrived under
  overstates what was lost — "generation-to-deploy" — worth correcting
  rather than carrying forward: the "Every carried finding leaves
  adjudicated…" entry above already settles, at ORC-155, that neither
  `setup` nor `retro` ever runs its own `checks`/`reconcile`/`merge`/
  `deploy` at all ("both agent steps drop the same three entries for
  the same reason"). There was never a deploy-bound progression to
  place; what this pass restores is placement in the two positions that
  were ever real for either flow, `pending` and its own agent-balled
  kind.**

  **The fix is the discipline `ContainerLifecycle.inline_dispatch_point?/1`
  already keeps, extended to this module rather than duplicated by
  name.** `positions/2`, when `flow_name` fails to resolve in
  `workflow.types`, now asks whether `flow_name` itself names one of
  the closed system-status kinds `Status.non_review_shaped_agent_step?/1`
  admits (`SystemStatus.agent_balled?/1` and not
  `SystemStatus.review_shaped?/1`) — the identical test that already
  decides whether `ContainerLifecycle` opens this flow inline in the
  first place, read directly rather than re-derived. If so, the flow's
  own effective sequence is fixed rather than resolved from any
  declared array: `[{:kind, :pending}, {:kind, <kind>}]` — the same
  "immediately preceded by its own pending, as that entry's sub-array
  head" shape §15.1 already gives every generation-shaped entry — and
  nothing after it, for the reason named above: an inline dispatch
  point has no `checks`/`reconcile`/`merge`/`deploy` position to place
  it at. **A `flow_name` naming neither a declared type nor one of
  these closed kinds is still the authoring bug `warn_unplaceable/3`
  describes** — a chain's `ticket:` face citing a label no declared
  type actually carries — and keeps logging it; this pass narrows the
  warning's trigger rather than removing it, since it was a false
  positive for exactly these two flows and no others.

  **Why the fixed sequence is exactly two entries and never more, not
  a detail to lose in translation:** `Projection.resting/3`'s own
  `Enum.find/3` never calls `passable?/2` on the *last* position in the
  list it walks — `&(&1 != last and not passable?(&1, state))`
  short-circuits before evaluating the right side once `&1 == last` —
  which is the only reason a kind `passable?/2` has no clause for
  (`:setup` and `:retro`, and for that matter `:design`/`:architecture`/
  `:implementation`/`:checks`/`:reconcile`/`:merge`/`:deploy` —
  `passable?/2`'s two clauses cover only `:pending`/`:generation`/
  `:critique` and any `{:gate, _}`) is never reached. This fix's
  two-entry list keeps the inline kind last by construction; a version
  that appended anything after it would hand `passable?/2` a
  `{:kind, :setup}` in a non-last position and crash the first time
  that flow's `commit_signature` is set. **`passable?/2`'s own missing
  clauses for the four other named generation/review-shaped kinds are
  not this pass's to fix** — latent rather than live, since no shipped
  type gives `feature.yaml` a second, non-terminal generation-shaped
  visit yet, and reachable only once one does; filed as a project
  finding against `systems/delivery.md`'s own file map rather than
  fixed here, since nothing this ticket touches exercises them.

  `Sequence.positions/2` and `warn_unplaceable/3`'s narrowed trigger
  both carry this.

- **ORC-198 (design pass) corrects three `FeatureLifecycle.Sequence`
  call sites, carrying four instances of the same bug between them,
  that stayed keyed on the reference-ambiguity test after
  `systems/core_dsl.md`'s own ORC-198 entry splits it from the
  runtime-collision one ORC-155's `name:` made distinct** (this
  system's own ORC-171 entry, above; `docs/dsl-syntax.md` §15.12).
  All four read `Type.namespaced_positions/1`'s `canonical`/`bare`
  fields — the reference-resolution identity — to decide something
  about a *runtime* position instead:

  `annotate/4` (`sequence.ex:185`) computes the `anchor` ORC-171 added
  to `annotated_position()` as `if namespaced.canonical ==
  namespaced.bare, do: nil, else: namespaced.namespace`. Two `status:
  pending` entries with distinct `name:` overrides get `canonical ==
  bare` — their names don't recur, so nothing marks them — and so both
  get `anchor: nil`, indistinguishable from each other once paired
  with `to_position/1`'s identical `{:kind, :pending}` for both: the
  exact failure ORC-171 closed, reopened through `name:`'s own escape
  hatch. Reads the new `kind_ambiguous` field instead: `anchor = if
  namespaced.kind_ambiguous, do: namespaced.namespace, else: nil`.

  `resolve_kind_reference/3` (`sequence.ex:258-262`), called from
  `resolve_position/3` (`sequence.ex:239-246`), carries two independent
  instances. Its own `anchor` line (`sequence.ex:261`) is the identical
  `canonical == bare` test as `annotate/4`'s, corrected the same way.
  Separately, it hands the resolved position's **`bare`** field —
  ORC-155's own display name, not its kind — through
  `String.to_existing_atom/1` to build `{:kind, atom}`. `to_position/1`,
  the only other builder of this shape, always reads the entry's
  literal `status:` field. For a `status: pending, name: alpha` entry
  the two disagree: `to_position/1` yields `{:kind, :pending}`,
  `resolve_position/3` yields `{:kind, :alpha}` — a `throwback_to`
  resolving through the second names a position the first never
  emits. `sequence.ex:203-208`'s own `String.to_existing_atom/1`
  discipline note justifies itself on `status:`'s closed,
  compile-time-literal vocabulary (`Catapult.Dsl.SystemStatus`); that
  argument holds at `to_position/1`, where the input *is* `status:`,
  and does not carry to this site, whose input is a bundle-authored
  `name:` with no reason to be in the atom table. Corrected to read
  the resolved position's own `entry.status` — `namespaced_positions/1`
  already carries the full `%Catapult.Dsl.Status{}` under `entry` —
  rather than `bare`, so both builders of `position()` agree by
  construction.

  `find_kind_entry/3` (`sequence.ex:315-322`), `Sequence.name/4`'s own
  helper, computes `entry_anchor` the identical `canonical == bare`
  way to match against a caller-supplied `anchor` and pick the entry a
  `{:kind, kind}` position displays under. Once `annotate/4` above
  stores `kind_ambiguous`-derived anchors, an entry_anchor still
  computed the old way silently stops matching the anchor
  `Projection.resting/3` actually passes in, for exactly the
  `name:`-recurring-kind case this whole entry is about — `name/4`
  would fall back to the bare kind (its own documented behavior for an
  anchor that "does not resolve to a real occurrence") for a position
  that does have one. Corrected the same way as `annotate/4`.

  All four read `kind_ambiguous`. The case that separates it from the
  reference-ambiguity test — a type recurring a kind under distinct
  `name:` overrides — is the shape no shipped bundle authors today,
  latent rather than live, the same standing this ticket's own
  argument opened with, and it is what `sequence_test.exs` has to
  seed for the difference to be exercised at all.

## Initial vs target

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
remaining a claim about individual tickets. `docs/dsl-syntax.md` §15's
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
landing §15's loader without migrating that content in the identical
change fails every workflow bundle's load, before anything else this
ticket builds ever runs. `bundles/**` is `platform_content`'s own
file map (unchanged, no map edit needed there either);
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
(`systems/foundation.md`'s design review finding): the endpoint rides
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
including the delivery-DSL extension registered with core_dsl, the
declared review sequences and environments of §7.19, and the outbound
mirror in place of the Linear adapter.

## Depends on

substrate, engine (state of record), foundation (serves the
dispatch-facing host port endpoint on its listener), generation (the
chain whose progress it projects), core_dsl (the workflow bundle's
declared statuses and environments, v5 §7.18-§7.19), dashboard (the
work surface — a hard dependency, since nothing else renders the
loop; concretely **ORC-75, UI v1** — until it ships the native review
screen, Phase 4's gates have no surface a human can act on, per the
ORC-33 entry above). Req for the GitHub client.
