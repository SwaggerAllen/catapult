defmodule Catapult.Delivery.DraftResolutionTest do
  @moduledoc """
  `DraftResolution.next_command/4` is the whole decision
  (`ContainerLifecycleTest`'s own precedent, restated for this
  module's own moduledoc): driving the real process manager end to end
  and asserting on `Catapult.Engine.Store` afterward would have to
  sleep or poll for its own `:eventual` dispatch to converge through
  `Catapult.Engine.Reducer`, which conventions §9 forbids. This tests
  the decision directly against a real loaded workflow and real node
  rows; `handle/2` around it is the thin part.

  Loads the shipped `bundles/default-flow`, whose `milestone` type is
  the worked example this module's own moduledoc argues from:
  `milestone-signoff` then `proposals-read`, both citing the same
  leading sub-array (`retro`'s own group — `workflow.yaml`'s
  `[review: milestone-signoff, status: retro, review: proposals-read]`).
  """

  use Catapult.DataCase, async: true

  alias Catapult.Delivery.DraftResolution
  alias Catapult.Dsl
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined
  alias Catapult.Engine.Store

  @project "draft-resolution-project"

  setup do
    assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
    %{workflow: workflow}
  end

  defp pm(entry_node_id) do
    %DraftResolution{
      project_id: @project,
      flow_id: "flow-1",
      entry_node_id: entry_node_id,
      flow_name: "milestone"
    }
  end

  defp node!(id, current_draft_id) do
    Store.upsert_node(%{
      id: id,
      project_id: @project,
      tier: "sysarch",
      scope_key: %{},
      status: :drafted,
      current_draft_id: current_draft_id,
      body_sha: "sha-#{current_draft_id}"
    })
  end

  describe "GateApproved" do
    test "an earlier gate in the review group dispatches nothing", %{workflow: workflow} do
      node = node!("sysarch", "d1")

      event = %GateApproved{
        project_id: @project,
        flow_id: "flow-1",
        gate: "milestone-signoff",
        actor_id: "human-1"
      }

      assert DraftResolution.next_command(workflow, pm("sysarch"), node, event) == nil
    end

    test "the review group's own last gate approves the node's own pending draft, actor threaded",
         %{workflow: workflow} do
      node = node!("sysarch", "d1")

      event = %GateApproved{
        project_id: @project,
        flow_id: "flow-1",
        gate: "proposals-read",
        actor_id: "human-1"
      }

      assert %ApproveDraft{
               project_id: @project,
               node_id: "sysarch",
               draft_id: "d1",
               actor_id: "human-1"
             } == DraftResolution.next_command(workflow, pm("sysarch"), node, event)
    end

    test "the group's own last gate dispatches nothing when the node carries no pending draft",
         %{workflow: workflow} do
      node = node!("sysarch", nil)

      event = %GateApproved{
        project_id: @project,
        flow_id: "flow-1",
        gate: "proposals-read",
        actor_id: "human-1"
      }

      assert DraftResolution.next_command(workflow, pm("sysarch"), node, event) == nil
    end
  end

  describe "GateDeclined" do
    test "discards the node's own pending draft unconditionally, actor threaded", %{
      workflow: workflow
    } do
      node = node!("sysarch", "d1")

      event = %GateDeclined{
        project_id: @project,
        flow_id: "flow-1",
        gate: "milestone-signoff",
        throwback_to: "main",
        since_sequence: nil,
        actor_id: "human-2"
      }

      assert %DiscardDraft{
               project_id: @project,
               node_id: "sysarch",
               draft_id: "d1",
               actor_id: "human-2"
             } == DraftResolution.next_command(workflow, pm("sysarch"), node, event)
    end

    test "dispatches nothing when the node carries no pending draft", %{workflow: workflow} do
      node = node!("sysarch", nil)

      event = %GateDeclined{
        project_id: @project,
        flow_id: "flow-1",
        gate: "ux-review",
        throwback_to: "pending",
        since_sequence: nil,
        actor_id: "human-2"
      }

      assert DraftResolution.next_command(workflow, pm("sysarch"), node, event) == nil
    end
  end
end
