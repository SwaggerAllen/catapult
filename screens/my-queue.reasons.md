# my-queue — reasons

The reason behind each rule in `screens/my-queue.md`, keyed by the rule's id (orchestration's DESIGN §4). Read one with `pipeline reasons my-queue#n` before changing the rule it belongs to.

## #1

The two tabs still exist as separate protocol questions — they will genuinely diverge the moment
identity ships a real assignee and role-holder mapping — but building an interim owner or a fake
filter now would be something for identity to replace rather than something it extends. The tab
structure is the decision; the filtering is not this ticket's to fake.

## #2

This is a data-model absence, not a control withheld on this ticket's own narrow path — it clears
the moment a machinery-filed type is declared, with no change needed here.

A decision arrives as one of the three above or as a PR; a fourth action kind with nothing that
emits it is a screen looking comprehensive, which `docs/ui-spec.md` §2's third rule refuses
outright.

Collapsing that distinction — putting an approve button on a queue row — would make the row's state
(what actions are legal, what the throwback targets are, what body a decline would be resolving
against) something this screen has to track independently of the screen that actually renders it,
for a screen whose whole job is triage-at-a-glance across every project the actor touches. Nothing
in this system dispatches a gate command from a screen that isn't showing the body it resolves
against; `my-queue` was never going to be the exception.

## #3

This is not an oversight against the rest of this system's per-project framing (`board`,
`event-log`, `explain-why` are each explicitly single-project screens) — it is what the inbox *is*,
stated already in the source of truth this screen implements rather than decided fresh here: v5
§7.10, on assignment, says it plainly — "at one human this degenerates correctly: 'My Issues' is
exactly the cross-project list of tickets needing the author — the inbox property, with **no
filtering**." A queue that made you pick a project before it would tell you what needs you defeats
the property that names it: the whole reason `my-queue` outranks `board` as the daily entry point
is that it is the one place that does not ask you to already know where to look.

`systems/ dashboard.md`'s own bullet carries this narrowing now, so this argument and that one stay
in agreement rather than needing reconciling against each other by a future reader.
