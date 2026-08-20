defmodule Catapult.Engine.Projections.ReadyScopes do
  @moduledoc """
  The scheduler's three-rule loop (v4 §A.2.7), rules 1 and 2 — enumerate,
  evaluate readiness — as a pure query against current projections
  rather than a maintained table: "the same query answers 'ready now'
  and 'ready at sequence T'" is `systems/engine.md`'s own restatement
  of the state-driven doctrine, and a query needs no background
  process to stay correct the way a materialized table would.

  Rule 3 (write the `ready_scopes` row) and the fast-path/sweeper
  triggers that decide *when* to re-run this query are the reactive
  scheduler — `systems/engine.md`'s own Initial-vs-target list, and
  out of this ticket's stated scope (the ticket names "event log,
  reducer, universal projections", not the scheduler that dispatches
  off them). This module is what a scheduler ticket calls; it does not
  build the calling loop.

  **Initial scope**: `singleton`, `per(X)` and `child_of(X)` scopes.
  `cascade_visit` is Target — it is engine-minted mid-flow-walk, and
  flow instances themselves are `systems/engine.md`'s own
  Initial-vs-target "Target" line.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc """
  Every `(tier, scope_key)` pair for `tier_name` currently ready to
  generate: not yet drafted (`:absent`), and every context entry
  resolves to a target that is itself `:approved`.
  """
  @spec ready(Chain.t(), binary(), String.t()) :: [Node.t()]
  def ready(%Chain{tiers: tiers} = chain, project_id, tier_name) do
    with {:ok, tier} <- Map.fetch(tiers, tier_name), true <- generation_tier?(tier) do
      tier
      |> candidates(chain, project_id)
      |> Enum.filter(&(&1.status == :absent and ready?(tier, &1)))
    else
      _not_a_generation_tier -> []
    end
  end

  defp generation_tier?(%Tier{reviews: nil, draft: draft}), do: not is_nil(draft)
  defp generation_tier?(%Tier{}), do: false

  defp ready?(tier, node) do
    Enum.all?(tier.context, &walk_ready?(&1, node))
  end

  defp walk_ready?(walk, node) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} -> Enum.all?(targets, &(&1.status == :approved))
      {:error, :unsupported} -> false
    end
  end

  defp candidates(%Tier{name: name, scope: {:singleton}}, _chain, project_id) do
    [existing_or_virtual(project_id, name, %{}, nil)]
  end

  defp candidates(%Tier{name: name, scope: {:per, parent_tier}}, _chain, project_id) do
    for parent <- Store.list_nodes(project_id, parent_tier) do
      existing_or_virtual(project_id, name, %{"per" => parent.id}, parent.id)
    end
  end

  defp candidates(%Tier{name: name, scope: {:child_of, _parent_tier}}, _chain, project_id) do
    Store.list_nodes(project_id, name)
  end

  defp candidates(%Tier{scope: {:cascade_visit}}, _chain, _project_id), do: []

  # `singleton`/`per(X)` nodes exist only once first drafted
  # (`Catapult.Engine.Reducer`'s design note); before that, readiness
  # still has to evaluate their context, so a transient, never-persisted
  # placeholder stands in — its id is never looked up by any edge (a
  # node not yet drafted has declared none), so it resolves exactly
  # like the real row would once one exists.
  defp existing_or_virtual(project_id, tier, scope_key, parent_node_id) do
    case Store.get_node_by_scope(project_id, tier, scope_key) do
      nil ->
        %Node{
          id: "virtual:#{tier}:#{inspect(scope_key)}",
          project_id: project_id,
          tier: tier,
          scope_key: scope_key,
          parent_node_id: parent_node_id,
          status: :absent
        }

      node ->
        node
    end
  end
end
