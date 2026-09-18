defmodule Catapult.Generation.Extraction do
  @moduledoc """
  Reads `fields:`, `produces:` and declared-edge instances out of a
  validated draft body (`chain.md` #5, #24) — the extraction
  `Catapult.Engine.Events.DraftCommitted`'s own moduledoc places "at
  the command edge... never inside the reducer." This is that command
  edge's structural half, over the xmerl tree `Catapult.Dsl.Grammar`
  already parsed and validated.

  **Every third-party-declared instance is in scope now** (ORC-236):
  `declared_in`'s leading tier still has to be the tier committing
  right now — this module can only navigate the draft body it was
  handed — but a `source`/`target` that names a *different* tier than
  the committing one is no longer skipped. `Catapult.Dsl.EdgeLocator`
  (`chain.md` #27) resolves each side to `self` (the committing
  node), `self.parent`, the node minted by a prefixing `fanout`
  instance, a `scope: singleton` endpoint, or an explicit
  `source_ref:`/`target_ref:` path — the identical five-kind
  resolution `Catapult.Dsl.Chain` already uses to decide whether an
  instance is legally locatable at all, run here a second time to
  compute the actual node.

  `type: policy_application` is not this mechanism: its two instances'
  `declared_in` (`policy.structural`, `policy.required`) name a marker
  on the *minting* instance element itself, not a location in a
  committed draft body, so they are read alongside an ordinary mint
  rather than through the locator above.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.EdgeLocator

  @type element :: tuple()
  @typedoc """
  `(tier, value_or_nil) -> node_id`, already bound to a project by the
  caller. `nil` value resolves a `scope: singleton` tier's one node.
  """
  @type resolver :: (String.t(), String.t() | nil -> binary() | nil)

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
  stripped; any other source (`"mint.<name>"`/`"mint.parent.<name>"` —
  join-target tiers, resolved at mint time by `mints/6` below;
  `"reference.<name>"` — a `scope: reference` tier's write-path
  payload, resolved by whichever write path creates the node) is
  skipped, since none of them has a committed draft to read from here.
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
  leading tier is `tier_name` and whose type is `:fanout`. Each matched
  element becomes one mint entry with its `mint.<name>`/
  `mint.parent.<name>` field values already resolved (`chain.md`
  #12) — `own_fields` is this same commit's own `fields/2` result and
  `own_produces_by_kind` its own `produces/3` result keyed by
  fragment kind, both already computed, purity-floor-clean, before
  this is called (`systems/engine.md`'s ORC-236 entry: "no new
  navigation, only a second place already-computed values are read
  from"). `status` is `:approved` when the target tier declares no
  `draft:` block (a join target, `chain.md` #5 — it has no
  commit path of its own to ever move it off whatever this writes,
  `systems/engine.md`'s ORC-117 entry) and `:absent` otherwise.

  Also emits `type: policy_application`'s two mint-time markers
  (`policy.structural`, `policy.required`) as declared-edge entries
  alongside a `policy` mint, off the identical instance element —
  `systems/core_dsl.md`'s own ORC-236 entry on why this is not
  `references/6`'s mechanism.
  """
  @spec mints(element(), String.t(), Chain.t(), map(), map(), binary() | nil, resolver()) ::
          %{mints: [map()], edges: [map()]}
  def mints(
        element,
        tier_name,
        chain,
        own_fields,
        own_produces_by_kind,
        parent_node_id,
        resolve_target
      ) do
    edges = Map.values(chain.edges)

    per_instance =
      for edge <- edges,
          instance <- edge_instances(edge),
          instance.source == tier_name,
          edge.type == "fanout",
          {:ok, path} <- [self_sourced_path(instance.declared_in, tier_name)] do
        identity_field = identity_field(chain, instance.target)
        status = mint_status(chain, instance.target)
        target_field_sources = tier_field_sources(chain, instance.target)

        for instance_el <- navigate_list(element, path) do
          node_id = node_id(instance.target, identity_field, instance_el)

          mint = %{
            node_id: node_id,
            tier: instance.target,
            scope_key: %{"id" => identity_value(identity_field, instance_el)},
            edge_name: edge.name,
            edge_type: :fanout,
            status: status,
            fields:
              resolve_mint_fields(
                target_field_sources,
                instance_el,
                own_fields,
                own_produces_by_kind
              )
          }

          policy_edges =
            policy_application_edges(
              edges,
              instance.target,
              node_id,
              instance_el,
              parent_node_id,
              resolve_target
            )

          {mint, policy_edges}
        end
      end
      |> List.flatten()

    %{
      mints: Enum.map(per_instance, &elem(&1, 0)),
      edges: Enum.flat_map(per_instance, &elem(&1, 1))
    }
  end

  defp resolve_mint_fields(field_sources, instance_el, own_fields, own_produces_by_kind) do
    for {name, source} <- field_sources, into: %{} do
      {name, resolve_mint_field(source, instance_el, own_fields, own_produces_by_kind)}
    end
  end

  defp resolve_mint_field("mint.parent." <> name, _instance_el, own_fields, own_produces_by_kind) do
    Map.get(own_fields, name) || Map.get(own_produces_by_kind, name)
  end

  defp resolve_mint_field("mint." <> name, instance_el, _own_fields, _own_produces_by_kind) do
    mint_field_value(instance_el, name)
  end

  defp resolve_mint_field(_other, _instance_el, _own_fields, _own_produces_by_kind), do: nil

  # A `mint.<name>` value read off the minting instance element itself:
  # an attribute or child-element named `name`, unvalidated at load
  # time — the retired grammar had no schema to check `<name>`
  # against. `chain.md` #32 closes that: a `declared_in` path resolving
  # to no element is a load error. The tree has not caught up, so the
  # fallback below still stands. A hyphenated fallback covers the same `_`/`-` mismatch
  # `systems/core_dsl.md`'s ORC-232/ORC-236 entries name for
  # schema-checked paths, harmless here since it only recovers a match
  # that would otherwise be silently absent.
  defp mint_field_value(instance_el, name) do
    attribute(instance_el, name) || text(instance_el, name) || hyphenated_text(instance_el, name)
  end

  defp hyphenated_text(instance_el, name) do
    if String.contains?(name, "_"), do: text(instance_el, String.replace(name, "_", "-"))
  end

  # A join target's field sources are `fields:`'s own `mint.parent.<kind>`
  # cross-node copies (chain.yaml-declared) plus its schema-derived own
  # fields, each read row-local off the minting element by its actual
  # schema tag rather than its declared name (`chain.md` #12, #32) —
  # `Catapult.Dsl.DeclaredInSchema.mints_and_fields/2`'s own reason for
  # keying `own_fields` by tag instead of a bare name list.
  defp tier_field_sources(%Chain{tiers: tiers}, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, %{fields: fields, mint_fields: mint_fields}} ->
        Map.merge(mint_local_sources(mint_fields), fields)

      :error ->
        %{}
    end
  end

  defp mint_local_sources(mint_fields) do
    Map.new(mint_fields, fn {name, tag} -> {name, "mint." <> tag} end)
  end

  # `type: policy_application`'s two instances read a marker off the
  # same fanout instance element a mint already walks — `structural`
  # targets the minting node's own parent (the declaring tier's own
  # comp, `systems/core_dsl.md`'s ORC-236 entry); `required` names a
  # resp id, resolved the identical way a `reference` edge's trailing
  # `@attr` already is.
  defp policy_application_edges(
         edges,
         source_tier,
         mint_node_id,
         instance_el,
         parent_node_id,
         resolve_target
       ) do
    for edge <- edges,
        edge.type == "policy_application",
        instance <- edge_instances(edge),
        instance.source == source_tier,
        target_node_id =
          policy_marker_target(instance, instance_el, parent_node_id, resolve_target),
        not is_nil(target_node_id) do
      %{
        edge_name: edge.name,
        type: :policy_application,
        source_node_id: mint_node_id,
        target_node_id: target_node_id
      }
    end
  end

  defp policy_marker_target(
         %{target: target_tier, declared_in: declared_in},
         instance_el,
         parent_node_id,
         resolve_target
       ) do
    case String.split(declared_in, ".", parts: 2) do
      [_marker_tier, "structural"] ->
        if not is_nil(text(instance_el, "structural")), do: parent_node_id

      [_marker_tier, "required"] ->
        case text(instance_el, "required") do
          nil -> nil
          value -> resolve_target.(target_tier, value)
        end

      _other ->
        nil
    end
  end

  @doc """
  Every declared-edge instance (`type: reference` or `type:
  dependency`) whose `declared_in` leading tier is `tier_name` —
  `own_node_id` is the id this commit's own node commits under (used
  whenever a side's locator resolves to `self`), `parent_node_id` its
  own parent (`self.parent`). Every other side is resolved through
  `Catapult.Dsl.EdgeLocator` — the node minted by a prefixing fanout
  instance (recomputed off the same anchor element mints/6 already
  used, never a second navigator), a `scope: singleton` tier's one
  node, or an explicit `source_ref:`/`target_ref:` attribute — the
  identical resolution `Catapult.Dsl.Chain` already confirmed is
  legally locatable at load time (`chain.md` #27).
  """
  @spec references(element(), String.t(), Chain.t(), binary(), binary() | nil, resolver()) :: [
          map()
        ]
  def references(element, tier_name, chain, own_node_id, parent_node_id, resolve_target) do
    ctx = %{
      element: element,
      chain: chain,
      own_node_id: own_node_id,
      parent_node_id: parent_node_id,
      resolve: resolve_target
    }

    for edge <- Map.values(chain.edges),
        edge.type in ["reference", "dependency"],
        instance <- edge_instances(edge),
        {:ok, declaring_tier} <- [declared_in_leading_tier(instance.declared_in)],
        declaring_tier == tier_name,
        entry <- instance_edges(edge, instance, declaring_tier, ctx) do
      entry
    end
  end

  defp instance_edges(edge, instance, declaring_tier, ctx) do
    {path, trailing_attr} = declared_in_path(instance.declared_in)
    explicit_source = instance[:source_ref] && EdgeLocator.parse(instance[:source_ref])
    explicit_target = instance[:target_ref] && EdgeLocator.parse(instance[:target_ref])

    case EdgeLocator.resolve(
           instance.source,
           instance.target,
           declaring_tier,
           instance.declared_in,
           trailing_attr,
           explicit_source,
           explicit_target,
           %{edges: ctx.chain.edges, tiers: ctx.chain.tiers}
         ) do
      {:error, _sides} ->
        []

      {:ok, source_locator, target_locator} ->
        {anchor_path, suffix_path} =
          split_at_fanout(
            ctx.chain,
            instance.declared_in,
            declaring_tier,
            path,
            instance.source,
            source_locator,
            instance.target,
            target_locator
          )

        ctx.element
        |> navigate_anchors(anchor_path)
        |> Enum.flat_map(
          &leaf_edges(
            &1,
            suffix_path,
            edge,
            instance,
            declaring_tier,
            source_locator,
            target_locator,
            ctx
          )
        )
    end
  end

  defp leaf_edges(
         anchor,
         suffix_path,
         edge,
         instance,
         declaring_tier,
         source_locator,
         target_locator,
         ctx
       ) do
    anchor
    |> navigate_leaves(suffix_path)
    |> Enum.map(fn leaf ->
      source_id = resolve_side(source_locator, instance.source, declaring_tier, anchor, leaf, ctx)
      target_id = resolve_side(target_locator, instance.target, declaring_tier, anchor, leaf, ctx)
      edge_entry(edge, source_id, target_id)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp edge_entry(_edge, nil, _target_id), do: nil
  defp edge_entry(_edge, _source_id, nil), do: nil

  defp edge_entry(edge, source_id, target_id) do
    %{
      edge_name: edge.name,
      type: edge_type_atom(edge.type),
      source_node_id: source_id,
      target_node_id: target_id
    }
  end

  defp edge_type_atom("reference"), do: :reference
  defp edge_type_atom("dependency"), do: :dependency

  # The anchor/suffix split: when a side resolves via `{:fanout,
  # edge_name}`, that fanout's own `declared_in` names the anchor depth
  # every leaf is navigated relative to (`chain.md` #27) — the
  # identical element `mints/6` already walked for that fanout, never a
  # second navigator. Neither side is a fanout locator (the ordinary
  # self-sourced case, or a same-tier explicit-path pair) means no
  # anchor at all: the whole path is the suffix, navigated straight off
  # `element`.
  defp split_at_fanout(
         chain,
         declared_in,
         declaring_tier,
         path,
         source_tier,
         source_locator,
         target_tier,
         target_locator
       ) do
    with nil <- fanout_prefix(chain, declared_in, declaring_tier, source_tier, source_locator),
         nil <- fanout_prefix(chain, declared_in, declaring_tier, target_tier, target_locator) do
      {[], path}
    else
      prefix -> {prefix, Enum.drop(path, length(prefix))}
    end
  end

  defp fanout_prefix(chain, declared_in, declaring_tier, side_tier, {:fanout, edge_name}) do
    case EdgeLocator.fanout_prefix_instance(chain.edges, edge_name, side_tier, declared_in) do
      nil ->
        nil

      instance ->
        with {:ok, prefix} <- self_sourced_path(instance.declared_in, declaring_tier), do: prefix
    end
  end

  defp fanout_prefix(_chain, _declared_in, _declaring_tier, _side_tier, _other), do: nil

  defp navigate_anchors(element, []), do: [element]
  defp navigate_anchors(element, prefix), do: navigate_list(element, prefix)

  defp navigate_leaves(anchor, []), do: [anchor]
  defp navigate_leaves(anchor, suffix), do: navigate_list(anchor, suffix)

  defp resolve_side(:self, _side_tier, _declaring_tier, _anchor, _leaf, ctx), do: ctx.own_node_id

  defp resolve_side(:self_parent, _side_tier, _declaring_tier, _anchor, _leaf, ctx),
    do: ctx.parent_node_id

  defp resolve_side({:fanout, _edge_name}, side_tier, _declaring_tier, anchor, _leaf, ctx) do
    node_id(side_tier, identity_field(ctx.chain, side_tier), anchor)
  end

  defp resolve_side(:singleton, side_tier, _declaring_tier, _anchor, _leaf, ctx) do
    ctx.resolve.(side_tier, nil)
  end

  # A same-tier explicit locator (`@from`/`@to`) whose tier is *also*
  # fanout-minted by this same declaring/committing tier — the six
  # same-tier `dependency` instances (`comp <-> comp` and its five
  # siblings), plus any instance connecting two siblings of one fanout
  # (`renders`'s `screen_coll -> ui_coll`, both minted by
  # `frontend_sysarch`) — names a sibling minted by this exact commit,
  # which cannot yet exist in the store: extraction runs before the
  # mint events it computes are ever applied. Resolved by re-navigating
  # the fanout's own anchor elements and matching identity, the
  # identical computation `mints/6` itself performs for that sibling —
  # never a plain string-concatenation guess, because a tier whose
  # identity extraction itself fails (the `id`/`alias` gap below —
  # `screen`/`resp`/`vocab`/`policy` carry neither)
  # must fail the same way here too, rather than construct an id the
  # real mint will never actually write.
  defp resolve_side({:path, "@" <> attr}, side_tier, declaring_tier, _anchor, leaf, ctx) do
    with value when not is_nil(value) <- attribute(leaf, attr) do
      case same_commit_fanout(ctx.chain, declaring_tier, side_tier) do
        nil ->
          ctx.resolve.(side_tier, value)

        {_edge_name, fanout_instance} ->
          resolve_sibling(
            ctx.chain,
            fanout_instance,
            declaring_tier,
            side_tier,
            ctx.element,
            value
          )
      end
    end
  end

  defp resolve_side(_other, _side_tier, _declaring_tier, _anchor, _leaf, _ctx), do: nil

  defp same_commit_fanout(%Chain{edges: edges}, declaring_tier, side_tier) do
    Enum.find_value(edges, fn {name, edge} ->
      if edge.type == "fanout" do
        find_fanout_instance(edge.instances, declaring_tier, side_tier, name)
      end
    end)
  end

  defp find_fanout_instance(instances, declaring_tier, side_tier, name) do
    case Enum.find(instances, &(&1.source == declaring_tier and &1.target == side_tier)) do
      nil -> nil
      instance -> {name, instance}
    end
  end

  defp resolve_sibling(chain, fanout_instance, declaring_tier, side_tier, element, value) do
    identity_field = identity_field(chain, side_tier)

    case self_sourced_path(fanout_instance.declared_in, declaring_tier) do
      {:ok, prefix} -> find_sibling_id(element, prefix, side_tier, identity_field, value)
      :skip -> nil
    end
  end

  defp find_sibling_id(element, prefix, side_tier, identity_field, value) do
    element
    |> navigate_list(prefix)
    |> Enum.find(&(identity_value(identity_field, &1) == value))
    |> case do
      nil -> nil
      sibling -> node_id(side_tier, identity_field, sibling)
    end
  end

  @doc """
  Every `produces:` entry whose `draft_path` source parses — the owner
  is always the scope parent now (`chain.md` #13), so this needs
  `parent_node_id` rather than a per-entry `owner:` to resolve against.
  """
  @spec produces(element(), [map()], binary() | nil) :: [map()]
  def produces(_element, _produces_decls, nil), do: []

  def produces(element, produces_decls, parent_node_id) do
    for %{kind: kind, draft_path: "draft." <> path} <- produces_decls,
        content = text(element, path),
        not is_nil(content) do
      %{owner_node_id: parent_node_id, kind: kind, content: content}
    end
  end

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

  defp declared_in_leading_tier(declared_in) do
    case String.split(declared_in, ".", parts: 2) do
      [tier, "draft." <> _rest] -> {:ok, tier}
      _other -> :skip
    end
  end

  # `declared_in`'s element path and optional trailing `@attr`,
  # relative to `draft.` — the leading tier already stripped by the
  # caller (`declared_in_leading_tier/1`).
  defp declared_in_path(declared_in) do
    {:ok, segments} =
      self_sourced_path(declared_in, declared_in |> String.split(".", parts: 2) |> hd())

    case Enum.split(segments, -1) do
      {path, ["@" <> attr]} when attr != "" -> {path, attr}
      _other -> {segments, nil}
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

  # `identity` (`chain.md` #32) names one of `id`, `alias`, `name` or
  # `slug`, and the retired grammar spelled nowhere which exact
  # attribute or element a minted instance carries it under — a real
  # gap, not a guess this module papers over. #32's
  # `<catapult:mints tier="comp" identity="alias"/>` annotation is what
  # closes it; until the loader reads that annotation the fallback
  # below stands. Measured against the one schema this ticket could check
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
      {:ok, %{draft: :none}} -> :approved
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
