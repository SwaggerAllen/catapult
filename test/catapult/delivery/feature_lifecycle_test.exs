defmodule Catapult.Delivery.FeatureLifecycleTest do
  @moduledoc """
  End to end, the same shape `Catapult.Engine.ProjectorTest` already
  proves for the fast path: real commands, dispatched through the real
  router, land in this projection's own read model — not
  `Catapult.Delivery.FeatureLifecycle.Projection` in isolation
  (`projection_test.exs` already covers the pure walk). Loads the real
  `bundles/default-flow` workflow this repo ships with, the same
  reference-deployment assumption `Catapult.Engine.Sweeper` and
  `Catapult.Engine.ProjectorTest` make.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery.FeatureLifecycle
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Router
  alias Ecto.Adapters.SQL.Sandbox

  # `engine_flows.entry_node_id` is a foreign key into `engine_nodes`
  # (`priv/repo/migrations/20260820000002_add_engine_store.exs`), so
  # the entry node has to exist before a flow can name it — the entry
  # commit is scaffolding (`FlowOpened`'s own moduledoc), not itself
  # part of the flow this process manager projects, and lands before
  # any flow is open to attribute it to.
  defp commit(project_id, draft_id) do
    %CommitDraft{
      project_id: project_id,
      node_id: "sysarch",
      tier: "sysarch",
      scope_key: %{},
      draft_id: draft_id,
      body_sha: "sha-" <> draft_id,
      committed_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  # Same reason as projector_test.exs: the process manager is a real,
  # already-started process sharing the caller's `:strong`-consistency
  # write through its own connection checkout.
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  test "opening a flow projects it at :queue" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "capability",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert row.entry_node_id == "sysarch"
    assert FeatureLifecycle.status(row) == {:kind, :queue}
  end

  test "a commit while the flow is open walks it to the first gate" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "capability",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    # Only one pending draft per node (v4 §A.3.3): approve the
    # scaffolding commit before a second one for the same node.
    approve = %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"}
    assert :ok = Router.dispatch(approve, consistency: :strong)

    assert :ok = Router.dispatch(commit(project_id, "d1"), consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:gate, "ux-review"}
  end
end
