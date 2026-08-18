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

## Initial vs target

Staged in `docs/ui-spec.md` §5; summarised here. Initial (Phase 4,
v0) is unmoved by the reversal: event log + ready_scopes explain-why,
the debugging minimum for the authoring loop. **v1 is the working
surface** — `my-queue`, `board`, `ticket`, `document-review` — and it
is **Phase 4's floor rather than a later addition**: there is no
third-party tracker in the loop to lean on while it is missing (v5
§7.17), so until v1 exists the authoring loop has no surface at all.
v2 adds what makes the native surface *better* rather than merely
available
(`ticket-graph`, sentence-granular anchoring, and the comment
navigation serving ui-spec's R1/R2 — mechanism sketch-grade). v3 is
ops and scale: bindings, configuration, workflow, registry,
milestone, triage, health, metrics, and identity consumption for
login (Phase 7; minimal auth before that).

## Depends on

engine (projections), delivery (run/dispatch data), substrate.
