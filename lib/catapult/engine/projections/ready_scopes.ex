defmodule Catapult.Engine.Projections.ReadyScopes do
  @moduledoc """
  The scheduler's three-rule loop, rules 1 and 2 — enumerate,
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

  require Logger

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Projections.PredicateEvaluator
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node

  @doc """
  Every `(tier, scope_key)` pair for `tier_name` currently ready to
  generate: passes the tier's `scope_filter` (if any), is not yet
  drafted (`:absent`), and every context entry resolves to a target
  that is itself `settled?/3` — not merely `:approved` bare, since a
  join target reads `:approved` from the instant it mints and an
  `all.<tier>` walk needs `drained?/3` on top of `settled?/3`, or an
  empty tier that simply hasn't drafted yet reads as vacuously ready
  (ORC-235, `systems/engine.md`).
  """
  @spec ready(Chain.t(), binary(), String.t()) :: [Node.t()]
  def ready(%Chain{tiers: tiers} = chain, project_id, tier_name) do
    with {:ok, tier} <- Map.fetch(tiers, tier_name), true <- generation_tier?(tier) do
      tier
      |> candidates(chain, project_id)
      |> Enum.filter(fn node ->
        scope_filter_passes?(chain, tier, node) and node.status == :absent and
          ready?(chain, tier, node)
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
            tier.context |> Enum.map(&walk_report(chain, &1, node)) |> Enum.reject(& &1.satisfied)
        }

      :error ->
        %{tier: tier_name, scope_key: node.scope_key, passes_scope_filter: true, blocking: []}
    end
  end

  defp walk_report(chain, walk, node) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} ->
        %{
          walk: walk.raw,
          satisfied: walk_satisfied?(chain, walk, node.project_id, targets),
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

  defp ready?(chain, tier, node) do
    Enum.all?(tier.context, &walk_ready?(chain, &1, node))
  end

  defp walk_ready?(chain, walk, node) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} -> walk_satisfied?(chain, walk, node.project_id, targets)
      {:error, :unsupported} -> false
    end
  end

  # An `all.<tier>` walk needs `drained?/3` on top of every resolved
  # target's own `settled?/3` — `Enum.all?/2` alone is vacuously true on
  # `[]`, which is correct for "no node of this tier will ever exist"
  # and wrong for "this tier hasn't drafted yet" (ORC-235,
  # `systems/engine.md`). Every other walk shape keeps the plain fold:
  # an empty `self`/`self.parent` walk is a structurally absent edge,
  # not a population this ticket's fix reaches (same entry).
  defp walk_satisfied?(chain, %ContextWalk{source: :all, target_tier: tier}, project_id, targets) do
    drained?(chain, project_id, tier) and Enum.all?(targets, &settled?(chain, project_id, &1))
  end

  defp walk_satisfied?(chain, _walk, project_id, targets) do
    Enum.all?(targets, &settled?(chain, project_id, &1))
  end

  # A node's readiness-effective status, resolved rather than read bare
  # (ORC-235, `systems/engine.md`): a tier with its own `draft:` is
  # `settled?` exactly when reviewed and approved; a `generator:
  # supplied` tier is `settled?` unconditionally, the moment the node
  # exists, since it has no draft anywhere in its history to be
  # unapproved; every other tier is a join target, minted by some other
  # node's `DraftCommitted`, and defers to whichever node minted it,
  # recursively. Terminates because `parent_node_id` is acyclic by
  # construction (a mint's parent is committed, and stored, strictly
  # before the mint that names it).
  defp settled?(chain, project_id, %Node{tier: tier_name} = node) do
    case Map.fetch(chain.tiers, tier_name) do
      {:ok, tier} -> tier_settled?(chain, project_id, tier, node)
      :error -> false
    end
  end

  defp tier_settled?(_chain, _project_id, %Tier{draft: draft}, node) when not is_nil(draft) do
    node.status == :approved
  end

  defp tier_settled?(_chain, _project_id, %Tier{generator: "supplied"}, _node) do
    true
  end

  defp tier_settled?(chain, project_id, _tier, node) do
    case node.parent_node_id do
      nil ->
        # Every fanout mint writes parent_node_id (Reducer's own
        # `apply_mint/2`), so its absence on a join-target node is a
        # data-integrity error, not a signal to read the node as
        # settled — surfaced by log rather than by crashing the
        # projector/sweeper process reading it, the same reason
        # `scope_filter_passes?` excludes rather than raises on an
        # unresolvable predicate above.
        Logger.warning(
          "node #{inspect(node.id)} (tier #{inspect(node.tier)}) has no parent_node_id, " <>
            "but its tier declares no draft: and is not generator: supplied — excluded from " <>
            "settled? rather than read as settled",
          component: :engine
        )

        false

      parent_id ->
        case Store.get_node(project_id, parent_id) do
          nil ->
            Logger.warning(
              "node #{inspect(node.id)}'s parent_node_id #{inspect(parent_id)} names no " <>
                "stored node — excluded from settled? rather than read as settled",
              component: :engine
            )

            false

          parent ->
            settled?(chain, project_id, parent)
        end
    end
  end

  # A tier's population is exhausted — no further node of that tier
  # will ever appear, and nothing that already exists is still pending
  # (ORC-235, `systems/engine.md`). The two branches below (`per(X)`,
  # `child_of(X1..Xn)`) test that differently because the two node
  # kinds come into existence at different points: a `per(X)` node has
  # no stored row until it drafts, so the existing-row count there is
  # never trustworthy as a final population on its own; a `child_of(X)`
  # node's row appears at its parent's mint, so once every minting
  # source is exhausted the current row count is already final.
  defp drained?(chain, project_id, tier_name) do
    case Map.fetch(chain.tiers, tier_name) do
      {:ok, tier} -> tier_drained?(chain, project_id, tier)
      :error -> false
    end
  end

  # A supplied tier's population is fixed at intake, before the chain
  # ever dispatches a single tier — there is no "not yet" state between
  # zero and its final count for this recursion to distinguish.
  defp tier_drained?(_chain, _project_id, %Tier{generator: "supplied", scope: {:singleton}}) do
    true
  end

  # A chain-dispatched singleton's count is exactly one once the chain
  # reaches it, never legitimately zero — drained once that one node
  # exists and is itself `settled?`.
  defp tier_drained?(chain, project_id, %Tier{name: name, scope: {:singleton}}) do
    case Store.get_node_by_scope(project_id, name, %{}) do
      nil -> false
      node -> settled?(chain, project_id, node)
    end
  end

  # Drained once the driving tier is drained (making the current row
  # list trustworthy as final) and every node that driving tier names
  # has its corresponding per(X) node `settled?` — a corresponding node
  # with no stored row at all reads as not settled, the same "hasn't
  # drafted yet" case the driving-tier check exists to catch.
  defp tier_drained?(chain, project_id, %Tier{name: name, scope: {:per, parent_tier}}) do
    drained?(chain, project_id, parent_tier) and
      Enum.all?(Store.list_nodes(project_id, parent_tier), fn parent ->
        case Store.get_node_by_scope(project_id, name, %{"per" => parent.id}) do
          nil -> false
          child -> settled?(chain, project_id, child)
        end
      end)
  end

  # Drained once every minting source `Xi` (every tier a `type: fanout`
  # edge instance targets, derived from the loaded chain rather than
  # from this tier's own single-tier `scope:` reference — `policy`'s
  # three fanout sources are the concrete case a single `child_of(X)`
  # scope name cannot spell) is itself drained, and every row already
  # at this tier is `settled?`.
  defp tier_drained?(chain, project_id, %Tier{name: name, scope: {:child_of, _ref}}) do
    drivers = child_of_drivers(chain, name)

    Enum.all?(drivers, &drained?(chain, project_id, &1)) and
      Enum.all?(Store.list_nodes(project_id, name), &settled?(chain, project_id, &1))
  end

  defp tier_drained?(_chain, _project_id, _tier), do: false

  defp child_of_drivers(%Chain{edges: edges}, tier_name) do
    for {_name, edge} <- edges,
        edge.type == "fanout",
        instance <- edge.instances,
        instance.target == tier_name,
        uniq: true do
      instance.source
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
