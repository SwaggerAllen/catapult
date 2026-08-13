---
paths:
  - lib/catapult_web/**
  - assets/**
  - test/catapult_web/**
---

# dashboard

The LiveView debugging and observation surface (v5 §7.4: a debugging
surface, not a working surface — Linear + GitHub are the working
interface). Owns: event-log inspection, replay-to-sequence,
ready_scopes explain-why ("what is blocking this scope" as a
first-class query), staleness provenance, dispatch history, agent-run
transcripts, and the review-queue views that exist for observation
rather than action.

Its screens are designed and delivered through **orchestration's
native screen machinery** — `screens/*.md` docs, stateless function
components, `.story.exs` variations, `screen:` labels — not through
Catapult's product tier (which doesn't apply to Catapult itself,
conventions §13).

## Standing decisions

- **Debugging surface for the work loop, permanently.** When a
  workflow need appears, the question is "which existing surface
  (Linear, PR, docs site) should carry this," and only then "should
  the dashboard." A pipeline this deep will generate constant
  temptation to grow a working UI here; this line exists to be
  pointed at. **Carve-out, explicit so this line isn't cited against
  it:** two more prongs beside debugging belong here — **admin/
  settings** (v5 §7.10's bindings UI — query-and-pick project
  wiring, tracker provisioning, plane-state tunables) and the
  **configuration surface** (registry consumption: policy tunings,
  component options — *graph* state, edited by composed PR: forms
  generated from declarations, save files a change through the
  normal entry machinery, review stays in the PR). Both are ops/
  authoring-composition, not the work loop. The non-goal forbids
  artifact review and ticket action migrating in; it does not
  forbid configuration, and the composer never bypasses a gate.
- **"Why is nothing happening" must be answerable in minutes** — the
  design bar for every view. Explain-why over dashboards-of-numbers.
- **LiveView + daisyUI, stateless presentational components** —
  orchestration's assumed stack, deliberately, so its design agent
  and storybook export machinery work on our own UI.
- Reads projections only; every mutation goes through engine
  commands. The dashboard can never be a second write path.

## Initial vs target

Initial (Phase 4, v0): event log + ready_scopes explain-why —
the debugging minimum for the authoring loop. Target: replay
tooling, transcripts, staleness provenance, health page; identity
consumption for login (Phase 7; minimal auth before that).

## Depends on

engine (projections), delivery (run/dispatch data), substrate.
