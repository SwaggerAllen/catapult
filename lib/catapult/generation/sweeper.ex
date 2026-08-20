defmodule Catapult.Generation.Sweeper do
  @moduledoc """
  Readiness-driven dispatch's own convergence floor (v5 §7.15: "resume
  is re-asking the readiness question" — no fast path is built here,
  see the hand-back for why). On a timer: every project id the engine
  store has ever heard from (`Catapult.Engine.Store.list_project_ids/0`,
  the same enumeration `Catapult.Engine.Sweeper` already walks),
  loads the chain, and enqueues one `Catapult.Generation.DispatchWorker`
  Oban job per ready `generator: "llm"` scope — generation and review
  tiers alike, `ReadyScopes.ready/3`/`.ready_review/3` together
  (`Catapult.Engine.Scheduler`'s own fold, replayed here since this
  ticket does not build the PubSub-subscribing fast path).

  Only `generator: "llm"` tiers dispatch through this executor
  (`systems/generation.md`'s own scope: agent-dispatch generation).
  `generator: synthesis` tiers (join targets, no `draft:`) are already
  excluded by `ReadyScopes.ready/3`'s own `generation_tier?/1` filter;
  a tier with a `draft:` block under `template`/`git_commit`/`webhook`/
  `external` would not be, and is skipped here explicitly — a
  different generator-type executor's ticket, not this one's
  (`systems/generation.md`'s "executor-profile routing" is Target,
  not Initial).

  Oban's own job uniqueness — keyed on `{project_id, tier, scope_key}`,
  held for the scope's in-flight window — is what turns this sweep's
  liberal re-announcement into one dispatch per scope (v5 §7.15's
  first invariant, `systems/generation.md`'s design note), not
  anything held here: this process holds no memory of what it last
  enqueued.
  """

  use GenServer

  require Logger

  alias Catapult.Config
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store
  alias Catapult.Generation.DispatchWorker

  @name :generation_sweeper

  @doc "Starts the sweeper, registered under `:generation_sweeper` (`Catapult.Generation.processes/0`) unless `opts` names a different `:name`."
  def start_link(opts \\ []) do
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
    case Dsl.load(Config.fetch!(:generation, :bundles_root)) do
      {:ok, loaded} ->
        Enum.each(Store.list_project_ids(), &sweep_project(loaded.chain, &1))

      {:error, reason} ->
        Logger.warning(
          "generation sweeper skipped a tick: bundle unloadable (#{inspect(reason)})",
          component: :generation
        )
    end
  end

  defp sweep_project(chain, project_id) do
    for {tier_name, tier} <- chain.tiers, dispatchable?(tier) do
      for node <- ReadyScopes.ready(chain, project_id, tier_name) do
        enqueue(project_id, tier_name, node.scope_key)
      end

      for node <- ReadyScopes.ready_review(chain, project_id, tier_name) do
        enqueue(project_id, tier_name, node.scope_key)
      end
    end

    :ok
  end

  defp dispatchable?(%{reviews: reviewed}) when not is_nil(reviewed), do: true
  defp dispatchable?(%{draft: draft, generator: "llm"}) when not is_nil(draft), do: true
  defp dispatchable?(_tier), do: false

  defp enqueue(project_id, tier, scope_key) do
    %{project_id: project_id, tier: tier, scope_key: scope_key}
    |> DispatchWorker.new()
    |> Oban.insert()
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, Config.fetch!(:generation, :sweep_interval_ms))
  end
end
