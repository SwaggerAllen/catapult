defmodule Catapult.Dsl.Graph do
  @moduledoc """
  Type-level acyclicity, via `libgraph` (dsl-syntax.md §4, §13,
  conventions §1's blessed graph library): the edge-instance graph
  (tiers as nodes, every declared edge as a `source -> target` arrow)
  and the workflow gate/environment ordering each reduce to "does this
  directed graph have a cycle."

  Self-loops (`source == target`, the ordinary shape of a `dependency`
  edge between components of one tier) are excluded from the
  edge-instance check: a type-level self-loop says nothing about a
  cross-tier cycle, and instance-level self-reference cycles are
  `graph_constraint: acyclic`'s job at projection time (dsl-syntax.md
  §4), not this loader's.
  """

  @doc """
  Whether the directed graph formed by `edges` (`{from, to}` pairs) has
  a cycle among *distinct* nodes — self-loops are dropped first, per
  the moduledoc.
  """
  @spec acyclic?([{term(), term()}]) :: boolean()
  def acyclic?(edges) do
    edges
    |> Enum.reject(fn {a, b} -> a == b end)
    |> build()
    |> Graph.is_acyclic?()
  end

  @doc "One cycle in the graph formed by `edges`, as a list of nodes, or `nil` if acyclic."
  @spec find_cycle([{term(), term()}]) :: [term()] | nil
  def find_cycle(edges) do
    graph = edges |> Enum.reject(fn {a, b} -> a == b end) |> build()

    case Graph.loop_vertices(graph) do
      [vertex | _rest] -> [vertex, vertex]
      [] -> cycle_via_scc(graph)
    end
  end

  @doc "Whether `to` is reachable from `from` in the graph formed by `edges`."
  @spec reachable?([{term(), term()}], term(), term()) :: boolean()
  def reachable?(edges, from, to) do
    graph = build(edges)
    to in Graph.reachable(graph, [from])
  end

  defp cycle_via_scc(graph) do
    graph
    |> Graph.strong_components()
    |> Enum.find(&(length(&1) > 1))
  end

  defp build(edges) do
    Enum.reduce(edges, Graph.new(type: :directed), fn {a, b}, g ->
      g |> Graph.add_vertex(a) |> Graph.add_vertex(b) |> Graph.add_edge(a, b)
    end)
  end
end
