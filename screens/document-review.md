---
paths:
  - storybook/screens/document_review/component.ex
  - storybook/screens/document_review/component.story.exs
---

# document-review

The design-gate action, at sentence granularity (`docs/ui-spec.md` §3.2): prose artifacts diff
badly per line, and the review comments that matter anchor to a claim rather than to a line.

## What this gate is reviewing

Whatever the chain produced at the step this gate follows, derived from position rather than
looked up separately (v5 §7.18) — the same node the ticket's sequence rail names as "current."
One artifact, one committed body at one `body_sha`; this screen never shows more than one tier's
worth of prose at a time.

## The sentence locator

`ee8dbd1` (ORC-34's harvesting design) left this screen holding the pen: `CommentPosted`'s
`body_sha` pins the exact reviewed version, but the *span within it* a comment anchors to is
"opaque to this system... `docs/ui-spec.md`'s to define." Settled here, since it is this screen's
diff that produces it and nothing downstream needs to parse it — only carry it and hand it back:

**A locator is `{body_sha, sentence_index}`** — `sentence_index` a zero-based ordinal into the
artifact's sentences as a deterministic splitter orders them, scoped to the exact `body_sha` it
was computed against. It is never recomputed against a later body: a locator is only ever read
back for rendering *that* `body_sha`'s own diff (this pass or `document-review`'s eventual
history), where the ordinal it was assigned under still applies by construction. Nothing outside
this screen re-derives an ordinal from a sentence's text — sentence identity here is positional,
not content-addressed, which is what keeps two identical sentences in one body distinguishable.

## The diff, per sentence

The prior committed body (the last `body_sha` this node held, or none on a first pass) and the
current one, sentence-aligned: unchanged, added, and removed sentences marked as such. A comment
attaches to one sentence in the **current** body — there is no commenting on a removed sentence,
since nothing downstream would ever read a locator pointing at prose that no longer exists.

## Approve or throw back

- **Approve** — the gate passes.
- **Throw back** — to one of the gate's declared exits, and it is here, not on `ticket`, that a
  throwback becomes a decline in ORC-34's sense: **at least one comment is required.** A throwback
  naming zero comments and no free-text reason is rejected at the point of action — a decline the
  harvester would find empty is refused before it becomes an event, never dispatched with blank
  feedback and never given a state of its own (`systems/delivery.md`'s ORC-34 entry).

**This is the screen `ticket`'s own gate action defers to for a design artifact.** `ticket` shows
that a gate is waiting and who holds it; when the position is a design review, its approve/throw-
back controls are this screen's, not a duplicate pair rendered twice.

## Stale marking

A passed gate whose artifact changed underneath — regenerated after approval, by a throwback
further downstream reopening it — is marked stale here, derived at render time from whether the
node's current `body_sha` matches what the gate's own approval event recorded, never a stored
flag (v5 §7.16, §7.19, §7.11's derived-staleness doctrine). A stale gate is shown, not hidden;
re-passing it costs nothing when nothing it saw actually changed, which is the entire point of
deriving rather than storing.

## Deferred beyond v1

- **Comment history across prior passes.** This screen shows the *current* pass's diff and lets
  you comment on it; it does not (yet) let you open a previous pass's diff and its comments side by
  side — that is the swim-lane navigator's job (`screens/ticket.md`'s "Deferred beyond v1"), out
  of this ticket's scope by the same name. A fresh `document-review` visit always starts from the
  latest committed body.
- **Rendering a `CommentPosted` back onto a stale, non-current sentence position.** Not needed for
  the golden path (review, decline, see regeneration happen inside one pass) and it is exactly the
  navigator's "every comment renders in the context of what it comments on" governing rule, which
  this ticket does not build a home for yet.
