# Waypoint — capability inventories

What the toy project can already lean on, if it existed for real
(nothing here is provisioned by this fixture — it is the kind of
inventory an intake pass would read):

- A single-user session already exists upstream (some auth layer this
  seed does not design) — every list and task read or write in this
  spec is implicitly scoped to "the current person," and nothing here
  needs to re-derive who that is.
- A clock service already exists for "is this task's due date today,
  or overdue" and for deciding when a reminder is due to fire — this
  seed treats time-telling as solved upstream, the same way
  `non_goals.md` treats sharing as a different product.
