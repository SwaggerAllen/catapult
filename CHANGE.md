# ORC-269 — A provisioned test project opens no scaffold ticket, so its drafts have no gate to be reviewed or declined at: open one when provisioning intakes the raft

## Decision (`systems/delivery.md` #ORC-269-1)

`Catapult.Delivery.Provisioning.provision/1` dispatches one `OpenFlow` through
`Catapult.Engine.Router` (`consistency: :strong`, as `Provisioning` already does
elsewhere) after `reset_and_intake/2` succeeds and **before**
`Store.activate_test_project/1`:

- `flow_name: "scaffold"`, `container_id: nil`, `queue: nil`, `ticket_ref: nil`,
  `actor_id` the module's existing `@actor_id`-style literal or nil.
- `flow_id: "scaffold-" <> project_id` — derived (re-open is the aggregate's
  rejection) and **colon-free**: `FeaturePublishWorker` builds
  `feature/<slug>-<flow_id>` from it.
- `entry_node_id: flow_id` — names no node; same convention as
  `ContainerLifecycle.open_inline/3`. The follow-on ticket (gates over node sets)
  replaces readers of it.
- An open failure takes the existing failure branch (`release_test_project/1`,
  502), never leaving an `:active` project without its ticket. Put the id
  derivation beside the other derived ids (e.g. `ContainerLifecycle.Ids` or a
  private function in `Provisioning`).
- Applies to every test project regardless of `stub_mode`.

## Tests

- `provisioning_test.exs`: after `provision/1`, exactly one open flow for the
  project (`Engine.Store`), `flow_name == "scaffold"`, `FeatureLifecycle`
  projection at the type's first position; a failing open releases the project.
- Boundary-suite provisioning tests must still pass unchanged. If a test counts
  `DraftCommitted`-driven Oban jobs or Fake-host branches, it will now see the
  `FeaturePublishWorker` branch/PR; adjust only such counts, and say why.
- Check `DocumentReviewLive` / `Store.tickets_for_project/1` / `DraftResolution`
  tolerate an `entry_node_id` naming no node (they read `get_node` → nil).

## Records amended in this pass

`delivery#11`, `#22`, `#105` and their `.reasons.md` entries;
`docs/build-plan.md` Phase 5 passage. Dev: grep for remaining "no flow on a test
project" wording in `lib/` comments (e.g. `Provisioning` moduledoc).

## Out of scope

Multi-node gates, position-aware advancement, gating dispatch on position, `entry:`
onboarding, `setup` tickets.
