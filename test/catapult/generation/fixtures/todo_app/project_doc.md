# Waypoint — project doc

Waypoint is a small personal to-do application: tasks, grouped into
named lists, with optional reminders. Three jobs, three components:

- **`tasks`** — the individual to-do item: a title, an optional note,
  a done/not-done state, an optional due date. Belongs to at most one
  list.
- **`lists`** — a named grouping of tasks (e.g. "Groceries", "Q3
  planning"). A list is created, renamed, and deleted; deleting a list
  does not delete its tasks — they fall back to no list rather than
  disappearing.
- **`reminders`** — a scheduled nudge tied to a task's due date, and a
  distinct subsystem from `tasks` on purpose: a task can exist with no
  reminder, a reminder always references exactly one task, and
  reminder delivery (deciding *when* to nudge, and marking a nudge
  sent) is its own scheduling concern rather than a field on the task
  record.

This spec names exactly these three components, deliberately: the
architecture chain this raft feeds is expected to mint a subcomponent
per name, and no more, so a reviewer checks the fan-out against this
list rather than a headcount.

## Why this exists

A to-do list is the smallest thing that is still a real product:
multiple entities, a real relationship between them (list has many
tasks; task has at most one reminder), and a UI with more than one
screen (today's tasks, a list's tasks, and setting a reminder are
three different views, not three tabs on the same one).

## Shape

- **Today view** is the hot path: every task due today or overdue,
  across every list, sorted soonest-first. Checking a task off from
  here is the single most common action in the app.
- **List view** is a slower, more deliberate path: pick a list, see
  every task in it (done and not-done, done ones collapsed by
  default), add a task, rename or delete the list itself.
- **Reminder view** is reached from a task, not standalone: set or
  clear a reminder on the task's due date, see whether a reminder
  already fired.

## Toy scope

This is a seed for Phase 5's exit-run — a small, self-contained
application written for the purpose (`docs/build-plan.md`'s Phase 5
section), not a spec for a real product. It is read in one sitting,
and it exists to give the architecture chain something small enough
to review end to end but real enough that reviewing it is not a
formality: three components, a real relationship between two of them,
and a UI that needs more than one screen to make sense.
