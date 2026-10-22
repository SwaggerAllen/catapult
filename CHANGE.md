# ORC-269 — A provisioned test project opens no scaffold ticket, so its drafts have no gate to be reviewed or declined at: open one when provisioning intakes the raft

## Decision (`systems/delivery.md` #ORC-269-1)

`Catapult.Delivery.Provisioning.provision/1` dispatches one `OpenFlow` through
`Catapult.Engine.Router` (`consistency: :strong`, as `Provisioning` already does
elsewhere) after `reset_and_intake/2` succeeds and **before**
`Store.activate_test_project/1`:

- `flow_name: "scaffold"`, `container_id: nil`, `queue: nil`, `ticket_ref: nil`,
  `actor_id: @actor_id` (`"live-suite"`, the literal `approve_drafts/2` uses).
- `flow_id: "scaffold-" <> project_id` — derived (re-open is the aggregate's
  rejection) and **colon-free**: `FeaturePublishWorker` builds
  `feature/<slug>-<flow_id>` from it.
- `entry_node_id: nil` (`engine#ORC-269-2`) — a flow id is not a node, and
  `engine_flows.entry_node_id` is a NOT NULL FK to `engine_nodes`, so the projection
  would raise. The follow-on ticket (gates over node sets) replaces readers of it.

## Engine change (`system:engine`, `engine#ORC-269-2`)

- New migration under `priv/repo/migrations/`: drop NOT NULL on
  `engine_flows.entry_node_id`; keep the composite FK (null skips it).
- Relax `@enforce_keys` on `OpenFlow` and `FlowOpened` (no version bump; the field
  is still present). `Engine.Reducer`/`Store.insert_flow/1` pass nil through.
- `ContainerLifecycle.open_inline/3` opens with `entry_node_id: nil` too; add a test
  that projects (`consistency: :strong`) an inline open and the scaffold open, since
  the existing tests only inspected commands.
- Audit readers of `Flow.entry_node_id` for nil (`DraftResolution`, `DocumentReviewLive`,
  `FeatureLifecycle` state, `Store.tickets_for_project/1`, the ticket argument read).
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

## Cleanup of the publication (review finding 1, `#ORC-269-1`)

Every provisioned project leaves branch `feature/<slug>-scaffold-<project_id>` and an
open PR in `catapult-test`. Cleanup is at **reclaim**: in `provision/1`'s loop over
`Store.list_released_test_projects()`, *before* `Store.delete_test_project/1`, read
`Store.get_feature_publication(project_id, "scaffold-" <> project_id)` and, if present,
call two new `HostPort` callbacks (add to the behaviour, `Actions`, and `Fake`):

- `close_pr(project_id, pr_number)` — `PATCH …/pulls/{n}` `%{state: "closed"}`.
- `delete_branch(project_id, branch)` — `DELETE …/git/refs/heads/{branch}`.

2xx, 404 and 422 are success (already closed / already gone); any other error keeps
the row for the next reclaim and never fails the current `provision/1`. `release/2`
is unchanged. No new token scope (Pull requests and Contents already held); dev
amends `SETUP.md` §2's bullets to name both endpoints (not design-owned). Tests: Fake
publication closed and branch removed on reclaim; already-gone is success; a failing
delete keeps the row.

The `": scaffold artifact set"` PR title is left alone.
