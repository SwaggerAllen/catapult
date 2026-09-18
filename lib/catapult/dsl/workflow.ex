defmodule Catapult.Dsl.Workflow do
  @moduledoc """
  Loads and validates one `kind: workflow` bundle end to end
  (`workflow.md`): declared gates and environments, and the unified
  work-item declaration `types.<name>` whose `statuses:` array positions
  everything by array index alone.

  **The cross-axis reference runs from here** (`bundle.md` #11,
  `workflow.md` #22, #23, #40, `systems/core_dsl.md`'s #45.2): a
  generation position names the chain tiers that run at it, and a
  ticket type names the chain flows it serves — the chain names
  nothing back. So `load/4` takes the already-loaded `Catapult.Dsl
  .Chain` and checks against it; the chain's own load never needs the
  workflow in view.

  Two of the structural checks need data this loader is never handed
  in Phase 3 — a gate's role holders live in the identity component,
  the mirror mapping with the outbound tracker add-on — so both are
  **opt-in**: passed via `role_holders`/`mirror_mapping` in `opts`,
  skipped (not failed) when absent.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Edge
  alias Catapult.Dsl.Environment
  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Tier
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Yaml

  @enforce_keys [:name, :entry]
  defstruct [:name, :entry, gates: %{}, environments: %{}, types: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          entry: String.t(),
          gates: %{String.t() => Gate.t()},
          environments: %{String.t() => Environment.t()},
          types: %{String.t() => Type.t()}
        }

  @top_keys ~w(name version kind entry types gates environments)
  @container_required_order ~w(setup prep main retro cleanup)

  @doc "Loads and validates the workflow bundle named `name` under `bundles_root`, against the already-loaded `chain`."
  @spec load(String.t(), String.t(), Chain.t(), keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def load(bundles_root, name, %Chain{} = chain, opts \\ []) do
    dir = Path.join(bundles_root, name)
    path = Path.join(dir, "workflow.yaml")

    with {:ok, raw} <- read_yaml(path),
         {:ok, raw} <- require_kind(raw, path) do
      build(raw, chain, opts)
    end
  end

  defp read_yaml(path) do
    case Yaml.read(path) do
      {:ok, raw} -> {:ok, raw}
      {:error, reason} -> {:error, [reason]}
    end
  end

  defp require_kind(%{"kind" => "workflow"} = raw, _path), do: {:ok, raw}

  defp require_kind(%{"kind" => other}, path) do
    {:error,
     [
       "#{path} is a #{other} bundle, expected workflow (catapult.yaml named it on the workflow axis)"
     ]}
  end

  defp require_kind(_raw, path), do: {:error, ["#{path} is missing required field \"kind\""]}

  defp build(raw, chain, opts) do
    {name, name_p} = Fields.require_string(raw, "name", "workflow.yaml")
    {_version, version_p} = Fields.optional_string(raw, "version", "workflow.yaml")
    {entry, entry_p} = Fields.require_string(raw, "entry", "workflow.yaml")
    {gates, gates_p} = parse_named(raw, "gates", Gate)
    {environments, env_p} = parse_named(raw, "environments", Environment, optional: true)
    {types, types_p} = parse_named(raw, "types", Type)
    unknown = Fields.unknown_keys(raw, @top_keys, "workflow.yaml")

    structural = name_p ++ version_p ++ entry_p ++ gates_p ++ env_p ++ types_p ++ unknown

    if structural != [] do
      {:error, Enum.uniq(structural)}
    else
      problems =
        gate_throwback_problems(types, gates) ++
          environment_promotion_problems(environments) ++
          role_holder_problems(gates, Keyword.get(opts, :role_holders)) ++
          mirror_mapping_problems(gates, Keyword.get(opts, :mirror_mapping)) ++
          skeleton_shape_problems(types) ++
          merge_reconcile_problems(types) ++
          critique_adjacency_problems(types) ++
          name_uniqueness_problems(types) ++
          gate_status_disjointness_problems(types, gates) ++
          flow_reference_problems(types) ++
          review_reference_problems(types, gates) ++
          environment_reference_problems(types, environments) ++
          blocks_problems(types) ++
          declaration_graph_problems(types) ++
          entry_problems(entry, types) ++
          tiers_problems(types, chain) ++
          serves_problems(types, chain) ++
          traversability_problems(types, chain)

      if problems == [] do
        {:ok,
         %__MODULE__{
           name: name,
           entry: entry,
           gates: gates,
           environments: environments,
           types: types
         }}
      else
        {:error, Enum.uniq(problems)}
      end
    end
  end

  defp parse_named(raw, key, module, opts \\ []) do
    fetch =
      if Keyword.get(opts, :optional, false), do: &optional_named/3, else: &Fields.require_map/3

    case fetch.(raw, key, "workflow.yaml") do
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

  ## -- Gate throwback (#33, #34, #35) -------------------------------------

  defp gate_throwback_problems(types, gates) do
    for {type_name, type} <- types,
        {status, index} <- Enum.with_index(type.statuses),
        not is_nil(status.review),
        gate = Map.get(gates, status.review),
        not is_nil(gate),
        not is_nil(gate.throwback),
        problem = gate_throwback_problem(type_name, type, index, status, gate) do
      problem
    end
    |> Enum.reject(&is_nil/1)
  end

  defp gate_throwback_problem(type_name, type, index, status, gate) do
    case resolve_reference(type, gate.throwback) do
      {:ambiguous, namespaces} ->
        "type #{inspect(type_name)}'s #{inspect(status.review)} (#{Type.declared_path(type, index)}) " <>
          "throwback names #{inspect(gate.throwback)}, ambiguous across #{inspect(namespaces)} — qualify it <anchor>.<name>"

      {:ok, %{index: target_index}} when target_index < index ->
        nil

      _not_earlier_or_not_found ->
        "type #{inspect(type_name)}'s #{inspect(status.review)} (#{Type.declared_path(type, index)}) " <>
          "throwback names #{inspect(gate.throwback)}, which is not earlier in this type's own statuses: array"
    end
  end

  defp earlier_names(%Type{} = type, index) do
    type |> earlier_positions(index) |> Enum.map(& &1.canonical)
  end

  defp earlier_positions(%Type{} = type, index) do
    type |> Type.namespaced_positions() |> Enum.filter(&(&1.index < index))
  end

  defp resolve_reference(%Type{} = type, ref) do
    positions = Type.namespaced_positions(type)

    case String.split(ref, ".", parts: 2) do
      [_anchor, _local] ->
        case Enum.find(positions, &(&1.qualified == ref)) do
          nil -> :error
          position -> {:ok, position}
        end

      [_bare] ->
        case Enum.filter(positions, &(&1.bare == ref)) do
          [] -> :error
          [position] -> {:ok, position}
          many -> {:ambiguous, Enum.map(many, & &1.namespace)}
        end
    end
  end

  defp citation(types, type_name, gate_name) do
    with {:ok, type} <- Map.fetch(types, type_name),
         index when not is_nil(index) <- Enum.find_index(type.statuses, &(&1.review == gate_name)) do
      {type, index}
    else
      _not_cited -> nil
    end
  end

  @doc "Every legal landing point for a decline at `gate_name` on a ticket of type `type_name` (#34)."
  @spec throwback_targets(t(), String.t(), String.t()) :: [String.t()]
  def throwback_targets(%__MODULE__{types: types}, type_name, gate_name) do
    case citation(types, type_name, gate_name) do
      {type, index} -> earlier_names(type, index)
      nil -> []
    end
  end

  @doc "Whether `target` is a legal decline target for `gate_name` on a ticket of type `type_name` (#34)."
  @spec throwback_legal?(t(), String.t(), String.t(), String.t()) :: boolean()
  def throwback_legal?(%__MODULE__{} = workflow, type_name, gate_name, target) do
    target in throwback_targets(workflow, type_name, gate_name)
  end

  @doc "`throwback_targets/3`, each target marked whether landing there leaves the gate's own sub-array."
  @spec throwback_target_details(t(), String.t(), String.t()) :: [
          %{target: String.t(), leaves_group: boolean()}
        ]
  def throwback_target_details(%__MODULE__{types: types}, type_name, gate_name) do
    case citation(types, type_name, gate_name) do
      {type, index} ->
        gate_group = Type.group_at(type, index)

        type
        |> earlier_positions(index)
        |> Enum.map(fn pos ->
          %{target: pos.canonical, leaves_group: leaves_group?(type, gate_group, pos.index)}
        end)

      nil ->
        []
    end
  end

  defp leaves_group?(_type, nil, _target_index), do: false

  defp leaves_group?(type, gate_group, target_index),
    do: Type.group_at(type, target_index) != gate_group

  @doc "Whether approving `gate_name` on a ticket of type `type_name` leaves that gate's own citing sub-array."
  @spec approve_leaves_group?(t(), String.t(), String.t()) :: boolean()
  def approve_leaves_group?(%__MODULE__{types: types}, type_name, gate_name) do
    case citation(types, type_name, gate_name) do
      {type, index} ->
        case Type.group_at(type, index) do
          nil -> true
          gate_group -> Type.group_at(type, index + 1) != gate_group
        end

      nil ->
        false
    end
  end

  @doc "Where a decline at `gate_name` lands by default for a ticket of type `type_name` (#34)."
  @spec throwback_default(t(), String.t(), String.t()) :: String.t() | nil
  def throwback_default(%__MODULE__{types: types, gates: gates}, type_name, gate_name) do
    case citation(types, type_name, gate_name) do
      {type, index} ->
        case Map.get(gates, gate_name) do
          %Gate{throwback: declared} when is_binary(declared) -> declared
          _derived -> derived_throwback(type, index)
        end

      nil ->
        nil
    end
  end

  defp derived_throwback(type, index) do
    case Type.group_at(type, index) do
      nil ->
        nil

      range ->
        case Type.anchor_index(type, range) do
          anchor_index when not is_nil(anchor_index) and anchor_index < index ->
            type
            |> Type.namespaced_positions()
            |> Enum.find(&(&1.index == anchor_index))
            |> Map.fetch!(:canonical)

          _nil_or_not_earlier ->
            nil
        end
    end
  end

  ## -- Environments (#39) --------------------------------------------------

  defp environment_promotion_problems(environments) do
    missing =
      for {name, env} <- environments,
          env.promote_from,
          not Map.has_key?(environments, env.promote_from) do
        "environment #{inspect(name)}'s promote_from #{inspect(env.promote_from)} names an environment that is not declared"
      end

    self_problems =
      for {name, env} <- environments, env.promote_from == name do
        "environments' promote_from: references cycle: #{inspect([name, name])}"
      end

    edges = for {name, env} <- environments, env.promote_from, do: {name, env.promote_from}

    cycle_problems =
      if DslGraph.acyclic?(edges) do
        []
      else
        ["environments' promote_from: references cycle: #{inspect(DslGraph.find_cycle(edges))}"]
      end

    missing ++ self_problems ++ cycle_problems
  end

  ## -- Opt-in checks --------------------------------------------------------

  defp role_holder_problems(_gates, nil), do: []

  defp role_holder_problems(gates, holders) do
    for {name, gate} <- gates, gate.role, Map.get(holders, gate.role, []) == [] do
      "gate #{inspect(name)}'s role #{inspect(gate.role)} has no holders — a gate with nobody to route to is indistinguishable from a slow reviewer (v5 §7.16)"
    end
  end

  defp mirror_mapping_problems(_gates, nil), do: []

  defp mirror_mapping_problems(gates, mapping) do
    for {name, _gate} <- gates, not Map.has_key?(mapping, name) do
      "gate #{inspect(name)} has no counterpart in the outbound tracker's mirror mapping (v5 §7.17)"
    end
  end

  ## -- Skeleton shape (#12, #13, #16) --------------------------------------

  defp skeleton_shape_problems(types) do
    Enum.flat_map(types, fn {name, type} ->
      case type.skeleton do
        "container" -> container_shape_problems(name, type)
        "ticket" -> ticket_shape_problems(name, type)
        nil -> []
      end
    end)
  end

  defp anchor_names(type) do
    for %Status{status: s} <- type.statuses, not is_nil(s), do: s
  end

  defp container_shape_problems(name, type) do
    names = anchor_names(type)
    present = Enum.filter(@container_required_order, &(&1 in names))

    cond do
      present != @container_required_order ->
        missing = @container_required_order -- present

        [
          "type #{inspect(name)}'s statuses: is missing #{inspect(missing)} (#16 requires setup, prep, main, retro, cleanup at least once each, in that relative order)"
        ]

      names == [] or List.last(names) != "terminal" ->
        [
          "type #{inspect(name)}'s statuses: must close with terminal; got #{inspect(List.last(names))}"
        ]

      Enum.count(names, &(&1 == "terminal")) > 1 ->
        ["type #{inspect(name)}'s statuses: declares terminal more than once"]

      true ->
        container_relative_order_problems(name, names)
    end
  end

  defp container_relative_order_problems(name, names) do
    indices = for req <- @container_required_order, do: Enum.find_index(names, &(&1 == req))

    if indices == Enum.sort(indices) do
      []
    else
      [
        "type #{inspect(name)}'s statuses: holds setup/prep/main/retro/cleanup out of their required relative order; got #{inspect(names)}"
      ]
    end
  end

  # #12: at least one generation-shaped entry, then checks, reconcile,
  # merge and deploy, in that relative order, then terminal last and once.
  defp ticket_shape_problems(name, type) do
    names = anchor_names(type)
    valid_names = Enum.map(SystemStatus.kinds(), &Atom.to_string/1)
    invalid = Enum.uniq(names) -- valid_names

    cond do
      invalid != [] ->
        [
          "type #{inspect(name)}'s statuses: names #{inspect(invalid)}, not part of the fixed anchor set #{inspect(valid_names)}"
        ]

      names == [] or List.last(names) != "terminal" ->
        [
          "type #{inspect(name)}'s statuses: must close with terminal; got #{inspect(List.last(names))}"
        ]

      Enum.count(names, &(&1 == "terminal")) > 1 ->
        ["type #{inspect(name)}'s statuses: declares terminal more than once"]

      true ->
        ticket_relative_order_problems(name, names)
    end
  end

  defp ticket_relative_order_problems(name, names) do
    has_generation_shaped? = Enum.any?(names, &SystemStatus.generation_shaped?/1)
    missing_fixed = for req <- ~w(checks reconcile merge deploy), req not in names, do: req

    if not has_generation_shaped? or missing_fixed != [] do
      missing = if has_generation_shaped?, do: [], else: ["a generation entry"]

      [
        "type #{inspect(name)}'s statuses: is missing #{inspect(missing ++ missing_fixed)} (#12 requires at least one generation entry, then checks, reconcile, merge and deploy)"
      ]
    else
      generation_index = Enum.find_index(names, &SystemStatus.generation_shaped?/1)

      fixed_indices =
        for req <- ~w(checks reconcile merge deploy), do: Enum.find_index(names, &(&1 == req))

      indices = [generation_index | fixed_indices]

      if indices == Enum.sort(indices) do
        []
      else
        [
          "type #{inspect(name)}'s statuses: holds a generation entry/checks/reconcile/merge/deploy out of their required relative order; got #{inspect(names)}"
        ]
      end
    end
  end

  ## `reconcile` before `merge` (#13), for the case a container's own
  ## array carries them (a ticket type's array is already covered by
  ## the relative-order check above).

  defp merge_reconcile_problems(types) do
    for {type_name, type} <- types do
      names = anchor_names(type)

      names
      |> Enum.with_index()
      |> Enum.filter(fn {name, i} ->
        name == "merge" and "reconcile" not in Enum.take(names, i)
      end)
      |> Enum.map(fn {_name, i} ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, anchor_index(type, i))} is merge, " <>
          "with no earlier reconcile entry in this type's own statuses: array (#13)"
      end)
    end
    |> List.flatten()
  end

  defp anchor_index(%Type{statuses: statuses}, anchor_occurrence) do
    statuses
    |> Enum.with_index()
    |> Enum.filter(fn {%Status{status: s}, _i} -> not is_nil(s) end)
    |> Enum.at(anchor_occurrence)
    |> elem(1)
  end

  ## Critique adjacency (#26): a critique-shaped position follows the
  ## generation position it reviews with no other generation-shaped
  ## position between; checks, gates and environments may sit between.

  defp critique_adjacency_problems(types) do
    for {type_name, type} <- types do
      labels = Enum.map(type.statuses, &entry_label/1)

      labels
      |> Enum.with_index()
      |> Enum.filter(fn {label, i} ->
        label == {:status, "critique"} and not critique_adjacent?(labels, i)
      end)
      |> Enum.map(fn {_label, i} ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, i)} is critique, with no generation " <>
          "position earlier in this array and no other generation position between them (#26)"
      end)
    end
    |> List.flatten()
  end

  defp critique_adjacent?(labels, i) do
    labels
    |> Enum.take(i)
    |> Enum.reverse()
    |> Enum.find(&generation_or_critique_label?/1)
    |> case do
      {:status, name} -> SystemStatus.generation_shaped?(name)
      _other -> false
    end
  end

  defp generation_or_critique_label?({:status, name}),
    do: SystemStatus.generation_shaped?(name) or name == "critique"

  defp generation_or_critique_label?(_other), do: false

  defp entry_label(%Status{status: s}) when not is_nil(s), do: {:status, s}
  defp entry_label(%Status{review: r}) when not is_nil(r), do: {:review, r}
  defp entry_label(%Status{environment: e}) when not is_nil(e), do: {:environment, e}

  ## Name uniqueness within a namespace (#7)

  defp name_uniqueness_problems(types) do
    for {type_name, type} <- types do
      top_level_name_problems(type_name, type) ++ group_name_problems(type_name, type)
    end
    |> List.flatten()
  end

  defp top_level_name_problems(type_name, type) do
    type
    |> Type.namespaced_positions()
    |> Enum.filter(&(&1.namespace == :top_level))
    |> duplicate_bare_name_problems(fn bare ->
      "type #{inspect(type_name)}'s top-level statuses: array names #{inspect(bare)} more than once"
    end)
  end

  defp group_name_problems(type_name, type) do
    for range <- type.groups do
      range
      |> Enum.map(&{&1, Status.name(Enum.at(type.statuses, &1))})
      |> duplicate_bare_name_pairs()
      |> Enum.map(fn bare ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, range.first)} sub-array names #{inspect(bare)} more than once"
      end)
    end
    |> List.flatten()
  end

  defp duplicate_bare_name_problems(positions, message) do
    positions |> Enum.map(& &1.bare) |> duplicate_bare_names() |> Enum.map(message)
  end

  defp duplicate_bare_name_pairs(pairs) do
    pairs |> Enum.map(fn {_index, bare} -> bare end) |> duplicate_bare_names()
  end

  defp duplicate_bare_names(bares) do
    bares
    |> Enum.frequencies()
    |> Enum.filter(fn {_bare, count} -> count > 1 end)
    |> Enum.map(fn {bare, _count} -> bare end)
  end

  ## Gate/status name disjointness (#7)

  defp gate_status_disjointness_problems(types, gates) do
    for {type_name, type} <- types,
        position <- Type.namespaced_positions(type),
        not is_nil(position.entry.status),
        {gate_name, gate} <- gates,
        gate_name in Enum.uniq([position.bare, position.qualified]) do
      gate_status_collision_problem(type_name, type, position, gate_name, gate)
    end
  end

  defp gate_status_collision_problem(
         type_name,
         type,
         %{bare: bare, qualified: bare} = position,
         gate_name,
         _gate
       ) do
    "gate #{inspect(gate_name)} collides with type #{inspect(type_name)}'s status name #{inspect(bare)} " <>
      "(#{Type.declared_path(type, position.index)}) — a declared gate's own name must stay disjoint from every addressable status name"
  end

  defp gate_status_collision_problem(type_name, type, position, gate_name, _gate) do
    "gate #{inspect(gate_name)} collides with type #{inspect(type_name)}'s status name #{inspect(position.bare)} " <>
      "in the #{inspect(position.namespace)} namespace (#{inspect(position.qualified)}, #{Type.declared_path(type, position.index)})"
  end

  ## `flow:`/`review:`/`environment:` cross-references

  defp flow_reference_problems(types) do
    for {type_name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        not Map.has_key?(types, status.flow) do
      "type #{inspect(type_name)}'s #{inspect(status.status)} flow: names #{inspect(status.flow)}, which is not a declared type"
    end
  end

  defp review_reference_problems(types, gates) do
    for {type_name, type} <- types,
        status <- type.statuses,
        not is_nil(status.review),
        not Map.has_key?(gates, status.review) do
      "type #{inspect(type_name)} cites review: #{inspect(status.review)}, which is not a declared gate"
    end
  end

  defp environment_reference_problems(types, environments) do
    for {type_name, type} <- types,
        status <- type.statuses,
        not is_nil(status.environment),
        not Map.has_key?(environments, status.environment) do
      "type #{inspect(type_name)} cites environment: #{inspect(status.environment)}, which is not a declared environment"
    end
  end

  ## `blocks:` scoping (#18)

  defp blocks_problems(types) do
    for {type_name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        target <- status.blocks do
      blocks_problem(type_name, type, status, target)
    end
    |> Enum.reject(&is_nil/1)
  end

  defp blocks_problem(type_name, _type, status, target) when target == status.status do
    "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names itself"
  end

  defp blocks_problem(type_name, type, status, target) do
    case resolve_reference(type, target) do
      {:ok, _position} ->
        nil

      {:ambiguous, namespaces} ->
        "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, ambiguous across #{inspect(namespaces)}"

      :error ->
        "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, which does not resolve to any entry in this type's own statuses: array"
    end
  end

  ## Declaration graph (#30)

  defp declaration_graph_nodes(types) do
    for {name, type} <- types, Enum.any?(type.statuses, &Status.queue_shaped?/1), do: name
  end

  defp declaration_graph_edges(types) do
    nodes = declaration_graph_nodes(types)

    for {name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        status.flow in nodes,
        do: {name, status.flow}
  end

  defp declaration_graph_problems(types) do
    edges = declaration_graph_edges(types)

    self_problems =
      for {from, to} <- edges, from == to do
        "type #{inspect(from)}'s flow: names itself"
      end

    cycle_problems =
      if DslGraph.acyclic?(edges) do
        []
      else
        [
          "the declaration graph (types' flow: references) has a cycle: #{inspect(DslGraph.find_cycle(edges))}"
        ]
      end

    self_problems ++ cycle_problems
  end

  defp declaration_graph_roots(types) do
    nodes = declaration_graph_nodes(types)
    targeted = for {_from, to} <- declaration_graph_edges(types), do: to
    nodes -- Enum.uniq(targeted)
  end

  defp entry_problems(entry_name, types) do
    case Map.fetch(types, entry_name) do
      :error ->
        ["entry #{inspect(entry_name)} does not resolve to a declared type"]

      {:ok, %Type{}} ->
        cond do
          entry_name not in declaration_graph_nodes(types) ->
            ["entry #{inspect(entry_name)} names a type with no population anchor of its own"]

          entry_name not in declaration_graph_roots(types) ->
            ["entry #{inspect(entry_name)} is not a root in the declaration graph"]

          true ->
            []
        end
    end
  end

  ## -- Cross-axis: tiers: (workflow.md #22) --------------------------------

  defp tiers_problems(types, chain) do
    Enum.flat_map(types, fn {type_name, type} -> type_tiers_problems(type_name, type, chain) end)
  end

  defp type_tiers_problems(type_name, type, chain) do
    seen = tier_positions(type)

    name_problems =
      for tier_name <- Enum.uniq(Enum.flat_map(type.statuses, & &1.tiers)) do
        tier_name_problem(type_name, tier_name, chain)
      end

    duplicate_problems =
      for {tier_name, indices} <- seen,
          length(Enum.uniq(indices)) > 1,
          not cascade_visit?(tier_name, chain) do
        "type #{inspect(type_name)} lists tier #{inspect(tier_name)} at more than one position (workflow.md #22)"
      end

    Enum.reject(name_problems, &is_nil/1) ++ duplicate_problems
  end

  defp tier_positions(type) do
    type.statuses
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {status, index}, acc -> record_tier_positions(status, index, acc) end)
  end

  defp record_tier_positions(status, index, acc) do
    Enum.reduce(status.tiers, acc, fn t, acc -> Map.update(acc, t, [index], &[index | &1]) end)
  end

  defp tier_name_problem(type_name, tier_name, chain) do
    case Map.fetch(chain.tiers, tier_name) do
      :error ->
        "type #{inspect(type_name)} lists #{inspect(tier_name)}, which is not a declared tier of the paired chain"

      {:ok, tier} ->
        if Tier.kind(tier) == :generating do
          nil
        else
          "type #{inspect(type_name)} lists #{inspect(tier_name)}, a #{Tier.kind(tier)} tier — only generating tiers run at a position"
        end
    end
  end

  defp cascade_visit?(tier_name, chain) do
    match?({:ok, %Tier{scope: {:cascade_visit}}}, Map.fetch(chain.tiers, tier_name))
  end

  ## -- Cross-axis: serves: (workflow.md #40) -------------------------------

  defp serves_problems(types, chain) do
    outright_claims =
      for {type_name, %Type{serves: {:list, flows}}} <- types,
          flow <- flows,
          do: {flow, type_name}

    duplicate_claims =
      outright_claims
      |> Enum.group_by(fn {flow, _type} -> flow end, fn {_flow, type} -> type end)
      |> Enum.filter(fn {_flow, claimants} -> length(claimants) > 1 end)
      |> Enum.map(fn {flow, claimants} ->
        "flow #{inspect(flow)} is claimed outright by more than one type: #{inspect(claimants)}"
      end)

    unknown_flow_claims =
      for {flow, type_name} <- outright_claims, not Map.has_key?(chain.flows, flow) do
        "type #{inspect(type_name)}'s serves: names flow #{inspect(flow)}, which is not declared in the paired chain"
      end

    unclaimed =
      for {flow_name, flow} <- chain.flows,
          serving_type(flow_name, flow, types, outright_claims) == :none do
        "flow #{inspect(flow_name)} is served by no type"
      end

    duplicate_claims ++ unknown_flow_claims ++ unclaimed
  end

  defp has_delta?(%{delta_tiers: [], delta_edges: []}), do: false
  defp has_delta?(_flow), do: true

  # A type naming a flow outright beats one matching it by predicate
  # (workflow.md #40); `:none` when nothing serves it at all.
  defp serving_type(flow_name, flow, types, outright_claims) do
    case Enum.find(outright_claims, fn {f, _t} -> f == flow_name end) do
      {_flow, type_name} -> type_name
      nil -> serving_type_by_predicate(flow, types)
    end
  end

  defp serving_type_by_predicate(flow, types) do
    want = if has_delta?(flow), do: "has_delta", else: "no_delta"

    case Enum.filter(types, fn {_name, t} -> t.serves == {:predicate, want} end) do
      [{type_name, _type}] -> type_name
      _none_or_many -> :none
    end
  end

  ## -- Cross-axis: traversability (workflow.md #23) ------------------------

  defp traversability_problems(types, chain) do
    all_delta = for {_name, flow} <- chain.flows, t <- flow.delta_tiers, uniq: true, do: t

    generating =
      for {name, tier} <- chain.tiers, Tier.kind(tier) == :generating, uniq: true, do: name

    layouts = for {name, type} <- types, into: %{}, do: {name, layout(type)}

    outright_claims =
      for {type_name, %Type{serves: {:list, flows}}} <- types,
          flow <- flows,
          do: {flow, type_name}

    Enum.flat_map(chain.flows, fn {flow_name, flow} ->
      case serving_type(flow_name, flow, types, outright_claims) do
        :none ->
          []

        type_name ->
          flow_traversability_problems(
            flow_name,
            flow,
            type_name,
            layouts,
            generating,
            all_delta,
            chain
          )
      end
    end)
  end

  defp flow_traversability_problems(
         flow_name,
         flow,
         type_name,
         layouts,
         generating,
         all_delta,
         chain
       ) do
    tier_at = Map.get(layouts, type_name, %{})
    active = (generating -- all_delta) ++ flow.delta_tiers

    Enum.flat_map(Enum.uniq(active), fn tier_name ->
      unfit_problem(flow_name, type_name, tier_name, tier_at) ++
        ordering_problems(flow_name, type_name, tier_name, tier_at, active, chain)
    end)
  end

  # `{position index by tier}`, from every position that names `tiers:`.
  defp layout(type) do
    type.statuses
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {status, index}, acc ->
      Enum.reduce(status.tiers, acc, fn t, acc -> Map.put_new(acc, t, index) end)
    end)
  end

  defp unfit_problem(flow_name, type_name, tier_name, tier_at) do
    if Map.has_key?(tier_at, tier_name) do
      []
    else
      [
        "flow #{inspect(flow_name)} -> type #{inspect(type_name)}: tier #{inspect(tier_name)} runs in this flow and no position lists it (workflow.md #22)"
      ]
    end
  end

  # Every structural read (a walk from self or the parent) must resolve
  # to a node whose generating tier sits at the same or an earlier
  # position (workflow.md #23) — `all.<tier>` reads are global and
  # ordered as a note only in the reference checker, never an error
  # here (a flow's plan tier reads the graph it is about to regenerate).
  defp ordering_problems(flow_name, type_name, tier_name, tier_at, active, chain) do
    tier = Map.fetch!(chain.tiers, tier_name)
    parent = scope_parent_name(tier)

    walk_targets =
      for {_var, walk} <- tier.effective_context,
          walk.source == :self,
          target = structural_target(walk, parent),
          not is_nil(target),
          uniq: true,
          do: target

    for target <- walk_targets,
        generating_ancestor = generating_ancestor(target, chain),
        generating_ancestor in active,
        Map.has_key?(tier_at, generating_ancestor),
        Map.has_key?(tier_at, tier_name),
        tier_at[generating_ancestor] > tier_at[tier_name] do
      "flow #{inspect(flow_name)} -> type #{inspect(type_name)}: #{tier_name} reads #{target}, generated at a later position"
    end
  end

  defp scope_parent_name(%Tier{scope: {:per, ref}}), do: ref
  defp scope_parent_name(%Tier{scope: {:child_of, ref}}), do: ref
  defp scope_parent_name(%Tier{}), do: nil

  defp structural_target(%{target_tier: target}, _parent) when not is_nil(target), do: target
  defp structural_target(%{source: :self, parent: true, target_tier: nil}, parent), do: parent
  defp structural_target(_walk, _parent), do: nil

  # A join target's position is its minting tier's; a supplied tier has none.
  defp generating_ancestor(tier_name, chain, seen \\ MapSet.new()) do
    cond do
      MapSet.member?(seen, tier_name) or not Map.has_key?(chain.tiers, tier_name) ->
        nil

      Tier.kind(Map.fetch!(chain.tiers, tier_name)) == :generating ->
        tier_name

      true ->
        case minting_source(tier_name, chain.edges) do
          nil -> nil
          source -> generating_ancestor(source, chain, MapSet.put(seen, tier_name))
        end
    end
  end

  defp minting_source(tier_name, edges) do
    Enum.find_value(edges, fn {_name, edge} -> fanout_source_for(edge, tier_name) end)
  end

  defp fanout_source_for(%Edge{type: "fanout", instances: instances}, tier_name) do
    Enum.find_value(instances, fn i -> if i.target == tier_name, do: i.source end)
  end

  defp fanout_source_for(_edge, _tier_name), do: nil
end
