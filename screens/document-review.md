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

The prior committed body — `Catapult.Delivery.Store.get_previous_draft_body/2`, `nil` on a first
pass — and the current one, sentence-aligned: unchanged, added, and removed sentences marked as
such. One previous body, not a log (`systems/delivery.md`'s ORC-114 entry): a fresh visit always
diffs against the immediately prior pass, never a deeper history. This is a
**reading aid**, not an anchoring mechanism (previous section) — prose diffs badly per line, so
showing the change per sentence is what makes the diff legible at all, independent of whether a
comment raised against a sentence is protocol-anchored to it. A comment is offered against one
sentence in the **current** body — there is no commenting on a removed sentence, since nothing
downstream would ever have prose left to show it beside.

## Approve or throw back

- **Approve** — `Catapult.Engine.Commands.ApproveGate{project_id, flow_id, gate, node_id, body_sha,
  actor_id}` → `GateApproved`. The gate passes; `Catapult.Delivery.FeatureLifecycle` advances the
  ticket's projected status to the next entry past this gate (`systems/delivery.md`'s ORC-34
  entry). Independently, off the same event, `Catapult.Delivery.DraftResolution` dispatches
  `ApproveDraft` against the node this screen is reviewing once this gate is the last review
  position standing between it and the group's own exit (`systems/engine.md`'s ORC-229 entry):
  approving `ux-review` alone advances the ticket only, and approving `engineering-review` after
  it is what marks the node `:approved`, which is what lets a downstream context walk depend on
  it. This screen issues one command and knows nothing of the other two — a second, engine-facing
  consequence of a human's approval is `DraftResolution`'s job, never this screen's own
  (`docs/ui-spec.md` §2 rule 1).
- **Throw back** — `Commands.DeclineGate{project_id, flow_id, gate, throwback_to, since_sequence,
  node_id, body_sha, actor_id}` → `GateDeclined`. `throwback_to` is never a free-text target and
  never carries a reason field, but it is no longer chosen from a per-gate declared list either —
  `docs/dsl-syntax.md` §15.10 retired that bound (ORC-115), and this section's own prior citation
  of `docs/ui-spec.md` §3.2 as "the throwback target chosen from the declared exits" no longer
  matches what that section says (ORC-116 correction). The control is a single primary button
  naming whatever `Catapult.Dsl.Workflow.throwback_default/3` resolves — the gate's own
  `throwback:` when it declares one, otherwise the derived default (§15.10, rendered rather than
  restated here) — with every earlier position in the
  effective sequence offered behind a secondary "choose a different target" disclosure: the
  identical earlier-prefix picker `screens/ticket.md`'s own Blocked-return control draws, over the
  identical legality test, and this screen reuses its "leaves this loop" annotation for an option
  outside the gate's own group rather than restating it. **At least one comment is required, and
  it is `DeclineGate`'s own aggregate state that enforces it, not this screen**: the aggregate
  keeps a project-wide comment counter and a per-gate mark of that counter's value as of the
  gate's last resolution, and rejects the command outright
  when nothing has advanced the counter past `gate`'s own mark since — pure aggregate state, no
  store read (`systems/engine.md`'s ORC-34 entry, fourth design-review correction). This screen
  surfaces that rejection **synchronously, at the point of action** — the identical compare-and-swap
  conflict rendering `screens/ticket.md` specs for a stale transition, reused rather than redefined
  here — and does not perform the check itself (`docs/ui-spec.md` §2 rule 1: no screen is a second
  write path). `since_sequence` is populated by whatever constructs the command (dev's LiveView)
  from `Catapult.Engine.Projections.GateComments.last_resolution_sequence(project_id, gate)`, read
  immediately before dispatch — this screen's own job is only to know the field exists and that a
  stale read of it is safe in the direction that matters (`systems/engine.md`'s own entry has the
  argument); computing it is not a rendering concern.

**`node_id`/`body_sha` are the identical pair `PostComment` already needs, gained by both gate
commands at ORC-114** (`systems/engine.md`): the aggregate rejects a resolution against a body it
has already moved past — regenerated after this screen's own view was rendered — the same
stale-view guard `PostComment` gets below. This screen already holds both values for the one
body it is rendering (see "What this gate is reviewing"), so supplying them on Approve/Throw back
is not a new read, only the same two values sent on a second pair of commands. A race between two
writers resolving the same still-open gate is rejected separately
(`{:engine_gate_already_resolved, gate:, disposition:}`) — the identical compare-and-swap conflict
`screens/ticket.md` specs, reused rather than redefined here.

**Throw back's own engine-facing consequence is unconditional, unlike Approve's.** Off the same
`GateDeclined`, `Catapult.Delivery.DraftResolution` dispatches `DiscardDraft` against the node
under review every time, regardless of which gate declined — a decline always throws the citing
sub-array back to its own leading `pending`, so the draft this gate was reviewing is never still
current afterward (`systems/engine.md`'s ORC-229 entry). This screen's own job is unchanged: it
dispatches `DeclineGate` and nothing else.

A posted comment is its own command, independent of the gate action: `Commands
.PostComment{project_id, node_id, body_sha, locator: nil, author_id, body, posted_at}` →
`CommentPosted`, validated against the node's currently committed `body_sha` — a comment posted
against a view the author hadn't refreshed is rejected the same stale-view way every other command
on this surface is, not silently attached to the wrong version.

**This is the screen `ticket`'s own gate action defers to for a design artifact.** `ticket` shows
that a gate is waiting and which role it routes to; when the position is a design review — every
position Phase 4's own `feature.yaml` declares — its approve/throw-back controls are this screen's,
not a duplicate pair rendered twice.

## Stale marking does not ship in v1

An earlier draft of this screen described deriving staleness — a passed gate whose artifact
changed underneath it — at render time from whether the node's current `body_sha` matches what
the gate's own approval event recorded. That draft was drawn against a shape the protocol does
not have: `GateApproved`/`GateDeclined` carry no content identity, deliberately, and §7.16's "what
a passed gate pins" is left open for Phase 7/ORC-115 by name (`systems/engine.md`'s own entry;
`systems/delivery.md`'s ORC-114 entry flags the mismatch directly and routes it here to resolve).
Adding a stopgap `body_sha` to the gate events now would be the first thing ORC-115 deletes, so
this screen does not build it. What v1 has instead — `Catapult.Delivery.Store
.get_previous_draft_body/2`, one previous body rather than a log — answers "the diff" above, a
narrower question ("what changed since the last pass") than "has what this gate approved
changed," which needs a content pin this ticket does not have. Recorded here rather than
silently dropped, since `docs/ui-spec.md` never named this mechanism and a reader diffing this
screen against an earlier commit would otherwise have to guess whether the gap is an omission.

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
