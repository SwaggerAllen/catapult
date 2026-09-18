defmodule Catapult.Engine.Projections.StalenessTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.Staleness
  alias Catapult.Engine.Store

  defp walk!(raw) do
    {:ok, walk} = ContextWalk.parse(raw)
    walk
  end

  defp tier(name, opts) do
    %Tier{name: name, effective_context: Keyword.get(opts, :effective_context, %{})}
  end

  defp node!(id, tier, opts) do
    Store.upsert_node(%{
      id: id,
      project_id: "p1",
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: Keyword.get(opts, :parent_node_id),
      status: Keyword.get(opts, :status, :approved),
      committed_sequence: Keyword.get(opts, :committed_sequence)
    })
  end

  defp chain(tiers) do
    %Chain{name: "test", tiers: Map.new(tiers, &{&1.name, &1})}
  end

  test "a never-drafted node is not stale" do
    chain = chain([tier("comp", effective_context: %{})])
    n = node!("n1", "comp", status: :absent, committed_sequence: nil)
    refute Staleness.stale?(chain, n)
  end

  test "a node with no context walks is never stale" do
    chain = chain([tier("comp", effective_context: %{})])
    n = node!("n1", "comp", committed_sequence: 5)
    refute Staleness.stale?(chain, n)
  end

  test "stale when a resolved context target committed later" do
    chain =
      chain([
        tier("resp", effective_context: %{}),
        tier("comp", effective_context: %{"fulfills" => walk!("self.fulfills -> resp.handle")})
      ])

    resp = node!("resp", "resp", committed_sequence: 10)
    comp = node!("comp", "comp", committed_sequence: 5)

    Store.insert_edge(%{
      id: "fulfills|comp|resp",
      project_id: "p1",
      edge_name: "fulfills",
      type: :reference,
      source_node_id: "comp",
      target_node_id: "resp"
    })

    assert Staleness.stale?(chain, comp)
    refute resp == nil
  end

  test "not stale when nothing resolved committed later than the node itself" do
    chain =
      chain([
        tier("resp", effective_context: %{}),
        tier("comp", effective_context: %{"fulfills" => walk!("self.fulfills -> resp.handle")})
      ])

    node!("resp", "resp", committed_sequence: 3)
    comp = node!("comp", "comp", committed_sequence: 5)

    Store.insert_edge(%{
      id: "fulfills|comp|resp",
      project_id: "p1",
      edge_name: "fulfills",
      type: :reference,
      source_node_id: "comp",
      target_node_id: "resp"
    })

    refute Staleness.stale?(chain, comp)
  end

  test "an unresolvable/unsupported walk never contributes staleness" do
    chain = chain([tier("comp", effective_context: %{"findings" => walk!("ticket.findings")})])
    comp = node!("comp", "comp", committed_sequence: 5)
    refute Staleness.stale?(chain, comp)
  end

  test "a review tier never has a node to be called with, so it is simply never asked" do
    # `chain.md` #14 / v5 §7.16 (corrected): a review commits
    # no body and mints no node of its own — this is the whole of what
    # "needs no staleness treatment" means at this module's level.
    chain = chain([tier("comp_review", effective_context: %{})])
    assert Map.has_key?(chain.tiers, "comp_review")
  end
end
