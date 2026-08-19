defmodule Catapult.Dsl.Edge do
  @moduledoc """
  One `edges/<edge>.yaml` declaration (dsl-syntax.md §4): a shared
  mechanism — `type`, `graph_constraint`, `consistency`, `navigation`,
  `constraint` — over one or more **instances**, each its own
  `source`/`target`/`declared_in`/`cardinality`.

  Most edges declare a single instance, inline at the top level (the
  common case, and the only shape earlier versions of this module
  supported). An edge whose relationship recurs at several sites in
  the tier graph — `decomposition` mints comp from sysarch, subcomp
  from comparch, and vocab from feature_expansion; `dependency` covers
  both comp→comp and subcomp→subcomp — names that once, under
  `instances:`, rather than once per site under a distinct edge name:
  "the mechanism is the same" (this repo's own bundle content cites
  this exact wording). A context walk still names the edge once
  (`.decomposition`, `.dependency`); which instance answers a given
  hop is resolved by matching the walking tier against each
  instance's `source`/`target` (`Catapult.Dsl.Chain`), not by the
  bundle author picking one.

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

  @typedoc "One source/target site sharing the edge's `type` and constraints."
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
  @flat_instance_keys ~w(source target declared_in cardinality)
  @instance_keys ~w(source target declared_in cardinality)
  @core_keys ~w(edge type source target declared_in cardinality instances graph_constraint
                consistency navigation constraint)

  @doc "Parses one edge declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "edge declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "edge", where)
    edge_where = if name, do: "edge #{inspect(name)} (#{file})", else: where

    {type, type_problems} = Fields.require_one_of(raw, "type", @types, edge_where)
    {instances, instance_problems} = parse_instances(raw, edge_where)
    {graph_constraint, gc_problems} = parse_graph_constraint(raw, edge_where)
    {consistency, consistency_problems} = parse_consistency(raw, type, edge_where)
    {navigation, nav_problems} = Fields.optional_boolean(raw, "navigation", edge_where, false)
    {constraint, constraint_problems} = Fields.optional_string(raw, "constraint", edge_where)

    unknown = Fields.unknown_keys(raw, @core_keys, edge_where)

    problems =
      name_problems ++
        type_problems ++
        instance_problems ++
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

  ## source/target/declared_in/cardinality — one instance inline, or
  ## several under instances: (mutually exclusive)

  defp parse_instances(raw, where) do
    flat? = Enum.any?(@flat_instance_keys, &Map.has_key?(raw, &1))
    list? = Map.has_key?(raw, "instances")

    cond do
      flat? and list? ->
        {[],
         [
           "#{where} declares both a flat source/target and instances: — use one instance inline or several under instances:, never both"
         ]}

      list? ->
        parse_instance_list(raw, where)

      flat? ->
        case parse_one_instance(raw, where) do
          {nil, problems} -> {[], problems}
          {instance, []} -> {[instance], []}
        end

      true ->
        {[], ["#{where} declares neither source/target nor instances:"]}
    end
  end

  defp parse_instance_list(raw, where) do
    case Map.fetch(raw, "instances") do
      {:ok, [_ | _] = list} ->
        iw = "#{where}'s instances"

        results =
          for {entry, index} <- Enum.with_index(list, 1),
              do: parse_one_instance(entry, "#{iw} ##{index}", true)

        problems = Enum.flat_map(results, &elem(&1, 1))
        instances = for {instance, []} <- results, do: instance
        {instances, problems}

      {:ok, []} ->
        {[], ["#{where}'s instances is empty, expected at least one"]}

      {:ok, other} ->
        {[], ["#{where}'s instances is #{inspect(other)}, expected a list"]}
    end
  end

  defp parse_one_instance(raw, where, check_unknown? \\ false)

  defp parse_one_instance(%{} = raw, where, check_unknown?) do
    {source, sp} = Fields.require_string(raw, "source", where)
    {target, tp} = Fields.require_string(raw, "target", where)
    {declared_in, dp} = Fields.require_string(raw, "declared_in", where)
    {cardinality, cp} = parse_cardinality(raw, where)

    unknown =
      if check_unknown?, do: Fields.unknown_keys(raw, @instance_keys, where), else: []

    problems = sp ++ tp ++ dp ++ cp ++ unknown

    if problems == [] do
      {%{source: source, target: target, declared_in: declared_in, cardinality: cardinality}, []}
    else
      {nil, problems}
    end
  end

  defp parse_one_instance(other, where, _check_unknown?) do
    {nil, ["#{where} is #{inspect(other)}, expected a YAML mapping"]}
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
