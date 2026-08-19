defmodule Catapult.Dsl.Edge do
  @moduledoc """
  One `edges/<edge>.yaml` declaration (dsl-syntax.md §4): one or more
  source/target/declared_in/cardinality **instances** sharing one name,
  one `type`, and one set of graph/consistency constraints.
  `graph_constraint: acyclic` is an *instance-level* constraint checked
  at projection time (the engine's); this module and
  `Catapult.Dsl.Chain` only check what §13 puts at load time — that the
  constraint set and type itself are from the closed vocabularies, and
  that the *type-level* edge-instance graph (every declared instance as
  a `source_tier -> target_tier` arrow) is acyclic
  (`Catapult.Dsl.Graph`).

  **The flat, single-site shape** (`source`/`target`/`declared_in`/
  `cardinality` inline) **and `instances:` are mutually exclusive**
  (dsl-syntax.md §4.1) — an edge declares exactly one instance inline,
  or several under `instances:`, never both, never neither. Both forms
  normalize to the same `instances:` list on this struct so every
  consumer (`Catapult.Dsl.Chain`) reads one shape regardless of which
  the bundle author wrote.

  Structural parsing only, same split as `Catapult.Dsl.Tier`: whether
  an instance's `source`/`target` name tiers that exist is a
  bundle-level cross-reference.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file]
  defstruct [
    :name,
    :file,
    :type,
    :consistency,
    :constraint_raw,
    instances: [],
    graph_constraint: [],
    navigation: false
  ]

  @typedoc "One `{source, target}` site sharing this edge's name and mechanism."
  @type instance :: %{
          source: String.t(),
          target: String.t(),
          declared_in: String.t(),
          cardinality: map()
        }

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          type: String.t() | nil,
          instances: [instance()],
          graph_constraint: [String.t()],
          consistency: String.t() | nil,
          navigation: boolean(),
          constraint_raw: String.t() | nil
        }

  @types ~w(fanout reference dependency policy_application synthesis)
  @graph_constraints ~w(acyclic no_self_loop tree)
  @consistencies ~w(eventual transactional)
  @common_keys ~w(edge type graph_constraint consistency navigation constraint)
  @instance_keys ~w(source target declared_in cardinality)
  @core_keys @common_keys ++ @instance_keys ++ ["instances"]

  @doc "Parses one edge declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "edge declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "edge", where)
    edge_where = if name, do: "edge #{inspect(name)} (#{file})", else: where

    {type, type_problems} = Fields.require_one_of(raw, "type", @types, edge_where)
    {instances, instances_problems} = parse_instances(raw, edge_where)
    {graph_constraint, gc_problems} = parse_graph_constraint(raw, edge_where)
    {consistency, consistency_problems} = parse_consistency(raw, type, edge_where)
    {navigation, nav_problems} = Fields.optional_boolean(raw, "navigation", edge_where, false)
    {constraint, constraint_problems} = Fields.optional_string(raw, "constraint", edge_where)

    unknown = Fields.unknown_keys(raw, @core_keys, edge_where)

    problems =
      name_problems ++
        type_problems ++
        instances_problems ++
        gc_problems ++
        consistency_problems ++
        nav_problems ++
        constraint_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         type: type,
         instances: instances,
         graph_constraint: graph_constraint,
         consistency: consistency,
         navigation: navigation,
         constraint_raw: constraint
       }}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["edge declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end

  ## instances: vs the flat single-site shape (§4.1) — mutually exclusive

  defp parse_instances(raw, where) do
    flat_present? = Enum.any?(@instance_keys, &Map.has_key?(raw, &1))
    instances_present? = Map.has_key?(raw, "instances")

    case {flat_present?, instances_present?} do
      {true, true} ->
        {[],
         [
           "#{where} declares both an inline instance (#{inspect(@instance_keys)}) and " <>
             "instances: — an edge names one instance inline or several under instances:, never both"
         ]}

      {false, false} ->
        {[],
         [
           "#{where} declares neither an inline instance (#{inspect(@instance_keys)}) nor instances:"
         ]}

      {true, false} ->
        # The flat form's source/target/declared_in/cardinality sit at the
        # same top level as the common keys (edge, type, ...); those are
        # already checked by parse/2's own top-level unknown_keys call, so
        # this parse skips a second, narrower one that would misreport them.
        case parse_instance_fields(raw, where) do
          {instance, []} -> {[instance], []}
          {_instance, problems} -> {[], problems}
        end

      {false, true} ->
        parse_instances_list(raw, where)
    end
  end

  defp parse_instances_list(raw, where) do
    case Map.fetch(raw, "instances") do
      {:ok, entries} when is_list(entries) and entries != [] ->
        results =
          for {entry, index} <- Enum.with_index(entries) do
            parse_instance_entry(entry, "#{where}'s instances[#{index}]")
          end

        problems = Enum.flat_map(results, &elem(&1, 1))
        instances = for {instance, []} <- results, do: instance
        {instances, problems}

      {:ok, []} ->
        {[], ["#{where}'s instances is empty, expected at least one instance"]}

      {:ok, other} ->
        {[], ["#{where}'s instances is #{inspect(other)}, expected a list"]}
    end
  end

  defp parse_instance_entry(%{} = entry, where) do
    unknown = Fields.unknown_keys(entry, @instance_keys, where)

    case parse_instance_fields(entry, where) do
      {instance, []} -> {instance, unknown}
      {_instance, problems} -> {nil, problems ++ unknown}
    end
  end

  defp parse_instance_entry(other, where) do
    {nil, ["#{where} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_instance_fields(raw, where) do
    {source, source_problems} = Fields.require_string(raw, "source", where)
    {target, target_problems} = Fields.require_string(raw, "target", where)
    {declared_in, declared_in_problems} = Fields.require_string(raw, "declared_in", where)
    {cardinality, cardinality_problems} = parse_cardinality(raw, where)

    problems = source_problems ++ target_problems ++ declared_in_problems ++ cardinality_problems

    if problems == [] do
      {%{source: source, target: target, declared_in: declared_in, cardinality: cardinality}, []}
    else
      {nil, problems}
    end
  end

  defp parse_cardinality(raw, where) do
    case Fields.require_map(raw, "cardinality", where) do
      {nil, problems} ->
        {%{}, problems}

      {cardinality, []} ->
        cw = "#{where}'s cardinality"
        {source, sp} = parse_cardinality_side(cardinality, "source", cw)
        {target, tp} = parse_cardinality_side(cardinality, "target", cw)
        {when_pred, wp} = Fields.optional_string(cardinality, "when", cw)
        {per_source, psp} = Fields.optional_string(cardinality, "per_source", cw)
        unknown = Fields.unknown_keys(cardinality, ["source", "target", "when", "per_source"], cw)
        problems = sp ++ tp ++ wp ++ psp ++ unknown

        if problems == [] do
          {%{source: source, target: target, when: when_pred, per_source: per_source}, []}
        else
          {%{}, problems}
        end
    end
  end

  defp parse_cardinality_side(cardinality, side, where) do
    case Fields.require_map(cardinality, side, where) do
      {nil, problems} ->
        {nil, problems}

      {bounds, []} ->
        bw = "#{where}'s #{side}"
        {min, minp} = require_non_negative_integer(bounds, "min", bw)
        {max, maxp} = optional_positive_integer(bounds, "max", bw)
        unknown = Fields.unknown_keys(bounds, ["min", "max"], bw)
        problems = minp ++ maxp ++ unknown

        if problems == [], do: {%{min: min, max: max}, []}, else: {nil, problems}
    end
  end

  defp require_non_negative_integer(map, key, where) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) and value >= 0 ->
        {value, []}

      {:ok, value} ->
        {nil, ["#{where} #{inspect(key)} is #{inspect(value)}, expected a non-negative integer"]}

      :error ->
        {nil, ["#{where} is missing required field #{inspect(key)}"]}
    end
  end

  defp optional_positive_integer(map, key, where) do
    case Map.fetch(map, key) do
      :error ->
        {:unbounded, []}

      {:ok, value} when is_integer(value) and value > 0 ->
        {value, []}

      {:ok, value} ->
        {:unbounded,
         ["#{where} #{inspect(key)} is #{inspect(value)}, expected a positive integer"]}
    end
  end

  defp parse_graph_constraint(raw, where) do
    {values, problems} = Fields.optional_string_list(raw, "graph_constraint", where)

    invalid =
      for value <- values, value not in @graph_constraints do
        "#{where}'s graph_constraint #{inspect(value)} is not one of #{inspect(@graph_constraints)}"
      end

    {values, problems ++ invalid}
  end

  # `consistency:` is meaningful only on `dependency` edges (dsl-syntax.md
  # §4); other edge types carry no eventual/transactional distinction, so
  # the field is refused there rather than silently ignored.
  defp parse_consistency(raw, "dependency", where) do
    Fields.optional_one_of(raw, "consistency", @consistencies, where, "eventual")
  end

  defp parse_consistency(raw, _type, where) do
    case Map.fetch(raw, "consistency") do
      :error ->
        {nil, []}

      {:ok, _value} ->
        {nil, ["#{where} declares consistency:, which only a dependency edge may carry"]}
    end
  end
end
