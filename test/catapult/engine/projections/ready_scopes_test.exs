defmodule Catapult.Engine.Projections.ReadyScopesTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store

  # Every id this module writes is namespaced to it. Async modules
  # share one `engine_nodes` table and the Ecto sandbox isolates
  # visibility, not row locks — two modules upserting the same primary
  # key each take a lock the other waits on, and Postgres kills one
  # with `ERROR 40P01 deadlock_detected`. Seen in CI, seed-dependent,
  # and it had nothing to do with the diff that tripped it. Tests
  # within a module run sequentially, so a per-module prefix is the
  # whole of the fix.
  @ns "ready_scopes"

  defp nid(nil), do: nil
  defp nid(id), do: @ns <> ":" <> id

  defp walk!(raw) do
    {:ok, walk} = ContextWalk.parse(raw)
    walk
  end

  defp chain(tiers), do: %Chain{name: "test", tiers: Map.new(tiers, &{&1.name, &1})}

  defp node!(id, tier, opts) do
    Store.upsert_node(%{
      id: nid(id),
      project_id: "p1",
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: Keyword.get(opts, :parent_node_id),
      status: Keyword.get(opts, :status, :absent)
    })
  end

  test "a singleton tier with an approved context is ready" do
    chain =
      chain([
        %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []}
      ])

    assert [candidate] = ReadyScopes.ready(chain, "p1", "sysarch")
    assert candidate.tier == "sysarch"
    assert candidate.status == :absent
  end

  test "a singleton tier already drafted is not ready" do
    node!("sysarch", "sysarch", status: :drafted)

    chain =
      chain([%Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []}])

    assert ReadyScopes.ready(chain, "p1", "sysarch") == []
  end

  test "per(X) enumerates one candidate per existing X, gated on X's own readiness" do
    node!("sysarch", "sysarch", status: :approved)

    chain =
      chain([
        %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
        %Tier{
          name: "comparch",
          file: "f",
          draft: %{},
          scope: {:per, "sysarch"},
          context: [walk!("self.parent.handle")]
        }
      ])

    assert [candidate] = ReadyScopes.ready(chain, "p1", "comparch")
    assert candidate.parent_node_id == nid("sysarch")
  end

  test "per(X) candidate is not ready when its own parent is not yet approved" do
    node!("sysarch", "sysarch", status: :drafted)

    chain =
      chain([
        %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
        %Tier{
          name: "comparch",
          file: "f",
          draft: %{},
          scope: {:per, "sysarch"},
          context: [walk!("self.parent.handle")]
        }
      ])

    assert ReadyScopes.ready(chain, "p1", "comparch") == []
  end

  test "child_of(X) enumerates already-minted, not-yet-drafted children" do
    node!("sysarch", "sysarch", status: :approved)

    node!("comp1", "comp",
      status: :absent,
      parent_node_id: "sysarch",
      scope_key: %{"n" => "comp1"}
    )

    node!("comp2", "comp",
      status: :drafted,
      parent_node_id: "sysarch",
      scope_key: %{"n" => "comp2"}
    )

    chain =
      chain([
        %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
        %Tier{name: "comp", file: "f", draft: %{}, scope: {:child_of, "sysarch"}, context: []}
      ])

    assert [candidate] = ReadyScopes.ready(chain, "p1", "comp")
    assert candidate.id == nid("comp1")
  end

  test "a review tier is never ready (dsl-syntax.md §3.3 — no draft: of its own)" do
    chain = chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])
    assert ReadyScopes.ready(chain, "p1", "comp_review") == []
  end

  test "cascade_visit enumerates nothing (Target — flow instances)" do
    chain =
      chain([%Tier{name: "plan", file: "f", draft: %{}, scope: {:cascade_visit}, context: []}])

    assert ReadyScopes.ready(chain, "p1", "plan") == []
  end
end
