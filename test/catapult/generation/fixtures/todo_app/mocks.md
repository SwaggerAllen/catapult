# Waypoint — mocks

No design system or visual asset library exists for this seed — these
are textual wireframes, pinned as seed evidence in the sense v5 §4.1
and §5.4 mean by mocks: read and designed against, never absorbed.
Three screens, one per journey `project_doc.md` names.

## Today view

```
┌─────────────────────────────────────────┐
│ Waypoint                       [+ list]  │
├───────────────┬───────────────────────────┤
│ Today          │ Groceries (3)             │
│ Groceries      │ Q3 planning (1)           │
│ Q3 planning    │ (no list) (1)              │
├───────────────┴───────────────────────────┤
│ ☐ Buy milk                    due: today   │
│ ☑ Renew library card          due: today   │
│ ☐ Draft roadmap doc           due: overdue │
│ ☐ Call dentist                due: today   │
└─────────────────────────────────────────┘
```

Left rail: every list, plus a fixed "Today" entry above them that
this screen renders. Checking a box toggles done in place — the row
stays visible, struck through, until the view is left and re-entered.
An overdue task's due-date label reads differently (`overdue` instead
of a date) so it stands out without a separate section.

## List view

```
┌─────────────────────────────────────────┐
│ ← Today       Groceries        [rename] [delete] │
├─────────────────────────────────────────┤
│ ☐ Buy milk                due: today   [⏰]│
│ ☐ Buy eggs                 no due date     │
│ ☑ Return bottles                           │
│                                             │
│ [+ add task]                               │
└─────────────────────────────────────────┘
```

Done tasks (here: "Return bottles") collapse to the bottom of the
list, struck through, no due-date label. The bell icon on a task with
a due date opens the reminder view for that task; a task with no due
date shows no bell at all — the affordance to set a reminder does not
exist until there is a date to schedule it against
(`behavior_docs.md`).

## Reminder view

```
┌─────────────────────────────────────────┐
│ ← Buy milk                                 │
├─────────────────────────────────────────┤
│ Due: today                                 │
│                                             │
│ Reminder: [ not set ]           [set]      │
│                                             │
│ (once set:)                                │
│ Reminder: today, 9:00am          [clear]   │
│ Fired: not yet                             │
└─────────────────────────────────────────┘
```

Reached only from a task (never a standalone nav entry, per
`project_doc.md`'s own shape). Two states matter: unset (one action,
"set," which schedules against the task's own due date) and set
(shows whether it already fired, per `behavior_docs.md`'s "a reminder
that already fired shows as fired, not silently cleared").
