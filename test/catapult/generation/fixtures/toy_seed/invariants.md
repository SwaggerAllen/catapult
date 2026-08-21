# Signpost — invariants

- A short code, once minted, never gets reassigned to a different
  target while it exists — the whole point of a stable link is that
  it stays stable.
- Two links never mint the same short code while both are live (code
  collision is a correctness bug, not a rare-but-acceptable event).
- A click count only ever increases; retiring a link freezes its
  count rather than resetting it.
