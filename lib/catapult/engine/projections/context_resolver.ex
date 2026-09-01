defmodule Catapult.Engine.Projections.ContextResolver do
  @moduledoc """
  Resolves one `Catapult.Dsl.ContextWalk` (dsl-syntax.md §7) against
  live graph state — the engine-side half the loader's own validation
  (`Catapult.Dsl.Chain`) never does: the loader confirms a walk is
  *well-formed* against declarations; this module walks it against
  actual node/edge instances, which is what `Catapult.Engine
  .Projections.Staleness` and `.ReadyScopes` are both built on.

  **Initial scope**: `self`/`self.parent` and `all.<tier>` (§7, §7.2),
  including multi-hop and reversed edges (§7.1). `ticket.<source>`
  (§7.2's v5 addition) resolves `:unsupported` — validation findings
  are delivery's Phase 7 storage and outside this ticket's universal
  projections.

  `input.<role>` and `input.*` resolve `{:ok, []}`, always (ORC-107).
  Neither is a graph walk at all — an input document is pinned prose,
  not a node with a tier, a status or edges (the intake raft is
  `Catapult.Delivery`'s own storage; `Catapult.Generation
  .ContextAssembly` reads it directly for rendering, a second and
  parallel step to this module's own node-collection fold,
  `systems/generation.md`'s ORC-107 entry) — so this module, whose
  whole job is walking *declared node/edge instances*, has nothing to
  resolve either form against. The empty list is the whole mechanism,
  not a placeholder for a real one: `ReadyScopes` and `Staleness` both
  already fold `{:ok, targets}` generically, and `Enum.all?/2` on `[]`
  is vacuously true while `Enum.any?/2` on `[]` is vacuously false, so
  neither module gained a line for this — an `input.<role>` walk is
  therefore *structurally* incapable of blocking readiness or
  reporting staleness, which is dsl-syntax.md §7's "a role with no
  documents never blocks readiness" and v5 §1.1's "an input-doc
  edit... stales nothing," both already true of every `{:ok, []}`
  regardless of source (`systems/engine.md`'s ORC-107 entry carries the
  full argument, including the synthetic-`Node` alternative this
  rejects).
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc """
  The nodes `walk` resolves to, starting from `node` — always `{:ok,
  []}` for `input.<role>`/`input.*` (above) — or `{:error,
  :unsupported}` for `ticket.<source>`, a source this ticket does not
  build.
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

  def resolve(%ContextWalk{source: :input}, %Node{}), do: {:ok, []}

  def resolve(%ContextWalk{source: :ticket}, %Node{}), do: {:error, :unsupported}

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
