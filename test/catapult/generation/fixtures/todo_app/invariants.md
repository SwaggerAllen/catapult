# Waypoint — invariants

- A task belongs to at most one list at any time — moving a task
  between lists is a reassignment, never a copy, so it never appears
  in two lists' views at once.
- A reminder always references exactly one task, and a task has at
  most one reminder — reminders are never shared across tasks and
  never stack.
- A reminder can only be set on a task that has a due date; if a
  task's due date is cleared, any reminder on it is cleared with it
  rather than left pointing at nothing.
- Deleting a task deletes its reminder, if it has one — a reminder
  never outlives the task it was set on.
- A list's deletion never deletes a task; only a task's own deletion
  does.
