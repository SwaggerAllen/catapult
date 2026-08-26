# Catapult UI — screen inventory and journeys (v0)

**Status:** the screen-level spec for Catapult's own UI, written after
the tracker reversal (v5 §7.17) turned it from a debugging surface
into the working surface. Names and functionality lists here are
normative for what exists; visual design, layout and component
inventory are not decided here — they arrive through orchestration's
screen machinery (`screens/*.md`, stateless function components,
`.story.exs` variations), per `docs/conventions.md` §13, because
Catapult does not run its own product tier over itself.

Related: v5 §7.4 (feedback surfaces), §7.10 (bindings, the
configuration composer), §7.16 (concurrent writers, approval as
status), §7.19 (system statuses, review sequences, fan-out depth),
`systems/dashboard.md` (the system and its file map).

**Not everything here is equally settled, and the document says which
is which.** Most screens are *determined* rather than designed —
`my-queue` follows from who-holds-the-ball, the ticket action surface
from §7.16 and §7.19, the observation screens were specced before the
reversal. Two things are **sketch-grade** and marked at the point of
use: the **swim-lane navigator** (§3.1, and its reappearance at
feature scope in `ticket-graph`) and the **bidirectional graph**
(§3.1). They are the novel parts, they carry §7.17's claim that the
native surface is *better* rather than merely available, and unlike
every other decision in this design record they cannot be checked
against anything — there is no internal contradiction a wrong screen
produces. They are staged at v2 (§5) precisely so that being wrong
about them costs a redraw and not a release.

---

## 1. Why this document exists

`docs/non-goals.md` used to hold **no dashboard-as-working-surface**,
and its stated purpose was to be pointed at: "a pipeline this deep
will generate constant temptation to grow a working UI here; this
line exists to be pointed at." Owning the tracker reversed the entry
but did not retire the temptation, and the entry said so — the
warning "wants a successor rule once the screen inventory exists."

This is that inventory, and §2 is that rule.

## 2. The three rules that bound this UI

1. **Reads are projections; writes are commands.** No screen holds
   state, and no screen is a second write path (`systems/dashboard
   .md`'s standing decision, unchanged by the reversal). A human
   action is a command the plane validates — accepted into the log or
   rejected — which is exactly §7.16's model, now delivered at the
   point of action instead of after the fact.
2. **No screen introduces protocol vocabulary.** If a screen needs a
   concept the protocol does not have, that is a protocol change
   first and a screen second. This is the successor to the retired
   entry and it is the one that will actually get cited: the
   temptation is never "build a whole tracker", it is "add one field
   here", and a field here is vocabulary.
3. **Every screen answers a named question or performs a
   protocol-defined action.** A screen that exists to look
   comprehensive is refused. Numbers are in-bounds where they *are*
   the answer — instance health is a numeric determination and
   throughput is evidence — but a number never substitutes for
   explain-why on "why is nothing happening" (§3.3). The old
   formulation, "explain-why over dashboards-of-numbers", overshot:
   the target was decoration, not measurement.

---

## 3. Screen inventory

### 3.1 Work surface

**`my-queue`** — the inbox, and the most important screen here.
**Two tabs, because they are two different questions.**

- **Assigned** — tickets assigned to *you*, directly. This is the
  delegation view, and it is the default. §7.11 already makes room
  for it: assignment is derived on state entry, and "a human
  reassignment within an author-owned state is delegation, respected
  until the next state entry re-derives". Reading assignment here is
  a *rendering* concern; §7.11's rule that the plane never reads
  assignees governs dispatch and protocol decisions, which this is
  not.
- **My roles** — tickets sitting in statuses one of your roles owns,
  whether or not anyone is assigned. The "could I unblock something"
  view, and the one that works before delegation has happened.

**The action-needed set is enumerated, and it is short** — these are
the only three things the plane asks a human to do:

- **sign off** — a review status whose role you hold: approve, or
  throw back to a declared exit
- **unblock** — a blocked ticket whose origin status you own: the
  prerequisite is done, choose the return (§7.19)
- **triage** — machinery-filed work awaiting batch-accept (§7.3)

Nothing else is emitted. In particular there is no *decide* action:
decisions arrive as one of the three above or as a PR, and an action
type with no emitter is a screen looking comprehensive (§2, rule 3).

Empty state is a real state and says so — an empty queue means the
machine has the ball, and the screen links to `explain-why`.

**`board`** — swim lanes for one project, the daily surface.

- lanes are the effective sequence for the selected ticket type
  (§7.19), so the board *is* the workflow, read left to right
- one assignee, one status per ticket (§7.19's sequential decision,
  which is what makes lanes legible)
- **blocked tickets group under the status that kicked them**, not
  in a lane of their own — origin comes from the log, no comment
  stamping (§7.6, §7.19)
- filters: type, label, milestone, mutex label, assignee

**Fan-out collapses, and collapsed is the default.** A declared
workflow can have many statuses and a fan-out can have many children,
so the unabridged board is unreadable by construction. Within a lane,
children group under their top-level ticket and render as one
roll-up; subcomponents group under their component the same way.
**The first thing the board answers is which top-level tickets are in
flight and what state their components are in** — everything below
that is expansion, not default content. Note the grouping is *per
lane*: one feature's components legitimately sit in several lanes at
once, so each lane rolls up only the children it holds.

**Lanes abbreviate to the ones you have standing in** — lanes your
roles own, plus lanes currently holding your tickets. The full set is
one control away and is the exception, not the view.

**Cards link to where pass-forward and pass-back are issued, rather
than issuing them.** `ApproveGate`/`DeclineGate` compare against the
`body_sha` of the artifact the actor is resolving (§7.16, landed at
ORC-114) — a real guard, not an anticipated one — and a card has no
body to read that value from. Filling it from the projection's
current value would make the compare pass unconditionally while the
card looked guarded, which is worse than no guard at all. Every gate
Phase 4's own workflow declares reviews a prose artifact, so a card's
pass-forward/pass-back links into `document-review` (or `ticket`, for
the same reason that screen's own gate action defers there) instead
of dispatching from where it stands; the card still names that a gate
is waiting. This resolves for real at ORC-116 — once a gate's node
set is derivable, staleness is computable plane-side from any
surface and a card needs no body view of its own to carry a real
compare.

**`ticket`** — one ticket, the detail and action surface.

- the *argument* (the human-readable case for the work, §7.2)
- position in the effective sequence, with what has passed and what
  remains, and the depth this ticket sits at
- the gate action, when this user's role holds it: **approve**
  (transition forward) or **throw back** — one click to the citing
  sub-array's own agent step (`dsl-syntax.md` §15.10's derived
  default), or the same earlier-prefix picker J4 gives Blocked-return
  (§7.19): one target rule for both entry points, never bounded by a
  per-gate declaration
- **blocked**: flavor label, origin status, and the return control —
  defaulting to the origin, with the earlier-prefix as a picker
  (§7.19); never forward
- child roll-up, blocking relations, linked PRs and runs
- optimistic-concurrency feedback: a rejected transition names who
  moved it and where (§7.16), rendered as a conflict at the point of
  action rather than a revert comment afterwards

**Two requirements here are settled; the mechanism that serves them
is not.** Recorded separately on purpose, so that discarding the
mechanism leaves a target rather than a blank page:

- **R1 — artifacts, tickets and comments are connected.** From a
  ticket you can reach the artifacts its work produced and consumed;
  from an artifact you can reach the tickets and comments that
  touched it. Neither direction is a search.
- **R2 — comments filter down to the ones you care about.** A
  lifecycle's worth of machine and human commentary is unusable as
  one stream; narrowing it is a first-class operation, not a Ctrl-F.

Both are stable. What follows is **one candidate mechanism** for
them, and it is sketch-grade — the marker tabs it replaced were an
earlier candidate for R2 alone, which is roughly the rate at which
these are expected to change.

**The swim-lane navigator as the ticket's spine.** The lanes this
ticket has passed through are the navigation, not a separate history
tab:

- **a generation lane** opens that lane's *generations* — every pass
  this ticket made through that step, the diff between consecutive
  ones, and the comments that sat between them. Regeneration history
  becomes legible as a sequence rather than as a scrolled log.
- **a review lane** opens the comments left at that step across the
  ticket's whole life — every time it passed through, including
  re-entries after a throwback.

**The governing rule, which outranks the mechanism: a comment is
always rendered in the context of what it comments on, or links to
it.** No orphan comment stream. This is R1 stated as a constraint on
every candidate, and it survives whatever replaces the navigator —
the lane spine happens to satisfy it by serving R1 and R2 with one
structure, which is the argument for it and also the thing to be
suspicious of.

**`ticket-graph`** — everything one top-level ticket touches, in
both directions. *Sketch-grade below the fan-out tree: the tree is
determined by §7.2, the upstream/staleness directions and the
navigator are invented and unvalidated.*

- **downstream**: the ticket tree as the projection of the doc DAG's
  fan-out it actually is (§7.2) — feature → component children →
  subcomponent grandchildren, with status and depth per node and
  blocking edges drawn
- **upstream**: the graph nodes this ticket's work reads — the
  handles and fragments its context walks consume — so "what does
  this depend on" is answerable without leaving the ticket
- **and what it makes stale**: downstream consumers of the artifacts
  it changes, which is the staleness projection (§7.11) rendered as
  neighbourhood rather than as a list
- **a doc and comment navigator, on the same swim-lane spine as the
  ticket screen**: every change related to this top-level ticket,
  filterable down to a single connected node. The whole-feature view
  of what the ticket screen shows for one ticket.
- one of the two reasons the native surface is *better* rather than
  merely available (§7.17) — a general tracker cannot draw any of it
- read-only; every action opens the ticket

**`milestone`** — commitment and queue progress (v5 §7.8, revised at
ORC-105 from a single boundary point to a declared queue sequence).

- what is committed, what is in flight, what is `Stubbed` and why —
  the "live, visible list of what is deliberately half-built" §7.11
  already requires
- which queue (`setup`/`prep`/`main`/`retro`/`cleanup`) is current, and
  any `blocks:` condition holding it there

**`triage`** — machinery-filed work awaiting batch-accept.

- maintenance and advisory-backed filings (§7.3), routine bumps
  batched, `Urgent` ones already past this screen
- accept / reject / re-rank, in bulk

### 3.2 Review surface

**`document-review`** — the gate action for design artifacts, and the
other reason the native surface wins (§7.17).

- **per-sentence diff**, not per-line: prose artifacts diff badly at
  line granularity, and the review comments that matter anchor to a
  claim rather than to a line
- comments anchored at sentence granularity, feeding the harvesting
  rule (§7.4) — the bucket key becomes the anchored span
- approve / throw back — one click to the derived default
  (`dsl-syntax.md` §15.10), or pick any earlier status from the same
  prefix J4 gives Blocked-return (§7.19, ORC-115 second design review:
  one target rule for both movements, never a gate's own declared
  list)
- shows what this gate is reviewing, derived from position (§7.18) —
  whatever the chain produced at the step this gate follows

**`artifact`** — read one settled document with its provenance.

- the body at a recorded SHA, its tier, its handle
- which walk consumed it, what it made stale
- links out to the PR that ratified it

**`preview`** — visual review, per branch: preview URLs and storybook
exports (§7.4's third surface), linked rather than rebuilt.

### 3.3 Observation

Load-bearing and genuinely hard (§7.4). "Why is nothing happening"
must be answerable in minutes.

**`explain-why`** — the flagship. "What is blocking this scope" as a
first-class query, over `ready_scopes`.

- for a scope, ticket, or the whole project: the blocking chain,
  named, with the next thing that would move
- surfaces intent-without-effect honestly (§7.1) — a recorded intent
  whose effect has not landed is visible here, not hidden

**`event-log`** — inspection and replay-to-sequence, with filters by
stream, ticket, and actor.

**`dispatch`** — runs, claims, mutex holdings, queue depth, budget
against the per-instance concurrency cap (§7.12.1).

**`run-transcript`** — one agent run: inputs, context served, output,
gates run, result.

**`staleness`** — what is stale and *why*, derived, never a stored
flag (§7.11). Includes passed gates gone stale (§7.19).

**`health`** — instance health, which is a **numeric** determination
and is rendered as one: queue depth and age, dispatch concurrency
against the per-instance cap (§7.12.1), run success and retry rates,
webhook and sweep liveness, error rates by class, storage and event
-log growth. On top of the numbers, the machine-shaped alert set
mirrored (§7.4): signal silence, dispatch-budget warn/cutoff,
bindings-credential expiry, deploy-detection anomalies,
restore/cutover lifecycle states.

**`metrics`** — throughput and cycle time, over time. Distinct from
`health`: health asks *is the instance well*, metrics asks *is the
system delivering*, and the second is how the platform's value gets
demonstrated rather than asserted.

- cycle time per ticket and per stage — how long work sits in each
  status, which is where a badly placed review gate becomes visible
- review latency per gate and per role, the number that tells an
  organization its own workflow is the bottleneck
- throughput: tickets and scopes completed per period, by type
- regeneration counts and throwback rates per gate — high throwback
  at one gate is a design problem upstream of it
- staleness volume and age
- filterable by project, milestone, ticket type and depth; every
  chart drills through to the tickets behind it, because a number
  you cannot open is decoration (rule 3)

### 3.4 Configuration and ops

Both prongs were always in-bounds, including under the retired
non-goal (§7.10).

**`bindings`** — settings and onboarding: query-and-pick project
wiring through the plane's adapters so the user picks from what
exists instead of pasting ids.

- tracker/host/deploy wiring, the `reviewers:` map (step → user),
  role display names, environment endpoints and credentials
- `tunable` thresholds, rendered as exactly the tunable surface so
  protocol-fixedness is visually enforced
- binding changes are event-sourced; the history is a real audit
  answer

**`configuration`** — the composer: forms generated from registry
declarations, where **save composes a well-formed diff and files it
through the normal entry machinery**. Review stays in the PR; the
composer never bypasses a gate.

**`workflow`** — read-only render of the active workflow bundle: the
sequence, where review statuses sit, their roles and depths, and the
environments and their promotions. Editing routes to `configuration`,
because the sequence is graph state and changing it is a PR.

**`registry`** — installed components and their versions, handle
diffs against upstream, and **consumption mode per component**:
dependency or adopted (§3.5). An adopted component shows its
handle-diff-seeded absorption tickets.

### 3.5 Identity

**`login`**, **`account`**, **`members`**, **`invites`** — consumed
from the identity component (§2.9) rather than built here:
magic-link and optional password, sessions, MFA, role-carrying invite
links, roles-as-data. Small teams are supported (§7.16), so member
and role management is a real screen, not a placeholder.

---

## 4. Journeys

**J1 — clear the queue.** `my-queue` → `ticket` → gate action. The
loop the author runs daily; success is that it is boring and that an
empty queue is legible as "the machine has it."

**J2 — sign off a design gate.** `my-queue` → `document-review` →
per-sentence comments → approve, or throw back — one click to the
target `dsl-syntax.md` §15.10 derives, or pick any earlier status from
the same prefix J4 uses (§7.19). On throwback, everything downstream
reopens (§7.19), and staleness derivation makes the re-pass free where
nothing that gate saw changed.

**J3 — why is nothing happening.** `explain-why` → `dispatch` →
`run-transcript`. The §7.4 promise, and the one journey with a
stated time budget: minutes.

**J4 — unblock.** `board` (blocked, grouped under origin) → `ticket`
→ return to origin, or pick an earlier status from the prefix. Never
forward; skipping a required step means changing the workflow bundle,
which is a PR (§7.19).

**J5 — onboard a project.** `bindings` wizard: pick host and deploy
targets through the adapters, provision the status vocabulary, set
the `reviewers:` map, confirm tunables. Ends with a preflight that
names anything still missing rather than failing later at dispatch.

**J6 — take an upstream component change.** `registry` → handle diff
→ absorption ticket → the normal upward flow (§3.5). Identical for a
dependency and an adopted component; only the trigger differs.

**J7 — change the workflow.** `workflow` (read the current sequence)
→ `configuration` (edit) → PR → cutover. Blocked tickets ride it and
re-resolve on the system statuses (§6, §7.19).

---

## 5. Staging

**v0 — the debugging minimum, unchanged from the pre-reversal plan:**
`event-log`, `explain-why`. These were always Phase 4 and the
reversal does not move them earlier or later.

**v1 — the working surface, and the authoring loop's floor:**
`my-queue`, `board`, `ticket`, `document-review`. **Not a later
stage.** There is no third-party tracker anywhere in Catapult (§7.17)
— no adapter is ever written and nothing is migrated off — so until
these exist, nothing renders the loop and Phase 4 has no surface to
be tested through. The reversal does not defer the UI; it makes it a
prerequisite.

*(Orchestration builds Catapult and orchestration uses Linear. That
is a different system running a different loop. It is not this
document's subject and nothing here changes it.)*

**v2 — the reasons the native surface is better:** `ticket-graph`,
per-sentence anchoring in `document-review`, and the comment
navigation serving §3.1's R1/R2 — mechanism sketch-grade. Also v2:
**`document-review`'s stale marking** (a passed gate whose artifact
changed underneath it, shown as stale) — it needs a content pin on
`GateApproved`/`GateDeclined` that §7.16 leaves open by name, and a
stopgap pin now would be the first thing its successor deletes.

**v3 — ops and scale:** `bindings`, `configuration`, `workflow`,
`registry`, `milestone`, `triage`, the identity screens, `health`,
`metrics`.

The outbound mirror is a **product feature** rather than a stage of
this surface: once tickets live here, a customer reporting into a
larger org's system gets top-level tickets projected outward. Nothing
in the loop depends on it.

---

## 6. Deliberately absent

Recorded so nobody adds them back as conveniences:

- **A second write path.** Every mutation is a command (§2's rule 1).
- **Editable protocol vocabulary.** Statuses the automation reads and
  agent steps are platform-fixed; a container's own five queue
  positions (`setup`/`prep`/`main`/`retro`/`cleanup`, v5 §7.8) are
  equally fixed, whatever container they belong to — only the
  project's own queue list, and what each anchor entry's `flow:`
  points at (a registered work-item type, `docs/dsl-syntax.md`
  §15.2), is workflow-bundle content, same as a gate or an
  environment, both of which are cited by position rather than a
  fixed predecessor field as of ORC-105's fourth pass (`docs/
  dsl-syntax.md` §15.3) — a distinction this UI never surfaces, since
  it never offers to add a container anchor or reorder one either way
  (§7.18).
- **Parallel review UI.** Review is sequential by decision (§7.19);
  the deferred *parallelize sequential review* toggle is a bindings
  setting when it arrives, not a second board mode.
- **Line-anchored review of prose artifacts.** Superseded by
  per-sentence anchoring; code review stays line-anchored in the PR,
  where it belongs.
- **Marker-prefixed comments as a protocol mechanism.** Retired here
  (§3.1): markers existed because an external tracker had nowhere to
  put typed data. Plane-authored annotations are records with kinds;
  parsing prose for `[pipeline:v1:…]` is not a thing this UI does.
  Markers survive only on surfaces we do not own — GitHub PR
  comments — where the original reason still holds.
- **An orphan comment stream.** Every comment renders against what it
  comments on, or links to it (§3.1).
- **An inbound write path from a mirrored tracker**
  (`docs/non-goals.md`) — nothing in this UI presents external
  tracker state as authoritative.
