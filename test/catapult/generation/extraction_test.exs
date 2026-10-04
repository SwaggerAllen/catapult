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

    test "skips mint./mint.parent./reference.-sourced fields (resolved elsewhere, not from a draft body)" do
      element = scan!("<sysarch/>")

      assert Extraction.fields(element, %{
               "name" => "mint.name",
               "parent" => "mint.parent.techspec",
               "title" => "reference.title"
             }) == %{}
    end

    test "a missing element resolves to nil rather than raising" do
      element = scan!("<sysarch/>")
      assert Extraction.fields(element, %{"intro" => "draft.introduction"}) == %{"intro" => nil}
    end
  end

  describe "mints/6 (fanout, self-sourced)" do
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

      result =
        Extraction.mints(element, "sysarch", chain, %{}, %{}, "sysarch:1", fn _tier, _value ->
          nil
        end)

      assert Enum.map(result.mints, & &1.node_id) |> Enum.sort() == ["comp:auth", "comp:billing"]
      assert Enum.all?(result.mints, &(&1.tier == "comp" and &1.edge_type == :fanout))
      assert Enum.find(result.mints, &(&1.node_id == "comp:auth")).scope_key == %{"id" => "auth"}

      assert Enum.find(result.mints, &(&1.node_id == "comp:auth")).fields == %{
               "name" => "Auth",
               "purpose" => nil,
               "is_foundation" => nil,
               "project_techspec" => nil,
               "project_policies_summary" => nil
             }
    end

    test "a tier that mints nothing returns no mints", %{chain: chain} do
      element = scan!("<vocab-entry><definition>x</definition></vocab-entry>")

      assert Extraction.mints(element, "vocab", chain, %{}, %{}, nil, fn _tier, _value -> nil end) ==
               %{mints: [], edges: []}
    end
  end

  describe "references/6 (reference, self-sourced attribute)" do
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

      resolve = fn tier, value -> "#{tier}:#{value}" end

      refs = Extraction.references(element, "comparch", chain, "comparch:1", nil, resolve)

      assert Enum.map(refs, & &1.target_node_id) |> Enum.sort() == ["ref:ref-1", "ref:ref-2"]
      assert Enum.all?(refs, &(&1.type == :reference and &1.edge_name == "reference"))
      assert Enum.all?(refs, &(&1.source_node_id == "comparch:1"))
    end

    test "a reference whose target does not resolve is dropped, not errored", %{chain: chain} do
      element =
        scan!("<comparch><references><reference target=\"gone\"/></references></comparch>")

      resolve = fn _tier, _value -> nil end

      assert Extraction.references(element, "comparch", chain, "comparch:1", nil, resolve) == []
    end
  end

  describe "produces/3" do
    test "resolves onto the scope parent (chain.md #13: the owner is always the scope parent)" do
      element = scan!("<comparch><techspec>The spec.</techspec></comparch>")
      decls = [%{kind: "techspec", draft_path: "draft.techspec"}]

      assert Extraction.produces(element, decls, "parent-1") == [
               %{owner_node_id: "parent-1", kind: "techspec", content: "The spec."}
             ]
    end

    test "no parent_node_id produces nothing" do
      element = scan!("<comparch><techspec>x</techspec></comparch>")
      decls = [%{kind: "techspec", draft_path: "draft.techspec"}]
      assert Extraction.produces(element, decls, nil) == []
    end
  end
end
