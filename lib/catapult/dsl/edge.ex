defmodule Catapult.Dsl.Edge do
  @moduledoc """
  One `edges/<edge>.yaml` declaration (dsl-syntax.md §4): source, target,
  cardinality, graph and consistency constraints. `graph_constraint:
  acyclic` is an *instance-level* constraint checked at projection time
  (the engine's); this module and `Catapult.Dsl.Bundle` only check what
  §13 puts at load time — that the constraint set and type itself are
  from the closed vocabularies, and that the *type-level* edge-instance
  graph (every declared edge as a `source_tier -> target_tier` arrow) is
  acyclic (`Catapult.Dsl.Graph.Acyclic`).

  Structural parsing only, same split as `Catapult.Dsl.Tier`: whether
  `source`/`target` name tiers that exist is a bundle-level
  cross-reference.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file]
  defstruct [
    :name,
    :file,
    :type,
    :source,
    :target,
    :declared_in,
    :consistency,
    :constraint_raw,
    cardinality: %{},
    graph_constraint: [],
    navigation: false
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          type: String.t() | nil,
          source: String.t() | nil,
          target: String.t() | nil,
          declared_in: String.t() | nil,
          cardinality: map(),
          graph_constraint: [String.t()],
          consistency: String.t() | nil,
          navigation: boolean(),
          constraint_raw: String.t() | nil
        }

  @types ~w(fanout reference dependency policy_application synthesis)
  @graph_constraints ~w(acyclic no_self_loop tree)
  @consistencies ~w(eventual transactional)
  @core_keys ~w(edge type source target declared_in cardinality graph_constraint consistency
                navigation constraint)

  @doc "Parses one edge declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "edge declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "edge", where)
    edge_where = if name, do: "edge #{inspect(name)} (#{file})", else: where

    {type, type_problems} = Fields.require_one_of(raw, "type", @types, edge_where)
    {source, source_problems} = Fields.require_string(raw, "source", edge_where)
    {target, target_problems} = Fields.require_string(raw, "target", edge_where)
    {declared_in, declared_in_problems} = Fields.require_string(raw, "declared_in", edge_where)
    {cardinality, cardinality_problems} = parse_cardinality(raw, edge_where)
    {graph_constraint, gc_problems} = parse_graph_constraint(raw, edge_where)
    {consistency, consistency_problems} = parse_consistency(raw, type, edge_where)
    {navigation, nav_problems} = Fields.optional_boolean(raw, "navigation", edge_where, false)
    {constraint, constraint_problems} = Fields.optional_string(raw, "constraint", edge_where)

    unknown = Fields.unknown_keys(raw, @core_keys, edge_where)

    problems =
      name_problems ++
        type_problems ++
        source_problems ++
        target_problems ++
        declared_in_problems ++
        cardinality_problems ++
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
         source: source,
         target: target,
         declared_in: declared_in,
         cardinality: cardinality,
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
