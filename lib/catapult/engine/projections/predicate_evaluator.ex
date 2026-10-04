defmodule Catapult.Engine.Projections.PredicateEvaluator do
  @moduledoc """
  Evaluates one `Catapult.Dsl.Predicate` AST (`chain.md` #37) against
  live graph state, anchored on one node — built as the shared home for
  the predicate language's four slots (`scope_filter`, `cardinality
  .when`, an edge `constraint`, a flow `completion`) to evaluate
  through, beside `Catapult.Engine.Projections.ContextResolver` and on
  the same `Store` edge/node primitives, when each slot's own ticket
  lands (`systems/engine.md`). `scope_filter` is this ticket's only
  caller.

  A path segment is always an edge name walked forward from the anchor
  (`Store.edges_from/3`) — the predicate grammar has no `~` reversal,
  unlike a context walk's hops. The final segment of a `field`/compare
  path is read off the landed node(s)' own `fields` map; multiple
  landings take the first rather than fan a scalar comparison out
  (undocumented by `chain.md` #37, unexercised by any shipped bundle
  today — an engine-side resolution call like the one below, not a
  spec reading).

  A bare single-segment operand on the right of a comparison is always
  the enum-literal reading, never a field lookup — `chain.md` #37's
  own grammar note ("a single bare word... could be either a path
  segment... or an enum literal. Both are legal... so it carries as a
  one-segment path and the loader resolves it against the field it is
  compared to") leaves that resolution to the consumer, and `kind ==
  presentational` (a field compared against a class name) is the shape
  every worked example in this language uses; a two-field comparison
  (`a == b`, both meant as node fields) is the case this reading gives
  up, unexercised anywhere today.

  `reaches(a, b)` is this module's own engine-side resolution, the same
  latitude `chain.md` #37 already exercises for
  `all(refactor_plan -> resolved)`'s tier-as-path-root reading in flow
  completion: `a` and `b` name tiers, the anchor must itself be of tier
  `a`, and the predicate holds when a forward walk from the anchor —
  restricted to `via`'s edge names, or unrestricted when `via` is empty
  — reaches some node of tier `b`.
  """

  alias Catapult.Dsl.Predicate
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc "Whether `predicate` holds with `node` as the walk's anchor (`self`)."
  @spec eval(Predicate.t(), Node.t()) :: boolean()
  def eval({:and, left, right}, node), do: eval(left, node) and eval(right, node)
  def eval({:or, left, right}, node), do: eval(left, node) or eval(right, node)
  def eval({:not, inner}, node), do: not eval(inner, node)

  def eval({:compare, cmp, left, right}, node) do
    compare(cmp, operand(left, node), enum_literal_or_operand(right, node))
  end

  def eval({:field, path}, node), do: truthy?(field_value(path, node))
  def eval({:has_edge, edge}, node), do: Store.edges_from(node.project_id, node.id, edge) != []

  def eval({:count, edge, cmp, n}, node) do
    compare(cmp, length(Store.edges_from(node.project_id, node.id, edge)), n)
  end

  def eval({:exists, path, predicate}, node) do
    Enum.any?(walk(path, node), &eval(predicate, &1))
  end

  def eval({:all, path, field}, node) do
    Enum.all?(walk(path, node), &truthy?(Map.get(&1.fields, field)))
  end

  def eval({:any, path, field}, node) do
    Enum.any?(walk(path, node), &truthy?(Map.get(&1.fields, field)))
  end

  def eval({:reaches, from_tier, to_tier, via: via}, node),
    do: reaches?(node, from_tier, to_tier, via)

  ## Operands and field access

  defp operand({:literal, value}, _node), do: value
  defp operand({:path, path}, node), do: field_value(path, node)

  defp enum_literal_or_operand({:path, [word]}, _node), do: word
  defp enum_literal_or_operand(operand, node), do: operand(operand, node)

  defp field_value(path, node) do
    {hops, [field]} = Enum.split(path, -1)

    case walk(hops, node) do
      [] -> nil
      [landed | _] -> Map.get(landed.fields, field)
    end
  end

  ## Path walking — every segment is a forward edge hop from the anchor

  defp walk([], node), do: [node]

  defp walk([edge | rest], node) do
    node.project_id
    |> Store.edges_from(node.id, edge)
    |> Enum.map(&Store.get_node(node.project_id, &1.target_node_id))
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(&walk(rest, &1))
  end

  ## Comparison and truthiness

  defp compare(:eq, a, b), do: a == b
  defp compare(:neq, a, b), do: a != b
  defp compare(:lt, a, b), do: a < b
  defp compare(:gt, a, b), do: a > b
  defp compare(:lte, a, b), do: a <= b
  defp compare(:gte, a, b), do: a >= b

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(_other), do: true

  ## reaches(a, b, via: [...]) — self-anchored, breadth-first

  defp reaches?(%Node{tier: from_tier} = node, from_tier, to_tier, via) do
    bfs(node.project_id, MapSet.new([node.id]), [node], to_tier, via)
  end

  defp reaches?(_node, _from_tier, _to_tier, _via), do: false

  defp bfs(_project_id, _visited, [], _to_tier, _via), do: false

  defp bfs(project_id, visited, [current | rest], to_tier, via) do
    neighbors =
      current.id
      |> outgoing(project_id, via)
      |> Enum.map(& &1.target_node_id)
      |> Enum.reject(&MapSet.member?(visited, &1))
      |> Enum.map(&Store.get_node(project_id, &1))
      |> Enum.reject(&is_nil/1)

    if Enum.any?(neighbors, &(&1.tier == to_tier)) do
      true
    else
      visited = Enum.reduce(neighbors, visited, &MapSet.put(&2, &1.id))
      bfs(project_id, visited, rest ++ neighbors, to_tier, via)
    end
  end

  defp outgoing(node_id, project_id, []), do: Store.edges_from(project_id, node_id)

  defp outgoing(node_id, project_id, edge_names),
    do: Enum.flat_map(edge_names, &Store.edges_from(project_id, node_id, &1))
end
