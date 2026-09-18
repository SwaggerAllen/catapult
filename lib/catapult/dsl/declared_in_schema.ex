defmodule Catapult.Dsl.DeclaredInSchema do
  @moduledoc """
  Cross-checks a `declared_in` path's element and attribute segments
  against the schema of the tier its own **leading segment** names
  (`chain.md` #32, `systems/core_dsl.md`'s ORC-232 entry) —
  `Catapult.Dsl.Chain`'s existing cross-reference pass never opened a
  schema file, so a segment spelled wrong against its own tier's XSD
  loaded silently and minted or resolved nothing at runtime (ORC-232:
  six wrong segments across nine `declared_in` instances, every one
  mismatched by an underscore standing where the schema hyphenates).

  Walks the same way `Catapult.Generation.Extraction.descend/2` walks a
  committed body — a segment is looked up by exact string equality,
  with a trailing `[]` trimmed first — except the tree walked here is
  the tier's XSD content model rather than a parsed draft. A
  `type="Name"` reference into a complexType declared elsewhere **in
  that same schema file** is followed exactly like an inline content
  model: this bundle factors nearly every multi-segment path's second
  level and beyond into a named complexType rather than inlining it, so
  a same-file `type=` reference is the ordinary shape here, not an
  exotic one.

  **Two outcomes, not one.** A segment the walk positively resolves —
  inline or through a same-file `type=` reference — and finds absent
  from the schema is a load error. A segment the walk cannot resolve at
  all is not: the leading segment names no declared tier, or a tier
  with no `draft:` of its own to check a path against; the tier's
  `grammar:` file does not exist; or the schema reaches the segment
  through a construct this walk does not model (`xs:group`,
  `xs:attributeGroup`, `xs:any`, an `xs:complexContent`/
  `xs:simpleContent` extension or restriction, or a type this schema
  file doesn't itself declare — an import, most likely). Blocking the
  load over an unresolvable segment would make this walk's own
  coverage gap the bundle author's problem, so it passes through
  unverified instead. A `declared_in` value that never reaches
  `<tier>.draft.<rest>` at all — the `policy_application` edge's
  mint-time `policy.structural`/`policy.required`, the `plan_target`
  edge's `<plan-tier>.cascade_target` — is the same kind of
  unresolvable, and is never walked; the schema has nothing to say
  about a field set at mint time rather than read from a draft body.
  """

  alias Catapult.Dsl.BundlePath

  @doc """
  Every `declared_in`/schema mismatch across every instance of every
  edge in `edges`, as a load-problem string. `dir` is the bundle's own
  directory (`Catapult.Dsl.Chain.load/3`'s `dir`), the same root a
  `draft.grammar` path is resolved against at commit time.
  """
  @spec problems(String.t(), %{String.t() => Catapult.Dsl.Tier.t()}, %{
          String.t() => Catapult.Dsl.Edge.t()
        }) :: [String.t()]
  def problems(dir, tiers, edges) do
    for {edge_name, edge} <- edges,
        instance <- edge.instances,
        problem <- instance_problems(dir, tiers, edge_name, instance) do
      problem
    end
  end

  @doc """
  Every `produces:` draft-path source's segments, checked against the
  *declaring* tier's own schema (`chain.md` #13, #32) — a fragment kind
  spelled wrong against its own tier's schema is the same silent-nil
  failure mode a wrong `declared_in` segment already was (ORC-232).
  `fields:` carries no schema path any more (`chain.md` #12: a join
  target's `fields:` names only `mint.parent.<kind>`, which is a
  cross-tier lookup `Catapult.Dsl.Chain`'s own `mint_parent_problems/2`
  checks, not a schema path).
  """
  @spec field_problems(String.t(), %{String.t() => Catapult.Dsl.Tier.t()}) :: [String.t()]
  def field_problems(dir, tiers) do
    for {tier_name, %{draft: %{grammar: grammar}, produces: produces}} <- tiers,
        %{kind: kind, draft_path: "draft." <> path} <- produces,
        problem <- path_problem(dir, grammar, path, tier_name, "produces", kind) do
      problem
    end
  end

  @doc """
  Every explicit `source_ref:`/`target_ref:` `@<attr>` locator's
  attribute, checked against the schema of whichever tier's draft
  `declared_in` resolves against (`chain.md` #29, ORC-236) —
  the identical cross-validation the block above runs for `declared_in`
  itself, now also run for the attribute name an explicit ref reads off
  that same terminal element. `self`/`self.parent`/`fanout(<edge>)`
  locators are structural, not schema paths, and are not this check's;
  `Catapult.Dsl.Chain`'s own locator-form check is what rejects
  anything that isn't one of those three or an `@<attr>` path.
  """
  @spec ref_problems(String.t(), %{String.t() => Catapult.Dsl.Tier.t()}, %{
          String.t() => Catapult.Dsl.Edge.t()
        }) :: [String.t()]
  def ref_problems(dir, tiers, edges) do
    for {edge_name, edge} <- edges,
        edge.type in ["reference", "dependency"],
        instance <- edge.instances,
        {label, attr} <- explicit_ref_attrs(instance),
        problem <- ref_attr_problem(dir, tiers, edge_name, instance.declared_in, label, attr) do
      problem
    end
  end

  defp explicit_ref_attrs(instance) do
    [
      {"source_ref", Map.get(instance, :source_ref)},
      {"target_ref", Map.get(instance, :target_ref)}
    ]
    |> Enum.flat_map(fn
      {label, "@" <> attr} when attr != "" -> [{label, attr}]
      _other -> []
    end)
  end

  defp ref_attr_problem(dir, tiers, edge_name, declared_in, label, attr) do
    with {:ok, tier_name, segments, _declared_attr} <- parse_path(declared_in),
         {:ok, grammar} <- tier_grammar(tiers, tier_name),
         {:ok, schema_path} <- resolve_grammar(dir, grammar),
         {:ok, schema} <- parse_schema(schema_path) do
      case walk(schema, segments, attr) do
        :ok ->
          []

        {:not_found, kind, name} ->
          [
            "edge #{inspect(edge_name)}'s instance's #{label} #{inspect("@" <> attr)} names " <>
              "#{kind} #{inspect(name)}, which tier #{inspect(tier_name)}'s schema (#{grammar}) " <>
              "does not declare"
          ]

        :unresolvable ->
          []
      end
    else
      _other -> []
    end
  end

  defp path_problem(dir, grammar, path, tier_name, label, name) do
    segments = String.split(path, ".")
    {element_segments, attr} = split_attr(segments)

    with {:ok, schema_path} <- resolve_grammar(dir, grammar),
         {:ok, schema} <- parse_schema(schema_path) do
      case walk(schema, Enum.map(element_segments, &repeat_tag/1), attr) do
        :ok ->
          []

        {:not_found, kind, found_name} ->
          [
            "tier #{inspect(tier_name)}'s #{label} #{inspect(name)} names #{kind} " <>
              "#{inspect(found_name)}, which its own schema (#{grammar}) does not declare"
          ]

        :unresolvable ->
          []
      end
    else
      _other -> []
    end
  end

  defp instance_problems(dir, tiers, edge_name, %{declared_in: declared_in} = _instance) do
    with {:ok, tier_name, segments, attr} <- parse_path(declared_in),
         {:ok, grammar} <- tier_grammar(tiers, tier_name),
         {:ok, schema_path} <- resolve_grammar(dir, grammar),
         {:ok, schema} <- parse_schema(schema_path) do
      case walk(schema, segments, attr) do
        :ok ->
          []

        {:not_found, kind, name} ->
          [
            "edge #{inspect(edge_name)}'s declared_in #{inspect(declared_in)} names #{kind} " <>
              "#{inspect(name)}, which tier #{inspect(tier_name)}'s schema (#{grammar}) " <>
              "does not declare"
          ]

        :unresolvable ->
          []
      end
    else
      _other -> []
    end
  end

  ## -- declared_in path parsing (mirrors Extraction's own) -----------------

  # "<tier>.draft.<rest>" -> {:ok, tier, element_segments, attr_or_nil}.
  # `tier` here is whichever tier the *path* names, not necessarily the
  # citing edge instance's `source` — a join-target tier with no
  # `draft:` of its own (`fulfills.yaml`'s `screen_coll -> screen`, e.g.)
  # has its relationship declared inside whichever tier's draft mints or
  # names it, and that tier is the path's leading segment.
  defp parse_path(declared_in) do
    case String.split(declared_in, ".") do
      [tier_name, "draft" | rest] when rest != [] ->
        {raw_segments, attr} = split_attr(rest)
        {:ok, tier_name, Enum.map(raw_segments, &repeat_tag/1), attr}

      _other ->
        :error
    end
  end

  defp split_attr(segments) do
    case List.pop_at(segments, -1) do
      {"@" <> attr, rest} when attr != "" -> {rest, attr}
      _other -> {segments, nil}
    end
  end

  defp repeat_tag(segment), do: String.trim_trailing(segment, "[]")

  defp tier_grammar(tiers, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, %{draft: %{grammar: grammar}}} -> {:ok, grammar}
      _other -> :error
    end
  end

  defp resolve_grammar(dir, grammar) do
    case BundlePath.resolve(dir, grammar) do
      nil -> :error
      path -> {:ok, path}
    end
  end

  ## -- XSD parsing -----------------------------------------------------------

  # Comments are stripped before scanning: this bundle's schemas carry
  # prose comments with characters (em dashes, curly quotes) that
  # `:xmerl_scan`'s comment handling rejects outright even though
  # they're legal XML — a scan of the structure has no use for comment
  # text anyway.
  defp parse_schema(path) do
    content = path |> File.read!() |> strip_comments()
    {root_el, _rest} = :xmerl_scan.string(String.to_charlist(content))
    top_level = element_children(root_el)

    named_types =
      for el <- top_level,
          xsd_tag(el) == "complexType",
          name = xsd_attr(el, "name"),
          not is_nil(name),
          into: %{},
          do: {name, el}

    simple_types =
      for el <- top_level,
          xsd_tag(el) == "simpleType",
          name = xsd_attr(el, "name"),
          not is_nil(name),
          into: MapSet.new(),
          do: name

    case Enum.find(top_level, &(xsd_tag(&1) == "element")) do
      nil -> :error
      root -> {:ok, %{root: root, named_types: named_types, simple_types: simple_types}}
    end
  rescue
    _error -> :error
  catch
    _kind, _reason -> :error
  end

  defp strip_comments(xml), do: Regex.replace(~r/<!--.*?-->/s, xml, "")

  ## -- content-model walk ----------------------------------------------------

  defp walk(schema, segments, attr) do
    case element_content(schema.root, schema) do
      :unresolvable -> :unresolvable
      {:ok, model} -> walk_segments(model, schema, segments, attr)
    end
  end

  defp walk_segments(_model, _schema, [], nil), do: :ok

  defp walk_segments(model, _schema, [], attr) do
    if MapSet.member?(model.attributes, attr) do
      :ok
    else
      {:not_found, "attribute", attr}
    end
  end

  defp walk_segments(model, schema, [segment | rest], attr) do
    case Map.fetch(model.elements, segment) do
      :error ->
        {:not_found, "element", segment}

      {:ok, el} ->
        case element_content(el, schema) do
          :unresolvable -> :unresolvable
          {:ok, next_model} -> walk_segments(next_model, schema, rest, attr)
        end
    end
  end

  # The content model reached by one `<xs:element>` node: its own
  # inline `<xs:complexType>`, or the type its `type=` names — a
  # builtin `xs:*`, this file's own named simpleType, or this file's
  # own named complexType. A `type=` this file declares neither as a
  # builtin nor as a named type of either kind is unresolvable rather
  # than absent — most likely a type this schema imports rather than
  # declares, which this walk was never meant to follow.
  defp element_content(el, schema) do
    case xsd_attr(el, "type") do
      nil ->
        case Enum.find(element_children(el), &(xsd_tag(&1) == "complexType")) do
          nil -> {:ok, leaf()}
          complex_type -> resolve_complex_type(complex_type)
        end

      "xs:" <> _builtin ->
        {:ok, leaf()}

      type_name ->
        cond do
          MapSet.member?(schema.simple_types, type_name) ->
            {:ok, leaf()}

          Map.has_key?(schema.named_types, type_name) ->
            resolve_complex_type(Map.fetch!(schema.named_types, type_name))

          true ->
            :unresolvable
        end
    end
  end

  defp leaf, do: %{elements: %{}, attributes: MapSet.new()}

  # `xs:simpleContent`/`xs:complexContent` (an extension or restriction
  # of another type) is exactly the "construct this walk does not
  # model" case named in the moduledoc — `impl.xsd`'s `Test` type is
  # this bundle's one instance of it.
  defp resolve_complex_type(complex_type_el) do
    children = element_children(complex_type_el)

    if Enum.any?(children, &(xsd_tag(&1) in ["simpleContent", "complexContent"])) do
      :unresolvable
    else
      case collect_elements(children) do
        :unresolvable -> :unresolvable
        {:ok, elements} -> {:ok, %{elements: elements, attributes: collect_attributes(children)}}
      end
    end
  end

  defp collect_attributes(children) do
    for el <- children,
        xsd_tag(el) == "attribute",
        name = xsd_attr(el, "name"),
        not is_nil(name),
        into: MapSet.new(),
        do: name
  end

  # Collects every `<xs:element>` reachable through this complexType's
  # own particle tree (`xs:sequence`/`xs:choice`/`xs:all`, arbitrarily
  # nested) without recursing into a found element's own inline
  # complexType — that inline type belongs to that one element, resolved
  # separately once the walk actually descends into it.
  defp collect_elements(nodes) do
    Enum.reduce_while(nodes, {:ok, %{}}, fn node, {:ok, acc} ->
      case collect_node(node, acc) do
        :unresolvable -> {:halt, :unresolvable}
        {:ok, acc} -> {:cont, {:ok, acc}}
      end
    end)
  end

  defp collect_node(node, acc) do
    case xsd_tag(node) do
      "element" -> {:ok, put_named_element(acc, node)}
      particle when particle in ["sequence", "choice", "all"] -> merge_nested(acc, node)
      unmodeled when unmodeled in ["group", "any", "attributeGroup"] -> :unresolvable
      _other -> {:ok, acc}
    end
  end

  defp put_named_element(acc, node) do
    case xsd_attr(node, "name") do
      nil -> acc
      name -> Map.put(acc, name, node)
    end
  end

  defp merge_nested(acc, node) do
    case collect_elements(element_children(node)) do
      :unresolvable -> :unresolvable
      {:ok, nested} -> {:ok, Map.merge(acc, nested)}
    end
  end

  ## -- xmerl helpers -----------------------------------------------------
  ##
  ## Namespace-unaware by construction: every schema under
  ## bundles/default/schemas/** binds the XSD namespace to the `xs:`
  ## prefix (checked against all twenty-two), so this walk matches that
  ## literal prefix rather than resolving namespaces generically.

  defp element_children(el) do
    for {:xmlElement, _, _, _, _, _, _, _, _, _, _, _} = child <- xml_content(el), do: child
  end

  defp xml_content({:xmlElement, _, _, _, _, _, _, _, content, _, _, _}), do: content

  defp xsd_tag({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}) do
    name |> to_string() |> String.replace_prefix("xs:", "")
  end

  defp xsd_attr({:xmlElement, _, _, _, _, _, _, attrs, _, _, _, _}, attr_name) do
    Enum.find_value(attrs, fn {:xmlAttribute, name, _, _, _, _, _, _, value, _} ->
      if to_string(name) == attr_name, do: to_string(value)
    end)
  end

  ## -- schema annotations (`chain.md` #32) --------------------------------
  ##
  ## `<catapult:mints tier="X" identity="Y"/>` on an element or the
  ## complexType it resolves to says the element mints tier X, whose
  ## identity is attribute Y; `<catapult:field name="Z"/>` makes an
  ## element or attribute a field of the node it belongs to;
  ## `<catapult:identity>id</catapult:identity>` on a generating tier's
  ## own root element says the same for that tier. `xsd_tag/1` already
  ## passes an unrecognized prefix through unchanged, so `catapult:*`
  ## tags compare exactly like the `xs:*` ones above.

  @doc """
  A generating tier's own identity attribute and field map, plus every
  tier its draft mints along the way — `%{identity:, own_fields:,
  mints: %{tier_name => %{identity:, fields: %{}}}}` — read straight
  off `tier`'s schema. Each `fields:` map is `field_name => schema_tag`
  rather than a bare name list: a field's declared name and the
  element or attribute that actually carries it can differ (`foundation`
  carries the `is_foundation` field), so extraction at commit time
  (`Catapult.Generation.Extraction`) has to navigate the body by the
  schema's own tag, never by the field's name. `{:error, reason}` when
  the schema cannot be read; every field/mint this walk cannot resolve
  (an `xs:any`, an import, a `simpleContent`/`complexContent`
  extension) is silently absent rather than blocking the load, the
  same "unresolvable, not absent" split `problems/3` draws.
  """
  @spec mints_and_fields(String.t(), Catapult.Dsl.Tier.t()) ::
          {:ok,
           %{
             identity: String.t() | nil,
             own_fields: %{String.t() => String.t()},
             mints: %{
               String.t() => %{identity: String.t() | nil, fields: %{String.t() => String.t()}}
             }
           }}
          | {:error, String.t()}
  def mints_and_fields(dir, %{draft: %{grammar: grammar}}) do
    with {:ok, schema_path} <- resolve_grammar(dir, grammar),
         {:ok, schema} <- parse_schema(schema_path) do
      identity = own_identity(schema.root, schema)
      {own_fields, mints} = scan_content(schema.root, schema)
      {:ok, %{identity: identity, own_fields: own_fields, mints: mints}}
    else
      _other -> {:error, "schema #{grammar} could not be read"}
    end
  end

  def mints_and_fields(_dir, _tier), do: {:error, "tier has no draft: to read a schema for"}

  # The children reachable from `el`'s own content model (its inline
  # complexType, or the named complexType/simpleType its `type=`
  # resolves to) — `:leaf` for a builtin/simple type or anything this
  # walk cannot resolve, exactly like `element_content/2` above, except
  # this returns the raw node rather than the name/attribute-only model
  # `walk_segments/4` needs, since an annotation lives on the node.
  defp resolved_type_node(el, schema) do
    case xsd_attr(el, "type") do
      nil ->
        case Enum.find(element_children(el), &(xsd_tag(&1) == "complexType")) do
          nil -> :leaf
          complex_type -> {:ok, complex_type}
        end

      "xs:" <> _builtin ->
        :leaf

      type_name ->
        cond do
          MapSet.member?(schema.simple_types, type_name) ->
            :leaf

          Map.has_key?(schema.named_types, type_name) ->
            {:ok, Map.fetch!(schema.named_types, type_name)}

          true ->
            :leaf
        end
    end
  end

  defp scan_content(el, schema) do
    case resolved_type_node(el, schema) do
      :leaf -> {%{}, %{}}
      {:ok, type_node} -> scan_children(element_children(type_node), schema)
    end
  end

  defp scan_children(children, schema) do
    Enum.reduce(children, {%{}, %{}}, fn child, {fields, mints} ->
      case xsd_tag(child) do
        particle when particle in ["sequence", "choice", "all"] ->
          {more_fields, more_mints} = scan_children(element_children(child), schema)
          {Map.merge(fields, more_fields), Map.merge(mints, more_mints)}

        "element" ->
          scan_element(child, schema, fields, mints)

        # An attribute is a leaf — it has no content model of its own
        # to descend into, only its own possible `<catapult:field>`.
        "attribute" ->
          scan_attribute(child, fields, mints)

        _other ->
          {fields, mints}
      end
    end)
  end

  defp scan_attribute(child, fields, mints) do
    case field_annotation(child) do
      nil -> {fields, mints}
      name -> {Map.put(fields, name, xsd_attr(child, "name")), mints}
    end
  end

  defp scan_element(el, schema, fields, mints) do
    case mints_annotation(el, schema) do
      {tier, identity} ->
        {child_fields, child_mints} = scan_content(el, schema)
        entry = %{identity: identity, fields: child_fields}
        {fields, mints |> Map.put(tier, entry) |> Map.merge(child_mints)}

      nil ->
        {more_fields, more_mints} = scan_content(el, schema)

        fields =
          case field_annotation(el) do
            nil -> fields
            name -> Map.put(fields, name, xsd_attr(el, "name"))
          end

        {Map.merge(fields, more_fields), Map.merge(mints, more_mints)}
    end
  end

  defp mints_annotation(el, schema) do
    own_mints(el) ||
      case resolved_type_node(el, schema) do
        {:ok, type_node} -> own_mints(type_node)
        :leaf -> nil
      end
  end

  defp own_identity(el, schema) do
    own_identity_text(el) ||
      case resolved_type_node(el, schema) do
        {:ok, type_node} -> own_identity_text(type_node)
        :leaf -> nil
      end
  end

  defp own_mints(el) do
    case Enum.find(appinfo_children(el), &(xsd_tag(&1) == "catapult:mints")) do
      nil -> nil
      node -> {xsd_attr(node, "tier"), xsd_attr(node, "identity")}
    end
  end

  defp field_annotation(el) do
    case Enum.find(appinfo_children(el), &(xsd_tag(&1) == "catapult:field")) do
      nil -> nil
      node -> xsd_attr(node, "name")
    end
  end

  defp own_identity_text(el) do
    case Enum.find(appinfo_children(el), &(xsd_tag(&1) == "catapult:identity")) do
      nil -> nil
      node -> element_text(node)
    end
  end

  defp appinfo_children(el) do
    el
    |> element_children()
    |> Enum.filter(&(xsd_tag(&1) == "annotation"))
    |> Enum.flat_map(&element_children/1)
    |> Enum.filter(&(xsd_tag(&1) == "appinfo"))
    |> Enum.flat_map(&element_children/1)
  end

  defp element_text(el) do
    el
    |> xml_content()
    |> Enum.filter(&match?({:xmlText, _, _, _, _, _}, &1))
    |> Enum.map_join("", fn {:xmlText, _, _, _, value, _} -> List.to_string(value) end)
    |> String.trim()
  end
end
