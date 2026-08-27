defmodule Catapult.Engine.Projections.CommentFeedbackTest do
  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Projections.CommentFeedback
  alias Catapult.Engine.Projections.GateComments
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Ecto.Adapters.SQL.Sandbox

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
        # Distinct per node_id: `engine_nodes` uniques on `(project_id,
        # tier, scope_key)`, and every node here shares one tier.
        scope_key: %{"id" => node_id},
        draft_id: "d-#{System.unique_integer([:positive])}",
        body_sha: body_sha,
        committed_at: ~U[2026-01-01 00:00:00Z]
      },
      consistency: :strong
    )
  end

  # Only one pending draft per node: a regeneration
  # commits a fresh body for the same node, but must approve the prior
  # draft first — the same scaffolding step every real dispatch takes.
  defp approve!(project_id, node_id) do
    %{current_draft_id: draft_id} = Store.get_node(project_id, node_id)

    Router.dispatch(
      %ApproveDraft{project_id: project_id, node_id: node_id, draft_id: draft_id},
      consistency: :strong
    )
  end

  defp comment!(project_id, node_id, body_sha, body) do
    Router.dispatch(
      %PostComment{
        project_id: project_id,
        node_id: node_id,
        body_sha: body_sha,
        author_id: "human-1",
        body: body,
        posted_at: ~U[2026-01-01 01:00:00Z]
      },
      consistency: :strong
    )
  end

  # `Catapult.Delivery.FeatureLifecycle` is `:strong`-subscribed to
  # `GateApproved`/`GateDeclined` too and starts a fresh instance for
  # an unseen `flow_id` (Commanded's `{:continue, id}` semantics) — one
  # that never applied `FlowOpened` would persist a row with no
  # `project_id`, which the store's composite primary key rejects. A
  # real flow is opened so every gate dispatch below has a real
  # process-manager row behind it, matching production dispatch.
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

  test "a project with no events has no feedback" do
    assert CommentFeedback.since_last_resolution("no-such-project", "n1") == []
  end

  test "no resolution has happened yet: feedback is empty even with comments posted" do
    project_id = "comment-feedback-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = comment!(project_id, "n1", "sha1", "a comment before any gate has run")

    assert CommentFeedback.since_last_resolution(project_id, "n1") == []
  end

  test "a decline renders every comment posted since its own since_sequence" do
    project_id = "comment-feedback-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1", "the comment that justifies the decline")

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

    assert [%{body: "the comment that justifies the decline", locator: nil}] =
             CommentFeedback.since_last_resolution(project_id, "n1")
  end

  test "an approval renders feedback empty, regardless of comments before it" do
    project_id = "comment-feedback-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1", "read before the approval")

    approve = %ApproveGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      node_id: "n1",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(approve, consistency: :strong)

    assert CommentFeedback.since_last_resolution(project_id, "n1") == []
  end

  test "a comment on a different node doesn't bleed into this one's feedback" do
    project_id = "comment-feedback-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = commit!(project_id, "n2", "sha2")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1", "about n1")
    assert :ok = comment!(project_id, "n2", "sha2", "about n2")

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

    assert [%{body: "about n1"}] = CommentFeedback.since_last_resolution(project_id, "n1")
    assert [%{body: "about n2"}] = CommentFeedback.since_last_resolution(project_id, "n2")
  end

  test "a comment answered by an earlier decline doesn't re-render on a later one" do
    project_id = "comment-feedback-#{System.unique_integer([:positive])}"
    assert :ok = commit!(project_id, "n1", "sha1")
    assert :ok = open_flow!(project_id, "f1", "n1")
    assert :ok = comment!(project_id, "n1", "sha1", "first round")

    first_decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: nil,
      node_id: "n1",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(first_decline, consistency: :strong)

    assert :ok = approve!(project_id, "n1")
    assert :ok = commit!(project_id, "n1", "sha2")
    assert :ok = comment!(project_id, "n1", "sha2", "second round")

    # The real command-construction boundary: `since_sequence` is read
    # from `GateComments.last_resolution_sequence/2` before dispatch,
    # never re-derived by the aggregate (`systems/engine.md`'s fourth
    # design-review correction) — this is what proves "first round" is
    # excluded because it predates the *first* decline, not because it
    # happens to be missing for some other reason.
    since_sequence = GateComments.last_resolution_sequence(project_id, "ux-review")

    second_decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: since_sequence,
      node_id: "n1",
      body_sha: "sha2"
    }

    assert :ok = Router.dispatch(second_decline, consistency: :strong)

    assert [%{body: "second round"}] = CommentFeedback.since_last_resolution(project_id, "n1")
  end
end
