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
   protocol-defined action.** Explain-why over dashboards-of-numbers
   (`systems/dashboard.md`). A screen that exists to look
   comprehensive is refused.

---

## 3. Screen inventory

### 3.1 Work surface

**`my-queue`** — the inbox, and the most important screen here.
Cross-project list of tickets where *this human holds the ball*,
derived from status ownership rather than from assignment (§7.11:
assignment renders who-has-the-ball, the plane never reads it).

- tickets in author-owned statuses this user's roles can act on
- blocked tickets whose origin status this user owns
- grouping by action needed: *sign off*, *unblock*, *triage*, *decide*
- empty state is a real state and says so — an empty queue means the
  machine has the ball, and the screen links to `explain-why`

**`board`** — swim lanes for one project, the daily surface.

- lanes are the effective sequence for the selected ticket type
  (§7.19), so the board *is* the workflow, read left to right
- one assignee, one status per ticket (§7.19's sequential decision,
  which is what makes lanes legible)
- **blocked tickets group under the status that kicked them**, not
  in a lane of their own — origin comes from the log, no comment
  stamping (§7.6, §7.19)
- fan-out depth as a visible axis: top level, components,
  subcomponents
- filters: type, label, milestone, mutex label, assignee

**`ticket`** — one ticket, the detail and action surface.

- the *argument* (the human-readable case for the work, §7.2)
- position in the effective sequence, with what has passed and what
  remains, and the depth this ticket sits at
- the gate action, when this user's role holds it: **approve**
  (transition forward) or **throw back** (to a declared target)
- **blocked**: flavor label, origin status, and the return control —
  defaulting to the origin, with the earlier-prefix as a picker
  (§7.19); never forward
- **comments with marker-filtered tabs** — the pipeline's own marker
  comments (`[pipeline:v1:…]`) separated from human discussion rather
  than interleaved. This is the concrete want that started the
  tracker reversal, and it is nearly free once comments are events
- child roll-up, blocking relations, linked PRs and runs
- optimistic-concurrency feedback: a rejected transition names who
  moved it and where (§7.16), rendered as a conflict at the point of
  action rather than a revert comment afterwards

**`ticket-graph`** — the fan-out under one top-level ticket.

- the ticket tree as the projection of the doc DAG's fan-out it
  actually is (§7.2): feature → component children → subcomponent
  grandchildren
- status and depth per node; blocking edges drawn
- one of the two reasons the native surface is *better* rather than
  merely available (§7.17) — a general tracker cannot easily draw it
- read-only; every action opens the ticket

**`milestone`** — commitment and boundary progress.

- what is committed, what is in flight, what is `Stubbed` and why —
  the "live, visible list of what is deliberately half-built" §7.11
  already requires
- the boundary's blockers and their state

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
- approve / throw back, with the throwback target chosen from the
  declared exits
- shows what this gate is reviewing, derived from position (§7.18) —
  whatever the chain produced at the step this gate follows
- **stale marking**: a passed gate whose artifact changed underneath
  is shown as stale here, derived rather than stored (§7.11, §7.19)

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

**`health`** — the machine-shaped alert set mirrored (§7.4): signal
silence, dispatch-budget warn/cutoff, bindings-credential expiry,
deploy-detection anomalies, restore/cutover lifecycle states.

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
per-sentence comments → approve, or throw back to a declared target.
On throwback, everything downstream reopens (§7.19), and staleness
derivation makes the re-pass free where nothing that gate saw
changed.

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

**v1 — the working surface**, and the gate on real product work:
`my-queue`, `board`, `ticket`, `document-review`. Delivery to Linear
stands until these exist (§7.17): the reversal is a direction, and
this row is the scope that makes it real.

**v2 — the reasons the native surface is better:** `ticket-graph`,
per-sentence anchoring in `document-review`, marker-filtered comment
tabs.

**v3 — ops and scale:** `bindings`, `configuration`, `workflow`,
`registry`, `milestone`, `triage`, the identity screens, `health`.

The outbound mirror add-on (§7.17) attaches at v1: once tickets live
here, mirroring top-level tickets outward is a projection leaving the
building.

---

## 6. Deliberately absent

Recorded so nobody adds them back as conveniences:

- **A second write path.** Every mutation is a command (§2's rule 1).
- **Editable protocol vocabulary.** Statuses the automation reads,
  queues and agent steps are platform-fixed; the UI renders them and
  never offers to add one (§7.18).
- **Parallel review UI.** Review is sequential by decision (§7.19);
  the deferred *parallelize sequential review* toggle is a bindings
  setting when it arrives, not a second board mode.
- **Line-anchored review of prose artifacts.** Superseded by
  per-sentence anchoring; code review stays line-anchored in the PR,
  where it belongs.
- **Dashboards of numbers.** Explain-why instead
  (`systems/dashboard.md`).
- **An inbound write path from a mirrored tracker**
  (`docs/non-goals.md`) — nothing in this UI presents external
  tracker state as authoritative.
