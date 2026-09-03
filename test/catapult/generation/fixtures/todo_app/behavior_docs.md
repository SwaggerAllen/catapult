# Waypoint — behavior docs

Observed/expected behavior, the kind an intake pass would distill
into requirements once it exists (Phase 4):

- Checking a task off in the today view removes it from that view
  immediately, without a page reload — it still exists, done, in its
  list's own view.
- Deleting a list moves every task that belonged to it to "no list"
  rather than deleting them; a task never disappears as a side effect
  of deleting something else.
- Setting a reminder on a task with no due date is refused up front —
  a reminder without a date to schedule against has nothing to fire
  against, so the UI does not offer the option until a due date
  exists.
- A reminder that already fired shows as fired on the task's own
  reminder view, not silently cleared — the task's history of "was I
  nudged about this" survives past the nudge itself.
- Renaming a list does not touch any task's own fields; a task's
  display always resolves its list's current name at read time, never
  a copy taken when the task was created.
