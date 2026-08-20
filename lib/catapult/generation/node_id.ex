defmodule Catapult.Generation.NodeId do
  @moduledoc """
  The real id a scope commits under. `Catapult.Engine.Projections
  .ReadyScopes` already gives an already-minted (`child_of`) node its
  real id — assigned once, at fanout time
  (`Catapult.Generation.Extraction.mints/4`) — but a `singleton`/
  `per(X)` scope has no mint step of its own and reads back only a
  transient, never-persisted placeholder before its first commit
  (`"virtual:<tier>:<scope_key inspected>"`, `ReadyScopes`'s own
  moduledoc). That placeholder is unfit to commit under or to key a
  `RunFailed` event against before a node exists at all — this module
  is the one real, deterministic id both cases resolve to, computed
  the same way every time a given `(tier, scope_key)` is asked about,
  so a re-dispatched scope's failure history keys the same id its
  eventual commit will (v5 §7.15's "no memory across dispatches":
  re-running a scope is indistinguishable from running it the first
  time, which requires the id it runs under to be indistinguishable
  too).
  """

  alias Catapult.Engine.Store.Node

  @doc "The id `node` commits under."
  @spec resolve(Node.t()) :: binary()
  def resolve(%Node{id: "virtual:" <> _, tier: tier, scope_key: scope_key}) do
    derive(tier, scope_key)
  end

  def resolve(%Node{id: id}), do: id

  defp derive(tier, %{"per" => parent_id}), do: tier <> ":" <> parent_id
  defp derive(tier, _singleton_scope_key), do: tier
end
