defmodule Catapult.Engine.Projections.GraphConstraintsTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.GraphConstraints
  alias Catapult.Engine.Store

  defp chain(tiers, edges) do
    %Chain{
      name: "test",
      tiers: Map.new(tiers, &{&1.name, &1}),
      edges: Map.new(edges, &{&1.name, &1})
    }
  end

  defp instance_edge(name, type, instance) do
    %Edge{name: name, file: "f", type: type, instances: [instance], graph_constraint: []}
  end

  defp node!(id, tier, opts) do
    Store.upsert_node(%{
      id: id,
      project_id: "p1",
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: Keyword.get(opts, :parent_node_id),
      status: Keyword.get(opts, :status, :absent)
    })
  end

  defp edge!(name, type, source_id, target_id) do
    Store.insert_edge(%{
      id: "#{name}|#{source_id}|#{target_id}",
      project_id: "p1",
      edge_name: name,
      type: type,
      source_node_id: source_id,
      target_node_id: target_id
    })
  end

  describe "cardinality — max bounds" do
    test "a max bound is checked eagerly, before the bound side is drained" do
      node!("comp1", "comp", status: :drafted)
      node!("resp1", "resp", scope_key: %{"id" => "resp1"})
      node!("resp2", "resp", scope_key: %{"id" => "resp2"})
      edge!("fulfills", :reference, "comp1", "resp1")
      edge!("fulfills", :reference, "comp1", "resp2")

      chain =
        chain(
          [
            %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}},
            %Tier{name: "resp", file: "f", scope: {:child_of, "requirements"}}
          ],
          [
            instance_edge("fulfills", "reference", %{
              source: "comp",
              target: "resp",
              declared_in: "x",
              cardinality: %{source: %{min: 0, max: 1}, target: %{min: 0, max: :unbounded}}
            })
          ]
        )

      assert [violation] = GraphConstraints.violations(chain, "p1")
      assert violation.kind == :cardinality
      assert violation.side == :source
      assert violation.node_id == "comp1"
      assert violation.count == 2
    end
  end

  describe "cardinality — min bounds wait on drainage" do
    test "a non-zero min is not reported while its own tier is still undrained" do
      node!("sysarch1", "sysarch", status: :drafted)
      node!("comp1", "comp", status: :approved, parent_node_id: "sysarch1")

      chain =
        chain(
          [
            %Tier{name: "sysarch", file: "f", scope: {:singleton}, draft: %{}},
            %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}},
            %Tier{name: "resp", file: "f", scope: {:child_of, "requirements"}}
          ],
          [
            instance_edge("fulfills", "reference", %{
              source: "comp",
              target: "resp",
              declared_in: "x",
              cardinality: %{
                source: %{min: 1, max: :unbounded},
                target: %{min: 0, max: :unbounded}
              }
            })
          ]
        )

      # sysarch is drafted, not settled (no review/approval recorded) — comp
      # is therefore not drained, so the un-fulfilled comp is not yet a
      # reportable violation.
      assert GraphConstraints.violations(chain, "p1") == []
    end

    test "a non-zero min is reported once its own tier is drained and unmet" do
      node!("sysarch1", "sysarch", status: :approved)
      node!("comp1", "comp", status: :approved, parent_node_id: "sysarch1")

      chain =
        chain(
          [
            %Tier{name: "sysarch", file: "f", scope: {:singleton}, draft: %{}},
            %Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}},
            %Tier{name: "resp", file: "f", scope: {:child_of, "requirements"}}
          ],
          [
            instance_edge("fulfills", "reference", %{
              source: "comp",
              target: "resp",
              declared_in: "x",
              cardinality: %{
                source: %{min: 1, max: :unbounded},
                target: %{min: 0, max: :unbounded}
              }
            })
          ]
        )

      assert [violation] = GraphConstraints.violations(chain, "p1")
      assert violation.kind == :cardinality
      assert violation.side == :source
      assert violation.node_id == "comp1"
      assert violation.count == 0
    end
  end

  describe "graph_constraint" do
    test "no_self_loop reports a self-referencing instance once both sides are drained" do
      node!("comp1", "comp", status: :approved)
      edge!("dependency", :dependency, "comp1", "comp1")

      chain =
        chain(
          [%Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, draft: %{}}],
          [
            %Edge{
              name: "dependency",
              file: "f",
              type: "dependency",
              graph_constraint: ["no_self_loop"],
              instances: [
                %{
                  source: "comp",
                  target: "comp",
                  declared_in: "x",
                  cardinality: %{
                    source: %{min: 0, max: :unbounded},
                    target: %{min: 0, max: :unbounded}
                  }
                }
              ]
            }
          ]
        )

      assert [violation] = GraphConstraints.violations(chain, "p1")
      assert violation.kind == :graph_constraint
      assert violation.constraint == "no_self_loop"
      assert violation.detail == %{self_loop_node_id: "comp1"}
    end

    test "acyclic reports a real cycle among committed instances" do
      node!("comp1", "comp", status: :approved, scope_key: %{"id" => "comp1"})
      node!("comp2", "comp", status: :approved, scope_key: %{"id" => "comp2"})
      edge!("dependency", :dependency, "comp1", "comp2")
      edge!("dependency", :dependency, "comp2", "comp1")

      chain =
        chain(
          [%Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}, draft: %{}}],
          [
            %Edge{
              name: "dependency",
              file: "f",
              type: "dependency",
              graph_constraint: ["acyclic"],
              instances: [
                %{
                  source: "comp",
                  target: "comp",
                  declared_in: "x",
                  cardinality: %{
                    source: %{min: 0, max: :unbounded},
                    target: %{min: 0, max: :unbounded}
                  }
                }
              ]
            }
          ]
        )

      assert [violation] = GraphConstraints.violations(chain, "p1")
      assert violation.kind == :graph_constraint
      assert violation.constraint == "acyclic"
    end

    test "no violation when nothing cites the constraint's edge" do
      chain =
        chain(
          [%Tier{name: "comp", file: "f", scope: {:child_of, "sysarch"}}],
          [
            %Edge{
              name: "dependency",
              file: "f",
              type: "dependency",
              graph_constraint: ["acyclic", "no_self_loop"],
              instances: [
                %{
                  source: "comp",
                  target: "comp",
                  declared_in: "x",
                  cardinality: %{
                    source: %{min: 0, max: :unbounded},
                    target: %{min: 0, max: :unbounded}
                  }
                }
              ]
            }
          ]
        )

      assert GraphConstraints.violations(chain, "p1") == []
    end
  end
end
