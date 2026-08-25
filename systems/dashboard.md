---
paths:
  - lib/catapult_web/**
  - assets/**
  - test/catapult_web/**
---

# dashboard

The LiveView UI. **Screens, functionality and journeys:
`docs/ui-spec.md`** — that document is the inventory; this one is the
system and its file map.

~~A debugging surface, not a working surface.~~ **Reversed** (v5
§7.17, §7.4): owning the tracker makes this the working surface as
well. It owns the work loop (`my-queue`, `board`, `ticket`,
`ticket-graph`), design-gate review at sentence granularity, and —
unchanged and still the hard part — event-log inspection,
replay-to-sequence, ready_scopes explain-why ("what is blocking this
scope" as a first-class query), staleness provenance, dispatch
history, agent-run transcripts.

**The name is now wrong** and is kept only to avoid churn mid-design;
renaming the system is a mechanical pass whenever it is worth doing.

Its screens are designed and delivered through **orchestration's
native screen machinery** — `screens/*.md` docs, stateless function
components, `.story.exs` variations, `screen:` labels — not through
Catapult's product tier (which doesn't apply to Catapult itself,
conventions §13).

## Standing decisions

- ~~**Debugging surface for the work loop, permanently.**~~
  **Reversed** (v5 §7.17). The temptation this line guarded against
  is real and did not go away with it, so it has a successor with
  teeth, in `docs/ui-spec.md` §2: reads are projections and writes
  are commands; **no screen introduces protocol vocabulary**; and
  every screen answers a named question or performs a
  protocol-defined action. The second is the one that will get cited
  — the temptation is never "build a tracker", it is "add one field
  here", and a field here is vocabulary.
- **The two non-work-loop prongs were always in-bounds and are
  unchanged:** **admin/settings** (v5 §7.10's bindings UI —
  query-and-pick project wiring, tracker provisioning, plane-state
  tunables) and the **configuration surface** (registry consumption:
  policy tunings, component options — *graph* state, edited by
  composed PR: forms generated from declarations, save files a change
  through the normal entry machinery, review stays in the PR). The
  composer never bypasses a gate.
- **"Why is nothing happening" must be answerable in minutes** — the
  design bar for every view, and explain-why is what answers it, not
  a number. **But numbers are in-bounds where they are the answer**
  (`docs/ui-spec.md` §2, §3.3): instance health is a numeric
  determination, and throughput and cycle time are how the platform's
  value is demonstrated rather than asserted. The earlier phrasing —
  "explain-why over dashboards-of-numbers" — overshot; the target was
  decoration, not measurement. The test that replaces it: a number
  you cannot drill through to the tickets behind it is decoration.
- **LiveView + daisyUI, stateless presentational components** —
  orchestration's assumed stack, deliberately, so its design agent
  and storybook export machinery work on our own UI.
- Reads projections only; every mutation goes through engine
  commands. The dashboard can never be a second write path.
- **`my-queue` is the one screen in this system with no project
  scope, and that is the decision, not an inconsistency** (ORC-75
  design pass). `board`, `event-log` and `explain-why` are each
  explicitly single-project; the inbox is not, because v5 §7.10 says
  so directly, about this exact screen, before this pass ever ran:
  "at one human this degenerates correctly: 'My Issues' is exactly
  the **cross-project** list of tickets needing the author — the
  inbox property, with no filtering." A project switcher gating
  `my-queue` would trade away the property that makes it the daily
  entry point rather than a second `board`. `screens/my-queue.md`
  carries the argument in full.
- **The gate action `ticket` and `document-review` render is ahead of
  what Phase 4 can execute** (ORC-75 design pass, recorded so dev
  doesn't rediscover it mid-implementation). "What advancing past a
  gate on a human's word dispatches to" is v5 §7.16's own still-open
  item ("Approval is a status... the mechanism is a later increment,
  and a sizeable one"), left open again by `systems/delivery.md`'s
  ORC-32 entry and, downstream of that, by `Catapult.Delivery
  .FeatureLifecycle.Projection`'s `pass/2`, which is dormant by
  construction today — nothing in this phase's event vocabulary calls
  it, so every resting walk stops at the first declared gate. **Throw
  back is real**: ORC-34 harvests a decline today; no gate-approval
  command stands behind an approve. Both screens' "Approve" control is
  designed now, on the reasonable bet that the command lands inside
  this phase's own work rather than waiting on Phase 7 proper — but
  until it does, dev's pass wires it against whatever exists, which
  may be a disabled control naming the gap rather than a working one,
  and that is this phase's decision to make, not a defect in either
  screen's design.
- **No boundary carve-out exists yet for the screen-machinery tree,
  and every `storybook/screens/**/component.ex` fails `mix compile
  --warnings-as-errors` until one lands** (ORC-75 design pass, verified
  by actually compiling this ticket's four components against
  `main`'s current `lib/catapult.ex`, which is a real gate run rather
  than an assumption). `lib/catapult.ex`'s own moduledoc names the
  shape — "One coarse boundary today; per-system boundaries... carve
  out of it as those systems land" — and a component built on
  `Phoenix.Component`/`Phoenix.LiveView`'s HEEx engine is exactly that
  case: neither app is in the root boundary's `deps:` list, so every
  `~H` template anywhere under `storybook/screens/` currently trips
  "forbidden reference," dozens of times per file, for every module the
  HEEx compiler expands to (`Phoenix.Component`,
  `Phoenix.Component.Declarative`, `Phoenix.LiveView.Engine`,
  `Phoenix.LiveView.HTMLEngine`, `Phoenix.LiveView.Rendered`,
  `Phoenix.LiveView.Comprehension`, `Phoenix.LiveView.LiveStream` were
  the ones this pass's own four components triggered — a real
  `Phoenix.LiveComponent` or `phoenix_storybook` macro reference would
  add more). This is **not** specific to this ticket's screens: any
  ticket's `storybook/screens/**/component.ex` hits the identical wall,
  design-owned code that cannot itself carry the fix — `lib/catapult.ex`
  is outside every design pass's committable paths (DESIGN §5). A
  `Catapult.Storybook` (or equivalently-named) boundary, declared with
  the modules above (and `deps: []`, since nothing calls back into the
  plane from a stateless shell) as its own `deps:`, unblocks every
  screen at once rather than one ticket's dev pass carving out only
  what its own components happened to reference. `.story.exs` files are
  unaffected today — they are not part of `mix compile`'s own pass,
  only `component.ex` is — but the same carve-out is where a story
  file's own compile-time needs would land if `phoenix_storybook`'s own
  macros ever trip the same check.

## Initial vs target

Staged in `docs/ui-spec.md` §5; summarised here. Initial (Phase 4,
v0) is unmoved by the reversal: event log + ready_scopes explain-why,
the debugging minimum for the authoring loop. **v1 is the working
surface** — `my-queue`, `board`, `ticket`, `document-review`
(`screens/my-queue.md`, `screens/board.md`, `screens/ticket.md`,
`screens/document-review.md`) — and it is **Phase 4's floor rather
than a later addition**: there is no third-party tracker in the loop
to lean on while it is missing (v5 §7.17), so until v1 exists the
authoring loop has no surface at all. v2 adds what makes the native
surface *better* rather than merely available (`ticket-graph`,
sentence-granular anchoring, and the comment navigation serving
ui-spec's R1/R2 — mechanism sketch-grade). v3 is ops and scale:
bindings, configuration, workflow, registry, milestone, triage,
health, metrics, and identity consumption for login (Phase 7; minimal
auth before that).

## Depends on

engine (projections), delivery (run/dispatch data), substrate.
