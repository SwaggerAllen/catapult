---
paths:
  - storybook/screens/ticket/component.ex
  - storybook/screens/ticket/component.story.exs
---

# ticket

One ticket: the argument, where it sits in its effective sequence, and the one or two controls
that move it from there (`docs/ui-spec.md` §3.1).

## The argument, first

The human-readable case for the work (v5 §7.2) opens the screen, above the mechanics. Everything
below is "what state is this in and what can I do about it" — the argument is "why does this
ticket exist," and a reviewer deciding a gate needs the second question answered in the context of
the first, not instead of it.

## Position in the effective sequence

Rendered as the same ordered list `board`'s lanes come from (`Catapult.Delivery.FeatureLifecycle
.Sequence.positions/2`, v5 §7.19): every position up to this ticket's type's reachable boundary,
each marked passed, current, or upcoming. A gate position additionally shows the role it routes to.
This is the same data `board` renders as columns; here it renders as a single ticket's row through
them, which is what makes "how far along is this, and what's next" answerable without cross-
referencing the board.

**Depth is shown, not explained.** A ticket's fan-out depth (v5 §7.19 — 0 top level, 1 components,
2 subcomponents) determines which positions in the type's declared sequence apply to it; the
screen shows the resolved sequence for this ticket's own depth, not the full declared array with
inapplicable entries grayed out. The distinction between "declared but not at this depth" and
"declared and upcoming" is not this screen's to draw — depth already resolved it upstream.

## The gate action

Shown only when the viewer's role holds the gate at the ticket's current position:

- **Approve** — advance to the next position.
- **Throw back** — to one of the gate's declared exits (v5 §7.16's "a gate declares... its exits,
  forward and throwback").

Both are commands under the same optimistic-concurrency compare as `board`'s cards (v5 §7.16):
the command carries the status the actor believed the ticket was at. **A rejected transition is
rendered as a conflict at the point of action, not an after-the-fact revert** — it names who moved
the ticket and to what, in place, so the actor's next move is informed rather than a guess. This is
the concrete case `docs/ui-spec.md`'s R-less prose gestures at when it says owning the surface is
what makes synchronous rejection possible at all: Linear cannot do this (v5 §7.16), and it is
worth a test asserting the conflict renders rather than the stale action silently applying or
silently failing.

## Blocked

- the flavor label (`needs-review` / `needs-setup` / failure — v5 §7.6)
- the origin status, read from the projection rather than a stamped comment (v5 §7.19 — "the
  projection is read rather than stamped onto a comment," now that this UI owns the surface)
- the return control: **defaults to the origin status**, with every earlier position in the
  effective sequence offered as a picker behind it. **Never forward** — skipping a required
  position is a workflow-bundle change, which is a PR, not a click here (v5 §7.19).

## Child roll-up

A flat list of this ticket's children with their own current position — not a nested board, not
the fan-out tree (`ticket-graph`'s job, and explicitly out of this ticket's scope). Each child
opens as its own `ticket`.

## Linked PRs and runs

The PRs and agent runs this ticket's own work produced, as a plain list — a name, a status, and a
link out to GitHub or `run-transcript`. Not a graph, not a timeline; the ordering question ("what
happened when, relative to what") is `run-transcript` and `event-log`'s to answer, not this
screen's to re-derive.

## Deferred beyond v1

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
