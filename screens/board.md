---
paths:
  - storybook/screens/board/component.ex
  - storybook/screens/board/component.story.exs
---

# board

Swim lanes for one project (`docs/ui-spec.md` §3.1), the daily surface once `my-queue` has sent
you somewhere: not the entry point, but where "what's actually in flight, and where is it stuck"
gets answered by looking rather than by asking.

## #1 Lanes are the workflow, read left to right

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

## #2 Sub-arrays render as a bounded box around their own lanes

A `statuses:` entry that is itself an array groups a contiguous run of lanes (`docs/dsl-syntax.md`
§15.10, ORC-115) — `generation`, its critique, and the gates that review it, in the default bundle's
own `feature.yaml`. `board` renders that grouping visibly rather than flattening it into the run
(ORC-116, closing the open question §15.10 left for this screen): the lanes it spans sit inside a
shared boundary, and one lane inside it carries a small badge marking it as where a throwback in
this group lands by default. Which lane that is is not this screen's to say — it renders whatever
`Catapult.Dsl.Workflow.throwback_default/3` resolves for the group (`docs/dsl-syntax.md` §15.10 has
the derivation), nothing here restates the rule that picks it.

**A group carries no name of its own** (`docs/dsl-syntax.md` §15.10 — "no `name:`, no `id:`"), so
the box itself is not labeled.

**A group is collapsible, and collapsed is the default — reversing this screen's own earlier
stance.** A sub-array's width is bundle-authored and not bounded (`docs/dsl-syntax.md` §15.2's own
revised `feature.yaml` example already carries groups of differing size, and §15.11's worked
`component.yaml` groups run longer still), so the "small, fixed width" argument for always-expanded
does not hold generally, and fan-out's own collapse-by-default answers the identical volume problem
here. **A collapsed group still has to show what the grouping exists to explain**: the box renders
at its full lane-count width even collapsed, carrying the default-landing badge on its own boundary
rather than on one lane inside it, plus a compact strip of the tickets currently sitting anywhere
inside the group (their ids, not their individual lanes) — so *this loop has N tickets in it, and
this is where a throwback lands* both read off the collapsed box without opening it. Expanding
trades that summary for the ordinary per-lane columns.

**Nested groups do not render, because they do not exist.** `docs/dsl-syntax.md` §15.10's own
grammar is flat and nesting is explicitly left undecided rather than built; `board` never receives
a group inside a group from the loader, so there is nothing here to draw a second boundary around.

**A group spanning lanes the abbreviation would otherwise hide degenerates the same way lane
abbreviation itself does today** (below) — no role-holder projection exists yet, so every gate lane
is one you have standing in and a group is never shown partially in Phase 4.

**A group's own lane set, and the group itself, can differ between two tickets of the same type.**
`docs/dsl-syntax.md` §15.11 makes an instance's own effective sequence a fact about its position in
the doc-graph tree, not only about its declared type — a leaf instance never reaches a `reconcile`
its own parent-shaped siblings do, and no instance but the tree's root ever reaches `merge`/`deploy`/
`terminal` at all (`systems/dashboard.md` carries both consequences). A lane or a group a given
card's own resolved sequence excludes is one that card is never shown in, the same "never shows a
card it does not itself hold" rule extended from occupancy to shape; a non-root card's own last
visible lane is whatever position its own sequence ends at, and it leaves the board for `terminal`
directly from there once its parent's `reconcile` merges it, with no `merge`/`deploy` lane of its
own to pass through first.

## #3 Fan-out collapses, and collapsed is the default

So a card is a top-level ticket, and within it, its in-flight children roll up by *their* lane —
a small per-lane count or chip on the parent card, not a nested board. Expanding a card shows its
children as a flat list with their own status, not a second swim-lane view; drilling into any of
them is `ticket`, same as drilling into the parent.

**Grouping is per lane, not per card — and only within one shared lane set.** A feature's children
are scattered across several lanes at once (that is the premise above), so "expand this feature"
has to mean something different in each lane it appears in — the `Implementation` lane's expansion shows
only the children currently in `Implementation`, not the feature's whole child list repeated in every
lane it touches. A lane never shows a child it does not itself hold.

That per-lane roll-up only works when a child reads its position off the same array as its parent.
`docs/dsl-syntax.md` §15.11 gives `component`/`subcomponent` their own declared type, sharing no
array with `feature` — a component's own lane has no counterpart on a feature's own board at all, so
there is no lane to roll it up into. A subcomponent inside a component is the one case that still
shares an array (both instances of `types/component.yaml`, one level deeper), and keeps the
per-lane roll-up above unchanged. A feature's own component children roll up as a single aggregate
count on the card instead — however many are in flight, wherever the feature's own lane happens to
be — since there is no lane of theirs to place a per-lane chip against.

**This is a different axis from sub-array grouping (above), and the two never overlap on screen**
(ORC-116). Fan-out grouping collapses a feature's *children* inside one lane, on the card; sub-array
grouping wraps a run of *lanes themselves*, spanning the lane headers. A card inside a grouped lane
still collapses its own children the ordinary way — the two compose without colliding because one
lives inside a card and the other around several lanes, so nothing on screen is ever ambiguous about
which grouping it belongs to.

## #4 Child roll-up has no data source in Phase 4

Everything above describes the shape the roll-up takes once there is data to roll up — a per-lane
chip, a feature's card-level count across the component-type boundary. There is no data yet:
`Catapult.Engine.Store.Flow` carries no parent-flow reference, and fan-out below a top-level
ticket is a node/tier concept today — `parent_node_id` on `Catapult.Engine.Store.Node` is
doc-graph scope structure an architecture ticket's own generation walks, a chain-axis concept, not
a ticket-delivery one — not a second flow instance. There is no query "these flows are this
ticket's children" to run, so every card's roll-up renders as an honest `children: []` rather than
a nested board or an aggregate count: the current data model, not a choice this screen makes to
hide anything (`systems/dashboard.md` carries the standing decision).

## #5 Blocked groups under the status that kicked it

Not a lane of its own. `blocked_origin` (v5 §7.19, `FeatureLifecycle.Projection.blocked_origin/1`)
names the position a ticket was standing at when a limit-class failure or a review throwback
parked it, and the board reads that projection rather than a stamped comment — Catapult owns the
log, so `from` is not bookkeeping here the way it is on a mirrored tracker. A blocked card renders
in its origin lane with a flavor badge (`needs-review` / `needs-setup` / failure, v5 §7.6) instead
of the lane's ordinary status chip.

## #6 Cards link to where pass-forward and pass-back are issued, rather than issuing them

`docs/ui-spec.md`'s "cards carry pass-forward and pass-back directly" is not what v1 builds, and
this is a correction rather than a narrowing of something that worked.

Every gate Phase 4's own `feature.yaml` declares reviews a prose artifact, so a card's
pass-forward/pass-back is a link into `document-review` (or `ticket`, for the same reason
`screens/ticket.md`'s own gate action defers there) rather than a second, competing control —
the identical move `ticket` already makes and for the identical reason. The card still names that
a gate is waiting and what it is, so the actor does not have to open the ticket to know there is
something to do; it just does not dispatch from where it stands.

## #7 Filters

`type` in v1. `docs/ui-spec.md` also names `label`, `milestone`, `mutex label` and `assignee`; all
four are deferred (see below) rather than cut on the merits.

## #8 Deferred beyond v1

- **`label` filter — cut, and not on the same footing as the other three below.** `label`'s only
  namesake in the DSL is a chain bundle's own `ticket: labels:` (`docs/dsl-syntax.md` §6): authored
  per `flow.yaml` at bundle-authoring time, matched against a queue entry to decide which type it
  opens as. It is never persisted per open flow/ticket instance, and it is not even the same
  vocabulary as the workflow-axis type name a ticket opens under — no load-time binding connects the
  two (`docs/dsl-syntax.md` §15.7). So there is no per-instance label anywhere in this system for a
  filter to query, and unlike the three below, nothing currently on this project's roadmap creates
  one — this is not "add it once the source lands," there is no source in view.
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
- **A collapsed group's own state, per user.** The identical nicety as the "show all lanes" toggle
  above, and cut for the identical reason — not needed to prove the loop once, cheap once a per-user
  preference has anywhere to live at all. Collapsed is the default every session starts from until
  then.
