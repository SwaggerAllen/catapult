# board — reasons

The reason behind each rule in `screens/board.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons board#n` before changing the rule it belongs to.

## #2

This is the whole point of grouping at all — a throwback's destination is only legible as *this is
the loop you fell back into* when the loop is drawn, and a flattened board just shows a gate
followed by an earlier-looking lane with no visual argument for why that lane is the one.

The one fact worth surfacing is the default-landing badge, and it carries it; inventing a group
title would be naming something the grammar deliberately doesn't.

## #3

A feature ticket's children legitimately sit in several lanes at once — the feature might be at
`Architecture review` while one component is already in `Implementation` and another hasn't started.
Rendering every child as its own card would make the board answer "what are all the tickets" instead
of its actual question, **which top-level tickets are in flight and what state their components are
in.**

## #4

The same missing fact costs more than the children list. "A group's own lane set, and the group
itself, can differ between two tickets of the same type" (above) relies on knowing whether a *given
instance* has children — a leaf never reaches `reconcile`, so a lane keyed only on type and depth
cannot exclude it there. That is the identical relationship this section says is absent, so today a
leaf card can sit in a `reconcile` lane it never reaches; the per-card exclusion rule reads as a
design intent this data model cannot yet enforce, not as working behavior with a gap next to it
(`systems/dashboard.md`'s ORC-129 entry has the detail).

Not gating: the source is `docs/build-plan.md`'s Phase 7 two-grain machinery — spawn and child
lifecycle, minting a child as its own addressable flow correlated to the parent that spawned it —
and nothing ahead of Phase 7 depends on it landing first.

## #6

`ApproveGate`/`DeclineGate` gained a `body_sha` compare-and-swap at ORC-114 (`systems/engine.md`):
the command carries the body the actor believes they are resolving against, and the aggregate
rejects a mismatch. A card shows a ticket, not a body — there is nothing on it to read a real
`body_sha` from. Filling the field from the projection's current value would make the compare pass
unconditionally while the card *looked* guarded, which is worse than not offering the control: a
guard that never rejects is indistinguishable, from the card, from no guard at all.

**This was expected to resolve for real at ORC-116, and it does not** — checked here rather than
assumed. `workflow.md` #6 does give a passed gate's approval a structural node to pin
*content identity* against, which answers §7.16's "what a passed gate pins." But that is a staleness
question — "has what this gate approved changed" — answerable from a log join with no body view, and
it is a different mechanism from the command-side `body_sha` compare a dispatch needs, which is "the
body the actor believes they are resolving against" (`systems/engine.md`'s own distinction between
the two; `systems/delivery.md`'s note that the staleness half is what §15.10 actually closed). A
card still shows no body, so it still has nothing honest to supply on `ApproveGate`/ `DeclineGate`'s
own compare, whatever the node derivation settles — the interim named above does not end here. What
the derivation *does* unlock is gate staleness display, `docs/ui-spec.md`'s own v2 stage (§5), with
the join itself still unbuilt (`systems/delivery.md`'s Phase 7). This is a v1 scope choice, not a
defect, and it is recorded here rather than silently narrowed so a later pass building non-prose
gates does not have to rediscover why the card lost the control `docs/ui-spec.md` describes for it.
