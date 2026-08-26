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
  alias Catapult.Delivery.FeatureLifecycle.Projection
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Commands.ResumeFlow
  alias Catapult.Engine.Router
  alias Commanded.Serialization.JsonSerializer
  alias Commanded.Serialization.ModuleNameTypeProvider
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

  test "opening a flow projects it at :pending" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert row.entry_node_id == "sysarch"
    assert FeatureLifecycle.status(row) == {:kind, :pending}
  end

  test "a commit while the flow is open walks it to the first gate" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
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

  test "GateApproved passes the gate and the ticket rests at the next entry" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)
    approve = %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"}
    assert :ok = Router.dispatch(approve, consistency: :strong)
    assert :ok = Router.dispatch(commit(project_id, "d1"), consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:gate, "ux-review"}

    approve_gate = %ApproveGate{
      project_id: project_id,
      flow_id: flow_id,
      gate: "ux-review",
      node_id: "sysarch",
      body_sha: "sha-d1",
      actor_id: "human-1"
    }

    assert :ok = Router.dispatch(approve_gate, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:gate, "engineering-review"}
  end

  test "GateDeclined moves the ticket straight to its throwback target" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)
    approve = %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"}
    assert :ok = Router.dispatch(approve, consistency: :strong)
    assert :ok = Router.dispatch(commit(project_id, "d1"), consistency: :strong)

    approve_gate = %ApproveGate{
      project_id: project_id,
      flow_id: flow_id,
      gate: "ux-review",
      node_id: "sysarch",
      body_sha: "sha-d1",
      actor_id: "human-1"
    }

    assert :ok = Router.dispatch(approve_gate, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:gate, "engineering-review"}

    # A decline requires at least one comment since this gate's last
    # resolution (`Catapult.Engine.AggregateTest` covers the rejection
    # in isolation) — post one against the node's current committed
    # body before declining.
    comment = %PostComment{
      project_id: project_id,
      node_id: "sysarch",
      body_sha: "sha-d1",
      author_id: "human-1",
      body: "needs another pass",
      posted_at: ~U[2026-01-02 00:00:00Z]
    }

    assert :ok = Router.dispatch(comment, consistency: :strong)

    decline_gate = %DeclineGate{
      project_id: project_id,
      flow_id: flow_id,
      gate: "engineering-review",
      throwback_to: "ux-review",
      since_sequence: nil,
      node_id: "sysarch",
      body_sha: "sha-d1",
      actor_id: "human-1"
    }

    assert :ok = Router.dispatch(decline_gate, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:gate, "ux-review"}
  end

  test "RunFailed blocks the ticket, and ResumeFlow resumes it at the chosen position" do
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:kind, :pending}

    failed = %RecordRunFailure{
      project_id: project_id,
      node_id: "sysarch",
      tier: "sysarch",
      scope_key: %{},
      run_id: "run-1",
      reason: "usage_limit",
      occurred_at: ~U[2026-01-02 00:00:00Z]
    }

    assert :ok = Router.dispatch(failed, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:kind, :blocked}
    assert row.blocked_origin_kind == "pending"

    resume = %ResumeFlow{
      project_id: project_id,
      flow_id: flow_id,
      to: {:kind, :generation},
      actor_id: "human-1"
    }

    assert :ok = Router.dispatch(resume, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert FeatureLifecycle.status(row) == {:kind, :generation}
    assert row.blocked_origin_kind == nil
  end

  test "a flow_name matching no declared type is projected without a position" do
    # §15.7's "residual failure, named rather than left to be
    # discovered later": no load-time check binds a chain flow's label
    # to a workflow type, so an unmatched one is a defined outcome —
    # the work item is open and real, and the workflow axis has no
    # sequence to place it in.
    project_id = "feature-lifecycle-#{System.unique_integer([:positive])}"
    flow_id = "flow-unmatched"

    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "no-such-declared-type",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    assert row.entry_node_id == "sysarch"
    assert FeatureLifecycle.status(row) == nil
  end

  describe "JSON round trip (ORC-120)" do
    # `Commanded.ProcessManagers.ProcessManagerInstance` calls
    # `persist_state/2` after every handled event, which serializes
    # this exact struct through `Commanded.Serialization
    # .JsonSerializer` — the identical round trip a real (non-
    # `InMemory`) event store takes on every `RunFailed`/`GateDeclined`.
    # `config/test.exs`'s adapter never exercises this path, which is
    # this ticket's own diagnosis for why the suite never caught the
    # crash; this test takes the real serializer rather than trusting
    # that diagnosis by inspection alone.
    test "a process manager instance with a populated projection round-trips through Commanded's own serializer" do
      pm = %FeatureLifecycle{
        project_id: "proj-1",
        flow_id: "flow-1",
        entry_node_id: "sysarch",
        flow_name: "feature",
        projection: %Projection{
          commit_signature: 3,
          passed: %{{:gate, "review"} => 3},
          blocked_from: nil,
          pinned_to: {:kind, :generation}
        }
      }

      type = ModuleNameTypeProvider.to_string(pm)

      assert pm
             |> JsonSerializer.serialize()
             |> JsonSerializer.deserialize(type: type) == pm
    end
  end
end
