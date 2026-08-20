defmodule Catapult.Engine.SchedulerTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.DraftDiscarded
  alias Catapult.Engine.Scheduler
  alias Catapult.Engine.Store
  alias Catapult.Engine.Topics

  # Namespaced ids AND a namespaced project id: node ids share one
  # `engine_nodes` table across async modules (see ready_scopes_test.exs),
  # and a project id here doubles as a PubSub topic suffix — a bare
  # "p1" could receive another async module's broadcast if one ever
  # reuses it.
  @ns "scheduler"
  @project "scheduler-p1"

  defp nid(id), do: @ns <> ":" <> id

  defp chain(tiers), do: %Chain{name: "test", tiers: Map.new(tiers, &{&1.name, &1})}

  defp node!(id, tier, opts) do
    Store.upsert_node(%{
      id: nid(id),
      project_id: @project,
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      status: Keyword.get(opts, :status, :absent),
      current_draft_id: opts |> Keyword.get(:current_draft_id) |> then(&(&1 && nid(&1)))
    })
  end

  defp draft!(id, node_id) do
    Store.insert_draft(%{
      id: nid(id),
      project_id: @project,
      node_id: node_id,
      body_sha: "sha",
      committed_sequence: 1,
      status: :pending
    })
  end

  describe "triggering_project_id/1" do
    test "a draft committed, a draft approved, and a chain-axis bundle flip all trigger" do
      assert Scheduler.triggering_project_id(%DraftCommitted{
               project_id: @project,
               node_id: "n",
               tier: "t",
               scope_key: %{},
               draft_id: "d",
               body_sha: "sha",
               committed_at: ~U[2026-01-01 00:00:00Z]
             }) == @project

      assert Scheduler.triggering_project_id(%DraftApproved{
               project_id: @project,
               node_id: "n",
               draft_id: "d"
             }) == @project

      assert Scheduler.triggering_project_id(%ActiveBundleFlipped{
               project_id: @project,
               axis: :chain,
               bundle_name: "default",
               version: "1.0.0",
               flip_id: "f"
             }) == @project
    end

    test "a workflow-axis bundle flip does not trigger" do
      refute Scheduler.triggering_project_id(%ActiveBundleFlipped{
               project_id: @project,
               axis: :workflow,
               bundle_name: "default-flow",
               version: "1.0.0",
               flip_id: "f"
             })
    end

    test "an event outside the named set does not trigger" do
      refute Scheduler.triggering_project_id(%DraftDiscarded{
               project_id: @project,
               node_id: "n",
               draft_id: "d"
             })
    end
  end

  describe "trigger/2" do
    test "broadcasts a ready generation-tier candidate as {tier, scope_key}" do
      :ok = Topics.subscribe(Topics.ready_scopes(@project))

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []}
        ])

      assert :ok = Scheduler.trigger(chain, @project)

      assert_receive {:ready_scopes, @project, pairs}
      assert {"sysarch", %{}} in pairs
    end

    test "broadcasts a ready review-tier candidate as {review_tier, scope_key}" do
      :ok = Topics.subscribe(Topics.ready_scopes(@project))

      node!("comp1", "comp", status: :drafted, current_draft_id: "draft1")
      draft!("draft1", nid("comp1"))

      chain =
        chain([
          %Tier{name: "comp_review", file: "f", reviews: "comp", context: []}
        ])

      assert :ok = Scheduler.trigger(chain, @project)

      assert_receive {:ready_scopes, @project, pairs}
      assert {"comp_review", %{}} in pairs
    end

    test "a tier with nothing ready still broadcasts (liberally, per systems/engine.md)" do
      :ok = Topics.subscribe(Topics.ready_scopes(@project))

      node!("sysarch", "sysarch", status: :drafted)

      chain =
        chain([%Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []}])

      assert :ok = Scheduler.trigger(chain, @project)
      assert_receive {:ready_scopes, @project, []}
    end

    test "a subscriber on a different project's topic hears nothing" do
      :ok = Topics.subscribe(Topics.ready_scopes("scheduler-other-project"))

      chain =
        chain([%Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []}])

      assert :ok = Scheduler.trigger(chain, @project)
      refute_receive {:ready_scopes, @project, _pairs}
    end
  end
end
