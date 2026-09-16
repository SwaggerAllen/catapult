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
  `<tier>.draft.<rest>` at all — `edges/policy_application.yaml`'s
  mint-time `policy.structural`/`policy.required`, `edges/
  plan_target.yaml`'s `<plan-tier>.cascade_target` — is the same kind
  of unresolvable, and is never walked; the schema has nothing to say
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
  Every `fields:`/`produces:` `"draft." <> path` source's segments,
  checked against the *declaring* tier's own schema — the identical
  widening `systems/core_dsl.md`'s ORC-236 entry describes: a
  `mint.parent.<name>` field reads a committing tier's own already-
  computed `fields:`/`produces:` value by name, so a segment spelled
  wrong against that tier's own schema is exactly the same silent-nil
  failure mode a wrong `declared_in` segment already was (ORC-232).
  """
  @spec field_problems(String.t(), %{String.t() => Catapult.Dsl.Tier.t()}) :: [String.t()]
  def field_problems(dir, tiers) do
    for {tier_name, %{draft: %{grammar: grammar}} = tier} <- tiers,
        {label, name, "draft." <> path} <- field_and_produces_sources(tier),
        problem <- path_problem(dir, grammar, path, tier_name, label, name) do
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

  defp field_and_produces_sources(%{fields: fields, produces: produces}) do
    Enum.map(fields, fn {name, source} -> {"fields", name, source} end) ++
      Enum.map(produces, fn %{kind: kind, authored: authored} -> {"produces", kind, authored} end)
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
end
