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

  Three more reads live here, beside `ready/3` rather than as parallel
  implementations, because each reuses its candidate/walk machinery
  directly (`systems/engine.md`, ORC-8):

    * `scope_filter` — evaluated inside `ready/3` itself. A node
      failing its tier's `scope_filter` is not a candidate at all
      (never appears in enumeration), distinct from appearing and
      being not-yet-ready.
    * `ready_review/3` — review-tier dispatch, a second and simpler
      rule than the context walk above: a review tier has no `context:`
      of its own to gate on (dsl-syntax.md §3.3), so its readiness is
      exactly "the reviewed tier's current draft has no review yet."
    * `explain/2` — "what is blocking this scope"
      (`systems/dashboard.md`'s naming), the same candidate/walk fold
      as `ready/3` replayed as a structured report instead of a
      boolean.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Projections.PredicateEvaluator
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc """
  Every `(tier, scope_key)` pair for `tier_name` currently ready to
  generate: passes the tier's `scope_filter` (if any), is not yet
  drafted (`:absent`), and every context entry resolves to a target
  that is itself `:approved`.
  """
  @spec ready(Chain.t(), binary(), String.t()) :: [Node.t()]
  def ready(%Chain{tiers: tiers} = chain, project_id, tier_name) do
    with {:ok, tier} <- Map.fetch(tiers, tier_name), true <- generation_tier?(tier) do
      tier
      |> candidates(chain, project_id)
      |> Enum.filter(fn node ->
        scope_filter_passes?(chain, tier, node) and node.status == :absent and ready?(tier, node)
      end)
    else
      _not_a_generation_tier -> []
    end
  end

  @doc """
  Review-tier dispatch (dsl-syntax.md §3.3, §7.19): every node of the
  tier `tier_name` reviews whose current draft has no review yet
  (`Store.reviews_for_draft/1`) — fired unconditionally the cycle after
  that draft commits, with no context walk of the review tier's own to
  gate on. `[]` for anything that is not a review tier.
  """
  @spec ready_review(Chain.t(), binary(), String.t()) :: [Node.t()]
  def ready_review(%Chain{tiers: tiers}, project_id, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, %Tier{reviews: reviewed}} when not is_nil(reviewed) ->
        project_id |> Store.list_nodes(reviewed) |> Enum.filter(&unreviewed_draft?/1)

      _not_a_review_tier ->
        []
    end
  end

  @doc """
  What is blocking `node`: whether it passes its tier's `scope_filter`,
  and for each of its tier's context-walk entries that is not yet
  satisfied, that walk's raw form plus its currently resolved targets
  and their status. Reuses `ContextResolver.resolve/2` — the same
  per-walk resolution `ready?/2` folds to a boolean — rather than
  walking the graph a second way.
  """
  @spec explain(Chain.t(), Node.t()) :: map()
  def explain(%Chain{tiers: tiers} = chain, %Node{tier: tier_name} = node) do
    case Map.fetch(tiers, tier_name) do
      {:ok, tier} ->
        %{
          tier: tier_name,
          scope_key: node.scope_key,
          passes_scope_filter: scope_filter_passes?(chain, tier, node),
          blocking:
            tier.context |> Enum.map(&walk_report(&1, node)) |> Enum.reject(& &1.satisfied)
        }

      :error ->
        %{tier: tier_name, scope_key: node.scope_key, passes_scope_filter: true, blocking: []}
    end
  end

  defp walk_report(walk, node) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} ->
        %{
          walk: walk.raw,
          satisfied: Enum.all?(targets, &(&1.status == :approved)),
          targets: Enum.map(targets, &%{node_id: &1.id, tier: &1.tier, status: &1.status})
        }

      {:error, :unsupported} ->
        %{walk: walk.raw, satisfied: false, targets: [], reason: :unsupported}
    end
  end

  defp generation_tier?(%Tier{reviews: nil, draft: draft}), do: not is_nil(draft)
  defp generation_tier?(%Tier{}), do: false

  defp scope_filter_passes?(_chain, %Tier{scope_filter_raw: nil}, _node), do: true

  defp scope_filter_passes?(chain, %Tier{scope_filter_raw: raw}, node) do
    case Chain.resolve_predicate(chain, raw) do
      {:ok, predicate} -> PredicateEvaluator.eval(predicate, node)
      # Load-time validation (Chain.build/3) already rejects a
      # scope_filter that fails to resolve; a chain that made it this
      # far and still doesn't is excluded rather than crashing the
      # scheduler over it.
      {:error, _reason} -> false
    end
  end

  defp unreviewed_draft?(%Node{current_draft_id: nil}), do: false

  defp unreviewed_draft?(%Node{current_draft_id: draft_id}),
    do: Store.reviews_for_draft(draft_id) == []

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
