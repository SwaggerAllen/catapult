defmodule Catapult.Engine.Projector do
  @moduledoc """
  Applies `Catapult.Engine.Reducer` to every committed event
  (`systems/engine.md`): a `Commanded.Event.Handler` with `:strong`
  consistency, so a caller dispatching with `consistency: :strong`
  (the default a command-edge caller should use) reads its own write
  back from the projections it just updated — the closest match to v4
  §A.3.2's "single Postgres transaction" framing Commanded's own
  primitives offer, without literally sharing one transaction across
  two connection pools (`Catapult.Repo`'s and the event store's own).

  The scheduler's fast path rides in here rather than in a second
  process (`systems/engine.md`): this handler already runs
  cluster-wide singleton by construction (a Commanded subscription is
  consumed once, in order, or replay guarantees break), so it was never
  a placement question — only the sweeper's own timer loop is. After
  the reducer folds an event that could plausibly move readiness (a
  draft committed, a draft approved, a chain-axis bundle flip —
  `Catapult.Engine.Scheduler.triggering_project_id/1`), the scheduler
  re-broadcasts. A bundle this handler cannot currently load is logged
  and otherwise ignored: the broadcast is a hint, not an authority, and
  the sweeper's own convergence floor catches whatever this skips.
  """

  # `name:` is Commanded's event-store subscription identity, not a
  # `Process.register/2` name — but the audit's AST-grade ban on
  # `name: __MODULE__` (conventions §5) doesn't distinguish the two, so
  # a plain atom is used instead and registered through `processes/0`
  # like any other placement decision (`Catapult.Engine`).
  use Commanded.Event.Handler,
    application: Catapult.Engine.Application,
    name: :engine_projector,
    consistency: :strong

  require Logger

  alias Catapult.Config
  alias Catapult.Dsl
  alias Catapult.Engine.Reducer
  alias Catapult.Engine.Scheduler

  def handle(event, metadata) do
    Reducer.apply(event, metadata)
    trigger(event)
    :ok
  end

  defp trigger(event) do
    case Scheduler.triggering_project_id(event) do
      nil -> :ok
      project_id -> trigger_project(project_id)
    end
  end

  defp trigger_project(project_id) do
    case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      {:ok, loaded} ->
        Scheduler.trigger(loaded.chain, project_id)

      {:error, reason} ->
        Logger.warning(
          "engine projector's fast path skipped a trigger for #{project_id}: " <>
            "bundle unloadable (#{inspect(reason)})",
          component: :engine
        )
    end
  end
end
