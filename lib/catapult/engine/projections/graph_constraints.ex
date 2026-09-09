defmodule Catapult.Engine.Projections.GraphConstraints do
  @moduledoc """
  Evaluates every edge instance's declared `cardinality` and every
  edge's `graph_constraint` against real committed edges —
  dsl-syntax.md §13's own "checked at projection time (the engine's)"
  answered concretely (`systems/engine.md`'s ORC-236 entry).

  **Reported, never blocking.** No function here declines a draft or
  gates a transition — a violation is a `Catapult.Engine.Projections
  .GraphConstraints.violation()` this module hands back, and where
  that surfaces (a ticket, a dashboard entry, a structured signal) is
  generation's/delivery's to build against this timing rule, not a new
  engine primitive.

  **Timing.** A `max` bound is evaluated unconditionally: a count that
  has already exceeded a ceiling stays exceeded regardless of what else
  is still pending, so checking early costs nothing. A `min` bound and
  every `graph_constraint` (`acyclic`/`no_self_loop`/`tree`, properties
  of the whole instance graph rather than of one edge as it is written)
  wait on `Catapult.Engine.Projections.ReadyScopes.drained?/3` for the
  bound side's own tier — the identical "has everything that could
  ever exist already committed and settled" question `all.<tier>`
  readiness already answers, asked here of a cardinality bound instead
  of a context walk. Evaluated any earlier, `fulfills`'s `source: {min:
  1}` ("every comp fulfills ≥1 resp") reads as violated on every comp
  that has not yet drafted its own `fulfills` edge — noise
  indistinguishable from a real defect, not a finding.

  `cardinality.when`/`per_source` are parsed by `Catapult.Dsl.Edge` but
  not evaluated here — no edge instance in `bundles/default` uses
  either, and building evaluation for a slot nothing exercises is
  exactly the half-finished implementation this grammar otherwise
  avoids. A bundle that adds one gets no cardinality check on that
  instance until a later pass builds it, rather than a wrong one.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store

  @typedoc "One declared bound (or graph constraint) this project's committed edges violate."
  @type violation ::
          %{
            kind: :cardinality,
            edge: String.t(),
            side: :source | :target,
            tier: String.t(),
            node_id: binary(),
            count: non_neg_integer(),
            bound: %{min: non_neg_integer(), max: pos_integer() | :unbounded}
          }
          | %{kind: :graph_constraint, edge: String.t(), constraint: String.t(), detail: term()}

  @doc """
  Every cardinality/graph_constraint violation `chain` declares against
  `project_id`'s current committed edges, evaluated at whatever bound
  each is honestly checkable now — a `min`/graph_constraint on a side
  whose tier is not yet `drained?/3` is skipped this call, not reported
  as satisfied.
  """
  @spec violations(Chain.t(), binary()) :: [violation()]
  def violations(%Chain{edges: edges} = chain, project_id) do
    cardinality_violations(chain, project_id, edges) ++
      graph_constraint_violations(chain, project_id, edges)
  end

  ## -- cardinality ---------------------------------------------------------

  defp cardinality_violations(chain, project_id, edges) do
    for {edge_name, edge} <- edges,
        instance <- instances(edge),
        {side, tier_name, bound} <- cardinality_sides(instance),
        bound_relevant?(bound),
        node <- Store.list_nodes(project_id, tier_name),
        count = edge_count(project_id, edge_name, side, node.id),
        bound_violated?(chain, project_id, tier_name, bound, count) do
      %{
        kind: :cardinality,
        edge: edge_name,
        side: side,
        tier: tier_name,
        node_id: node.id,
        count: count,
        bound: bound
      }
    end
  end

  defp cardinality_sides(%{source: source_tier, target: target_tier, cardinality: cardinality}) do
    for {side, tier_name} <- [{:source, source_tier}, {:target, target_tier}],
        bound = Map.get(cardinality, side),
        not is_nil(bound) do
      {side, tier_name, bound}
    end
  end

  # `{min: 0, max: :unbounded}` can never be violated by any count, so
  # it is skipped before a single node is even listed.
  defp bound_relevant?(%{min: 0, max: :unbounded}), do: false
  defp bound_relevant?(_bound), do: true

  # The `min` half and the `max` half are gated independently, per the
  # moduledoc's own timing rule: `max` is checked unconditionally — a
  # count that has already exceeded a ceiling stays exceeded regardless
  # of what else is still pending — while `min` waits on the bound
  # side's own tier being `drained?/3`. A combined `{min: 1, max: 1}`
  # bound (nearly every fanout-mint target's shape) therefore reports
  # its `max` half before the tier drains even though its `min` half
  # does not.
  defp bound_violated?(_chain, _project_id, _tier_name, %{max: max}, count)
       when max != :unbounded and count > max,
       do: true

  defp bound_violated?(chain, project_id, tier_name, %{min: min}, count)
       when min > 0 and count < min,
       do: ReadyScopes.drained?(chain, project_id, tier_name)

  defp bound_violated?(_chain, _project_id, _tier_name, _bound, _count), do: false

  defp edge_count(project_id, edge_name, :source, node_id),
    do: length(Store.edges_from(project_id, node_id, edge_name))

  defp edge_count(project_id, edge_name, :target, node_id),
    do: length(Store.edges_to(project_id, node_id, edge_name))

  ## -- graph_constraint ------------------------------------------------------

  defp graph_constraint_violations(chain, project_id, edges) do
    for {edge_name, edge} <- edges,
        constraint <- edge.graph_constraint,
        instance <- instances(edge),
        drained_both_sides?(chain, project_id, instance),
        detail <- constraint_violations(constraint, project_id, edge_name, instance) do
      %{kind: :graph_constraint, edge: edge_name, constraint: constraint, detail: detail}
    end
  end

  defp drained_both_sides?(chain, project_id, %{source: source_tier, target: target_tier}) do
    ReadyScopes.drained?(chain, project_id, source_tier) and
      ReadyScopes.drained?(chain, project_id, target_tier)
  end

  defp constraint_violations("no_self_loop", project_id, edge_name, %{source: source_tier}) do
    for node <- Store.list_nodes(project_id, source_tier),
        edge <- Store.edges_from(project_id, node.id, edge_name),
        edge.target_node_id == node.id do
      %{self_loop_node_id: node.id}
    end
  end

  defp constraint_violations(constraint, project_id, edge_name, %{source: source_tier})
       when constraint in ["acyclic", "tree"] do
    pairs =
      for node <- Store.list_nodes(project_id, source_tier),
          edge <- Store.edges_from(project_id, node.id, edge_name),
          do: {edge.source_node_id, edge.target_node_id}

    case DslGraph.find_cycle(pairs) do
      nil -> []
      cycle -> [%{cycle: cycle}]
    end
  end

  defp constraint_violations(_constraint, _project_id, _edge_name, _instance), do: []

  defp instances(%{instances: instances}) when is_list(instances), do: instances
  defp instances(%{source: source, target: target}), do: [%{source: source, target: target}]
end
