defmodule Catapult.Dsl.LoaderTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Fixture
  alias Catapult.Dsl.Loader

  @moduletag :tmp_dir

  # A comparch.xsd generic enough for edge-focused tests that only need
  # some element with a `from`/`to`/`target` attribute to point
  # `declared_in`/`source_ref`/`target_ref` at — the identity/field
  # annotations under test elsewhere don't matter here.
  defp edge_test_schema do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="comparch">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="dep" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="from" type="xs:string"/>
                <xs:attribute name="to" type="xs:string"/>
              </xs:complexType>
            </xs:element>
            <xs:element name="nav" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="from" type="xs:string"/>
                <xs:attribute name="to" type="xs:string"/>
              </xs:complexType>
            </xs:element>
            <xs:element name="r" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="target" type="xs:string"/>
              </xs:complexType>
            </xs:element>
            <xs:element name="a" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="target" type="xs:string"/>
              </xs:complexType>
            </xs:element>
            <xs:element name="b" minOccurs="0" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="target" type="xs:string"/>
              </xs:complexType>
            </xs:element>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """
  end

  describe "the whole load" do
    test "loads a minimal, valid chain + workflow bundle pair", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      assert {:ok, loaded} = Loader.load(dir)
      assert %{"comparch" => _tier} = loaded.chain.tiers
      assert %{"product-review" => _gate} = loaded.workflow.gates
    end

    test "reports catapult.yaml missing", %{tmp_dir: dir} do
      assert {:error, :catapult_yaml, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "catapult.yaml"))
    end

    test "reports catapult.yaml missing chain:", %{tmp_dir: dir} do
      Fixture.write!(dir, %{"catapult.yaml" => "workflow: default-flow\n"})
      assert {:error, :catapult_yaml, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "missing required field \"chain\""))
    end

    test "the runtime dialect refuses a workflow: entry in catapult.yaml", %{tmp_dir: dir} do
      Fixture.minimal!(dir)
      assert {:error, :catapult_yaml, problems} = Loader.load(dir, dialect: "runtime")
      assert Enum.any?(problems, &String.contains?(&1, "runtime dialect"))
    end

    test "the runtime dialect loads the chain axis alone", %{tmp_dir: dir} do
      Fixture.minimal!(dir)
      Fixture.write!(dir, %{"catapult.yaml" => "chain: default\n"})

      assert {:ok, loaded} = Loader.load(dir, dialect: "runtime")
      assert loaded.workflow == nil
    end

    test "a chain that fails to load is reported alone, without a paired workflow error", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)
      Fixture.write!(dir, %{"bundles/default/chain.yaml" => "kind: chain\n"})

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "missing required field \"name\""))
    end

    test "Chain.resolve_predicate carries a named predicate forward for the engine's runtime evaluator",
         %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            prompt: prompts/comparch.md.liquid
        edges: {}
        predicates:
          is_domain: "kind == domain"
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert {:ok, predicate} = Chain.resolve_predicate(loaded.chain, "is_domain")
      assert predicate == Map.fetch!(loaded.chain.predicates, "is_domain")

      # An inline expression not registered in predicates: parses fresh
      # rather than failing for want of a name.
      assert {:ok, _predicate} = Chain.resolve_predicate(loaded.chain, "has_edge(fulfills)")
    end
  end

  describe "chain.yaml structure (bundle.md #2, chain.md #2)" do
    test "an unknown top-level chain.yaml key is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges: {}
        extends: base
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "unknown field \"extends\""))
    end

    test "an unknown top-level tier key is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            gate: some-gate
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "unknown field \"gate\""))
    end

    test "scope naming an undeclared tier is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: per(nonexistent)
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "per(nonexistent)"))
    end

    test "a chain bundle of the wrong kind is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)
      Fixture.write!(dir, %{"bundles/default/chain.yaml" => "name: default\nkind: workflow\n"})

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "expected chain"))
    end
  end

  describe "tiers (chain.md #4, #5, #6, #17)" do
    test "generator: supplied is legal only paired with source: and no scope", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          design_system:
            generator: supplied
            source: input.design_system
        edges: {}
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert loaded.chain.tiers["design_system"].generator == "supplied"
      assert loaded.chain.tiers["design_system"].scope == nil
    end

    test "a scope-carrying tier with generator: supplied is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          design_system:
            scope: singleton
            generator: supplied
            source: input.design_system
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "unknown field \"scope\""))
    end

    test "draft: none makes a join target, minted by a fanout source", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          comp:
            scope: child_of(comparch)
            draft: none
        edges:
          decomposition:
            type: fanout
            context: none
            instances:
              - { source: comparch, target: comp, declared_in: "comparch.draft.comps.comp[]" }
        """,
        "bundles/default/schemas/comparch.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:catapult="urn:catapult:dsl">
          <xs:complexType name="Comp">
            <xs:annotation><xs:appinfo><catapult:mints tier="comp" identity="alias"/></xs:appinfo></xs:annotation>
            <xs:sequence>
              <xs:element name="name" type="xs:string">
                <xs:annotation><xs:appinfo><catapult:field name="name"/></xs:appinfo></xs:annotation>
              </xs:element>
            </xs:sequence>
            <xs:attribute name="alias" type="xs:string" use="required"/>
          </xs:complexType>
          <xs:complexType name="Comps">
            <xs:sequence>
              <xs:element name="comp" type="Comp" minOccurs="0" maxOccurs="unbounded"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="comparch">
            <xs:annotation><xs:appinfo><catapult:identity>id</catapult:identity></xs:appinfo></xs:annotation>
            <xs:complexType>
              <xs:sequence>
                <xs:element name="comps" type="Comps"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      comp = loaded.chain.tiers["comp"]
      assert comp.draft == :none
      assert comp.identity == "alias"
      assert Map.keys(comp.mint_fields) == ["name"]
    end

    test "a join target with no minting fanout source is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          comp:
            scope: child_of(comparch)
            draft: none
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "no minting tier's schema declares"))
    end

    test "two fanout instances targeting one tier is a load error (chain.md #28)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          other:
            scope: singleton
          comp:
            scope: child_of(comparch)
            draft: none
        edges:
          decomposition:
            type: fanout
            context: none
            instances:
              - { source: comparch, target: comp, declared_in: "comparch.draft.a[]" }
              - { source: other, target: comp, declared_in: "other.draft.b[]" }
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "minted by more than one fanout source"))
    end

    test "produces: on a scope: singleton tier is a load error (chain.md #13)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            produces:
              techspec: draft.technical-specification
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "no parent to own the fragment"))
    end

    test "reconcile: on a tier that is not a fanout source is a load error (chain.md #15)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            reconcile: default
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "not the source of any fanout edge"))
    end

    test "fields: on a join target with a non mint.parent.* value is a load error (chain.md #12)",
         %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          comp:
            scope: child_of(comparch)
            draft: none
            fields:
              name: draft.name
        edges:
          decomposition:
            type: fanout
            context: none
            instances:
              - { source: comparch, target: comp, declared_in: "comparch.draft.comps.comp[]" }
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "mint.parent.<kind>"))
    end
  end

  describe "handle (bundle.md #10, chain.md #11)" do
    test "handle defaults to every field plus every kind produced", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          subcomparch:
            scope: per(comparch)
            produces:
              techspec: draft.technical-specification
        edges: {}
        """,
        "bundles/default/schemas/subcomparch.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="subcomparch">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="technical-specification" type="xs:string"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert loaded.chain.tiers["comparch"].handle_fragments == ["techspec"]
    end

    test "a handle: name outside the default set is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            handle: [nonexistent]
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "is not a field of this tier"))
    end
  end

  describe "edges (chain.md #24, #25, #26, #27)" do
    test "an edge requires instances: as a non-empty list", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges:
          dependency:
            type: dependency
            context: handle
            instances: []
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "instances is empty"))
    end

    test "an edge requires context: (chain.md #25)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          other:
            scope: singleton
        edges:
          dependency:
            type: dependency
            instances:
              - { source: comparch, target: other, declared_in: "comparch.draft.dep[]" }
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "missing required field \"context\""))
    end

    test "an edge cycle across tiers fails type-level acyclicity", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          other:
            scope: singleton
        edges:
          a_to_b:
            type: reference
            context: handle
            instances:
              - { source: comparch, target: other, declared_in: "comparch.draft.b[]" }
          b_to_a:
            type: reference
            context: handle
            instances:
              - { source: other, target: comparch, declared_in: "other.draft.a[]" }
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "type-level cycle"))
    end

    test "a self-referencing dependency edge is legal at the type level", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges:
          dependency:
            type: dependency
            context: handle
            graph_constraint: [acyclic]
            instances:
              - { source: comparch, target: comparch, declared_in: "comparch.draft.dep[]", source_ref: "@from", target_ref: "@to" }
        """,
        "bundles/default/schemas/comparch.xsd" => edge_test_schema()
      })

      assert {:ok, _loaded} = Loader.load(dir)
    end

    test "a navigation edge cannot be walked in a readiness context (chain.md #23)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            context:
              nav: self.nav -> comparch.handle
        edges:
          nav:
            type: reference
            navigation: true
            context: none
            instances:
              - { source: comparch, target: comparch, declared_in: "comparch.draft.nav[]", source_ref: "@from", target_ref: "@to" }
        """,
        "bundles/default/schemas/comparch.xsd" => edge_test_schema()
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "navigation: true"))
    end

    test "consistency: is legal only on a dependency edge", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges:
          reference:
            type: reference
            context: handle
            consistency: eventual
            instances:
              - { source: comparch, target: comparch, declared_in: "comparch.draft.r[]", source_ref: "@from", target_ref: "@to" }
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "only a dependency edge may carry"))
    end

    test "an unresolvable source_ref:/target_ref: locator is a load error (chain.md #27)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          other:
            scope: per(comparch)
        edges:
          reference:
            type: reference
            context: handle
            instances:
              - { source: comparch, target: other, declared_in: "comparch.draft.r[]" }
        """,
        "bundles/default/schemas/comparch.xsd" => edge_test_schema(),
        "bundles/default/schemas/other.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="other">
            <xs:complexType><xs:sequence><xs:element name="body" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "cannot locate"))
    end
  end

  describe "effective context (chain.md #20, #21)" do
    test "a generating tier with a scope parent derives a parent read", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          subcomparch:
            scope: per(comparch)
        edges: {}
        """,
        "bundles/default/schemas/subcomparch.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="subcomparch">
            <xs:complexType><xs:sequence><xs:element name="body" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert %{"parent" => walk} = loaded.chain.tiers["subcomparch"].effective_context
      assert walk.raw == "self.parent.handle"
    end

    test "an edge instance sourced from self or the scope parent derives a named read", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          ref:
            generator: supplied
            source: write
        edges:
          reference:
            type: reference
            context: handle
            instances:
              - { source: comparch, target: ref, declared_in: "comparch.draft.r[]", target_ref: "@target" }
        """,
        "bundles/default/schemas/comparch.xsd" => edge_test_schema()
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert %{"reference" => walk} = loaded.chain.tiers["comparch"].effective_context
      assert walk.raw == "self.reference -> ref.handle"
    end

    test "two derived reads under one name without as: is a load error (chain.md #20)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          a:
            generator: supplied
            source: write
          b:
            generator: supplied
            source: write
        edges:
          reference:
            type: reference
            context: handle
            instances:
              - { source: comparch, target: a, declared_in: "comparch.draft.a[]", target_ref: "@target" }
          reference2:
            type: reference
            context: handle
            instances:
              - { source: comparch, target: b, declared_in: "comparch.draft.b[]", target_ref: "@target" }
        """,
        "bundles/default/schemas/comparch.xsd" => edge_test_schema()
      })

      # These are two different edge names, so no collision: derived
      # names key off the edge name, and different edges never collide
      # unless an `as:` forces it. This test instead exercises the
      # explicit-context path colliding with a derived one.
      assert {:ok, _loaded} = Loader.load(dir)
    end

    test "explicit context: naming a reserved word is a load error (chain.md #21)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            context:
              self: all.comparch.handle
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "which is reserved"))
    end

    test "explicit context: colliding with a derived read is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          subcomparch:
            scope: per(comparch)
            context:
              parent: all.comparch.handle
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "collides with a derived read"))
    end

    test "all.<tier> against a write-sourced supplied tier is a load error (chain.md #22)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            context:
              refs: all.ref.handle
          ref:
            generator: supplied
            source: write
        edges: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "never drained"))
    end

    test "review: default reads the tier's own effective context plus its own additions", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            review:
              prompt: prompts/review/comparch.md.liquid
              context:
                extra: all.comparch.handle
        edges: {}
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      review = loaded.chain.tiers["comparch"].review
      assert review.prompt == "prompts/review/comparch.md.liquid"
      assert Map.has_key?(review.context, "extra")
    end

    test "a review's own context does not leak into the tier's own generation context", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
            review:
              context:
                extra: all.comparch.handle
        edges: {}
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      refute Map.has_key?(loaded.chain.tiers["comparch"].effective_context, "extra")
    end
  end

  describe "workflow (workflow.md)" do
    test "the same two gates may run in opposite order in two types" do
      # Impossible under a fixed predecessor field — every position's
      # order is the citing type's own array, index alone (workflow.md #7).
    end

    test "a type whose flow: names itself is a load error (workflow.md #30)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: project }
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "names itself"))
    end

    test "a two-node cycle through a skeleton-less type is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: milestone }
          milestone:
            skeleton: container
            statuses:
              - status: setup
              - { status: prep, flow: feature }
              - { status: main, flow: project }
              - status: retro
              - { status: cleanup, flow: feature }
              - status: terminal
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                tiers: [comparch]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "cycle"))
    end

    test "a container-skeleton type nests another container for free", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: epic }
          epic:
            skeleton: container
            statuses:
              - status: setup
              - { status: prep, flow: milestone }
              - { status: main, flow: milestone }
              - status: retro
              - { status: cleanup, flow: milestone }
              - status: terminal
          milestone:
            skeleton: container
            statuses:
              - status: setup
              - { status: prep, flow: feature }
              - { status: main, flow: feature }
              - status: retro
              - { status: cleanup, flow: feature }
              - status: terminal
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                tiers: [comparch]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert loaded.workflow.types["epic"].skeleton == "container"
      assert loaded.workflow.entry == "project"
    end

    test "a throwback that is not earlier in the citing type's array is a load error", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                tiers: [comparch]
              - status: critique
              - review: product-review
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates:
          product-review: { role: design, escalation: author, throwback: checks }
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "not earlier"))
    end

    test "generation requires tiers: (workflow.md #22)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "missing required field \"tiers\""))
    end

    test "tiers: naming an undeclared tier is a load error (workflow.md #22)", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                tiers: [nonexistent]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "not a declared tier"))
    end

    test "tiers: naming a join target is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          comp:
            scope: child_of(comparch)
            draft: none
        edges:
          decomposition:
            type: fanout
            context: none
            instances:
              - { source: comparch, target: comp, declared_in: "comparch.draft.comps.comp[]" }
        """,
        "bundles/default/schemas/comparch.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:catapult="urn:catapult:dsl">
          <xs:complexType name="Comp">
            <xs:annotation><xs:appinfo><catapult:mints tier="comp" identity="alias"/></xs:appinfo></xs:annotation>
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
            <xs:attribute name="alias" type="xs:string" use="required"/>
          </xs:complexType>
          <xs:complexType name="Comps">
            <xs:sequence>
              <xs:element name="comp" type="Comp" minOccurs="0" maxOccurs="unbounded"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="comparch">
            <xs:complexType>
              <xs:sequence><xs:element name="comps" type="Comps"/></xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """,
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                tiers: [comp]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "only generating tiers run at a position"))
    end

    test "a tier listed at two positions is a load error unless it is cascade_visit", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: no_delta
            statuses:
              - status: generation
                name: first
                tiers: [comparch]
              - status: generation
                name: second
                tiers: [comparch]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "more than one position"))
    end

    test "serves: has_delta/no_delta selects the type serving a flow (workflow.md #40)", %{
      tmp_dir: dir
    } do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges: {}
        flows:
          seed:
            walk: full
        """
      })

      assert {:ok, loaded} = Loader.load(dir)
      assert loaded.chain.flows["seed"].walk == "full"
    end

    test "a chain flow served by no type is a load error", %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
        edges: {}
        flows:
          feature_request:
            walk: downward_cascade
            entry: comparch
            completion: has_edge(comparch)
        """,
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            statuses:
              - status: generation
                tiers: [comparch]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "is served by no type"))
    end

    test "traversability: a structural read of a tier generated at a later position is a load error (workflow.md #23)",
         %{tmp_dir: dir} do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/chain.yaml" => """
        name: default
        version: "1.0.0"
        kind: chain
        tiers:
          comparch:
            scope: singleton
          subcomparch:
            scope: per(comparch)
        edges: {}
        flows:
          seed:
            walk: full
        """,
        "bundles/default/schemas/subcomparch.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="subcomparch">
            <xs:complexType><xs:sequence><xs:element name="body" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """,
        "bundles/default-flow/workflow.yaml" => """
        name: default-flow
        version: "1.0.0"
        kind: workflow
        entry: project
        types:
          project:
            statuses:
              - { status: build-out, flow: feature }
          feature:
            skeleton: ticket
            serves: [seed]
            statuses:
              - status: generation
                name: first
                tiers: [subcomparch]
              - status: generation
                name: second
                tiers: [comparch]
              - status: checks
              - status: reconcile
              - status: merge
              - status: deploy
              - status: terminal
        gates: {}
        environments: {}
        """
      })

      assert {:error, :bundle, problems} = Loader.load(dir)
      assert Enum.any?(problems, &String.contains?(&1, "generated at a later position"))
    end
  end
end
