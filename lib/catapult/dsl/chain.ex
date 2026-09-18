defmodule Catapult.Dsl.Chain do
  @moduledoc """
  Loads and validates one `kind: chain` bundle end to end (`bundle.md`
  #3, `chain.md`): one `chain.yaml`, plus the schemas and prompts it
  names. Every tier's effective context (`chain.md` #20, #21) and
  handle (`bundle.md` #10, `chain.md` #11, #32) are computed here, from
  the declared edges and each generating tier's own schema, and stored
  back onto the tier — this is the one place either is derived, so
  every later reader (the engine, generation) reads a plain field
  rather than re-deriving it.
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.DeclaredInSchema
  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.EdgeLocator
  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.Flow
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Dsl.Predicate
  alias Catapult.Dsl.Registry
  alias Catapult.Dsl.Tier
  alias Catapult.Dsl.Yaml

  @enforce_keys [:name]
  defstruct [:name, :version, defaults: %{}, tiers: %{}, edges: %{}, flows: %{}, predicates: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          version: String.t() | nil,
          defaults: map(),
          tiers: %{String.t() => Tier.t()},
          edges: %{String.t() => Edge.t()},
          flows: %{String.t() => Flow.t()},
          predicates: %{String.t() => Predicate.t() | nil}
        }

  @top_keys ~w(name version kind defaults tiers edges predicates flows)
  @reserved_names ~w(self draft feedback prior_review)

  @doc """
  Resolves a predicate-language slot's raw string (`chain.md` #37) — a
  fanout instance's `when:` or a flow's `completion:` — against this
  bundle's own `predicates:` map: a registered name wins (even one
  whose value is `nil`, reserved with no expression yet), an inline
  expression parses fresh.
  """
  @spec resolve_predicate(t(), String.t()) :: {:ok, Predicate.t() | nil} | {:error, String.t()}
  def resolve_predicate(%__MODULE__{predicates: named}, raw) do
    case Map.fetch(named, raw) do
      {:ok, predicate} -> {:ok, predicate}
      :error -> Predicate.parse(raw)
    end
  end

  @doc "Loads and validates the chain bundle named `name` under `bundles_root`."
  @spec load(String.t(), String.t(), Registry.t()) :: {:ok, t()} | {:error, [String.t()]}
  def load(bundles_root, name, %Registry{} = registry) do
    dir = Path.join(bundles_root, name)
    path = Path.join(dir, "chain.yaml")

    with {:ok, raw} <- read_yaml(path),
         {:ok, raw} <- require_kind(raw, path) do
      build(dir, raw, registry)
    end
  end

  defp read_yaml(path) do
    case Yaml.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp require_kind(%{"kind" => "chain"} = raw, _path), do: {:ok, raw}

  defp require_kind(%{"kind" => other}, path) do
    {:error,
     ["#{path} is a #{other} bundle, expected chain (catapult.yaml named it on the chain axis)"]}
  end

  defp require_kind(_raw, path), do: {:error, ["#{path} is missing required field \"kind\""]}

  defp build(dir, raw, registry) do
    {name, name_p} = Fields.require_string(raw, "name", "chain.yaml")
    {version, version_p} = Fields.optional_string(raw, "version", "chain.yaml")
    {defaults, defaults_p} = parse_defaults(raw)
    {tiers, tiers_p} = parse_named(raw, "tiers", Tier)
    {edges, edges_p} = parse_named(raw, "edges", Edge)
    {predicates, predicates_p} = parse_predicates(raw)
    {flows, flows_p} = parse_named(raw, "flows", Flow, optional: true)
    unknown = Fields.unknown_keys(raw, @top_keys, "chain.yaml")

    structural =
      name_p ++
        version_p ++ defaults_p ++ tiers_p ++ edges_p ++ predicates_p ++ flows_p ++ unknown

    if structural != [] do
      {:error, Enum.uniq(structural)}
    else
      tiers = apply_executor_defaults(tiers, defaults)

      case cross_reference_problems(dir, tiers, edges, flows, predicates, registry) do
        {[], tiers} ->
          {:ok,
           %__MODULE__{
             name: name,
             version: version,
             defaults: defaults,
             tiers: tiers,
             edges: edges,
             flows: flows,
             predicates: predicates
           }}

        {problems, _tiers} ->
          {:error, Enum.uniq(problems)}
      end
    end
  end

  defp parse_defaults(raw) do
    case Fields.optional_map(raw, "defaults", "chain.yaml") do
      {nil, []} ->
        {%{}, []}

      {defaults, []} ->
        {executor, ep} = Fields.optional_map(defaults, "executor", "chain.yaml's defaults")
        unknown = Fields.unknown_keys(defaults, ["executor"], "chain.yaml's defaults")
        {%{executor: executor}, ep ++ unknown}

      {nil, problems} ->
        {%{}, problems}
    end
  end

  defp parse_named(raw, key, module, opts \\ []) do
    fetch =
      if Keyword.get(opts, :optional, false), do: &optional_named/3, else: &Fields.require_map/3

    case fetch.(raw, key, "chain.yaml") do
      {nil, problems} ->
        {%{}, problems}

      {map, []} ->
        results = for {name, entry} <- map, do: {name, module.parse(name, entry)}
        problems = for {_name, {:error, p}} <- results, problem <- p, do: problem
        parsed = for {name, {:ok, entry}} <- results, into: %{}, do: {name, entry}
        {parsed, problems}
    end
  end

  defp optional_named(raw, key, where) do
    case Fields.optional_map(raw, key, where) do
      {nil, []} -> {%{}, []}
      other -> other
    end
  end

  defp parse_predicates(raw) do
    case Fields.optional_map(raw, "predicates", "chain.yaml") do
      {nil, []} ->
        {%{}, []}

      {map, []} ->
        results = for {name, expr} <- map, do: {name, parse_one_predicate(name, expr)}
        problems = for {_name, {:error, reason}} <- results, do: reason
        parsed = for {name, {:ok, value}} <- results, into: %{}, do: {name, value}
        {parsed, problems}

      {nil, problems} ->
        {%{}, problems}
    end
  end

  defp parse_one_predicate(_name, nil), do: {:ok, nil}
  defp parse_one_predicate(_name, expr) when is_binary(expr), do: Predicate.parse(expr)

  defp parse_one_predicate(name, other) do
    {:error,
     "chain.yaml's predicates #{inspect(name)} is #{inspect(other)}, expected a string or null"}
  end

  defp apply_executor_defaults(tiers, defaults) do
    Map.new(tiers, fn {name, tier} ->
      case Tier.kind(tier) do
        :generating -> {name, %{tier | executor: tier.executor || Map.get(defaults, :executor)}}
        _other -> {name, tier}
      end
    end)
  end

  ## -- Cross-reference validation, and the derivations that ride it ------

  defp cross_reference_problems(dir, tiers, edges, flows, predicates, registry) do
    problems =
      scope_problems(tiers) ++
        edge_endpoint_problems(edges, tiers) ++
        edge_acyclicity_problems(edges) ++
        single_minting_parent_problems(edges) ++
        predicate_slot_problems(edges, flows, predicates) ++
        edge_locator_problems(edges, tiers) ++
        DeclaredInSchema.problems(dir, tiers, edges) ++
        DeclaredInSchema.field_problems(dir, tiers) ++
        DeclaredInSchema.ref_problems(dir, tiers, edges) ++
        produces_scope_problems(tiers) ++
        reconcile_fanout_problems(tiers, edges) ++
        enforcement_problems(tiers, registry) ++
        flow_reference_problems(flows, tiers, edges)

    if problems != [] do
      {problems, tiers}
    else
      {tiers, schema_problems} = fill_identity_and_fields(dir, tiers, edges)
      {tiers, handle_problems} = fill_handles(tiers, edges)
      {tiers, context_problems} = fill_effective_context(tiers, edges)
      {schema_problems ++ handle_problems ++ context_problems, tiers}
    end
  end

  defp scope_problems(tiers) do
    for {name, tier} <- tiers,
        {kind, ref} <- [scope_ref(tier)],
        kind in [:per, :child_of],
        not Map.has_key?(tiers, ref) do
      "tier #{inspect(name)}'s scope #{kind}(#{ref}) names a tier that is not declared"
    end
  end

  defp scope_ref(%Tier{scope: {kind, ref}}), do: {kind, ref}
  defp scope_ref(%Tier{}), do: {nil, nil}

  defp edge_endpoint_problems(edges, tiers) do
    for {name, edge} <- edges,
        instance <- edge.instances,
        {side, ref} <- [{:source, instance.source} | target_refs(instance.target)],
        not Map.has_key?(tiers, ref) do
      "edge #{inspect(name)}'s #{side} #{inspect(ref)} names a tier that is not declared"
    end
  end

  defp target_refs(targets) when is_list(targets), do: for(t <- targets, do: {:target, t})
  defp target_refs(target), do: [{:target, target}]

  defp edge_acyclicity_problems(edges) do
    pairs =
      for {_name, edge} <- edges,
          %{source: s, target: t} <- edge.instances,
          target <- List.wrap(t),
          do: {s, target}

    if DslGraph.acyclic?(pairs) do
      []
    else
      case DslGraph.find_cycle(pairs) do
        nil -> ["the edge-instance graph has a type-level cycle"]
        cycle -> ["the edge-instance graph has a type-level cycle among tiers: #{inspect(cycle)}"]
      end
    end
  end

  # chain.md #28: a tier has exactly one minting parent — two `fanout`
  # instances may not target one tier.
  defp single_minting_parent_problems(edges) do
    edges
    |> Enum.flat_map(&fanout_source_target_pairs/1)
    |> Enum.group_by(fn {_source, target} -> target end, fn {source, _target} -> source end)
    |> Enum.filter(fn {_target, sources} -> length(Enum.uniq(sources)) > 1 end)
    |> Enum.map(fn {target, sources} ->
      "tier #{inspect(target)} is minted by more than one fanout source #{inspect(Enum.uniq(sources))} (chain.md #28)"
    end)
  end

  defp fanout_source_target_pairs({_name, %Edge{type: "fanout", instances: instances}}) do
    for i <- instances, do: {i.source, i.target}
  end

  defp fanout_source_target_pairs({_name, _edge}), do: []

  defp predicate_slot_problems(edges, flows, predicates) do
    fanout_when =
      for {edge_name, edge} <- edges,
          instance <- edge.instances,
          instance.when do
        predicate_problem(
          instance.when,
          predicates,
          "edge #{inspect(edge_name)}'s instance's when"
        )
      end

    completion =
      for {flow_name, flow} <- flows, flow.completion do
        predicate_problem(flow.completion, predicates, "flow #{inspect(flow_name)}'s completion")
      end

    Enum.reject(fanout_when ++ completion, &is_nil/1)
  end

  defp predicate_problem(raw, named, where) do
    if Map.has_key?(named, raw) do
      nil
    else
      case Predicate.parse(raw) do
        {:ok, _ast} -> nil
        {:error, reason} -> "#{where} #{reason}"
      end
    end
  end

  ## source_ref:/target_ref: (chain.md #27)

  defp edge_locator_problems(edges, tiers) do
    for {edge_name, edge} <- edges,
        edge.type in ["reference", "dependency"],
        instance <- edge.instances,
        problem <- instance_locator_problems(edge_name, instance, edges, tiers) do
      problem
    end
  end

  defp instance_locator_problems(edge_name, instance, edges, tiers) do
    case declared_in_leading_tier(instance.declared_in) do
      nil ->
        []

      declaring_tier ->
        trailing_attr = declared_in_trailing_attr(instance.declared_in)
        explicit_source = instance.source_ref && EdgeLocator.parse(instance.source_ref)
        explicit_target = instance.target_ref && EdgeLocator.parse(instance.target_ref)

        explicit_locator_form_problems(edge_name, "source_ref", instance.source_ref) ++
          explicit_locator_form_problems(edge_name, "target_ref", instance.target_ref) ++
          instance_resolution_problems(
            edge_name,
            instance,
            edges,
            tiers,
            declaring_tier,
            trailing_attr,
            explicit_source,
            explicit_target
          )
    end
  end

  defp explicit_locator_form_problems(_edge_name, _label, nil), do: []

  defp explicit_locator_form_problems(edge_name, label, raw) do
    case EdgeLocator.parse(raw) do
      {:path, "@" <> attr} when attr != "" ->
        []

      :self ->
        []

      :self_parent ->
        []

      {:fanout, _edge} ->
        []

      _other ->
        [
          "edge #{inspect(edge_name)}'s instance's #{label} #{inspect(raw)} is not a recognized locator (chain.md #27)"
        ]
    end
  end

  defp instance_resolution_problems(
         edge_name,
         instance,
         edges,
         tiers,
         declaring_tier,
         trailing_attr,
         explicit_source,
         explicit_target
       ) do
    case instance.target do
      target when is_list(target) ->
        []

      target ->
        case EdgeLocator.resolve(
               instance.source,
               target,
               declaring_tier,
               instance.declared_in,
               trailing_attr,
               explicit_source,
               explicit_target,
               %{edges: edges, tiers: tiers}
             ) do
          {:ok, _source, _target} ->
            []

          {:error, sides} ->
            [
              "edge #{inspect(edge_name)}'s instance (source #{inspect(instance.source)}, " <>
                "target #{inspect(target)}, declared_in #{inspect(instance.declared_in)}) " <>
                "cannot locate #{inspect(sides)} — declare an explicit source_ref:/target_ref: (chain.md #27)"
            ]
        end
    end
  end

  defp declared_in_leading_tier(declared_in) do
    case String.split(declared_in, ".", parts: 2) do
      [tier, "draft." <> _rest] -> tier
      _other -> nil
    end
  end

  defp declared_in_trailing_attr(declared_in) do
    case declared_in |> String.split(".") |> List.last() do
      "@" <> attr when attr != "" -> attr
      _other -> nil
    end
  end

  ## produces: (chain.md #13) — the owner is always the scope parent, so
  ## only a per(X)/child_of(X)-scoped generating tier may declare it.

  defp produces_scope_problems(tiers) do
    for {name, %Tier{produces: produces} = tier} <- tiers,
        produces != [],
        not has_scope_parent?(tier) do
      "tier #{inspect(name)} declares produces:, but its scope has no parent to own the fragment (chain.md #13)"
    end
  end

  defp has_scope_parent?(%Tier{scope: {:per, _}}), do: true
  defp has_scope_parent?(%Tier{scope: {:child_of, _}}), do: true
  defp has_scope_parent?(%Tier{}), do: false

  ## reconcile: (chain.md #15) — a fan-out tier's own block.

  defp reconcile_fanout_problems(tiers, edges) do
    for {name, %Tier{reconcile: reconcile}} <- tiers,
        not is_nil(reconcile),
        not fanout_source?(name, edges) do
      "tier #{inspect(name)} declares reconcile:, but is not the source of any fanout edge (chain.md #15)"
    end
  end

  defp fanout_source?(name, edges) do
    Enum.any?(edges, fn {_ename, edge} ->
      edge.type == "fanout" and Enum.any?(edge.instances, &(&1.source == name))
    end)
  end

  defp enforcement_problems(tiers, registry) do
    for {name, tier} <- tiers,
        profile <- tier.enforcement,
        not Registry.enforcement_profile?(registry, profile) do
      "tier #{inspect(name)}'s enforcement names profile #{inspect(profile)}, which is not installed"
    end
  end

  defp flow_reference_problems(flows, tiers, edges) do
    Enum.flat_map(flows, fn {name, flow} ->
      entry_problem =
        if flow.entry && not Map.has_key?(tiers, flow.entry) do
          [
            "flow #{inspect(name)}'s entry #{inspect(flow.entry)} names a tier that is not declared"
          ]
        else
          []
        end

      tier_problems =
        for t <- flow.delta_tiers, not Map.has_key?(tiers, t) do
          "flow #{inspect(name)}'s delta names tier #{inspect(t)}, which is not declared"
        end

      edge_problems =
        for e <- flow.delta_edges, not Map.has_key?(edges, e) do
          "flow #{inspect(name)}'s delta names edge #{inspect(e)}, which is not declared"
        end

      entry_problem ++ tier_problems ++ edge_problems
    end)
  end

  ## -- Identity, own fields (bundle.md #10, chain.md #32) -----------------

  defp fill_identity_and_fields(dir, tiers, edges) do
    generating =
      for {name, tier} <- tiers, Tier.kind(tier) == :generating, into: %{}, do: {name, tier}

    {scanned, scan_problems} =
      Enum.reduce(generating, {%{}, []}, fn {name, tier}, {acc, problems} ->
        case DeclaredInSchema.mints_and_fields(dir, tier) do
          {:ok, info} -> {Map.put(acc, name, info), problems}
          {:error, reason} -> {acc, ["tier #{inspect(name)}'s #{reason}" | problems]}
        end
      end)

    minting_source = minting_sources(edges)

    {tiers, join_problems} =
      Enum.reduce(tiers, {%{}, []}, fn {name, tier}, {acc, problems} ->
        {tier, tier_problems} = apply_schema_info(tier, name, minting_source, scanned)
        {Map.put(acc, name, tier), tier_problems ++ problems}
      end)

    {tiers, Enum.reverse(scan_problems) ++ join_problems}
  end

  # A generating tier can also be a fanout target (`vocab`: minted
  # per-term from feature_expansion's draft, then separately authors
  # its own draft) — its identity is its own schema's when it declares
  # one, else whatever minted it; `draft_fields`/`mint_fields` stay
  # separate since each is read a different way at a different time.
  defp apply_schema_info(tier, name, minting_source, scanned) do
    case Tier.kind(tier) do
      :generating ->
        own = Map.get(scanned, name, %{identity: nil, own_fields: %{}})

        {identity, mint_fields} =
          case join_target_info(name, minting_source, scanned) do
            {:ok, info} -> {own.identity || info.identity, info.fields}
            {:error, _not_a_mint_target} -> {own.identity, %{}}
          end

        {%{tier | identity: identity, draft_fields: own.own_fields, mint_fields: mint_fields}, []}

      :join ->
        case join_target_info(name, minting_source, scanned) do
          {:ok, info} -> {%{tier | identity: info.identity, mint_fields: info.fields}, []}
          {:error, reason} -> {tier, [reason]}
        end

      :supplied ->
        {tier, []}
    end
  end

  defp minting_sources(edges) do
    for {_name, edge} <- edges,
        edge.type == "fanout",
        instance <- edge.instances,
        uniq: true,
        into: %{} do
      {instance.target, instance.source}
    end
  end

  defp join_target_info(name, minting_source, scanned) do
    with {:ok, source} <- Map.fetch(minting_source, name),
         {:ok, %{mints: mints}} <- Map.fetch(scanned, source),
         {:ok, entry} <- Map.fetch(mints, name) do
      {:ok, entry}
    else
      _other ->
        {:error,
         "tier #{inspect(name)} is a join target, but no minting tier's schema declares " <>
           "<catapult:mints tier=#{inspect(name)}> (chain.md #32)"}
    end
  end

  ## -- Handle (bundle.md #10, chain.md #11) -------------------------------

  defp fill_handles(tiers, _edges) do
    produced_kinds = produced_kinds_by_owner(tiers)

    Enum.reduce(tiers, {%{}, []}, fn {name, tier}, {acc, problems} ->
      default_fields =
        Map.keys(tier.draft_fields) ++ Map.keys(tier.mint_fields) ++ Map.keys(tier.fields)

      default_fragments = Map.get(produced_kinds, name, [])
      unknown = unknown_handle_names(tier.handle_narrow, default_fields, default_fragments)
      {fields, fragments} = narrow_handle(tier.handle_narrow, default_fields, default_fragments)

      unknown_problems =
        for n <- unknown do
          "tier #{inspect(name)}'s handle names #{inspect(n)}, which is not a field of this tier or a kind it produces (chain.md #11)"
        end

      {Map.put(acc, name, %{tier | handle_fields: fields, handle_fragments: fragments}),
       problems ++ unknown_problems}
    end)
  end

  defp unknown_handle_names(nil, _default_fields, _default_fragments), do: []

  defp unknown_handle_names(names, default_fields, default_fragments),
    do: names -- (default_fields ++ default_fragments)

  # `produces:` always lands on the scope parent (chain.md #13): a
  # tier's own produced kinds are collected under the *parent's* name.
  defp produced_kinds_by_owner(tiers) do
    for {_name, tier} <- tiers,
        parent = scope_parent(tier),
        not is_nil(parent),
        kind <- Enum.map(tier.produces, & &1.kind),
        reduce: %{} do
      acc -> Map.update(acc, parent, [kind], &Enum.uniq(&1 ++ [kind]))
    end
  end

  defp scope_parent(%Tier{scope: {:per, ref}}), do: ref
  defp scope_parent(%Tier{scope: {:child_of, ref}}), do: ref
  defp scope_parent(%Tier{}), do: nil

  # chain.md #11: a name outside the default set is a load error. The
  # bundle ships no tier that narrows, so this path is exercised by
  # `test/catapult/dsl/chain_test.exs` rather than by `bundles/default`.
  defp narrow_handle(nil, default_fields, default_fragments),
    do: {default_fields, default_fragments}

  defp narrow_handle(names, default_fields, default_fragments) do
    {Enum.filter(default_fields, &(&1 in names)), Enum.filter(default_fragments, &(&1 in names))}
  end

  ## -- Effective context (chain.md #20, #21) -------------------------------

  defp fill_effective_context(tiers, edges) do
    Enum.reduce(tiers, {%{}, []}, fn {name, tier}, {acc, problems} ->
      case Tier.kind(tier) do
        :generating ->
          {tier, tier_problems} = effective_context_for(name, tier, tiers, edges)
          {Map.put(acc, name, tier), problems ++ tier_problems}

        _other ->
          {Map.put(acc, name, tier), problems}
      end
    end)
  end

  # A review or reconcile block's own `context:` adds to the tier's
  # generation-time effective context (chain.md #14) — it is a property
  # of *that block's own render*, never merged back into the tier's own
  # `effective_context`, since a generation dispatch must never see a
  # review-only read.
  defp effective_context_for(name, tier, tiers, edges) do
    parent = scope_parent(tier)
    {derived, derive_problems} = derived_reads(name, parent, edges)

    {explicit, explicit_problems} =
      explicit_reads(name, parent, tier.context_raw, derived, tiers, edges)

    own_context = Map.merge(derived, explicit)

    {review, review_problems} =
      attach_block_context(tier.review, name, parent, "review", own_context, tiers, edges)

    {reconcile, reconcile_problems} =
      attach_block_context(tier.reconcile, name, parent, "reconcile", own_context, tiers, edges)

    tier = %{tier | effective_context: own_context, review: review, reconcile: reconcile}
    {tier, derive_problems ++ explicit_problems ++ review_problems ++ reconcile_problems}
  end

  defp attach_block_context(nil, _name, _parent, _label, _own_context, _tiers, _edges),
    do: {nil, []}

  defp attach_block_context(block, name, parent, label, own_context, tiers, edges) do
    {extra, problems} =
      review_or_reconcile_reads(name, parent, block, label, own_context, tiers, edges)

    {%{block | context: Map.merge(own_context, extra)}, problems}
  end

  # chain.md #20: for every edge instance whose source is `name` or its
  # scope parent, a read named by the edge (or the instance's `as:`)
  # projected by the instance's own `context:` or the edge's default —
  # skipped when that projection is `none`. `type: synthesis` instances
  # are excluded: their target is a list (chain.md #27), which the walk
  # grammar has no syntax for, and the flow engine that would read them
  # is reserved and unbuilt (chain.md #26, #40).
  defp derived_reads(name, parent, edges) do
    {acc, problems} = parent_read(name, parent)

    Enum.reduce(edges, {acc, problems}, fn {edge_name, edge}, {acc, problems} ->
      Enum.reduce(edge.instances, {acc, problems}, fn instance, {acc, problems} ->
        derive_instance(name, parent, edge_name, edge, instance, acc, problems)
      end)
    end)
  end

  # "A generating tier reads its scope parent's handle as parent" —
  # chain.md #20's own first rule, ahead of the edge-instance loop.
  defp parent_read(_name, nil), do: {%{}, []}

  defp parent_read(name, _parent) do
    case ContextWalk.parse("self.parent.handle") do
      {:ok, walk} -> {%{"parent" => walk}, []}
      {:error, reason} -> {%{}, ["tier #{inspect(name)} #{reason}"]}
    end
  end

  defp derive_instance(
         _name,
         _parent,
         _edge_name,
         %{type: "synthesis"},
         _instance,
         acc,
         problems
       ),
       do: {acc, problems}

  defp derive_instance(name, parent, edge_name, edge, instance, acc, problems) do
    proj = instance.context_raw || edge.context_raw
    walk_prefix = walk_prefix(name, parent, edge_name, instance.source, proj)

    if is_nil(walk_prefix) or is_list(instance.target) do
      {acc, problems}
    else
      var = instance.as || edge_name
      raw = "#{walk_prefix} -> #{instance.target}.#{proj}"
      add_derived(name, var, raw, acc, problems)
    end
  end

  defp walk_prefix(_name, _parent, _edge_name, _source, proj) when proj in [nil, "none"], do: nil
  defp walk_prefix(name, _parent, edge_name, name, _proj), do: "self.#{edge_name}"

  defp walk_prefix(_name, parent, edge_name, parent, _proj) when not is_nil(parent),
    do: "self.parent.#{edge_name}"

  defp walk_prefix(_name, _parent, _edge_name, _source, _proj), do: nil

  defp add_derived(name, var, raw, acc, problems) do
    case Map.fetch(acc, var) do
      :error ->
        case ContextWalk.parse(raw) do
          {:ok, walk} -> {Map.put(acc, var, walk), problems}
          {:error, reason} -> {acc, ["tier #{inspect(name)} #{reason}" | problems]}
        end

      {:ok, _existing} ->
        {acc,
         [
           "tier #{inspect(name)}: two derived reads are named #{inspect(var)} — the second " <>
             "instance needs an as: (chain.md #20)"
           | problems
         ]}
    end
  end

  # chain.md #21: `context:` adds to the derived reads; a name
  # colliding with a derived read or a reserved word is a load error.
  defp explicit_reads(name, parent, context_raw, derived, tiers, edges) do
    Enum.reduce(context_raw, {%{}, []}, fn {var, raw}, {acc, problems} ->
      collision_problem = collision_problem(name, var, derived, acc)

      case ContextWalk.parse(raw) do
        {:ok, walk} ->
          walk_problems = walk_cross_reference_problems(name, parent, walk, tiers, edges)
          {Map.put(acc, var, walk), problems ++ List.wrap(collision_problem) ++ walk_problems}

        {:error, reason} ->
          {acc, problems ++ List.wrap(collision_problem) ++ ["tier #{inspect(name)}'s #{reason}"]}
      end
    end)
  end

  defp review_or_reconcile_reads(_name, _parent, nil, _label, _derived, _tiers, _edges),
    do: {%{}, []}

  defp review_or_reconcile_reads(
         name,
         parent,
         %{context_raw: context_raw},
         label,
         derived,
         tiers,
         edges
       ) do
    Enum.reduce(context_raw, {%{}, []}, fn {var, raw}, {acc, problems} ->
      collision_problem = collision_problem(name, var, derived, acc)

      case ContextWalk.parse(raw) do
        {:ok, walk} ->
          walk_problems = walk_cross_reference_problems(name, parent, walk, tiers, edges)

          {Map.put(acc, var, walk), problems ++ List.wrap(collision_problem) ++ walk_problems}

        {:error, reason} ->
          {acc,
           problems ++
             List.wrap(collision_problem) ++ ["tier #{inspect(name)}'s #{label} #{reason}"]}
      end
    end)
  end

  defp collision_problem(name, var, derived, acc) do
    cond do
      var in @reserved_names ->
        "tier #{inspect(name)}'s context names #{inspect(var)}, which is reserved (chain.md #21)"

      Map.has_key?(derived, var) ->
        "tier #{inspect(name)}'s context names #{inspect(var)}, which collides with a derived read (chain.md #21)"

      Map.has_key?(acc, var) ->
        "tier #{inspect(name)}'s context names #{inspect(var)} more than once"

      true ->
        nil
    end
  end

  defp walk_cross_reference_problems(
         name,
         parent,
         %ContextWalk{source: :self, hops: hops, target_tier: target} = walk,
         tiers,
         edges
       )
       when hops != [] do
    hop_chain_problems(name, parent, walk, hops, target, edges) ++
      target_problem(name, target, tiers, walk)
  end

  defp walk_cross_reference_problems(
         _name,
         _parent,
         %ContextWalk{source: :self, target_tier: nil},
         _tiers,
         _edges
       ),
       do: []

  defp walk_cross_reference_problems(
         name,
         _parent,
         %ContextWalk{source: :all, target_tier: target} = walk,
         tiers,
         _edges
       ) do
    target_problem(name, target, tiers, walk) ++
      all_write_scope_problem(name, target, tiers, walk)
  end

  defp walk_cross_reference_problems(
         _name,
         _parent,
         %ContextWalk{source: :input},
         _tiers,
         _edges
       ),
       do: []

  defp walk_cross_reference_problems(
         _name,
         _parent,
         %ContextWalk{source: :ticket},
         _tiers,
         _edges
       ),
       do: []

  defp walk_cross_reference_problems(_name, _parent, _walk, _tiers, _edges), do: []

  defp hop_chain_problems(name, parent, walk, hops, target_tier, edges) do
    last_index = length(hops) - 1
    start = if walk.parent, do: parent, else: name

    {problems, _final_walker} =
      hops
      |> Enum.with_index()
      |> Enum.reduce({[], start}, fn {hop, index}, {problems, current} ->
        {hop_problems, next} =
          resolve_hop(name, walk, current, hop, index == last_index, target_tier, edges)

        {problems ++ hop_problems, next}
      end)

    problems
  end

  defp resolve_hop(name, walk, nil, _hop, _last?, _target_tier, _edges) do
    # `self.parent.<edge>` on a tier with no scope parent at all —
    # reported once as unresolved rather than walking a hop with no
    # basis to start from.
    {[
       "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} starts from self.parent, but this tier has no scope parent"
     ], nil}
  end

  defp resolve_hop(name, walk, walker, hop, last?, target_tier, edges) do
    case Map.fetch(edges, hop.edge) do
      :error ->
        {[
           "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} names edge #{inspect(hop.edge)}, which is not declared"
         ], walker}

      {:ok, declared} ->
        resolve_hop_against(name, walk, walker, hop, declared, last?, target_tier)
    end
  end

  defp resolve_hop_against(name, walk, walker, hop, declared, last?, target_tier) do
    nav = navigation_problem(name, declared, walk, hop.edge)
    matches = matching_instances(declared, hop.reversed?, walker)
    wanted = if last?, do: target_tier
    candidates = if wanted, do: filter_landing(matches, hop.reversed?, wanted), else: matches

    cond do
      candidates != [] ->
        {nav, landing_tier(hd(candidates), hop.reversed?)}

      matches == [] ->
        side = if hop.reversed?, do: "target", else: "source"
        reversal = if hop.reversed?, do: " (reversed)", else: ""

        {nav ++
           [
             "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} traverses edge " <>
               "#{inspect(hop.edge)}#{reversal}, whose declared #{side} does not include #{inspect(walker)}"
           ], walker}

      true ->
        {nav ++
           [
             "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} traverses edge " <>
               "#{inspect(hop.edge)}, but no matching instance lands on #{inspect(wanted)}"
           ], walker}
    end
  end

  defp matching_instances(%Edge{instances: instances}, false, walker) do
    Enum.filter(instances, &(&1.source == walker))
  end

  defp matching_instances(%Edge{instances: instances}, true, walker) do
    Enum.filter(instances, &target_includes?(&1.target, walker))
  end

  defp target_includes?(targets, walker) when is_list(targets), do: walker in targets
  defp target_includes?(target, walker), do: target == walker

  defp filter_landing(instances, reversed?, wanted) do
    Enum.filter(instances, &(landing_tier(&1, reversed?) == wanted))
  end

  defp landing_tier(%{target: t}, false), do: t
  defp landing_tier(%{source: s}, true), do: s

  defp navigation_problem(name, %Edge{navigation: true}, walk, edge_name) do
    [
      "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} traverses edge #{inspect(edge_name)}, marked navigation: true (chain.md #23)"
    ]
  end

  defp navigation_problem(_name, _edge, _walk, _edge_name), do: []

  defp target_problem(_name, nil, _tiers, _walk), do: []

  defp target_problem(name, target, tiers, walk) do
    if Map.has_key?(tiers, target) do
      []
    else
      [
        "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} targets tier #{inspect(target)}, which is not declared"
      ]
    end
  end

  defp all_write_scope_problem(name, target, tiers, walk) do
    case Map.fetch(tiers, target) do
      {:ok, %Tier{generator: "supplied", source_raw: "write"}} ->
        [
          "tier #{inspect(name)}'s context walk #{inspect(walk.raw)} is an all.<tier> walk " <>
            "targeting #{inspect(target)}, a write-sourced supplied tier — never drained (chain.md #22)"
        ]

      _other ->
        []
    end
  end
end
