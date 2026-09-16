defmodule Catapult.Engine.Projections.ReadyScopesTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.Predicate
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store

  defp walk!(raw) do
    {:ok, walk} = ContextWalk.parse(raw)
    walk
  end

  defp chain(tiers), do: %Chain{name: "test", tiers: Map.new(tiers, &{&1.name, &1})}

  defp chain(tiers, edges) do
    %Chain{
      name: "test",
      tiers: Map.new(tiers, &{&1.name, &1}),
      edges: Map.new(edges, &{&1.name, &1})
    }
  end

  defp fanout_edge!(name, source, target) do
    %Edge{
      name: name,
      file: "f",
      type: "fanout",
      instances: [%{source: source, target: target, declared_in: "x", cardinality: %{}}]
    }
  end

  defp node!(id, tier, opts) do
    Store.upsert_node(%{
      id: id,
      project_id: "p1",
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: Keyword.get(opts, :parent_node_id),
      status: Keyword.get(opts, :status, :absent),
      current_draft_id: Keyword.get(opts, :current_draft_id)
    })
  end

  defp draft!(id, node_id, opts \\ []) do
    Store.insert_draft(%{
      id: id,
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
    assert candidate.parent_node_id == "sysarch"
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
    assert candidate.id == "comp1"
  end

  test "a review is never ready on its own (chain.md #14 — no draft: of its own)" do
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
        id: "fulfills|sysarch|resp1",
        project_id: "p1",
        edge_name: "fulfills",
        type: :reference,
        source_node_id: "sysarch",
        target_node_id: "resp1"
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
      assert candidate.id == "sysarch"
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
      draft!("draft1", "comp1")

      chain =
        chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])

      assert [candidate] = ReadyScopes.ready_review(chain, "p1", "comp_review")
      assert candidate.id == "comp1"
    end

    test "a node with no current draft is not ready to review" do
      node!("comp1", "comp", status: :absent)

      chain = chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])
      assert ReadyScopes.ready_review(chain, "p1", "comp_review") == []
    end

    test "a node whose current draft already has a review is not ready to review again" do
      node!("comp1", "comp", status: :drafted, current_draft_id: "draft1")
      draft!("draft1", "comp1")

      Store.insert_review(%{
        id: "review1",
        project_id: "p1",
        draft_id: "draft1",
        score: 90,
        findings: [],
        body_sha: "sha",
        kind: :ai
      })

      chain = chain([%Tier{name: "comp_review", file: "f", reviews: "comp", context: []}])
      assert ReadyScopes.ready_review(chain, "p1", "comp_review") == []
    end
  end

  describe "settled? (ORC-235): a join target's mint-time :approved defers to its minting parent" do
    test "a join target minted :approved is not settled while its minting parent is still drafted" do
      node!("sysarch", "sysarch", status: :drafted)

      node!("comp1", "comp",
        status: :approved,
        parent_node_id: "sysarch",
        scope_key: %{"id" => "comp1"}
      )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, generator: "synthesis"},
          %Tier{
            name: "reader",
            file: "f",
            draft: %{},
            scope: {:per, "comp"},
            context: [walk!("self.parent.handle")]
          }
        ])

      assert ReadyScopes.ready(chain, "p1", "reader") == []
    end

    test "settled once the minting parent is itself approved" do
      node!("sysarch", "sysarch", status: :approved)

      node!("comp1", "comp",
        status: :approved,
        parent_node_id: "sysarch",
        scope_key: %{"id" => "comp1"}
      )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, generator: "synthesis"},
          %Tier{
            name: "reader",
            file: "f",
            draft: %{},
            scope: {:per, "comp"},
            context: [walk!("self.parent.handle")]
          }
        ])

      assert [candidate] = ReadyScopes.ready(chain, "p1", "reader")
      assert candidate.parent_node_id == "comp1"
    end

    test "a chain one level deeper recurses through two join targets to a real approval" do
      node!("sysarch", "sysarch", status: :drafted)

      node!("comp1", "comp",
        status: :approved,
        parent_node_id: "sysarch",
        scope_key: %{"id" => "comp1"}
      )

      node!("subcomp1", "subcomp",
        status: :approved,
        parent_node_id: "comp1",
        scope_key: %{"id" => "subcomp1"}
      )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, generator: "synthesis"},
          %Tier{name: "subcomp", file: "f", scope: {:child_of, "comp"}, generator: "synthesis"},
          %Tier{
            name: "reader",
            file: "f",
            draft: %{},
            scope: {:per, "subcomp"},
            context: [walk!("self.parent.handle")]
          }
        ])

      assert ReadyScopes.ready(chain, "p1", "reader") == []

      Store.upsert_node(%{id: "sysarch", project_id: "p1", tier: "sysarch", status: :approved})
      assert [_candidate] = ReadyScopes.ready(chain, "p1", "reader")
    end

    test "a generator: supplied tier is settled unconditionally, regardless of its stored status" do
      node!("design_system", "design_system", status: :absent)

      chain =
        chain([
          %Tier{
            name: "design_system",
            file: "f",
            scope: {:singleton},
            generator: "supplied"
          },
          %Tier{
            name: "reader",
            file: "f",
            draft: %{},
            scope: {:per, "design_system"},
            context: [walk!("self.parent.handle")]
          }
        ])

      assert [_candidate] = ReadyScopes.ready(chain, "p1", "reader")
    end
  end

  describe "drained? (ORC-235): all.<tier> is satisfied only once <tier>'s population is exhausted" do
    test "an empty all.<tier> walk is not satisfied while the driving tier hasn't drafted yet" do
      node!("driver", "driver", status: :absent)

      chain =
        chain(
          [
            %Tier{name: "driver", file: "f", draft: %{}, scope: {:singleton}, context: []},
            %Tier{name: "child", file: "f", scope: {:child_of, "driver"}, generator: "synthesis"},
            %Tier{
              name: "reader",
              file: "f",
              draft: %{},
              scope: {:singleton},
              context: [walk!("all.child.handle")]
            }
          ],
          [fanout_edge!("decomp", "driver", "child")]
        )

      assert ReadyScopes.ready(chain, "p1", "reader") == []
    end

    test "an empty all.<tier> walk is satisfied once the driving tier is approved with zero children" do
      node!("driver", "driver", status: :approved)

      chain =
        chain(
          [
            %Tier{name: "driver", file: "f", draft: %{}, scope: {:singleton}, context: []},
            %Tier{name: "child", file: "f", scope: {:child_of, "driver"}, generator: "synthesis"},
            %Tier{
              name: "reader",
              file: "f",
              draft: %{},
              scope: {:singleton},
              context: [walk!("all.child.handle")]
            }
          ],
          [fanout_edge!("decomp", "driver", "child")]
        )

      assert [_candidate] = ReadyScopes.ready(chain, "p1", "reader")
    end

    test "not satisfied while an existing child is still pending, even with the driving tier approved" do
      node!("driver", "driver", status: :approved)

      node!("child1", "child",
        status: :absent,
        parent_node_id: "driver",
        scope_key: %{"id" => "child1"}
      )

      chain =
        chain(
          [
            %Tier{name: "driver", file: "f", draft: %{}, scope: {:singleton}, context: []},
            %Tier{name: "child", file: "f", draft: %{}, scope: {:child_of, "driver"}},
            %Tier{
              name: "reader",
              file: "f",
              draft: %{},
              scope: {:singleton},
              context: [walk!("all.child.handle")]
            }
          ],
          [fanout_edge!("decomp", "driver", "child")]
        )

      assert ReadyScopes.ready(chain, "p1", "reader") == []
    end

    test "a child_of tier with several fanout sources is drained only once every source is drained" do
      node!("sysarch", "sysarch", status: :approved)
      node!("comparch", "comparch", status: :drafted)

      chain =
        chain(
          [
            %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
            %Tier{name: "comparch", file: "f", draft: %{}, scope: {:singleton}, context: []},
            %Tier{
              name: "policy",
              file: "f",
              scope: {:child_of, "sysarch"},
              generator: "synthesis"
            },
            %Tier{
              name: "reader",
              file: "f",
              draft: %{},
              scope: {:singleton},
              context: [walk!("all.policy.handle")]
            }
          ],
          [
            fanout_edge!("decomp_sysarch", "sysarch", "policy"),
            fanout_edge!("decomp_comparch", "comparch", "policy")
          ]
        )

      assert ReadyScopes.ready(chain, "p1", "reader") == []

      Store.upsert_node(%{id: "comparch", project_id: "p1", tier: "comparch", status: :approved})
      assert [_candidate] = ReadyScopes.ready(chain, "p1", "reader")
    end

    test "a per(X) tier is drained only once every existing X's own child is settled, not merely X itself" do
      node!("sysarch", "sysarch", status: :approved)

      node!("comp1", "comp",
        status: :approved,
        parent_node_id: "sysarch",
        scope_key: %{"id" => "comp1"}
      )

      chain =
        chain([
          %Tier{name: "sysarch", file: "f", draft: %{}, scope: {:singleton}, context: []},
          %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, generator: "synthesis"},
          %Tier{name: "comparch", file: "f", draft: %{}, scope: {:per, "comp"}, context: []},
          %Tier{
            name: "reader",
            file: "f",
            draft: %{},
            scope: {:singleton},
            context: [walk!("all.comparch.handle")]
          }
        ])

      assert ReadyScopes.ready(chain, "p1", "reader") == []
    end
  end

  describe "explain/2" do
    test "an unmet context walk is reported with its target's status" do
      node!("sysarch", "sysarch", status: :drafted)

      node =
        node!("comp1", "comp",
          scope_key: %{"per" => "sysarch"},
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

      assert target.node_id == "sysarch"
      assert target.status == :drafted
    end

    test "no blocking entries once every context walk is satisfied" do
      node!("sysarch", "sysarch", status: :approved)

      node =
        node!("comp1", "comp",
          scope_key: %{"per" => "sysarch"},
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
