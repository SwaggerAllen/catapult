defmodule Catapult.Engine.Scheduler do
  @moduledoc """
  The reactive scheduler (`systems/engine.md`, v5 §1.2's inversion):
  `ready_scopes` is the plane's only dispatch source, and this is the
  module that makes that sentence true in code — the engine writes it,
  nothing else initiates work.

  `trigger/2` is rules 1-3 of v4 §A.2.7 run together: enumerate every
  tier in `chain` (both a generation tier's own context-walk readiness,
  `Catapult.Engine.Projections.ReadyScopes.ready/3`, and a review
  tier's simpler rule, `.ready_review/3`), fold the two into one set of
  `{tier, scope_key}` pairs, and broadcast — never a materialized
  `ready_scopes` table (the standing "never materialized" decision
  applies to the scheduler's own output too).

  The scheduler holds no memory of what it last broadcast. Diffing
  against a remembered ready-set to announce only deltas would grow
  exactly the in-memory pending-set the state-driven doctrine refuses,
  so every trigger re-announces liberally: the full ready set for every
  tier, whether or not it actually changed since the last trigger. The
  payload is a hint, never an authority — a consumer re-validates
  before acting on it (§7.1's validate-or-revert discipline applied to
  an internal signal), which is also why the broadcast needs no
  de-duplication of its own.

  Two callers, one function: `Catapult.Engine.Projector`'s fast path
  (`triggering_project_id/1` picks the events that could plausibly move
  readiness — a draft committed, a draft approved, a chain-axis bundle
  flip — straight off the event the projector just folded) and
  `Catapult.Engine.Sweeper`'s 30s convergence floor. Neither resolves
  its own `Chain` — both take one as a parameter, exactly like
  `ReadyScopes.ready/3` already does, because which bundle is active
  for a project is a different, not-yet-built concern (no `projects`
  table exists anywhere in this store yet either) and this module must
  not guess at its shape.
  """

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Tier
  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Topics

  @doc """
  Recomputes readiness for every tier `chain` declares, for `project_id`,
  and broadcasts the resulting `{tier, scope_key}` pairs on
  `Catapult.Engine.Topics.ready_scopes(project_id)`.
  """
  @spec trigger(Chain.t(), binary()) :: :ok
  def trigger(%Chain{tiers: tiers} = chain, project_id) do
    pairs = tiers |> Map.values() |> Enum.flat_map(&ready_pairs(chain, project_id, &1))

    Topics.broadcast(Topics.ready_scopes(project_id), {:ready_scopes, project_id, pairs})
    :ok
  end

  @doc """
  The project id to re-trigger for `event`, or `nil` when `event` is
  not one of the triggers the sketch names (`systems/engine.md`): a
  draft committed, a draft approved, or a chain-axis bundle flip. Every
  other event leaves every tier's ready set untouched.
  """
  @spec triggering_project_id(struct()) :: binary() | nil
  def triggering_project_id(%DraftCommitted{project_id: id}), do: id
  def triggering_project_id(%DraftApproved{project_id: id}), do: id
  def triggering_project_id(%ActiveBundleFlipped{project_id: id, axis: :chain}), do: id
  def triggering_project_id(_event), do: nil

  defp ready_pairs(chain, project_id, %Tier{reviews: nil, draft: draft, name: name})
       when not is_nil(draft) do
    for node <- ReadyScopes.ready(chain, project_id, name), do: {name, node.scope_key}
  end

  defp ready_pairs(chain, project_id, %Tier{reviews: reviewed, name: name})
       when not is_nil(reviewed) do
    for node <- ReadyScopes.ready_review(chain, project_id, name), do: {name, node.scope_key}
  end

  defp ready_pairs(_chain, _project_id, _tier), do: []
end
