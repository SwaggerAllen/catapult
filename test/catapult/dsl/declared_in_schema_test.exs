defmodule Catapult.Dsl.DeclaredInSchemaTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Fixture
  alias Catapult.Dsl.Loader

  @moduletag :tmp_dir

  # A minimal comparch-shaped schema: <comparch><widgets><widget/></widgets>
  # <primitives><thing type="Thing"/></primitives></comparch>, "Thing" a
  # named complexType carrying one attribute — enough surface to exercise
  # a same-file `type=` reference and an attribute check without pulling
  # in the real bundle's own schemas.
  @schema """
  <?xml version="1.0" encoding="UTF-8"?>
  <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
    <xs:complexType name="Widgets">
      <xs:sequence>
        <xs:element name="widget" minOccurs="0" maxOccurs="unbounded">
          <xs:complexType>
            <xs:attribute name="from" type="xs:string"/>
            <xs:attribute name="to" type="xs:string"/>
          </xs:complexType>
        </xs:element>
      </xs:sequence>
    </xs:complexType>
    <xs:complexType name="Thing">
      <xs:attribute name="ref" type="xs:string" use="required"/>
    </xs:complexType>
    <xs:complexType name="Primitives">
      <xs:sequence>
        <xs:element name="thing" type="Thing" minOccurs="0"/>
      </xs:sequence>
    </xs:complexType>
    <xs:complexType name="Grown">
      <xs:simpleContent>
        <xs:extension base="xs:string">
          <xs:attribute name="tag" type="xs:string"/>
        </xs:extension>
      </xs:simpleContent>
    </xs:complexType>
    <xs:element name="comparch">
      <xs:complexType>
        <xs:sequence>
          <xs:element name="name" type="xs:string" minOccurs="0"/>
          <xs:element name="widgets" type="Widgets"/>
          <xs:element name="primitives" type="Primitives"/>
          <xs:element name="grown" type="Grown"/>
        </xs:sequence>
      </xs:complexType>
    </xs:element>
  </xs:schema>
  """

  defp write_bundle!(dir, edge_yaml) do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/schemas/comparch.xsd" => @schema,
      "bundles/default/chain.yaml" => """
      name: default
      version: "1.0.0"
      kind: chain
      tiers:
        comparch:
          scope: singleton
      edges:
      #{edge_yaml}
      """
    })
  end

  defp indent(yaml) do
    yaml
    |> String.split("\n")
    |> Enum.map_join("\n", &("  " <> &1))
  end

  test "a declared_in path whose segments all match the schema loads clean", %{tmp_dir: dir} do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: fanout
        context: none
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.draft.widgets.widget[]" }
      """)
    )

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a wrong element segment is a load error naming the edge, instance and segment", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: fanout
        context: none
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.draft.widgetz.widget[]" }
      """)
    )

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(problems, fn p ->
             String.contains?(p, inspect("probe")) and
               String.contains?(p, inspect("comparch.draft.widgetz.widget[]")) and
               String.contains?(p, inspect("widgetz"))
           end)
  end

  test "a segment reached through a same-file type= reference resolves", %{tmp_dir: dir} do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: reference
        context: handle
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.draft.primitives.thing.@ref" }
      """)
    )

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a wrong attribute segment behind a same-file type= reference is a load error", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: reference
        context: handle
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.draft.primitives.thing.@target" }
      """)
    )

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(problems, fn p ->
             String.contains?(p, "attribute") and String.contains?(p, inspect("target"))
           end)
  end

  test "a segment behind xs:simpleContent/xs:extension is unresolvable, not an error", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: reference
        context: handle
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.draft.grown.@tag" }
      """)
    )

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a declared_in whose leading tier is undeclared is unresolvable, not an error", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: reference
        context: handle
        instances:
          - { source: comparch, target: comparch, declared_in: "nonexistent_tier.draft.widgets.widget[]", source_ref: "@from", target_ref: "@to" }
      """)
    )

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a mint-time declared_in with no draft segment at all is unresolvable, not an error", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: policy_application
        context: none
        instances:
          - { source: comparch, target: comparch, declared_in: "comparch.structural" }
      """)
    )

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "the leading tier checked is the path's own, not the citing instance's source", %{
    tmp_dir: dir
  } do
    write_bundle!(
      dir,
      indent("""
      probe:
        type: reference
        context: handle
        instances:
          - { source: other, target: comparch, declared_in: "comparch.draft.widgets.widgetz[]", target_ref: "@to" }
      """)
    )

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
        probe:
          type: reference
          context: handle
          instances:
            - { source: other, target: comparch, declared_in: "comparch.draft.widgets.widgetz[]", target_ref: "@to" }
      """,
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
    assert Enum.any?(problems, &String.contains?(&1, inspect("widgetz")))
  end

  describe "explicit source_ref:/target_ref: @<attr> locators" do
    defp write_dependency_bundle!(dir, source_ref, target_ref) do
      Fixture.minimal!(dir)

      Fixture.write!(dir, %{
        "bundles/default/schemas/comparch.xsd" => @schema,
        "bundles/default/schemas/other.xsd" => """
        <?xml version="1.0" encoding="UTF-8"?>
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="other">
            <xs:complexType><xs:sequence><xs:element name="body" type="xs:string"/></xs:sequence></xs:complexType>
          </xs:element>
        </xs:schema>
        """,
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
          probe:
            type: dependency
            context: handle
            instances:
              - { source: other, target: other, declared_in: "comparch.draft.widgets.widget[]", source_ref: "#{source_ref}", target_ref: "#{target_ref}" }
        """
      })
    end

    test "an explicit ref's attribute that matches the schema loads clean", %{tmp_dir: dir} do
      write_dependency_bundle!(dir, "@from", "@to")

      assert {:ok, _loaded} = Loader.load(dir)
    end

    test "an explicit ref's attribute the schema does not declare is a load error naming the ref and the attribute",
         %{tmp_dir: dir} do
      write_dependency_bundle!(dir, "@from", "@nope")

      assert {:error, :bundle, problems} = Loader.load(dir)

      assert Enum.any?(problems, fn p ->
               String.contains?(p, "target_ref") and String.contains?(p, inspect("@nope"))
             end)
    end

    test "a source_ref/target_ref that isn't self, self.parent, fanout(<edge>) or an @<attr> path is a load error",
         %{tmp_dir: dir} do
      write_dependency_bundle!(dir, "@from", "widgets.widget")

      assert {:error, :bundle, problems} = Loader.load(dir)

      assert Enum.any?(problems, fn p ->
               String.contains?(p, "target_ref") and
                 String.contains?(p, inspect("widgets.widget")) and
                 String.contains?(p, "not a recognized locator")
             end)
    end
  end
end
