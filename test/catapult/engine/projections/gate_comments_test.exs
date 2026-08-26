defmodule Catapult.Engine.Projections.GateCommentsTest do
  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Projections.GateComments
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Ecto.Adapters.SQL.Sandbox

  # `:strong` consistency touches the projector's own DB write
  # (`Catapult.Engine.Reducer`), which needs shared sandbox mode —
  # `Catapult.Engine.RouterTest`'s own precedent.
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  defp commit!(project_id, node_id, body_sha) do
    Router.dispatch(
      %CommitDraft{
        project_id: project_id,
        node_id: node_id,
        tier: "comp",
        scope_key: %{},
        draft_id: "d-#{System.unique_integer([:positive])}",
        body_sha: body_sha,
        committed_at: ~U[2026-01-01 00:00:00Z]
      },
      consistency: :strong
    )
  end

  # Only one pending draft per node (v4 §A.3.3): a regeneration
  # commits a fresh body for the same node, but must approve the prior
  # draft first — the same scaffolding step every real dispatch takes.
  defp approve!(project_id, node_id) do
    %{current_draft_id: draft_id} = Store.get_node(project_id, node_id)

    Router.dispatch(
      %ApproveDraft{project_id: project_id, node_id: node_id, draft_id: draft_id},
      consistency: :strong
    )
  end

  defp comment!(project_id, node_id, body_sha) do
    Router.dispatch(
      %PostComment{
        project_id: project_id,
        node_id: node_id,
        body_sha: body_sha,
        author_id: "human-1",
        body: "needs work",
        posted_at: ~U[2026-01-01 01:00:00Z]
      },
      consistency: :strong
    )
  end

  # `Catapult.Delivery.FeatureLifecycle` is `:strong`-subscribed to
  # every engine event including `GateApproved`/`GateDeclined`, and
  # starts a fresh process manager instance for a `flow_id` it hasn't
  # seen before (Commanded's own `{:continue, id}` semantics) — one
  # that never applied a `FlowOpened` would try to persist a row with
  # no `project_id`, which the store's own composite primary key
  # rejects. A real flow is opened here so that persist has a real row
  # to write, exactly as production dispatch would.
  defp open_flow!(project_id, flow_id, entry_node_id) do
    Router.dispatch(
      %OpenFlow{
        project_id: project_id,
        flow_id: flow_id,
        flow_name: "feature",
        entry_node_id: entry_node_id
      },
      consistency: :strong
    )
  end

  test "a project with no resolutions has no last resolution sequence" do
    assert GateComments.last_resolution_sequence("no-such-project", "ux-review") == nil
  end

  test "an approval's own position is returned for its gate" do
    project_id = "gate-comments-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1")

    approve = %ApproveGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      node_id: "n1",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(approve, consistency: :strong)

    assert GateComments.last_resolution_sequence(project_id, "ux-review") != nil
  end

  test "a decline's own position is returned for its gate, and only its gate" do
    project_id = "gate-comments-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1")

    decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: nil,
      node_id: "n1",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(decline, consistency: :strong)

    assert GateComments.last_resolution_sequence(project_id, "ux-review") != nil
    assert GateComments.last_resolution_sequence(project_id, "engineering-review") == nil
  end

  test "a later resolution on the same gate overrides an earlier one" do
    project_id = "gate-comments-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1")

    decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: nil,
      node_id: "n1",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(decline, consistency: :strong)
    first = GateComments.last_resolution_sequence(project_id, "ux-review")

    assert :ok = approve!(project_id, "n1")
    assert :ok = commit!(project_id, "n1", "sha2")
    assert :ok = comment!(project_id, "n1", "sha2")

    approve = %ApproveGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      node_id: "n1",
      body_sha: "sha2"
    }

    assert :ok = Router.dispatch(approve, consistency: :strong)

    second = GateComments.last_resolution_sequence(project_id, "ux-review")
    assert second > first
  end
end
