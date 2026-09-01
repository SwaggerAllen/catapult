defmodule Catapult.Engine.Projections.ContextResolverTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Store

  defp walk!(raw) do
    {:ok, walk} = ContextWalk.parse(raw)
    walk
  end

  defp node!(id, tier, opts \\ []) do
    Store.upsert_node(%{
      id: id,
      project_id: Keyword.get(opts, :project_id, "p1"),
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: Keyword.get(opts, :parent_node_id),
      status: Keyword.get(opts, :status, :absent)
    })
  end

  describe "self" do
    test "resolves to the node itself" do
      n = node!("n1", "comp")
      assert {:ok, [^n]} = ContextResolver.resolve(walk!("self"), n)
    end

    test "self.parent resolves to the parent node" do
      parent = node!("parent", "sysarch")
      child = node!("child", "comp", parent_node_id: "parent")

      assert {:ok, [^parent]} = ContextResolver.resolve(walk!("self.parent"), child)
    end

    test "self.parent is empty when there is no parent" do
      root = node!("root", "sysarch")
      assert {:ok, []} = ContextResolver.resolve(walk!("self.parent"), root)
    end
  end

  describe "single and multi-hop edges" do
    test "self.parent.<edge> -> <tier>.handle walks forward through a fanout edge" do
      sysarch = node!("sysarch", "sysarch")
      comp = node!("comp", "comp", parent_node_id: "sysarch")
      resp = node!("resp", "resp")

      Store.insert_edge(%{
        id: "fulfills|comp|resp",
        project_id: "p1",
        edge_name: "fulfills",
        type: :reference,
        source_node_id: "comp",
        target_node_id: "resp"
      })

      assert {:ok, [^resp]} = ContextResolver.resolve(walk!("self.fulfills -> resp.handle"), comp)
      refute sysarch == nil
    end

    test "a reversed hop (~) walks target -> source" do
      policy = node!("policy", "policy")
      resp = node!("resp", "resp")

      Store.insert_edge(%{
        id: "policy_application|policy|resp",
        project_id: "p1",
        edge_name: "policy_application",
        type: :policy_application,
        source_node_id: "policy",
        target_node_id: "resp"
      })

      assert {:ok, [^policy]} =
               ContextResolver.resolve(walk!("self.policy_application~ -> policy.handle"), resp)
    end
  end

  describe "all.<tier>" do
    test "reads every declared instance of a tier, unfiltered" do
      v1 = node!("v1", "vocab", scope_key: %{"n" => "v1"})
      v2 = node!("v2", "vocab", scope_key: %{"n" => "v2"})
      _other = node!("o1", "comp")

      {:ok, resolved} = ContextResolver.resolve(walk!("all.vocab.handle"), v1)
      assert Enum.sort_by(resolved, & &1.id) == Enum.sort_by([v1, v2], & &1.id)
    end
  end

  describe "input.<role> and input.*" do
    test "input.<role> always resolves {:ok, []} — not a graph walk (ORC-107)" do
      n = node!("n1", "comp")
      assert {:ok, []} = ContextResolver.resolve(walk!("input.project_doc"), n)
    end

    test "input.* always resolves {:ok, []} too" do
      n = node!("n1", "comp")
      assert {:ok, []} = ContextResolver.resolve(walk!("input.*"), n)
    end
  end

  describe "unsupported sources" do
    test "ticket.<source> is explicitly unsupported" do
      n = node!("n1", "comp")
      assert {:error, :unsupported} = ContextResolver.resolve(walk!("ticket.findings"), n)
    end
  end
end
