defmodule Catapult.Dsl.Chain do
  @moduledoc """
  Loads and validates one `kind: chain` bundle end to end
  (dsl-syntax.md §1-§8, §11, §13): resolves its `extends:` layers,
  parses every tier/edge/flow file, then runs the cross-reference and
  acyclicity checks that need the whole bundle in view. All problems
  at once, the way `Catapult.Component.Composer` and `Catapult.Config`
  already do it in this codebase.
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.Extends
  alias Catapult.Dsl.Flow
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Dsl.Manifest
  alias Catapult.Dsl.Predicate
  alias Catapult.Dsl.PredicatesFile
  alias Catapult.Dsl.Registry
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Tier
  alias Catapult.Dsl.Yaml

  @enforce_keys [:name]
  defstruct [:name, tiers: %{}, edges: %{}, flows: %{}, fragments: []]

  @type t :: %__MODULE__{
          name: String.t(),
          tiers: %{String.t() => Tier.t()},
          edges: %{String.t() => Edge.t()},
          flows: %{String.t() => Flow.t()},
          fragments: [String.t()]
        }

  @doc "Loads and validates the chain bundle named `name` under `bundles_root`."
  @spec load(String.t(), String.t(), Registry.t()) :: {:ok, t()} | {:error, [String.t()]}
  def load(bundles_root, name, %Registry{} = registry) do
    manifest_path = Path.join([bundles_root, name, "bundle.yaml"])

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw),
         {:ok, manifest} <- require_kind(manifest, "chain"),
         {:ok, layers} <- Extends.chain(bundles_root, Path.join(bundles_root, name), manifest) do
      build(name, layers, registry)
    end
  end

  defp require_kind(%{kind: kind} = manifest, kind), do: {:ok, manifest}

  defp require_kind(manifest, expected) do
    {:error,
     [
       "#{manifest.file} is a #{manifest.kind} bundle, expected #{expected} " <>
         "(catapult.yaml named it on the #{expected} axis)"
     ]}
  end

  defp build(name, layers, registry) do
    tier_files = Extends.resolve_files(layers, :tier_globs)
    edge_files = Extends.resolve_files(layers, :edge_globs)
    flow_files = Extends.resolve_files(layers, :flow_globs)
    fragments = Extends.fragment_vocabulary(layers)

    {tiers, tier_problems} = parse_all(tier_files, Tier)
    {edges, edge_problems} = parse_all(edge_files, Edge)
    {flows, flow_problems} = parse_all(flow_files, Flow)

    predicates_path = PredicatesFile.resolve(layers)

    with {:ok, named_predicates} <- PredicatesFile.parse(predicates_path) do
      tier_map = index(tiers)
      edge_map = index(edges)
      flow_map = index(flows)

      problems =
        tier_problems ++
          edge_problems ++
          flow_problems ++
          duplicate_names(tiers, "tier") ++
          duplicate_names(edges, "edge") ++
          duplicate_names(flows, "flow") ++
          cross_reference_problems(
            tier_map,
            edge_map,
            flow_map,
            fragments,
            named_predicates,
            registry
          )

      if problems == [] do
        {:ok,
         %__MODULE__{
           name: name,
           tiers: tier_map,
           edges: edge_map,
           flows: flow_map,
           fragments: fragments
         }}
      else
        {:error, Enum.uniq(problems)}
      end
    end
  end

  defp parse_all(files, module) do
    results =
      for path <- files do
        case Yaml.read(path) do
          {:ok, raw} -> module.parse(path, raw)
          {:error, reason} -> {:error, [reason]}
        end
      end

    problems =
      Enum.flat_map(results, fn
        {:ok, _} -> []
        {:error, p} -> p
      end)

    parsed = for {:ok, entry} <- results, do: entry
    {parsed, problems}
  end

  defp index(entries), do: Map.new(entries, &{&1.name, &1})

  defp duplicate_names(entries, label) do
    entries
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> "two or more #{label} declarations name #{inspect(name)}" end)
  end

  ## Cross-reference validation (dsl-syntax.md §13)

  defp cross_reference_problems(tiers, edges, flows, fragments, named_predicates, registry) do
    scope_problems(tiers) ++
      predicate_slot_problems(tiers, edges, flows, named_predicates) ++
      edge_endpoint_problems(edges, tiers) ++
      edge_acyclicity_problems(edges) ++
      Enum.flat_map(tiers, fn {_name, tier} ->
        tier_reference_problems(tier, tiers, edges, fragments, registry)
      end) ++
      flow_reference_problems(flows, tiers)
  end

  defp scope_problems(tiers) do
    for {name, %{scope: {kind, ref}}} <- tiers,
        kind in [:per, :child_of],
        not Map.has_key?(tiers, ref) do
      "tier #{inspect(name)}'s scope #{kind}(#{ref}) names a tier that is not declared"
    end
  end

  defp predicate_slot_problems(tiers, edges, flows, named) do
    tier_slots =
      for {name, tier} <- tiers, tier.scope_filter_raw do
        predicate_problem(tier.scope_filter_raw, named, "tier #{inspect(name)}'s scope_filter")
      end

    cardinality_slots =
      for {name, edge} <- edges,
          instance <- edge.instances,
          when_expr = get_in(instance.cardinality, [:when]),
          when_expr do
        predicate_problem(when_expr, named, "edge #{inspect(name)}'s cardinality.when")
      end

    constraint_slots =
      for {name, edge} <- edges, edge.constraint_raw do
        predicate_problem(edge.constraint_raw, named, "edge #{inspect(name)}'s constraint")
      end

    completion_slots =
      for {name, flow} <- flows, flow.completion do
        predicate_problem(flow.completion, named, "flow #{inspect(name)}'s completion")
      end

    Enum.reject(
      tier_slots ++ cardinality_slots ++ constraint_slots ++ completion_slots,
      &is_nil/1
    )
  end

  # A slot resolves either as a `predicates.yaml` name or as an inline
  # expression (dsl-syntax.md §8) — a bare identifier parses fine either
  # way, so the named form is tried first and the inline parse is the
  # fallback, never a competing error.
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

  defp edge_endpoint_problems(edges, tiers) do
    for {name, edge} <- edges,
        {instance, index} <- Enum.with_index(edge.instances, 1),
        side <- [:source, :target],
        ref = Map.get(instance, side),
        ref && not Map.has_key?(tiers, ref) do
      "edge #{edge_label(edge, name, index)} #{side} #{inspect(ref)} names a tier that is not declared"
    end
  end

  # Single-instance edges (the common case) keep the plain "edge X's"
  # phrasing; only a multi-instance edge needs to say which instance,
  # since its instances may disagree.
  defp edge_label(%{instances: [_one]}, name, _index), do: "#{inspect(name)}'s"
  defp edge_label(_edge, name, index), do: "#{inspect(name)}'s instance ##{index}'s"

  defp edge_acyclicity_problems(edges) do
    pairs =
      for {_name, edge} <- edges, %{source: s, target: t} <- edge.instances, s && t, do: {s, t}

    if DslGraph.acyclic?(pairs) do
      []
    else
      case DslGraph.find_cycle(pairs) do
        nil -> ["the edge-instance graph has a type-level cycle"]
        cycle -> ["the edge-instance graph has a type-level cycle among tiers: #{inspect(cycle)}"]
      end
    end
  end

  defp tier_reference_problems(tier, tiers, edges, fragments, registry) do
    fragment_kind_problems(tier, fragments) ++
      produces_problems(tier, fragments) ++
      context_problems(tier, tier.name, tiers, edges, registry) ++
      delivery_problems(tier) ++
      enforcement_problems(tier, registry)
  end

  defp fragment_kind_problems(tier, fragments) do
    for kind <- tier.handle_fragments, kind not in fragments do
      "tier #{inspect(tier.name)}'s handle.fragments names #{inspect(kind)}, which is not in the bundle's fragment vocabulary #{inspect(fragments)}"
    end
  end

  defp produces_problems(tier, fragments) do
    for produced <- tier.produces do
      cond do
        produced.kind not in fragments ->
          "tier #{inspect(tier.name)}'s produces names fragment kind #{inspect(produced.kind)}, which is not in the bundle's fragment vocabulary #{inspect(fragments)}"

        not self_reference?(produced.owner_raw) ->
          "tier #{inspect(tier.name)}'s produces owner #{inspect(produced.owner_raw)} is not self or self.parent"

        true ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp self_reference?(raw) do
    case ContextWalk.parse(raw) do
      {:ok, %ContextWalk{source: :self, hops: [], target_tier: nil, projection: nil}} -> true
      _other -> false
    end
  end

  defp context_problems(tier, tier_name, tiers, edges, registry) do
    parent_tier =
      case tier.scope do
        {:per, ref} -> ref
        {:child_of, ref} -> ref
        _other -> nil
      end

    Enum.flat_map(
      tier.context,
      &context_entry_problems(&1, tier_name, parent_tier, tiers, edges, registry)
    )
  end

  defp context_entry_problems(
         %ContextWalk{source: :self, hops: []},
         _tier_name,
         _parent,
         _tiers,
         _edges,
         _registry
       ),
       do: []

  defp context_entry_problems(
         %ContextWalk{source: :self, hops: hops, target_tier: target} = walk,
         tier_name,
         parent,
         tiers,
         edges,
         _registry
       )
       when hops != [] do
    walker = if walk.parent, do: parent, else: tier_name

    case walk_hops(hops, walker, edges, walk, tier_name) do
      {:ok, _final_walker} -> target_problem(target, tiers, walk, tier_name)
      {:error, problems} -> problems
    end
  end

  defp context_entry_problems(
         %ContextWalk{source: :all, pool_tier: tier} = walk,
         tier_name,
         _parent,
         tiers,
         _edges,
         _registry
       ) do
    if Map.has_key?(tiers, tier) do
      []
    else
      [
        "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} names all.#{tier}, which is not a declared tier"
      ]
    end
  end

  defp context_entry_problems(
         %ContextWalk{source: :ticket, ticket_source: source} = walk,
         tier_name,
         _parent,
         _tiers,
         _edges,
         registry
       ) do
    if Registry.context_source?(registry, source) do
      []
    else
      [
        "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} names context source " <>
          "#{inspect("ticket." <> source)}, which is not installed (§12: an annotation against an " <>
          "uninstalled extension is a load error naming the missing extension)"
      ]
    end
  end

  defp context_entry_problems(_walk, _tier_name, _parent, _tiers, _edges, _registry), do: []

  # Walks a hop chain from `walker`, one edge at a time: a forward hop
  # requires an instance whose `source` matches the current walker and
  # continues from its `target`; a reversed hop (`.<edge>~`) requires an
  # instance whose `target` matches and continues from its `source`.
  # One edge NAME may carry several instances (`Catapult.Dsl.Edge`); any
  # one of them matching the walker is a legal continuation — the bundle
  # names the edge once, the loader picks the site. When several
  # instances match the walker (an edge fanning one source out to many
  # target tiers, e.g. a flow's plan reaching several possible scaffold
  # kinds), the walk's own `-> <tier>.<projection>` on the *last* hop
  # disambiguates: an instance landing on that tier is preferred over an
  # arbitrary match, so the string the author wrote is the one honored.
  defp walk_hops(hops, walker, edges, walk, tier_name) do
    last_index = length(hops) - 1

    hops
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, walker}, fn {hop, index}, {:ok, current} ->
      prefer = if index == last_index, do: walk.target_tier
      resolve_hop(Map.fetch(edges, hop.edge), hop, current, prefer, walk, tier_name)
    end)
  end

  defp resolve_hop(:error, hop, _current, _prefer, walk, tier_name) do
    {:halt,
     {:error,
      [
        "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} names edge #{inspect(hop.edge)}, which is not declared"
      ]}}
  end

  defp resolve_hop({:ok, declared}, hop, current, prefer, walk, tier_name) do
    case navigation_problem(declared, hop, walk, tier_name) do
      [] -> match_instance_or_error(declared, hop, current, prefer, walk, tier_name)
      problems -> {:halt, {:error, problems}}
    end
  end

  defp match_instance_or_error(declared, hop, current, prefer, walk, tier_name) do
    case find_instance(declared.instances, current, hop.reverse, prefer) do
      {:ok, next} ->
        {:cont, {:ok, next}}

      {:error, :no_candidates} ->
        side = if hop.reverse, do: "target", else: "source"
        reversed = if hop.reverse, do: " (reversed)", else: ""

        {:halt,
         {:error,
          [
            "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} traverses edge #{inspect(hop.edge)}#{reversed}, none of whose instances has #{side} #{inspect(current)}"
          ]}}

      {:error, :no_preferred_match} ->
        {:halt,
         {:error,
          [
            "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} traverses edge #{inspect(hop.edge)}, which has more than one instance matching #{inspect(current)} but none landing on #{inspect(prefer)}"
          ]}}
    end
  end

  defp find_instance(instances, walker, reverse?, prefer) do
    candidates = Enum.filter(instances, &walker_side_matches?(&1, walker, reverse?))
    pick_instance(candidates, reverse?, prefer)
  end

  # One candidate: take it, `prefer` or not — this is the single-
  # instance edge's own long-standing looseness (a walk's `->` target
  # was never checked for equality against the edge's actual target,
  # only for existence as a declared tier — target_problem/2 below),
  # preserved rather than newly tightened.
  defp pick_instance([instance], reverse?, _prefer), do: {:ok, other_side(instance, reverse?)}

  defp pick_instance([], _reverse?, _prefer), do: {:error, :no_candidates}

  # More than one candidate is a genuine fan-out (one source, several
  # target tiers, or the reverse) — the walk's own `prefer` (its final
  # hop's `-> <tier>.<projection>`) is what disambiguates, and here,
  # unlike the single-candidate case, a `prefer` that matches none of
  # them is a real error rather than an arbitrary pick: silently
  # landing on whichever candidate came first would resolve the walk
  # to a tier the walk string never named.
  defp pick_instance(candidates, reverse?, prefer) when prefer != nil do
    case Enum.find(candidates, &(other_side(&1, reverse?) == prefer)) do
      nil -> {:error, :no_preferred_match}
      instance -> {:ok, other_side(instance, reverse?)}
    end
  end

  defp pick_instance(candidates, reverse?, nil) do
    {:ok, other_side(List.first(candidates), reverse?)}
  end

  defp walker_side_matches?(%{source: source}, walker, false), do: source == walker
  defp walker_side_matches?(%{target: target}, walker, true), do: target == walker

  defp other_side(%{target: target}, false), do: target
  defp other_side(%{source: source}, true), do: source

  defp navigation_problem(%{navigation: true}, hop, walk, tier_name) do
    [
      "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} traverses edge #{inspect(hop.edge)}, marked navigation: true — navigation edges are never readiness-bearing (dsl-syntax.md §4, §13)"
    ]
  end

  defp navigation_problem(_edge, _hop, _walk, _tier_name), do: []

  defp target_problem(nil, _tiers, _walk, _tier_name), do: []

  defp target_problem(target, tiers, walk, tier_name) do
    if Map.has_key?(tiers, target) do
      []
    else
      [
        "tier #{inspect(tier_name)}'s context walk #{inspect(walk.raw)} targets tier #{inspect(target)}, which is not declared"
      ]
    end
  end

  defp delivery_problems(%{delivery: nil}), do: []

  defp delivery_problems(%{delivery: %{phase: phase, agent_step: step}, name: name}) do
    phase_problem =
      if phase in Enum.map(SystemStatus.kinds(), &to_string/1) do
        []
      else
        [
          "tier #{inspect(name)}'s delivery.phase #{inspect(phase)} is not a system status " <>
            "(#{inspect(Enum.map(SystemStatus.kinds(), &to_string/1))})"
        ]
      end

    step_problem =
      if step in Enum.map(SystemStatus.agent_steps(), &to_string/1) do
        []
      else
        [
          "tier #{inspect(name)}'s delivery.agent_step #{inspect(step)} is not an agent step " <>
            "(#{inspect(Enum.map(SystemStatus.agent_steps(), &to_string/1))})"
        ]
      end

    phase_problem ++ step_problem
  end

  defp enforcement_problems(%{enforcement: profiles, name: name}, registry) do
    for profile <- profiles, not Registry.enforcement_profile?(registry, profile) do
      "tier #{inspect(name)}'s enforcement names profile #{inspect(profile)}, which is not installed " <>
        "(§12: an annotation against an uninstalled extension is a load error naming the missing extension)"
    end
  end

  defp flow_reference_problems(flows, tiers) do
    for {name, flow} <- flows, flow.ticket_entry, not Map.has_key?(tiers, flow.ticket_entry) do
      "flow #{inspect(name)}'s ticket.entry #{inspect(flow.ticket_entry)} names a tier that is not declared"
    end
  end
end
