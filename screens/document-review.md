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

## The sentence locator is unset in v1

`Catapult.Engine.Commands.PostComment` carries a `locator` field, and it is nullable — final,
merged ORC-34 (`systems/engine.md`) settles it as **always null in Phase 4**: "v1 (Phase 4's own)
has no diff producing one yet," and per-sentence anchoring is `docs/ui-spec.md` §5's own v2 stage,
not this ticket's. An earlier draft of this screen (drawn against ORC-34's own pre-review draft)
committed to computing a real `{body_sha, sentence_index}` locator here and sending it on every
comment; that draft was thrown back before merging; this screen does not build the thing it was
thrown back for. **This screen posts every `PostComment` with `locator: nil`.** The sentence a
comment was raised against is kept only as this render's own local grouping — which sentence a
comment sits beside on screen — and is never sent to the aggregate and never round-trips: reload
this screen and every comment on a node renders together, undifferentiated by sentence, which is
exactly what `Catapult.Engine.Projections.CommentFeedback.since_last_resolution/2` already folds
(per-node, not per-span — "v5 §7.4's per-span bucket key degenerates to per-node today," in
`systems/engine.md`'s own words). Per-sentence anchoring activates later **without a protocol
change**: the field already exists on the command, unpopulated; a future pass teaches this screen
to compute and send a real one, and nothing downstream has to change to read it.

## The diff, per sentence

The prior committed body (the last `body_sha` this node held, or none on a first pass) and the
current one, sentence-aligned: unchanged, added, and removed sentences marked as such. This is a
**reading aid**, not an anchoring mechanism (previous section) — prose diffs badly per line, so
showing the change per sentence is what makes the diff legible at all, independent of whether a
comment raised against a sentence is protocol-anchored to it. A comment is offered against one
sentence in the **current** body — there is no commenting on a removed sentence, since nothing
downstream would ever have prose left to show it beside.

## Approve or throw back

- **Approve** — `Catapult.Engine.Commands.ApproveGate{project_id, flow_id, gate, actor_id}` →
  `GateApproved`. The gate passes; `Catapult.Delivery.FeatureLifecycle` advances the ticket's
  projected status to the next entry past this gate (`systems/delivery.md`'s ORC-34 entry).
- **Throw back** — `Commands.DeclineGate{project_id, flow_id, gate, throwback_to, since_sequence,
  actor_id}` → `GateDeclined`, `throwback_to` chosen from the gate's own declared exits (never a
  free-text target, and never a reason field — `docs/ui-spec.md` §3.2's own action set is
  "approve / throw back... with the throwback target chosen from the declared exits"). **At least
  one comment is required, and it is `DeclineGate`'s own aggregate state that enforces it, not
  this screen**: the aggregate keeps a project-wide comment counter and a per-gate mark of that
  counter's value as of the gate's last resolution, and rejects the command outright when nothing
  has advanced the counter past `gate`'s own mark since — pure aggregate state, no store read
  (`systems/engine.md`'s ORC-34 entry, fourth design-review correction). This screen surfaces that
  rejection **synchronously, at the point of action** — the identical compare-and-swap conflict
  rendering `screens/ticket.md` specs for a stale transition, reused rather than redefined here —
  and does not perform the check itself (`docs/ui-spec.md` §2 rule 1: no screen is a second write
  path). `since_sequence` is populated by whatever constructs the command (dev's LiveView) from
  `Catapult.Engine.Projections.GateComments.last_resolution_sequence(project_id, gate)`, read
  immediately before dispatch — this screen's own job is only to know the field exists and that a
  stale read of it is safe in the direction that matters (`systems/engine.md`'s own entry has the
  argument); computing it is not a rendering concern.

A posted comment is its own command, independent of the gate action: `Commands
.PostComment{project_id, node_id, body_sha, locator: nil, author_id, body, posted_at}` →
`CommentPosted`, validated against the node's currently committed `body_sha` — a comment posted
against a view the author hadn't refreshed is rejected the same stale-view way every other command
on this surface is, not silently attached to the wrong version.

**This is the screen `ticket`'s own gate action defers to for a design artifact.** `ticket` shows
that a gate is waiting and who holds it; when the position is a design review — every position
Phase 4's own `feature.yaml` declares — its approve/throw-back controls are this screen's, not a
duplicate pair rendered twice.

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
