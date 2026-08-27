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
exception: most days, most lanes are not where you have any business looking. In Phase 4 this
degenerates the same way `my-queue`'s tabs do (`screens/my-queue.md`, `systems/dashboard.md`): no
role-holder projection exists yet, so every gate lane is one you have standing in and the
abbreviated view and the full one coincide until identity ships a real mapping.

## Sub-arrays render as a bounded box around their own lanes

A `statuses:` entry that is itself an array groups a contiguous run of lanes (`docs/dsl-syntax.md`
§15.10, ORC-115) — `generation`, its critique, and the gates that review it, in the default bundle's
own `feature.yaml`. `board` renders that grouping visibly rather than flattening it into the run
(ORC-116, closing the open question §15.10 left for this screen): the lanes it spans sit inside a
shared boundary, and the group's one non-critique agent step (the sub-array's own load-time-checked
anchor, §15.10) carries a small badge marking it as where a throwback in this group lands by
default. This is the whole point of grouping at all — a throwback's destination is only legible as
*this is the loop you fell back into* when the loop is drawn, and a flattened board just shows a
gate followed by an earlier-looking lane with no visual argument for why that lane is the one.

**A group carries no name of its own** (`docs/dsl-syntax.md` §15.10 — "no `name:`, no `id:`"), so
the box itself is not labeled. The one fact worth surfacing is the anchor, and the anchor badge
carries it; inventing a group title would be naming something the grammar deliberately doesn't.

**Groups are always expanded — never collapsed the way fan-out is** (below). A sub-array is
bundle-authored content with a small, fixed width — `feature.yaml`'s own group holds four entries —
so there is no clutter problem collapsing would solve, and collapsing would hide exactly the loop
the grouping exists to explain. Fan-out's collapse-by-default answers a volume problem (many
children, unbounded); this grouping doesn't have one, so it doesn't need the same default.

**Nested groups do not render, because they do not exist.** `docs/dsl-syntax.md` §15.10's own
grammar is flat and nesting is explicitly left undecided rather than built; `board` never receives
a group inside a group from the loader, so there is nothing here to draw a second boundary around.

**A group spanning lanes the abbreviation would otherwise hide degenerates the same way lane
abbreviation itself does today** (below) — no role-holder projection exists yet, so every gate lane
is one you have standing in and a group is never shown partially in Phase 4.

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

**This is a different axis from sub-array grouping (above), and the two never overlap on screen**
(ORC-116). Fan-out grouping collapses a feature's *children* inside one lane, on the card; sub-array
grouping wraps a run of *lanes themselves*, spanning the lane headers. A card inside a grouped lane
still collapses its own children the ordinary way — the two compose without colliding because one
lives inside a card and the other around several lanes, so nothing on screen is ever ambiguous about
which grouping it belongs to.

## Blocked groups under the status that kicked it

Not a lane of its own. `blocked_origin` (v5 §7.19, `FeatureLifecycle.Projection.blocked_origin/1`)
names the position a ticket was standing at when a limit-class failure or a review throwback
parked it, and the board reads that projection rather than a stamped comment — Catapult owns the
log, so `from` is not bookkeeping here the way it is on a mirrored tracker. A blocked card renders
in its origin lane with a flavor badge (`needs-review` / `needs-setup` / failure, v5 §7.6) instead
of the lane's ordinary status chip.

## Cards link to where pass-forward and pass-back are issued, rather than issuing them

`docs/ui-spec.md`'s "cards carry pass-forward and pass-back directly" is not what v1 builds, and
this is a correction rather than a narrowing of something that worked. `ApproveGate`/`DeclineGate`
gained a `body_sha` compare-and-swap at ORC-114 (`systems/engine.md`): the command carries the
body the actor believes they are resolving against, and the aggregate rejects a mismatch. A card
shows a ticket, not a body — there is nothing on it to read a real `body_sha` from. Filling the
field from the projection's current value would make the compare pass unconditionally while the
card *looked* guarded, which is worse than not offering the control: a guard that never rejects is
indistinguishable, from the card, from no guard at all.

Every gate Phase 4's own `feature.yaml` declares reviews a prose artifact, so a card's
pass-forward/pass-back is a link into `document-review` (or `ticket`, for the same reason
`screens/ticket.md`'s own gate action defers there) rather than a second, competing control —
the identical move `ticket` already makes and for the identical reason. The card still names that
a gate is waiting and what it is, so the actor does not have to open the ticket to know there is
something to do; it just does not dispatch from where it stands.

**This was expected to resolve for real at ORC-116, and it does not** — checked here rather than
assumed. `docs/dsl-syntax.md` §15.10 does give a passed gate's approval a structural node to pin
*content identity* against, which answers §7.16's "what a passed gate pins." But that is a staleness
question — "has what this gate approved changed" — answerable from a log join with no body view,
and it is a different mechanism from the command-side `body_sha` compare a dispatch needs, which is
"the body the actor believes they are resolving against" (`systems/engine.md`'s own distinction
between the two; `systems/delivery.md`'s note that the staleness half is what §15.10 actually
closed). A card still shows no body, so it still has nothing honest to supply on `ApproveGate`/
`DeclineGate`'s own compare, whatever the node derivation settles — the interim named above does not
end here. What the derivation *does* unlock is gate staleness display, `docs/ui-spec.md`'s own v2
stage (§5), with the join itself still unbuilt (`systems/delivery.md`'s Phase 7). This is a v1 scope
choice, not a defect, and it is recorded here rather than silently narrowed so a later pass building
non-prose gates does not have to rediscover why the card lost the control `docs/ui-spec.md`
describes for it.

## Filters

`type` and `label` in v1. `docs/ui-spec.md` also names `milestone`, `mutex label` and `assignee`;
all three are deferred (see below) rather than cut on the merits.

## Deferred beyond v1

- **`milestone`, `mutex label` and `assignee` filters.** All three are real and all three are cut
  for the same reason: none has a source to filter *against* yet inside this ticket's scope —
  `milestone` is a v3 screen, mutex labels are a design-time/CI concept with no rendered
  projection here today, and no assignee or role-holder projection exists anywhere in this system
  (`systems/dashboard.md`'s own standing decision — identity is Phase 7). Adding a filter control
  ahead of something for it to query would be decoration. Add each once its source lands.
- **The "show all lanes" toggle's own persistence** (remembering it per user) — a real nicety,
  not needed to prove the loop once through, and cheap to add once there is a place to persist a
  per-user UI preference at all.
- **Nested board-in-card view of a fanned-out feature.** Explicitly not built (see "Fan-out
  collapses" above) — this is the closest thing to `ticket-graph`'s downstream tree that a lane
  view could grow into, and growing it here would be the same sketch-grade mechanism the ticket
  names as out of scope, arrived at from a different screen.
- **A sub-array group cut in half by real lane abbreviation.** Moot today (see "Sub-arrays render
  as a bounded box" above) since abbreviation is a no-op until identity ships a role-holder
  projection. Once it isn't: decide then whether abbreviation cuts a group's member lanes to the
  ones you hold standing in, or a group renders whole the moment any one of its lanes qualifies —
  a real choice with nothing today to test it against.
