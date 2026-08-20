defmodule Catapult.Generation.ExtractionTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Dialect
  alias Catapult.Dsl.Registry
  alias Catapult.Generation.Extraction

  setup_all do
    {:ok, dialect} = Dialect.by_name("design")
    {:ok, registry} = Registry.build(dialect.extensions)
    {:ok, chain} = Chain.load("bundles", "default", registry)
    %{chain: chain}
  end

  defp scan!(xml), do: xml |> String.to_charlist() |> :xmerl_scan.string() |> elem(0)

  describe "fields/2" do
    test "reads draft.<tag>-sourced fields, including nested markup" do
      element = scan!("<sysarch><introduction>Hi *there*.</introduction></sysarch>")

      assert Extraction.fields(element, %{"intro" => "draft.introduction"}) == %{
               "intro" => "Hi *there*."
             }
    end

    test "skips mint.-sourced fields (join-target tiers, out of this module's scope)" do
      element = scan!("<sysarch/>")
      assert Extraction.fields(element, %{"name" => "mint.name"}) == %{}
    end

    test "a missing element resolves to nil rather than raising" do
      element = scan!("<sysarch/>")
      assert Extraction.fields(element, %{"intro" => "draft.introduction"}) == %{"intro" => nil}
    end
  end

  describe "mints/4 (fanout, self-sourced)" do
    test "extracts one mint per fanout instance, using the alias attribute fallback for identity: id",
         %{
           chain: chain
         } do
      element =
        scan!("""
        <sysarch>
          <components>
            <component alias="auth"><name>Auth</name></component>
            <component alias="billing"><name>Billing</name></component>
          </components>
        </sysarch>
        """)

      mints = Extraction.mints(element, "sysarch", Map.values(chain.edges), chain)

      assert Enum.map(mints, & &1.node_id) |> Enum.sort() == ["comp:auth", "comp:billing"]
      assert Enum.all?(mints, &(&1.tier == "comp" and &1.edge_type == :fanout))
      assert Enum.find(mints, &(&1.node_id == "comp:auth")).scope_key == %{"id" => "auth"}
    end

    test "a tier that mints nothing returns no mints", %{chain: chain} do
      element = scan!("<vocab-entry><definition>x</definition></vocab-entry>")
      assert Extraction.mints(element, "vocab", Map.values(chain.edges), chain) == []
    end
  end

  describe "references/5 (reference, self-sourced attribute)" do
    test "resolves each reference's target attribute via the resolver callback", %{chain: chain} do
      element =
        scan!("""
        <comparch>
          <references>
            <reference target="ref-1"/>
            <reference target="ref-2"/>
          </references>
        </comparch>
        """)

      resolve = fn _project_id, tier, value -> "#{tier}:#{value}" end

      refs =
        Extraction.references(element, "comparch", Map.values(chain.edges), "p1", resolve)

      assert Enum.map(refs, & &1.target_node_id) |> Enum.sort() == ["ref:ref-1", "ref:ref-2"]
      assert Enum.all?(refs, &(&1.type == :reference and &1.edge_name == "reference"))
    end

    test "a reference whose target does not resolve is dropped, not errored", %{chain: chain} do
      element =
        scan!("<comparch><references><reference target=\"gone\"/></references></comparch>")

      resolve = fn _project_id, _tier, _value -> nil end

      assert Extraction.references(element, "comparch", Map.values(chain.edges), "p1", resolve) ==
               []
    end
  end

  describe "produces/3" do
    test "resolves self.parent owners and skips self (unresolvable before the node exists)" do
      element = scan!("<comparch><techspec>The spec.</techspec></comparch>")

      decls = [
        %{owner_raw: "self.parent", kind: "techspec", authored: "draft.techspec"},
        %{owner_raw: "self", kind: "techspec", authored: "draft.techspec"}
      ]

      assert Extraction.produces(element, decls, "parent-1") == [
               %{owner_node_id: "parent-1", kind: "techspec", content: "The spec."}
             ]
    end

    test "self.parent with no parent produces nothing" do
      element = scan!("<comparch><techspec>x</techspec></comparch>")
      decls = [%{owner_raw: "self.parent", kind: "techspec", authored: "draft.techspec"}]
      assert Extraction.produces(element, decls, nil) == []
    end
  end
end
