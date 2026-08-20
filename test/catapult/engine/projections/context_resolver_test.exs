defmodule Catapult.Engine.Projections.ContextResolverTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Store

  # Every id this module writes is namespaced to it. Async modules
  # share one `engine_nodes` table and the Ecto sandbox isolates
  # visibility, not row locks — two modules upserting the same primary
  # key each take a lock the other waits on, and Postgres kills one
  # with `ERROR 40P01 deadlock_detected`. Seen in CI, seed-dependent,
  # and it had nothing to do with the diff that tripped it. Tests
  # within a module run sequentially, so a per-module prefix is the
  # whole of the fix.
  @ns "context_resolver"

  defp nid(nil), do: nil
  defp nid(id), do: @ns <> ":" <> id

  defp walk!(raw) do
    {:ok, walk} = ContextWalk.parse(raw)
    walk
  end

  defp node!(id, tier, opts \\ []) do
    Store.upsert_node(%{
      id: nid(id),
      project_id: Keyword.get(opts, :project_id, "p1"),
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: nid(Keyword.get(opts, :parent_node_id)),
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
        id: nid("fulfills|comp|resp"),
        project_id: "p1",
        edge_name: "fulfills",
        type: :reference,
        source_node_id: nid("comp"),
        target_node_id: nid("resp")
      })

      assert {:ok, [^resp]} = ContextResolver.resolve(walk!("self.fulfills -> resp.handle"), comp)
      refute sysarch == nil
    end

    test "a reversed hop (~) walks target -> source" do
      policy = node!("policy", "policy")
      resp = node!("resp", "resp")

      Store.insert_edge(%{
        id: nid("policy_application|policy|resp"),
        project_id: "p1",
        edge_name: "policy_application",
        type: :policy_application,
        source_node_id: nid("policy"),
        target_node_id: nid("resp")
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

  describe "unsupported sources" do
    test "input.<role> is explicitly unsupported" do
      n = node!("n1", "comp")
      assert {:error, :unsupported} = ContextResolver.resolve(walk!("input.project_doc"), n)
    end

    test "ticket.<source> is explicitly unsupported" do
      n = node!("n1", "comp")
      assert {:error, :unsupported} = ContextResolver.resolve(walk!("ticket.findings"), n)
    end
  end
end
