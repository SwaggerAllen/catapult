defmodule Catapult.Engine.AggregateTest do
  use ExUnit.Case, async: true

  alias Catapult.Engine.Aggregate
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Events.CommentPosted
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined

  @committed_at ~U[2026-01-01 00:00:00Z]
  @posted_at ~U[2026-01-02 00:00:00Z]

  describe "OpenFlow" do
    test "produces FlowOpened" do
      cmd = %OpenFlow{
        project_id: "p1",
        flow_id: "f1",
        flow_name: "capability",
        entry_node_id: "n1"
      }

      assert %FlowOpened{
               project_id: "p1",
               flow_id: "f1",
               flow_name: "capability",
               entry_node_id: "n1"
             } =
               Aggregate.execute(%Aggregate{}, cmd)
    end
  end

  describe "CommitDraft" do
    test "produces DraftCommitted when the node has no pending draft" do
      cmd = %CommitDraft{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d1",
        body_sha: "sha1",
        committed_at: @committed_at
      }

      assert %DraftCommitted{node_id: "n1", draft_id: "d1"} = Aggregate.execute(%Aggregate{}, cmd)
    end

    test "rejects a second commit while a draft is still pending" do
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: "d1", body_sha: "sha1"}}}

      cmd = %CommitDraft{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d2",
        body_sha: "sha2",
        committed_at: @committed_at
      }

      assert {:error, {:engine_draft_conflict, details}} = Aggregate.execute(agg, cmd)
      assert details[:pending_draft_id] == "d1"
    end

    test "allows a commit once the prior draft is no longer pending" do
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: nil, body_sha: "sha1"}}}

      cmd = %CommitDraft{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d2",
        body_sha: "sha2",
        committed_at: @committed_at
      }

      assert %DraftCommitted{draft_id: "d2"} = Aggregate.execute(agg, cmd)
    end
  end

  describe "ApproveDraft" do
    test "produces DraftApproved" do
      cmd = %ApproveDraft{project_id: "p1", node_id: "n1", draft_id: "d1"}
      assert %DraftApproved{node_id: "n1", draft_id: "d1"} = Aggregate.execute(%Aggregate{}, cmd)
    end
  end

  describe "PostComment" do
    test "produces CommentPosted when body_sha matches the node's committed draft" do
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: nil, body_sha: "sha1"}}}

      cmd = %PostComment{
        project_id: "p1",
        node_id: "n1",
        body_sha: "sha1",
        author_id: "human-1",
        body: "this needs work",
        posted_at: @posted_at
      }

      assert %CommentPosted{node_id: "n1", body_sha: "sha1", locator: nil} =
               Aggregate.execute(agg, cmd)
    end

    test "rejects a comment against a body_sha that isn't the node's current one" do
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: nil, body_sha: "sha1"}}}

      cmd = %PostComment{
        project_id: "p1",
        node_id: "n1",
        body_sha: "stale-sha",
        author_id: "human-1",
        body: "this needs work",
        posted_at: @posted_at
      }

      assert {:error, {:engine_stale_comment, details}} = Aggregate.execute(agg, cmd)
      assert details[:current] == "sha1"
    end

    test "rejects a comment against a node this project has never committed" do
      cmd = %PostComment{
        project_id: "p1",
        node_id: "no-such-node",
        body_sha: "sha1",
        author_id: "human-1",
        body: "this needs work",
        posted_at: @posted_at
      }

      assert {:error, {:engine_comment_unknown_node, node_id: "no-such-node"}} =
               Aggregate.execute(%Aggregate{}, cmd)
    end
  end

  describe "ApproveGate" do
    test "produces GateApproved unconditionally" do
      cmd = %ApproveGate{project_id: "p1", flow_id: "f1", gate: "ux-review", actor_id: "human-1"}

      assert %GateApproved{flow_id: "f1", gate: "ux-review"} =
               Aggregate.execute(%Aggregate{}, cmd)
    end
  end

  describe "DeclineGate" do
    test "rejects a decline when no comment has landed since the gate's last resolution" do
      cmd = %DeclineGate{
        project_id: "p1",
        flow_id: "f1",
        gate: "ux-review",
        throwback_to: "generation",
        since_sequence: nil,
        actor_id: "human-1"
      }

      assert {:error, {:engine_gate_decline_without_comment, gate: "ux-review"}} =
               Aggregate.execute(%Aggregate{}, cmd)
    end

    test "produces GateDeclined once a comment has landed since the gate's last mark" do
      agg = %Aggregate{comment_count: 1, gate_marks: %{"ux-review" => 0}}

      cmd = %DeclineGate{
        project_id: "p1",
        flow_id: "f1",
        gate: "ux-review",
        throwback_to: "generation",
        since_sequence: 5,
        actor_id: "human-1"
      }

      assert %GateDeclined{gate: "ux-review", throwback_to: "generation", since_sequence: 5} =
               Aggregate.execute(agg, cmd)
    end

    test "rejects a second decline on the same gate with no fresh comment in between" do
      agg = %Aggregate{comment_count: 1, gate_marks: %{"ux-review" => 1}}

      cmd = %DeclineGate{
        project_id: "p1",
        flow_id: "f1",
        gate: "ux-review",
        throwback_to: "generation",
        since_sequence: 5,
        actor_id: "human-1"
      }

      assert {:error, {:engine_gate_decline_without_comment, gate: "ux-review"}} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "apply/2 rehydration" do
    test "a committed draft becomes the node's pending draft, and mints placeholders" do
      event = %DraftCommitted{
        project_id: "p1",
        node_id: "n1",
        tier: "sysarch",
        scope_key: %{},
        draft_id: "d1",
        body_sha: "sha1",
        committed_at: @committed_at,
        mints: [
          %{
            node_id: "c1",
            tier: "comp",
            scope_key: %{},
            edge_name: "decomposition",
            edge_type: :fanout
          }
        ]
      }

      agg = Aggregate.apply(%Aggregate{}, event)

      assert agg.project_id == "p1"
      assert agg.nodes["n1"] == %{pending_draft_id: "d1", body_sha: "sha1"}
      assert agg.nodes["c1"] == %{pending_draft_id: nil, body_sha: nil}
    end

    test "approval clears the pending draft, which then allows a fresh commit" do
      committed = %DraftCommitted{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d1",
        body_sha: "sha1",
        committed_at: @committed_at
      }

      agg = Aggregate.apply(%Aggregate{}, committed)

      cmd = %CommitDraft{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d2",
        body_sha: "sha2",
        committed_at: @committed_at
      }

      assert {:error, {:engine_draft_conflict, _details}} = Aggregate.execute(agg, cmd)

      approved = %DraftApproved{project_id: "p1", node_id: "n1", draft_id: "d1"}
      agg = Aggregate.apply(agg, approved)

      assert %DraftCommitted{draft_id: "d2"} = Aggregate.execute(agg, cmd)
    end

    test "approval preserves the node's own body_sha rather than dropping it" do
      committed = %DraftCommitted{
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        draft_id: "d1",
        body_sha: "sha1",
        committed_at: @committed_at
      }

      agg =
        Aggregate.apply(%Aggregate{}, committed)
        |> Aggregate.apply(%DraftApproved{project_id: "p1", node_id: "n1", draft_id: "d1"})

      assert agg.nodes["n1"] == %{pending_draft_id: nil, body_sha: "sha1"}
    end

    test "each posted comment bumps the project-wide comment counter" do
      event = %CommentPosted{
        project_id: "p1",
        node_id: "n1",
        body_sha: "sha1",
        author_id: "human-1",
        body: "needs work",
        posted_at: @posted_at
      }

      agg = %Aggregate{} |> Aggregate.apply(event) |> Aggregate.apply(event)

      assert agg.comment_count == 2
    end

    test "GateApproved and GateDeclined each mark the gate at the counter's current value" do
      comment = %CommentPosted{
        project_id: "p1",
        node_id: "n1",
        body_sha: "sha1",
        author_id: "human-1",
        body: "needs work",
        posted_at: @posted_at
      }

      approved = %GateApproved{project_id: "p1", flow_id: "f1", gate: "ux-review"}

      declined = %GateDeclined{
        project_id: "p1",
        flow_id: "f1",
        gate: "engineering-review",
        throwback_to: "ux-review",
        since_sequence: 1
      }

      agg =
        %Aggregate{}
        |> Aggregate.apply(comment)
        |> Aggregate.apply(approved)
        |> Aggregate.apply(comment)
        |> Aggregate.apply(declined)

      assert agg.gate_marks == %{"ux-review" => 1, "engineering-review" => 2}
    end
  end
end
