---
paths:
  - storybook/screens/board/component.ex
  - storybook/screens/board/component.story.exs
---

# board

Swim lanes for one project (`docs/ui-spec.md` §3.1), the daily surface once `my-queue` has sent
you somewhere: not the entry point, but where "what's actually in flight, and where is it stuck"
gets answered by looking rather than by asking.

## Lanes are the workflow, read left to right

A lane is one position in the ticket type's **effective sequence** — the declared `statuses:`
array for that type, filtered by fan-out depth, order preserved (v5 §7.19;
`Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` is the read this renders). A position is
either a fixed system-status kind (`{:kind, :generation}`) or a declared review gate by name
(`{:gate, "product-review"}`) — the board does not distinguish these in how a lane behaves, only
in its label: a gate lane shows the role it routes to, a system-status lane shows the status name.
There is no separate "workflow view" this duplicates; the lane order *is* the sequence.

**Lanes abbreviate to the ones you have standing in** — lanes your roles own, plus lanes currently
holding your tickets. The full sequence is one control away (a "show all lanes" toggle) and is the
exception: most days, most lanes are not where you have any business looking.

## Fan-out collapses, and collapsed is the default

A feature ticket's children legitimately sit in several lanes at once — the feature might be at
`Architecture review` while one component is already in `Building` and another hasn't started.
Rendering every child as its own card would make the board answer "what are all the tickets"
instead of its actual question, **which top-level tickets are in flight and what state their
components are in.**

So a card is a top-level ticket, and within it, its in-flight children roll up by *their* lane —
a small per-lane count or chip on the parent card, not a nested board. Expanding a card shows its
children as a flat list with their own status, not a second swim-lane view; drilling into any of
them is `ticket`, same as drilling into the parent.

**Grouping is per lane, not per card.** A feature's children are scattered across several lanes at
once (that is the premise above), so "expand this feature" has to mean something different in each
lane it appears in — the `Building` lane's expansion shows only the children currently in
`Building`, not the feature's whole child list repeated in every lane it touches. A lane never
shows a child it does not itself hold.

## Blocked groups under the status that kicked it

Not a lane of its own. `blocked_origin` (v5 §7.19, `FeatureLifecycle.Projection.blocked_origin/1`)
names the position a ticket was standing at when a limit-class failure or a review throwback
parked it, and the board reads that projection rather than a stamped comment — Catapult owns the
log, so `from` is not bookkeeping here the way it is on a mirrored tracker. A blocked card renders
in its origin lane with a flavor badge (`needs-review` / `needs-setup` / failure, v5 §7.6) instead
of the lane's ordinary status chip.

## Cards carry pass-forward and pass-back directly

With lanes abbreviated and fan-out collapsed, the common action has to be reachable without
opening a ticket. A card exposes the same two commands `ticket` dispatches — `ApproveGate` and
`DeclineGate` (`Catapult.Engine.Commands`, `screens/ticket.md`) — under the same optimistic-
concurrency compare as everywhere else in this system (v5 §7.16): the command carries the status
the card believed it was leaving, and a stale card is rejected and told who moved it, in place,
rather than silently failing or applying the wrong transition. `screens/ticket.md` describes the
conflict rendering once; this screen reuses it rather than defining a second version.

**A card's own throw-back inherits `DeclineGate`'s comment requirement, unmodified.** For Phase
4's prose-only gates, throwing back with no comment posted yet is rejected the identical
synchronous way `screens/document-review.md` specs — a card offers the control because the
command is real and the rejection renders in place either way, not because a comment can be left
from the card itself. The ordinary path to a working pass-back is `document-review` first,
then either screen to send it; the card exists for the case where a comment already went in from
an earlier visit and the actor is back on `board` deciding what to do next.

## Filters

`type`, `label` and `assignee` in v1. `docs/ui-spec.md` also names `milestone` and `mutex label`;
both are deferred (see below) rather than cut on the merits.

## Deferred beyond v1

- **`milestone` and `mutex label` filters.** Both are real and both are cut for the same reason:
  neither has a source to filter *against* yet inside this ticket's scope — `milestone` is a v3
  screen and mutex labels are a design-time/CI concept with no rendered projection here today.
  Adding the filter control ahead of something for it to query would be decoration. Add them
  together with whichever lands first.
- **The "show all lanes" toggle's own persistence** (remembering it per user) — a real nicety,
  not needed to prove the loop once through, and cheap to add once there is a place to persist a
  per-user UI preference at all.
- **Nested board-in-card view of a fanned-out feature.** Explicitly not built (see "Fan-out
  collapses" above) — this is the closest thing to `ticket-graph`'s downstream tree that a lane
  view could grow into, and growing it here would be the same sketch-grade mechanism the ticket
  names as out of scope, arrived at from a different screen.
