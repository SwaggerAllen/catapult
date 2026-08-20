defmodule Catapult.Engine.Sweeper do
  @moduledoc """
  The convergence floor beside the fast path (`systems/engine.md`): on
  a timer, re-broadcast every project's ready set, catching whatever
  the fast path missed (a lost PubSub message — process crash,
  netsplit) within one cycle in practice.

  A tick walks its projects **serially, never fanned out**
  (`Enum.each/2`, not `Task.async_stream/2`): `Catapult.Repo`'s pool is
  a shared, finite budget sized against the projector's writes, Oban's
  workers, the health check and this sweep together on the one
  reference cluster this code deploys to (SETUP.md §2), and a default
  `Task.async_stream/2` width reaches for more connections than that
  pool holds. One project at a time keeps a tick's own footprint at a
  single checked-out connection regardless of how many projects exist
  — affordable at this cadence because a readiness query is cheap and
  the floor's job is convergence, not speed.

  Registered `:singleton` (`Catapult.Engine.processes/0`), the same
  placement `engine_projector` already uses: a rolling deploy's brief
  two-instance overlap must run one sweeper cluster-wide, not two,
  against the same connection budget the paragraph above already
  spends down to one.

  Cadence defaults to 30s, `tunable` (`ENGINE_SWEEPER_INTERVAL_MS`) —
  enough headroom that a burst of events doesn't turn this into a
  second fast path, short enough that a missed broadcast is invisible
  in practice.
  """

  use GenServer

  require Logger

  alias Catapult.Config
  alias Catapult.Dsl
  alias Catapult.Engine.Scheduler
  alias Catapult.Engine.Store

  @name :engine_sweeper

  @doc """
  Starts the sweeper, registered under `:engine_sweeper`
  (`Catapult.Engine.processes/0`) unless `opts` names a different
  `:name` — the escape a test double needs, since the production
  process is already running under the registered name by the time a
  test suite boots.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, @name))
  end

  @impl GenServer
  def init(_opts) do
    schedule_tick()
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    sweep()
    schedule_tick()
    {:noreply, state}
  end

  defp sweep do
    case current_chain() do
      {:ok, chain} ->
        Enum.each(Store.list_project_ids(), &Scheduler.trigger(chain, &1))

      {:error, reason} ->
        Logger.warning("engine sweeper skipped a tick: bundle unloadable (#{inspect(reason)})",
          component: :engine
        )
    end
  end

  defp current_chain do
    case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      {:ok, loaded} -> {:ok, loaded.chain}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, Config.fetch!(:engine, :sweeper_interval_ms))
  end
end
