defmodule Catapult.Engine.AggregateTest do
  use ExUnit.Case, async: true

  alias Catapult.Engine.Aggregate
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FlowOpened

  @committed_at ~U[2026-01-01 00:00:00Z]

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
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: "d1"}}}

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
      agg = %Aggregate{nodes: %{"n1" => %{pending_draft_id: nil}}}

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
      assert agg.nodes["n1"] == %{pending_draft_id: "d1"}
      assert agg.nodes["c1"] == %{pending_draft_id: nil}
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
  end
end
