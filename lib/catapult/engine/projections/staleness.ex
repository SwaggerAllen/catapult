defmodule Catapult.Engine.Projections.Staleness do
  @moduledoc """
  Staleness is a projection, never stored state (v5 §7.11,
  `systems/engine.md`'s standing decision): a node is stale when its
  committed content predates the inputs its context walk reads,
  computed from the log on demand. No stale flag is ever written.

  A review tier needs no staleness treatment at all
  (`docs/v5-design-decisions.md` §7.16, corrected) — and this module
  never has to special-case it, because a review tier commits no body
  and mints no node of its own (dsl-syntax.md §3.3): it is simply
  never a `node.tier` this function is called with.

  `chain` is the loaded bundle (`Catapult.Dsl.Chain`) whose tier
  declarations name each node's `context:` walks — read at the
  sequence a caller chooses to pass a historical `chain`, never
  `core_dsl`'s currently-loaded one implicitly, so "was this stale at
  sequence T" is answerable the same way "is this stale now" is.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Store.Node

  @doc """
  Whether `node`'s current committed content predates any resolved
  context target's own — `false` for a node with nothing committed
  yet (`:absent`), which is not stale, merely not drafted.
  """
  @spec stale?(Chain.t(), Node.t()) :: boolean()
  def stale?(%Chain{}, %Node{status: :absent}), do: false

  def stale?(%Chain{tiers: tiers}, %Node{} = node) do
    case Map.fetch(tiers, node.tier) do
      :error -> false
      {:ok, tier} -> Enum.any?(tier.context, &walk_stales?(&1, node))
    end
  end

  defp walk_stales?(walk, node) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} -> Enum.any?(targets, &target_newer?(&1, node))
      {:error, :unsupported} -> false
    end
  end

  defp target_newer?(%Node{committed_sequence: nil}, _node), do: false

  defp target_newer?(%Node{committed_sequence: target_sequence}, %Node{
         committed_sequence: node_sequence
       }) do
    not is_nil(node_sequence) and target_sequence > node_sequence
  end
end
