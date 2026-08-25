---
paths:
  - storybook/screens/my_queue/component.ex
  - storybook/screens/my_queue/component.story.exs
---

# my-queue

The inbox (`docs/ui-spec.md` §3.1), and the most important screen in this system: the daily
entry point, the thing an author opens first, and the screen the "boring and empty is legible"
bar (J1) is written against.

## Two tabs, because they are two questions

- **Assigned** (default) — tickets assigned to *you*, directly. The delegation view. Assignment
  here is a rendering concern, not a dispatch one: the plane derives and writes tracker assignees
  as a projection of who-has-the-ball (v5 §7.10), and a human reassignment within an author-owned
  state is delegation, respected until the next state entry re-derives it. Reading that projection
  is all this tab does.
- **My roles** — tickets sitting in statuses one of your roles owns, whether or not anyone in
  particular is assigned. The "could I unblock something" view, and the one that works before any
  delegation has happened.

Tabs are a display filter over the same underlying read, not two different queries with
independently-evolving shapes.

## The action-needed set is enumerated, and nothing else is emitted

Three kinds, fixed by protocol (v5 §7.10, §7.6, §7.3), each rendered as a row with the ticket, its
project, and which kind it is:

- **sign off** — a review status whose role you hold. Opens `ticket` (or `document-review` for a
  design-gate) to actually approve or throw back; this screen names the ticket and the kind, it
  does not carry the gate control itself.
- **unblock** — a blocked ticket whose origin status you own. Opens `ticket`, where the return
  control lives (defaulting to origin, earlier-prefix as a picker, never forward — `screens/
  ticket.md`).
- **triage** — machinery-filed work awaiting batch-accept (v5 §7.3). See "Deferred beyond v1"
  below for what this kind does *not* do yet.

There is no *decide* row and no generic "needs attention" bucket. A decision arrives as one of the
three above or as a PR; a fourth action kind with nothing that emits it is a screen looking
comprehensive, which `docs/ui-spec.md` §2's third rule refuses outright.

**This screen issues no commands.** Unlike `board`, whose cards carry pass-forward/pass-back
directly, a queue row is a pointer: ticket, project, kind, and a link to the screen that holds the
actual control. Collapsing that distinction — putting an approve button on a queue row — would
make the row's state (what actions are legal, what the throwback targets are) something this
screen has to track independently of `ticket`, for a screen whose whole job is triage-at-a-glance
across every project the actor touches. `board` earns the direct control because it is already
scoped to one project's cards; `my-queue` is not.

## Cross-project, deliberately

Every row names its project, and the list itself is not scoped to one. This is not an oversight
against the rest of this system's per-project framing (`board`, `event-log`, `explain-why` are
each explicitly single-project screens) — it is what the inbox *is*, stated already in the source
of truth this screen implements rather than decided fresh here: v5 §7.10, on assignment, says it
plainly — "at one human this degenerates correctly: 'My Issues' is exactly the cross-project list
of tickets needing the author — the inbox property, with **no filtering**." A queue that made you
pick a project before it would tell you what needs you defeats the property that names it: the
whole reason `my-queue` outranks `board` as the daily entry point is that it is the one place that
does not ask you to already know where to look.

**A project switcher on this screen would be a second, worse `board`.** If a per-project filter is
ever wanted here, it is a narrowing control over the same cross-project read, not a precondition
for the read to run.

## Empty is a real state

An empty queue is not a loading state or a degenerate case of a populated list — it means the
machine has the ball, on every ticket in both tabs, which is the "boring" outcome this loop is
supposed to produce most days. It links to `explain-why`, for the day it isn't boring and someone
wants to know what the machine is waiting on.

## Deferred beyond v1

Cut against this ticket's own narrow path (file, watch states move, review a diff, decline, see
regeneration) rather than against anything ruled out on the merits — recorded here so a later pass
knows what was deferred and why, not rediscovers it as a gap:

- **Triage stays per-ticket.** The `triage` kind is shown and it links to `ticket`, but there is no
  batch accept/reject/re-rank here or anywhere in v1 — that is the dedicated `triage` screen
  (`docs/ui-spec.md` §3.1), staged v3. Nothing on the exit-criterion path (proving one ticket
  through the loop) needs bulk operations over machinery-filed work; a single accept, done from the
  ticket itself, does.
- **No inline gate action on a row**, per "This screen issues no commands" above — not a v1
  narrowing so much as a standing shape, but recorded here since it is the natural first thing a
  denser v1 would reach for.
- **No cross-tab counts or badges beyond the row list itself** (e.g. a nav-level unread count).
  Real, and deferred as decoration until something reads it the way `docs/ui-spec.md` §2's third
  rule asks: drillable to the rows behind it, which the tab itself already is.
