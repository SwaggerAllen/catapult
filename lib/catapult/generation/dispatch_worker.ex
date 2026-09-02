defmodule Catapult.Generation.DispatchWorker do
  @moduledoc """
  One dispatched run per ready scope (v5 §7.15's first invariant):
  `Catapult.Generation.Sweeper` enqueues one of these per `{project_id,
  tier, scope_key}`, and Oban's own job uniqueness — held for the
  scope's in-flight window (`:available`/`:scheduled`/`:executing`/
  `:retryable`, no time limit) — is what keeps a liberally re-sweeping
  floor from ever running two at once for the same scope, without a
  new in-plane pending-set (`systems/generation.md`'s design note).

  **Re-validates before acting** (§7.1's validate-or-revert discipline
  applied to the sweeper's own hint, same as every other consumer of a
  broadcast/enumeration in this codebase): still ready, not already
  committed, not repeatedly limit-class-failing, and — ORC-216,
  `systems/delivery.md`'s ORC-216 entry — still sweepable, closing the
  gap the sweeper's own upstream skip leaves open: a job already
  enqueued on the tick before a test project releases would otherwise
  dispatch after it. No memory across dispatches — every run
  re-renders its context walk and starts clean (v5 §7.15's third
  invariant); this worker holds nothing between attempts beyond what
  Oban itself retries with.
  """

  use Oban.Worker,
    queue: :generation_dispatch,
    unique: [period: :infinity, keys: [:project_id, :tier, :scope_key], states: :incomplete]

  require Logger

  alias Catapult.Config
  alias Catapult.Delivery
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Projections.RunFailures
  alias Catapult.Generation.ContextAssembly
  alias Catapult.Generation.NodeId

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"project_id" => project_id, "tier" => tier, "scope_key" => scope_key}
      }) do
    with :ok <- still_sweepable(project_id),
         {:ok, loaded} <- Dsl.load(Config.fetch!(:generation, :bundles_root)),
         {:ok, node} <- still_ready(loaded.chain, project_id, tier, scope_key),
         :ok <- not_blocked(project_id, node, tier),
         {:ok, request} <- ContextAssembly.build(loaded.chain, project_id, tier, node) do
      dispatch(request)
    else
      {:skip, reason} ->
        Logger.info("generation dispatch skipped: #{inspect(reason)}", component: :generation)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ORC-216: the third re-validation, alongside `still_ready/4` and
  # `not_blocked/3` — a job the sweeper enqueued before a test project
  # released must not dispatch after it.
  defp still_sweepable(project_id) do
    if Delivery.sweepable_project?(project_id) do
      :ok
    else
      {:skip, {:not_sweepable, project_id}}
    end
  end

  # The scope's own node, if it is still ready — a fresh re-check
  # against current projections, never the sweeper's own snapshot
  # (which may be stale by the time this job actually runs).
  defp still_ready(chain, project_id, tier, scope_key) do
    ready =
      ReadyScopes.ready(chain, project_id, tier) ++
        ReadyScopes.ready_review(chain, project_id, tier)

    case Enum.find(ready, &(&1.scope_key == scope_key)) do
      nil -> {:skip, :no_longer_ready}
      node -> {:ok, node}
    end
  end

  # §7.15's "never another retry": two or more limit-class failures
  # since this node's last commit means the scope does not fit in one
  # window, and redispatching it forever would look like progress
  # while making none. Derived from the log, never held
  # (`Catapult.Engine.Projections.RunFailures`).
  defp not_blocked(project_id, node, _tier) do
    node_id = NodeId.resolve(node)

    if RunFailures.count_since_commit(project_id, node_id) >= 2 do
      {:skip, {:blocked, node_id}}
    else
      :ok
    end
  end

  defp dispatch(request) do
    adapter = Delivery.host_port_adapter()

    case adapter.dispatch_run(request) do
      {:ok, _run} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
