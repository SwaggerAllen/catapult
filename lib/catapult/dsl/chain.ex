defmodule Catapult.Dsl.Chain do
  @moduledoc """
  Loads and validates one `kind: chain` bundle end to end
  (dsl-syntax.md §1-§8, §11, §13): reads its one directory, parses
  every tier/edge/flow file, then runs the cross-reference and
  acyclicity checks that need the whole bundle in view. All problems
  at once, the way `Catapult.Component.Composer` and `Catapult.Config`
  already do it in this codebase.
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.DeclaredInSchema
  alias Catapult.Dsl.Edge
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
  defstruct [:name, tiers: %{}, edges: %{}, flows: %{}, fragments: [], predicates: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          tiers: %{String.t() => Tier.t()},
          edges: %{String.t() => Edge.t()},
          flows: %{String.t() => Flow.t()},
          fragments: [String.t()],
          predicates: %{String.t() => Predicate.t()}
        }

  @doc """
  Resolves a predicate-language slot's raw string (dsl-syntax.md §8) —
  `scope_filter`, `cardinality.when`, an edge `constraint`, a flow
  `completion` — against this bundle's own `predicates.yaml`: a
  registered name wins, an inline expression parses fresh. The same
  two-step `build/3` already runs at load time to validate every slot;
  this is that step exposed as a value instead of only a pass/fail,
  because a runtime evaluator (`Catapult.Engine.Projections
  .PredicateEvaluator`) needs the resolved AST, not a validation
  verdict (`systems/core_dsl.md`, ORC-8).
  """
  @spec resolve_predicate(t(), String.t()) :: {:ok, Predicate.t()} | {:error, String.t()}
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
    manifest_path = Path.join(dir, "bundle.yaml")

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw),
         {:ok, manifest} <- require_kind(manifest, "chain") do
      build(dir, manifest, registry)
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

  defp build(dir, manifest, registry) do
    tier_files = resolve_globs(dir, manifest.tier_globs)
    edge_files = resolve_globs(dir, manifest.edge_globs)
    flow_files = resolve_globs(dir, manifest.flow_globs)
    fragments = manifest.fragments

    {tiers, tier_problems} = parse_all(tier_files, Tier)
    {edges, edge_problems} = parse_all(edge_files, Edge)
    {flows, flow_problems} = parse_all(flow_files, Flow)

    predicates_path = PredicatesFile.resolve(dir)

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
            dir,
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
           name: manifest.name,
           tiers: tier_map,
           edges: edge_map,
           flows: flow_map,
           fragments: fragments,
           predicates: named_predicates
         }}
      else
        {:error, Enum.uniq(problems)}
      end
    end
  end

  defp resolve_globs(dir, globs) do
    globs |> Enum.flat_map(&Yaml.glob(dir, &1)) |> Enum.uniq() |> Enum.sort()
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

  defp cross_reference_problems(dir, tiers, edges, flows, fragments, named_predicates, registry) do
    scope_problems(tiers) ++
      predicate_slot_problems(tiers, edges, flows, named_predicates) ++
      edge_endpoint_problems(edges, tiers) ++
      edge_acyclicity_problems(edges) ++
      declared_in_schema_problems(dir, tiers, edges) ++
      review_tier_problems(tiers) ++
      Enum.flat_map(tiers, fn {_name, tier} ->
        tier_reference_problems(tier, tiers, edges, fragments, registry)
      end) ++
      flow_reference_problems(flows, tiers)
  end

  defp declared_in_schema_problems(dir, tiers, edges),
    do: DeclaredInSchema.problems(dir, tiers, edges)

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
          when_expr = get_in(instance, [:cardinality, :when]),
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
        instance <- edge.instances,
        {side, ref} <- [{:source, instance.source}, {:target, instance.target}],
        not Map.has_key?(tiers, ref) do
      "edge #{inspect(name)}'s #{side} #{inspect(ref)} names a tier that is not declared"
    end
  end

  defp edge_acyclicity_problems(edges) do
    pairs = for {_name, edge} <- edges, %{source: s, target: t} <- edge.instances, do: {s, t}

    if DslGraph.acyclic?(pairs) do
      []
    else
      case DslGraph.find_cycle(pairs) do
        nil -> ["the edge-instance graph has a type-level cycle"]
        cycle -> ["the edge-instance graph has a type-level cycle among tiers: #{inspect(cycle)}"]
      end
    end
  end

  ## Review tiers (dsl-syntax.md §3.3, §13): `reviews:` names a
  ## declared tier, and the review tier's own `context:` is exactly the
  ## same set of walks as the reviewed tier's — the per-tier triad
  ## invariant (§9), checked rather than trusted.

  defp review_tier_problems(tiers) do
    for {name, %{reviews: reviews} = tier} <- tiers, not is_nil(reviews) do
      review_reference_problems(name, tier, reviews, tiers)
    end
    |> List.flatten()
  end

  defp review_reference_problems(name, _tier, reviewed_name, tiers)
       when not is_map_key(tiers, reviewed_name) do
    [
      "tier #{inspect(name)}'s reviews #{inspect(reviewed_name)} names a tier that is not declared"
    ]
  end

  defp review_reference_problems(name, tier, reviewed_name, tiers) do
    reviewed = Map.fetch!(tiers, reviewed_name)
    own = MapSet.new(tier.context, & &1.raw)
    theirs = MapSet.new(reviewed.context, & &1.raw)

    if MapSet.equal?(own, theirs) do
      []
    else
      diff = MapSet.symmetric_difference(own, theirs) |> MapSet.to_list() |> Enum.sort()

      [
        "tier #{inspect(name)}'s context does not match reviewed tier #{inspect(reviewed_name)}'s " <>
          "own context (dsl-syntax.md §3.3) — differing entries: #{inspect(diff)}"
      ]
    end
  end

  defp tier_reference_problems(tier, tiers, edges, fragments, registry) do
    fragment_kind_problems(tier, fragments) ++
      produces_problems(tier, fragments) ++
      context_problems(tier, tiers, edges, registry) ++
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

  ## context: (§7, §7.1, §7.2) — walker resolution. A review tier has no
  ## scope of its own (§3.3): `self`/`self.parent` inside its `context:`
  ## resolve exactly as they do for the tier it reviews, since the
  ## underlying node is the same one, so the walker basis is the
  ## reviewed tier's name/parent rather than the review tier's own.

  defp context_problems(tier, tiers, edges, registry) do
    {walker_name, parent_tier} = walker_basis(tier, tiers)

    Enum.flat_map(
      tier.context,
      &context_entry_problems(&1, tier.name, walker_name, parent_tier, tiers, edges, registry)
    )
  end

  defp walker_basis(%{reviews: reviews}, tiers) when not is_nil(reviews) do
    case Map.fetch(tiers, reviews) do
      {:ok, reviewed} -> {reviews, parent_tier_of(reviewed)}
      # Unresolvable reviews: already reported by review_tier_problems/1.
      :error -> {reviews, nil}
    end
  end

  defp walker_basis(tier, _tiers), do: {tier.name, parent_tier_of(tier)}

  defp parent_tier_of(%{scope: {:per, ref}}), do: ref
  defp parent_tier_of(%{scope: {:child_of, ref}}), do: ref
  defp parent_tier_of(_tier), do: nil

  defp context_entry_problems(
         %ContextWalk{source: :self, hops: []},
         _message_name,
         _walker_name,
         _parent,
         _tiers,
         _edges,
         _registry
       ),
       do: []

  defp context_entry_problems(
         %ContextWalk{source: :self, hops: hops, target_tier: target} = walk,
         message_name,
         walker_name,
         parent,
         tiers,
         edges,
         _registry
       )
       when hops != [] do
    walker = if walk.parent, do: parent, else: walker_name

    hop_chain_problems(walk, message_name, walker, hops, target, edges) ++
      target_problem(target, tiers, walk, message_name)
  end

  defp context_entry_problems(
         %ContextWalk{source: :all, target_tier: target} = walk,
         message_name,
         _walker_name,
         _parent,
         tiers,
         _edges,
         _registry
       ) do
    target_problem(target, tiers, walk, message_name)
  end

  defp context_entry_problems(
         %ContextWalk{source: :ticket, ticket_source: source} = walk,
         message_name,
         _walker_name,
         _parent,
         _tiers,
         _edges,
         registry
       ) do
    if Registry.context_source?(registry, source) do
      []
    else
      [
        "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} names context source " <>
          "#{inspect("ticket." <> source)}, which is not installed (§12: an annotation against an " <>
          "uninstalled extension is a load error naming the missing extension)"
      ]
    end
  end

  defp context_entry_problems(
         _walk,
         _message_name,
         _walker_name,
         _parent,
         _tiers,
         _edges,
         _registry
       ),
       do: []

  # Walks the hop chain from `walker`, checking each hop's edge is
  # declared and has an instance on the required side (§7.1: a
  # reversed hop matches the edge's `target` instead of its `source`).
  # `Catapult.Dsl.Edge`'s `instances:` form (§4.1) means more than one
  # instance can share a hop's required side; only the *last* hop's own
  # declared target type disambiguates among them — every earlier hop
  # just needs some instance on the required side.
  defp hop_chain_problems(walk, message_name, walker, hops, target_tier, edges) do
    last_index = length(hops) - 1

    {problems, _final_walker} =
      hops
      |> Enum.with_index()
      |> Enum.reduce({[], walker}, fn {hop, index}, {problems, current} ->
        {hop_problems, next_walker} =
          resolve_hop(walk, message_name, current, hop, index == last_index, target_tier, edges)

        {problems ++ hop_problems, next_walker}
      end)

    problems
  end

  defp resolve_hop(walk, message_name, walker, hop, last?, target_tier, edges) do
    case Map.fetch(edges, hop.edge) do
      :error ->
        {
          [
            "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} names edge " <>
              "#{inspect(hop.edge)}, which is not declared"
          ],
          walker
        }

      {:ok, declared} ->
        resolve_hop_against(walk, message_name, walker, hop, declared, last?, target_tier)
    end
  end

  defp resolve_hop_against(walk, message_name, walker, hop, declared, last?, target_tier) do
    nav = navigation_problem(declared, walk, message_name, hop.edge)
    matches = matching_instances(declared, hop.reversed?, walker)
    wanted = if last?, do: target_tier
    candidates = if wanted, do: filter_landing(matches, hop.reversed?, wanted), else: matches

    cond do
      candidates != [] ->
        {nav, landing_tier(hd(candidates), hop.reversed?)}

      matches == [] ->
        side = if hop.reversed?, do: "target", else: "source"
        reversal = if hop.reversed?, do: " (reversed)", else: ""

        {
          nav ++
            [
              "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} traverses edge " <>
                "#{inspect(hop.edge)}#{reversal}, whose declared #{side} does not include #{inspect(walker)}"
            ],
          walker
        }

      true ->
        {
          nav ++
            [
              "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} traverses edge " <>
                "#{inspect(hop.edge)}, but no matching instance lands on #{inspect(wanted)}"
            ],
          walker
        }
    end
  end

  defp matching_instances(%Edge{instances: instances}, false, walker) do
    Enum.filter(instances, &(&1.source == walker))
  end

  defp matching_instances(%Edge{instances: instances}, true, walker) do
    Enum.filter(instances, &(&1.target == walker))
  end

  defp filter_landing(instances, reversed?, wanted) do
    Enum.filter(instances, &(landing_tier(&1, reversed?) == wanted))
  end

  defp landing_tier(%{target: t}, false), do: t
  defp landing_tier(%{source: s}, true), do: s

  defp navigation_problem(%Edge{navigation: true}, walk, message_name, edge_name) do
    [
      "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} traverses edge #{inspect(edge_name)}, marked navigation: true — navigation edges are never readiness-bearing (dsl-syntax.md §4, §13)"
    ]
  end

  defp navigation_problem(_edge, _walk, _message_name, _edge_name), do: []

  defp target_problem(nil, _tiers, _walk, _message_name), do: []

  defp target_problem(target, tiers, walk, message_name) do
    if Map.has_key?(tiers, target) do
      []
    else
      [
        "tier #{inspect(message_name)}'s context walk #{inspect(walk.raw)} targets tier #{inspect(target)}, which is not declared"
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
