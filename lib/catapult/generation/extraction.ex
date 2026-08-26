defmodule Catapult.Generation.Extraction do
  @moduledoc """
  Reads `fields:`, `produces:` and self-sourced `declared_in`
  instances out of a validated draft body (dsl-syntax.md §3, §4) —
  the extraction `Catapult.Engine.Events.DraftCommitted`'s own
  moduledoc places "at the command edge... never inside the reducer."
  This is that command edge's structural half, over the xmerl tree
  `Catapult.Dsl.Grammar` already parsed and validated.

  **Scope, stated rather than discovered later.** `declared_in` paths
  whose leading tier differs from the tier being committed (a
  `dependency`/`policy_application` edge declared from a *third*
  tier's draft, e.g. `sysarch.draft.dependencies.dep[]` naming a
  `comp`-to-`comp` edge) need per-edge-type knowledge of that
  instance element's own shape (which child names source vs. target)
  that the generic navigator below cannot safely infer, and are not
  extracted here — a bundle relying on one commits its fanout/
  reference edges correctly and simply carries no `dependency`/
  `policy_application` instances yet. `type: fanout` (self-sourced,
  the minted element itself is the value) and `type: reference`
  (self-sourced, a trailing `.@attr` names the target directly) are
  both fully self-sourced and fully supported. Neither gap is a
  regression: no command edge existed before this ticket to extract
  any of it (`systems/engine.md`'s own "no command edge has landed
  yet").
  """

  @type element :: tuple()

  @doc "The text (including any nested markup, reconstructed) under `element`'s child named `tag`, or `nil`."
  @spec text(element(), String.t()) :: String.t() | nil
  def text(element, tag), do: navigate_single(element, String.split(tag, "."))

  @doc "`element`'s own serialized content (its text and any nested markup), with no further descent."
  @spec own_text(element()) :: String.t()
  def own_text(element), do: serialize(content(element))

  @doc "The attribute `name` on `element`, or `nil`."
  @spec attribute(element(), String.t()) :: String.t() | nil
  def attribute(element, name) do
    element
    |> attributes()
    |> Enum.find_value(fn attr ->
      if to_string(attribute_name(attr)) == name, do: to_string(attribute_value(attr))
    end)
  end

  @doc """
  Scalar `fields:` values, keyed as declared: each `"draft.<path>"`
  source resolves against `element` with the leading `"draft"`
  stripped; any other source (`"mint.<name>"` — join-target tiers,
  out of scope here, see moduledoc) is skipped.
  """
  @spec fields(element(), %{String.t() => String.t()}) :: map()
  def fields(element, field_sources) do
    for {name, "draft." <> path} <- field_sources, into: %{} do
      {name, navigate_single(element, String.split(path, "."))}
    end
  end

  # Walks single (non-repeating) dotted segments to a final element and
  # returns its serialized content, or `nil` anywhere the walk misses.
  defp navigate_single(element, segments) do
    case Enum.reduce_while(segments, element, &descend/2) do
      nil -> nil
      found -> serialize(content(found))
    end
  end

  @doc """
  Fanout mints declared self-sourced from `element` (the tier being
  committed): every `declared_in` instance across `edges` whose path's
  leading tier is `tier_name` and whose type is `:fanout`. Each
  matched element becomes one mint entry; `scope_key` is `%{"id" =>
  value}` where `value` is the instance element's own identity-shaped
  child (matching the target tier's `identity:` field name) — the
  `mint.<name>` field values themselves are not extracted (out of
  scope, see moduledoc: no synthesis-generator commit path exists to
  consume them yet). `status` is `:approved` when the target tier
  declares no `draft:` block (a join-target tier, dsl-syntax.md §3 —
  it has no commit path of its own to ever move it off whatever this
  writes, `systems/engine.md`'s ORC-117 entry) and `:absent`
  otherwise.
  """
  @spec mints(element(), String.t(), [map()], Catapult.Dsl.Chain.t()) :: [map()]
  def mints(element, tier_name, edges, chain) do
    for edge <- edges,
        instance <- edge_instances(edge),
        instance.source == tier_name,
        edge.type == "fanout",
        {:ok, path} <- [self_sourced_path(instance.declared_in, tier_name)] do
      identity_field = identity_field(chain, instance.target)
      status = mint_status(chain, instance.target)

      for instance_el <- navigate_list(element, path) do
        %{
          node_id: node_id(instance.target, identity_field, instance_el),
          tier: instance.target,
          scope_key: %{"id" => identity_value(identity_field, instance_el)},
          edge_name: edge.name,
          edge_type: :fanout,
          status: status
        }
      end
    end
    |> List.flatten()
  end

  @doc """
  Self-sourced `reference`-type edges: every `declared_in` instance
  across `edges` whose path is `<tier_name>.draft....[].@attr` — the
  attribute names the target's `id` directly, resolved against
  `project_id` via `resolve_target`.
  """
  @spec references(element(), String.t(), [map()], binary(), (binary(), String.t(), map() ->
                                                                binary() | nil)) :: [map()]
  def references(element, tier_name, edges, project_id, resolve_target) do
    for edge <- edges,
        instance <- edge_instances(edge),
        instance.source == tier_name,
        edge.type == "reference",
        {:ok, {path, attr}} <- [self_sourced_attr_path(instance.declared_in, tier_name)] do
      for instance_el <- navigate_list(element, path),
          value = attribute(instance_el, attr),
          not is_nil(value),
          target_id = resolve_target.(project_id, instance.target, value),
          not is_nil(target_id) do
        %{edge_name: edge.name, type: :reference, target_node_id: target_id}
      end
    end
    |> List.flatten()
  end

  @doc "Every `produces:` entry whose `owner` resolves (`self`/`self.parent`) and whose `authored` source parses."
  @spec produces(element(), [map()], binary() | nil) :: [map()]
  def produces(element, produces_decls, parent_node_id) do
    for %{owner_raw: owner_raw, kind: kind, authored: "draft." <> path} <- produces_decls,
        {:ok, owner_node_id} <- [resolve_owner(owner_raw, parent_node_id)],
        content = text(element, path),
        not is_nil(content) do
      %{owner_node_id: owner_node_id, kind: kind, content: content}
    end
  end

  ## -- self/self.parent owner resolution --------------------------------

  defp resolve_owner("self", _parent_node_id), do: {:error, :self_not_yet_known}
  defp resolve_owner("self.parent", nil), do: {:error, :no_parent}
  defp resolve_owner("self.parent", parent_node_id), do: {:ok, parent_node_id}
  defp resolve_owner(_other, _parent_node_id), do: {:error, :unsupported}

  ## -- declared_in path parsing -------------------------------------------

  # "<tier>.draft.<rest>[]" -> {:ok, rest_as_navigate_path} when <tier>
  # matches the tier being committed; anything else (a different
  # source tier, or a shape this module does not resolve) is skipped
  # rather than guessed at.
  defp self_sourced_path(declared_in, tier_name) do
    case String.split(declared_in, ".", parts: 2) do
      [^tier_name, "draft." <> rest] -> {:ok, String.split(rest, ".")}
      _other -> :skip
    end
  end

  # "<tier>.draft....<repeating>[].@attr" -> {:ok, {path_to_repeating,
  # attr}} — the trailing `@attr` segment (its own dot-separated
  # segment, e.g. "reference[].@target" splits to "reference[]" then
  # "@target") names an attribute read off each instance the leading
  # path finds, not a further descent.
  defp self_sourced_attr_path(declared_in, tier_name) do
    with {:ok, segments} <- self_sourced_path(declared_in, tier_name),
         {path, ["@" <> attr]} <- Enum.split(segments, -1),
         true <- attr != "" do
      {:ok, {path, attr}}
    else
      _other -> :skip
    end
  end

  ## -- element navigation (xmerl) -----------------------------------------

  @doc "Every element matching the final `tag[]` segment of `path`, navigating intermediate segments as single children."
  @spec navigate_list(element(), [String.t()]) :: [element()]
  def navigate_list(element, path) do
    case Enum.split(path, -1) do
      {containers, [last]} ->
        case Enum.reduce_while(containers, element, &descend/2) do
          nil -> []
          found -> children(found, repeat_tag(last))
        end

      {_containers, []} ->
        []
    end
  end

  defp descend(segment, element) do
    case child(element, repeat_tag(segment)) do
      nil -> {:halt, nil}
      found -> {:cont, found}
    end
  end

  defp repeat_tag(segment), do: segment |> to_string() |> String.trim_trailing("[]")

  defp node_id(target_tier, identity_field, instance_el) do
    target_tier <> ":" <> to_string(identity_value(identity_field, instance_el))
  end

  # `identity: id | alias | name` (dsl-syntax.md §3) names one of three
  # closed *strategies*, and nothing in that doc or `dsl-syntax.md`
  # elsewhere spells the exact attribute/element a minted instance
  # carries it under — a real gap, not a guess this module papers
  # over. Measured against the one schema this ticket could check
  # (`sysarch.xsd`'s `Component`, minted by `comp`'s `identity: id`):
  # the instance carries no `id` element or attribute at all, only a
  # required `alias` attribute — so `alias` is tried as a named
  # fallback for the `id` strategy specifically, the one place this
  # was checked against real content. A tier minting under a shape
  # this fallback doesn't cover fails extraction cleanly (`nil`
  # `scope_key` value) rather than silently guessing further.
  defp identity_value(identity_field, instance_el) do
    attribute(instance_el, identity_field) || text(instance_el, identity_field) ||
      (identity_field == "id" && attribute(instance_el, "alias"))
  end

  defp identity_field(%{tiers: tiers}, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, %{identity: identity}} when is_binary(identity) -> identity
      _other -> "id"
    end
  end

  defp mint_status(%{tiers: tiers}, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, %{draft: nil}} -> :approved
      _other -> :absent
    end
  end

  defp edge_instances(%{instances: instances}) when is_list(instances), do: instances

  defp edge_instances(%{source: source, target: target, declared_in: declared_in}) do
    [%{source: source, target: target, declared_in: declared_in}]
  end

  # Matched by stringified tag name rather than an atom comparison —
  # `tag` comes from bundle-declared field/edge sources (already
  # strings), and the body's own element names are whatever `xmerl`
  # interned while scanning; comparing as strings needs no
  # `to_existing_atom` guess about which side already exists.
  defp child(element, tag) do
    Enum.find(content(element), &element_named?(&1, tag))
  end

  defp children(element, tag) do
    Enum.filter(content(element), &element_named?(&1, tag))
  end

  defp element_named?({:xmlElement, name, _, _, _, _, _, _, _, _, _, _}, tag),
    do: to_string(name) == tag

  defp element_named?(_other, _tag), do: false

  defp content(element), do: elem(element, 8)
  defp attributes(element), do: elem(element, 7)
  defp attribute_name(attr), do: elem(attr, 1)
  defp attribute_value(attr), do: elem(attr, 8)

  defp serialize(content) do
    content
    |> :xmerl.export_simple_content(:xmerl_xml)
    |> List.flatten()
    |> to_string()
    |> String.trim()
  end
end
