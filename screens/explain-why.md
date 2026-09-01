---
paths:
  - storybook/screens/explain_why/component.ex
  - storybook/screens/explain_why/component.story.exs
---

# explain-why

"What is blocking this scope," as a first-class query (`docs/ui-spec.md` §3.3's flagship) — the
answer to "why is nothing happening," in minutes, for one node. Consumes
`Catapult.Engine.Projections.ReadyScopes.explain/2` verbatim: the same candidate/walk fold
`ready/3` uses to decide yes/no, replayed here as a structured report instead of a boolean. This
screen renders that report. **It does not recompute readiness** — the whole reason `explain/2` was
pulled forward into Phase 3 beside the readiness logic itself was so that nothing downstream ever
has a second opinion about what "blocked" means.

## What it reads

One node: a project, a tier, a scope key (ORC-87 — the route carries the project; there is no
cross-project view here either). `explain/2` returns three facts, and the screen has a place for
each:

- **`passes_scope_filter`** — `false` means the node was never a candidate for generation at all;
  it is excluded before context is even considered. This renders as its own top-level state, not
  as "zero blockers" — a node excluded by its tier's `scope_filter` is not "ready," and saying so
  by omission would be exactly the false "nothing is blocking this" the whole screen exists to
  avoid.
- **`blocking`** — every context-walk entry that is not yet satisfied: the walk's own raw form
  (`self.parent.dependency -> comp.handle.fragments[pubapi]`, read verbatim off the tier
  declaration — never re-rendered into different words), and for each, the targets it currently
  resolves to with their status (`absent | drafted | approved`). A walk with several targets can
  be partially satisfied; the screen shows every target's status rather than collapsing to
  pass/fail, because "two of three approved" is a materially different answer from "zero of
  three" for the operator deciding what to chase next.
- **an empty `blocking` list with `passes_scope_filter: true`** — every context walk this tier
  declares is satisfied. Rendered as "nothing in scope is blocking this" — deliberately not
  "ready," see the review-tier caveat below, and not a claim that generation has actually fired
  (the scheduler's own dispatch is a later screen, out of this ticket's scope).

## `:unsupported` is not an ordinary blocker

One source of walk — `ticket.<source>` — resolves `{:error, :unsupported}` rather than to real
targets (`Catapult.Engine.Projections.ContextResolver`'s Initial scope; it belongs to v5 §7.11's
validation loop, Phase 7). `explain/2` folds that into a blocking entry carrying
`reason: :unsupported` and no targets.

**No tier in `bundles/default` can put this row on screen today.** A `ticket.<source>` walk loads
only if its source is a registered context source (`Catapult.Dsl.Chain`'s
`Registry.context_source?/2` check), and no extension registers one yet — `chain.ex` rejects the
walk at load rather than letting it reach `explain/2` unsupported. The section stays because
Phase 7 is what registers the first one, and the visual treatment below is what that walk will
need the moment it does; the storybook variation demonstrating it is illustrative for that reason,
not a state reachable from this repo's own bundle content.

**Rendering that row the same way as an ordinary blocker is a lie by omission**, and the ticket
that asked for this screen named the failure mode directly: it tells the operator to go approve
something that does not exist. So an `:unsupported` entry gets its own visual treatment — no
target list (there is none), no "waiting on approval" language, a label that says plainly that
this walk is not wired up yet and that the tier's designer, not an approver, is who unblocks it.
It still counts toward "this node has blockers" at the top of the screen; it must not be mistaken
for one an operator can act on today.

**`input.<role>` and `input.*` walks are not this case, and never were the same case for the
reason they looked like it** (ORC-107, `systems/engine.md`'s entry). They used to share
`ContextResolver`'s blanket `:unsupported` answer with `ticket.<source>` by coincidence — intake
storage simply didn't exist yet — not because a role is structurally the same kind of gap a
validation-loop source is. Now that intake exists, `input.<role>`/`input.*` resolve `{:ok, []}`,
always: `walk_report/2` folds that to `satisfied: true, targets: []`, the identical shape a fully
satisfied ordinary walk has, so `Enum.reject(& &1.satisfied)` drops it out of `blocking` entirely.
An input-role walk therefore never appears on this screen at all, satisfied or not — which is the
correct rendering of "a role with no documents never blocks readiness" (`dsl-syntax.md` §7):
nothing here has an "input roles aren't ready yet" row to accidentally show, because the row
never existed to begin with.

## The review-tier caveat

A review tier has no `context:` of its own (`ReadyScopes`'s own moduledoc) — its readiness is "the
reviewed tier's current draft has no review yet," a different and simpler rule `ready_review/3`
answers, not `explain/2`. Calling `explain/2` on a review-tier node is legal and returns a report —
`passes_scope_filter: true`, `blocking: []`, always, because there is no context to walk — and
that report is **not** "this review tier is ready." This screen says so wherever it renders a
review-tier node: an explicit caveat line rather than silence, because silence here reads as the
same "nothing is blocking this" the ordinary empty state means, and for a review tier that would
be a claim this screen has no way to back up. Whether an unreviewed draft is waiting is a fact
this view does not have; a future pass may extend `explain/2`'s report or build a sibling query for
it, but this ticket renders what exists.

## Navigation out

**The one link this screen offers is to `event-log`, project- and node-scoped.** J3 in
`docs/ui-spec.md` is `explain-why` → `dispatch` → `run-transcript`; both of the latter are out of
this ticket's scope (`systems/dashboard.md`'s Initial-vs-target), so the only next step this
screen can honestly offer today is "see what has happened to this node so far" — which is
`event-log`'s node filter, described there. No link is drawn to a screen that does not exist yet.

## Non-goals

- No readiness recomputation in the view layer, ever — see above. A screen that walked the graph
  a second way to double-check `explain/2` would be the exact drift `ReadyScopes`'s own moduledoc
  built this function to prevent.
- No approve/throw-back affordance here. This is `docs/ui-spec.md`'s `ticket`/`document-review`
  surface (v1, out of scope) — explain-why only ever explains.
