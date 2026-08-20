defmodule Catapult.Engine.Projections.ReadyScopesTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Predicate
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
      parent_node_id: nid(Keyword.get(opts, :parent_node_id)),
      status: Keyword.get(opts, :status, :absent),
      current_draft_id: nid(Keyword.get(opts, :current_draft_id))
    })
  end

  defp draft!(id, node_id, opts \\ []) do
    Store.insert_draft(%{
      id: nid(id),
      project_id: "p1",
      node_id: node_id,
      body_sha: "sha",
      committed_sequence: 1,
      status: Keyword.get(opts, :status, :pending)
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

  describe "scope_filter" do
    test "a candidate failing scope_filter never appears, even with an otherwise-met context" do
      chain =
        chain([
          %Tier{
            name: "sysarch",
            file: "f",
            draft: %{},
            scope: {:singleton},
            scope_filter_raw: "has_edge(fulfills)",
            context: []
          }
        ])

      assert ReadyScopes.ready(chain, "p1", "sysarch") == []
    end

    test "a candidate passing scope_filter is enumerated as usual" do
      node!("sysarch", "sysarch", status: :absent)
      node!("resp1", "resp", scope_key: %{"n" => "resp1"})

      Store.insert_edge(%{
        id: "fulfills|" <> nid("sysarch") <> "|" <> nid("resp1"),
        project_id: "p1",
        edge_name: "fulfills",
        type: :reference,
        source_node_id: nid("sysarch"),
        target_node_id: nid("resp1")
      })

      chain =
        chain([
          %Tier{
            name: "sysarch",
            file: "f",
            draft: %{},
            scope: {:singleton},
            scope_filter_raw: "has_edge(fulfills)",
            context: []
          }
        ])

      assert [candidate] = ReadyScopes.ready(chain, "p1", "sysarch")
      assert candidate.id == nid("sysarch")
    end

    test "a named predicate in Chain.predicates resolves the same way an inline one does" do
      node!("sysarch", "sysarch", status: :drafted)

      chain = %Chain{
        name: "test",
        tiers: %{
          "sysarch" => %Tier{
            name: "sysarch",
            file: "f",
            draft: %{},
            scope: {:singleton},
            scope_filter_raw: "always_true",
            context: []
          }
        },
        predicates: %{"always_true" => elem(Predicate.parse("true == true"), 1)}
      }

      # Drafted already, so scope_filter passing doesn't make it ready —
      # this only proves the named predicate resolved (and didn't
      # exclude it outright the way a failed resolution would).
      assert ReadyScopes.ready(chain, "p1", "sysarch") == []
    end
  end

  describe "ready_review/3" do
    test "[] for a tier that is not a review tier" do
      chain =
        chain([%Tier{name: "comp", file: "f", draft: %{}, scope: {:singleton}, context: []}])

      assert ReadyScopes.ready_review(chain, "p1", "comp") == []
    end

    test "a reviewed tier's node with a current draft and no review is ready to review" do
      node!("comp1", "comp", status: :drafted, current_draft_id: "draft1")
      draft!("draft1", nid("comp1"))

      chain =
        chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])

      assert [candidate] = ReadyScopes.ready_review(chain, "p1", "comp_review")
      assert candidate.id == nid("comp1")
    end

    test "a node with no current draft is not ready to review" do
      node!("comp1", "comp", status: :absent)

      chain = chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])
      assert ReadyScopes.ready_review(chain, "p1", "comp_review") == []
    end

    test "a node whose current draft already has a review is not ready to review again" do
      node!("comp1", "comp", status: :drafted, current_draft_id: "draft1")
      draft!("draft1", nid("comp1"))

      Store.insert_review(%{
        id: nid("review1"),
        project_id: "p1",
        draft_id: nid("draft1"),
        score: 90,
        findings: [],
        body_sha: "sha",
        kind: :ai
      })

      chain = chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])
      assert ReadyScopes.ready_review(chain, "p1", "comp_review") == []
    end
  end

  describe "explain/2" do
    test "an unmet context walk is reported with its target's status" do
      node!("sysarch", "sysarch", status: :drafted)

      node =
        node!("comp1", "comp",
          scope_key: %{"per" => nid("sysarch")},
          parent_node_id: "sysarch"
        )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{
            name: "comp",
            file: "f",
            draft: %{},
            scope: {:per, "sysarch"},
            context: [walk!("self.parent.handle")]
          }
        ])

      report = ReadyScopes.explain(chain, node)

      assert report.tier == "comp"
      assert report.passes_scope_filter == true

      assert [%{walk: "self.parent.handle", satisfied: false, targets: [target]}] =
               report.blocking

      assert target.node_id == nid("sysarch")
      assert target.status == :drafted
    end

    test "no blocking entries once every context walk is satisfied" do
      node!("sysarch", "sysarch", status: :approved)

      node =
        node!("comp1", "comp",
          scope_key: %{"per" => nid("sysarch")},
          parent_node_id: "sysarch"
        )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{
            name: "comp",
            file: "f",
            draft: %{},
            scope: {:per, "sysarch"},
            context: [walk!("self.parent.handle")]
          }
        ])

      assert ReadyScopes.explain(chain, node).blocking == []
    end

    test "reports passes_scope_filter: false when the tier's scope_filter fails" do
      node =
        node!("sysarch", "sysarch",
          status: :absent,
          scope_key: %{}
        )

      chain =
        chain([
          %Tier{
            name: "sysarch",
            file: "f",
            draft: %{},
            scope: {:singleton},
            scope_filter_raw: "has_edge(fulfills)",
            context: []
          }
        ])

      assert ReadyScopes.explain(chain, node).passes_scope_filter == false
    end
  end
end
