defmodule Catapult.Dsl.EdgeLocatorTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.EdgeLocator
  alias Catapult.Dsl.Tier

  defp graph(tiers, edges \\ []) do
    %{
      tiers: Map.new(tiers, &{&1.name, &1}),
      edges: Map.new(edges, &{&1.name, &1})
    }
  end

  defp fanout_edge(name, instances) do
    %Edge{name: name, type: "fanout", context_raw: "none", instances: instances}
  end

  defp tier(name, scope), do: %Tier{name: name, scope: scope}

  describe "parse/1" do
    test "self, self.parent and fanout(<edge>) are the closed keywords" do
      assert EdgeLocator.parse("self") == :self
      assert EdgeLocator.parse("self.parent") == :self_parent
      assert EdgeLocator.parse("fanout(decomposition)") == {:fanout, "decomposition"}
    end

    test "anything else is an explicit path" do
      assert EdgeLocator.parse("@from") == {:path, "@from"}
    end
  end

  describe "resolve/8 — self and defaults" do
    test "the declaring tier itself resolves to :self with no locator needed" do
      g = graph([tier("comp", {:child_of, "sysarch"})])

      assert {:ok, :self, {:path, "@id"}} =
               EdgeLocator.resolve(
                 "comp",
                 "resp",
                 "comp",
                 "comp.draft.x[].@id",
                 "id",
                 nil,
                 nil,
                 g
               )
    end

    test "the non-self side defaults to the trailing .@attr when the other side resolves structurally" do
      g =
        graph(
          [tier("sysarch", {:per, "requirements"}), tier("resp", {:child_of, "requirements"})],
          [
            fanout_edge("decomposition", [
              %{
                source: "sysarch",
                target: "comp",
                declared_in: "sysarch.draft.components.component[]"
              }
            ])
          ]
        )

      assert {:ok, {:fanout, "decomposition"}, {:path, "@id"}} =
               EdgeLocator.resolve(
                 "comp",
                 "resp",
                 "sysarch",
                 "sysarch.draft.components.component[].responsibilities.resp[].@id",
                 "id",
                 nil,
                 nil,
                 g
               )
    end

    test "neither side resolving and no trailing attr is an error naming both sides" do
      g = graph([tier("comp", {:child_of, "sysarch"})])

      assert {:error, [:source, :target]} =
               EdgeLocator.resolve(
                 "comp",
                 "comp",
                 "sysarch",
                 "sysarch.draft.dependencies.dep[]",
                 nil,
                 nil,
                 nil,
                 g
               )
    end

    test "neither side resolving with an explicit pair on both sides succeeds" do
      g = graph([tier("comp", {:child_of, "sysarch"})])

      assert {:ok, {:path, "@from"}, {:path, "@to"}} =
               EdgeLocator.resolve(
                 "comp",
                 "comp",
                 "sysarch",
                 "sysarch.draft.dependencies.dep[]",
                 nil,
                 {:path, "@from"},
                 {:path, "@to"},
                 g
               )
    end
  end

  describe "resolve/8 — self.parent and singleton" do
    test "self.parent resolves when the declaring tier's own scope names the side tier" do
      g = graph([tier("ui_collarch", {:per, "ui_coll"}), tier("design_system", {:singleton})])

      assert {:ok, :self_parent, :singleton} =
               EdgeLocator.resolve(
                 "ui_coll",
                 "design_system",
                 "ui_collarch",
                 "ui_collarch.draft.primitives.design-system[]",
                 nil,
                 nil,
                 nil,
                 g
               )
    end

    test "self.parent does not match a tier whose scope names something else" do
      g = graph([tier("comparch", {:per, "comp"}), tier("journey", {:child_of, "journeys"})])

      assert {:error, [:source]} =
               EdgeLocator.resolve(
                 "journey",
                 "screen",
                 "comparch",
                 "comparch.draft.x[]",
                 nil,
                 :self_parent,
                 {:path, "@ref"},
                 g
               )
    end
  end

  describe "resolve/8 — same-tier self-reference (navigation)" do
    test "source claims the fanout locator, target falls back to the trailing attr rather than colliding" do
      g =
        graph(
          [tier("screens", {:singleton}), tier("screen", {:child_of, "screens"})],
          [
            fanout_edge("decomposition", [
              %{source: "screens", target: "screen", declared_in: "screens.draft.screen[]"}
            ])
          ]
        )

      assert {:ok, {:fanout, "decomposition"}, {:path, "@to"}} =
               EdgeLocator.resolve(
                 "screen",
                 "screen",
                 "screens",
                 "screens.draft.screen[].navigation.edge[].@to",
                 "to",
                 nil,
                 nil,
                 g
               )
    end
  end

  describe "fanout_prefix_instance/4" do
    test "matches an edge by name whose own declared_in strictly prefixes the given path" do
      g =
        graph([], [
          fanout_edge("decomposition", [
            %{
              source: "sysarch",
              target: "comp",
              declared_in: "sysarch.draft.components.component[]"
            }
          ])
        ])

      assert %{target: "comp"} =
               EdgeLocator.fanout_prefix_instance(
                 g.edges,
                 "decomposition",
                 "comp",
                 "sysarch.draft.components.component[].responsibilities.resp[].@id"
               )
    end

    test "a declared_in equal to (not strictly prefixing) the fanout's own is not a match" do
      g =
        graph([], [
          fanout_edge("decomposition", [
            %{
              source: "sysarch",
              target: "comp",
              declared_in: "sysarch.draft.components.component[]"
            }
          ])
        ])

      assert is_nil(
               EdgeLocator.fanout_prefix_instance(
                 g.edges,
                 "decomposition",
                 "comp",
                 "sysarch.draft.components.component[]"
               )
             )
    end

    test "an unknown edge name resolves to nil" do
      assert is_nil(EdgeLocator.fanout_prefix_instance(%{}, "nope", "comp", "sysarch.draft.x[]"))
    end
  end
end
