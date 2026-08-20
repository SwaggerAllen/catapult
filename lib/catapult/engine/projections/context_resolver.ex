defmodule Catapult.Engine.Projections.ContextResolver do
  @moduledoc """
  Resolves one `Catapult.Dsl.ContextWalk` (dsl-syntax.md §7) against
  live graph state — the engine-side half the loader's own validation
  (`Catapult.Dsl.Chain`) never does: the loader confirms a walk is
  *well-formed* against declarations; this module walks it against
  actual node/edge instances, which is what `Catapult.Engine
  .Projections.Staleness` and `.ReadyScopes` are both built on
  (v4 §A.2.5/§A.2.7).

  **Initial scope**: `self`/`self.parent` and `all.<tier>` (§7, §7.2),
  including multi-hop and reversed edges (§7.1). `input.<role>` and
  `ticket.<source>` (§7.2's v5 additions) resolve `:unsupported` —
  intake documents and validation findings are a different system's
  storage (`platform_content`, delivery's Phase 7 respectively) and
  outside this ticket's universal projections.
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc """
  The nodes `walk` resolves to, starting from `node`, or
  `{:error, :unsupported}` for a source this ticket does not build.
  """
  @spec resolve(ContextWalk.t(), Node.t()) :: {:ok, [Node.t()]} | {:error, :unsupported}
  def resolve(%ContextWalk{source: :self} = walk, %Node{} = node) do
    start = if walk.parent, do: parent_of(node), else: node

    case start do
      nil -> {:ok, []}
      start -> {:ok, walk_hops(walk.hops, [start])}
    end
  end

  def resolve(%ContextWalk{source: :all, target_tier: tier}, %Node{project_id: project_id}) do
    {:ok, Store.list_nodes(project_id, tier)}
  end

  def resolve(%ContextWalk{source: source}, %Node{}) when source in [:input, :ticket] do
    {:error, :unsupported}
  end

  defp parent_of(%Node{parent_node_id: nil}), do: nil

  defp parent_of(%Node{project_id: project_id, parent_node_id: id}),
    do: Store.get_node(project_id, id)

  # Each hop fans a set of "current" walkers out to the next set,
  # following the edge forward (source -> target) or reversed (§7.1's
  # `~` — target -> source) — a multi-instance edge can land on more
  # than one node per walker, which is why this folds over lists
  # rather than single nodes throughout.
  defp walk_hops(hops, current) do
    Enum.reduce(hops, current, fn hop, walkers ->
      walkers
      |> Enum.flat_map(&landings(hop, &1))
      |> Enum.uniq_by(& &1.id)
    end)
  end

  defp landings(%{edge: edge_name, reversed?: false}, %Node{project_id: project_id, id: id}) do
    project_id
    |> Store.edges_from(id, edge_name)
    |> Enum.map(&Store.get_node(project_id, &1.target_node_id))
  end

  defp landings(%{edge: edge_name, reversed?: true}, %Node{project_id: project_id, id: id}) do
    project_id
    |> Store.edges_to(id, edge_name)
    |> Enum.map(&Store.get_node(project_id, &1.source_node_id))
  end
end
