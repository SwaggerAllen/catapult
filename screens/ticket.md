---
paths:
  - storybook/screens/ticket/component.ex
  - storybook/screens/ticket/component.story.exs
---

# ticket

One ticket: the argument, where it sits in its effective sequence, and the one or two controls
that move it from there (`docs/ui-spec.md` §3.1).

## #1 The argument, first

The human-readable case for the work (v5 §7.2) opens the screen, above the mechanics.

Rendered off `Catapult.Delivery.Store.tickets_for_project/1`'s own `argument` field (ORC-114) —
`fields["argument"]` off the node at the flow's `entry_node_id`, the reserved field name `chain.md` #32 gives
exactly this screen. Blank until a type's entry tier declares it,
the same unset-is-empty behavior `prior_review` already has; a blank argument is rendered as
such, not hidden.

## #2 Position in the effective sequence

Rendered as the same ordered list `board`'s lanes come from (`Catapult.Delivery.FeatureLifecycle
.Sequence.positions/2`, v5 §7.19): every position up to this ticket's type's reachable boundary,
each marked passed, current, or upcoming. A gate position additionally shows the role it routes to.
This is the same data `board` renders as columns; here it renders as a single ticket's row through
them, which is what makes "how far along is this, and what's next" answerable without cross-
referencing the board.

**Where the sequence declares a sub-array (`workflow.md` #6), the rail
groups the
identical way `board`'s lanes do** (ORC-116, `screens/board.md`): the positions it spans sit inside
a shared boundary, and one entry inside it carries the same anchor badge `board` gives its own
groups — whatever `Catapult.Dsl.Workflow.throwback_default/3` resolves for the group (`workflow.md` #34 has the
derivation), rendered rather than restated here. A ticket
standing at a position inside a group reads as *inside this loop*, not at an anonymous point in a
flat row.

**A ticket whose own tree position is not the root never shows a `merge`/`deploy`/`terminal` entry
of its own on this rail** (ORC-116, `workflow.md` #28, `systems/dashboard.md`). Its own
effective sequence stops at its own last reachable position; the rail simply ends there, and the
ticket closes as `terminal` the moment its parent's `reconcile` merges it — v5 §7.6's `Merged →
Done` — with no intermediate rail entry standing in for that. What a non-root ticket's own `deploy` means, if anything, is still
open, not this screen's to answer by
inventing a rail entry for it.

**Depth is shown, not explained.** A ticket's fan-out depth (v5 §7.19 — 0 top level, 1 components,
2 subcomponents) determines which positions in the type's declared sequence apply to it; the
screen shows the resolved sequence for this ticket's own depth, not the full declared array with
inapplicable entries grayed out. The distinction between "declared but not at this depth" and
"declared and upcoming" is not this screen's to draw — depth already resolved it upstream.

## #3 The gate action

Shown to every viewer in Phase 4, not filtered by role — no role-holder projection exists yet
(identity is Phase 7, `Catapult.Engine.Commands.ApproveGate`'s own moduledoc defers authorization
there), and Phase 4 has exactly one author, so the correct rendering is the degenerate case rather
than a modeled interim owner (`systems/dashboard.md`). Dispatching one of two real commands
(`Catapult.Engine.Commands`, `systems/engine.md`'s ORC-34 entry, given a compare-and-swap at
ORC-114):

- **Approve** — `ApproveGate{project_id, flow_id, gate, node_id, body_sha, actor_id}` →
  `GateApproved`, advancing to the next position.
- **Throw back** — `DeclineGate{project_id, flow_id, gate, throwback_to, since_sequence, node_id,
  body_sha, actor_id}` → `GateDeclined`, `throwback_to` one of the gate's declared exits (v5
  §7.16's "a gate declares... its exits, forward and throwback"), validated at the command edge
  against the loaded workflow bundle before dispatch — never by the aggregate, which checks only
  its own pure state (`Catapult.Engine.Aggregate`'s own moduledoc; `systems/engine.md`'s ORC-34
  entry records this as a deliberate dev-pass correction of an earlier design-review suggestion
  that the aggregate re-check membership, on the same division `Catapult.Delivery
  .ContainerLifecycle`'s own commands already draw) — the same way `document-review`'s own
  throwback picker only ever offers a gate's declared exits.

`node_id` and `body_sha` are `PostComment`'s own pair (ORC-114): the aggregate rejects a
resolution whose view is a body it has already moved past, the identical stale-view guard
`PostComment` already had. This screen never issues either command itself (see below), so
supplying that pair is `document-review`'s obligation, not this screen's.

**Every gate Phase 4's own `feature.yaml` declares reviews a prose artifact, so in v1 this screen's
own gate action is never the one issuing the command.** `screens/document-review.md` holds the
actual approve/throw-back controls and the comment-count check `DeclineGate` enforces for a decline;
this screen shows that a gate is waiting and which role it routes to (a bundle- declared string,
`Catapult.Dsl.Gate.role`, not an actor — no viewer filtering yet, above), and links there rather
than rendering a second, competing pair.

Both are commands under a real optimistic-concurrency compare, landed at ORC-114
(`systems/engine.md`): a second writer racing the first on one still-open resolution is rejected
with `{:engine_gate_already_resolved, gate:, disposition:}`, and a resolution against a body the
aggregate has already moved past is rejected separately with `{:engine_stale_gate_resolution,
node_id:, current:, got:}`. **A rejected transition is rendered as a conflict at the point of
action, not an after-the-fact revert.** What the rejection names synchronously is the value the
actor's command conflicted with — the disposition already recorded, or the body that moved
underneath the view — not an actor identity: neither error carries who made the winning write, the
same "name the value, not the actor" level of detail `AdvanceContainerQueue`'s own conflict already
gives. Attributing the conflict to *who* is a follow-up read of the project's event stream for the
gate's most recent `GateApproved`/`GateDeclined` (both carry `actor_id`) — the identical "read the
log for a display fact" pattern `Catapult.Engine.Projections.GateComments`/`CommentFeedback` already
establish, not a new mechanism, and not required for the conflict to render correctly.

## #4 Blocked

- the flavor label (`needs-review` / `needs-setup` / failure — v5 §7.6)
- the origin status, read from the projection rather than a stamped comment (v5 §7.19 — "the
  projection is read rather than stamped onto a comment," now that this UI owns the surface) —
  `Catapult.Delivery.Store.tickets_for_project/1`'s own `blocked_origin_kind`/`blocked_origin_gate`
  columns name it directly, the same `Sequence.position()` shape as everywhere else on this screen
- the return control: **defaults to the origin status**, with every earlier position in the
  effective sequence offered as a picker behind it. **Never forward** — skipping a required
  position is a workflow-bundle change, which is a PR, not a click here (v5 §7.19).

**An earlier option that sits outside the origin's own sub-array is marked as leaving it**
(ORC-116): the origin default here and a gate's own derived default (its citing sub-array's generation position,
`workflow.md` #34) are both a visible fall-back to the head of a box the screen already
draws, but the picker's remaining options reach earlier than that box too — the earlier-prefix
legality test (§15.10) never stops at a group boundary. An option inside the current group renders
plainly; one outside it carries a small "leaves this loop" note, so choosing it reads as an arrow
leaving the box rather than a silent landing somewhere else. `screens/document-review.md`'s own
throwback picker draws the identical distinction over the identical test, and cites this section
rather than restating it.

**The return control is a real write, `ResumeFlow{project_id, flow_id, to, actor_id}` →
`FlowResumed`** (ORC-114, closing the gap this screen's own earlier draft assumed away —
`Catapult.Delivery.FeatureLifecycle.Projection`'s own moduledoc had stated plainly that a block
"clears only via a subsequent `DraftCommitted` retry — never a human action," with no command to
dispatch). `to` is validated at the command edge against the effective-sequence prefix up to and
including `blocked_origin` — never forward, the identical rule stated above — before dispatch, the
same bundle/projection-content split `gate`/`throwback_to` above already draw. A stale resume
(someone else already resumed it, or a retry already landed) is rejected the same synchronous way
as the gate action, reusing that conflict rendering rather than a third version of it.

## #5 Child roll-up

A flat list of this ticket's children with their own current position — not a nested board, not
the fan-out tree (`ticket-graph`'s job, and explicitly out of this ticket's scope). Each child
opens as its own `ticket`.

**There is no data source for this list in Phase 4.** `Catapult.Engine.Store.Flow` carries no
parent-flow reference — fan-out below a top-level ticket is a node/tier concept today
(`parent_node_id` on `Catapult.Engine.Store.Node` is doc-graph scope structure, not a
ticket-delivery relationship), not a second flow instance — so this screen renders an honest empty
list rather than a hidden or narrowed one (`systems/dashboard.md`'s standing decision;
`screens/board.md`'s identical gap on its own roll-up).

## #6 Linked PRs and runs

The PRs and agent runs this ticket's own work produced, as a plain list — a name, a status, and a
link out to GitHub or `run-transcript`. `Catapult.Delivery.Store.get_feature_publication/2` gives
the one PR a flow's branch carries; `dispatch_runs_for_flow/2` (ORC-114) gives every dispatch run
correlated to the flow, oldest first — both real reads as of this pass, closing the gap this
screen's own earlier draft had (`systems/delivery.md`'s ORC-114 entry). Not a graph, not a
timeline; the ordering question ("what happened when, relative to what") is `run-transcript` and
`event-log`'s to answer, not this screen's to re-derive.

## #7 Deferred beyond v1

- **The swim-lane comment navigator, and R1/R2 entirely.** Named explicitly out of this ticket's
  scope (`docs/ui-spec.md` §3.1 marks the mechanism sketch-grade and stages it v2). This screen
  carries **no comment stream of any kind** in v1 — not a flat one, not the lane-spine one. Review
  commentary lives in the PR for code and in `document-review`'s own per-sentence comments for
  prose, both already reachable without this screen's help; nothing on the exit-criterion path
  (file, watch states move, review a diff, decline, see regeneration) requires reading historical
  comments from `ticket` itself. Building a flat placeholder stream now would be the exact
  premature commitment the ticket text warns against — a v1 shape the v2 mechanism would then have
  to migrate away from rather than fill in.
- **`ticket-graph`'s downstream/upstream/staleness views.** Out of scope by name. The child
  roll-up above is deliberately flatter than any of them.
