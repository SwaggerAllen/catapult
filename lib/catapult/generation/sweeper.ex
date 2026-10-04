defmodule Catapult.Generation.Sweeper do
  @moduledoc """
  Readiness-driven dispatch's own convergence floor (v5 §7.15: "resume
  is re-asking the readiness question" — no fast path is built here,
  see the hand-back for why). On a timer: every project id the engine
  store has ever heard from (`Catapult.Engine.Store.list_project_ids/0`,
  the same enumeration `Catapult.Engine.Sweeper` already walks) union
  every project id `Catapult.Delivery` has ever bound to a repo
  (`Catapult.Delivery.list_bound_project_ids/0`, ORC-216,
  `systems/generation.md`'s ORC-216 entry) — a freshly provisioned test
  project has no engine row of its own yet, since no node has ever been
  drafted for it, so the engine-only enumeration alone would never
  surface it to a sweep tick — loads the chain, and enqueues one
  `Catapult.Generation.DispatchWorker` Oban job per ready `generator:
  "llm"` scope — generation and review tiers alike,
  `ReadyScopes.ready/3`/`.ready_review/3` together (`Catapult.Engine
  .Scheduler`'s own fold, replayed here since this ticket does not
  build the PubSub-subscribing fast path).

  **Honours the test-project lifecycle** (ORC-216, `systems/delivery
  .md`'s ORC-216 entry): a project id `Catapult.Delivery
  .sweepable_project?/1` answers `false` for — a released or deleted
  test project, or one still `:provisioning` (ORC-224 — minted, not
  yet safe to dispatch against) — is skipped outright, upstream of the
  tier walk, so a debugging session never has the chain move under it,
  and neither does a tick landing while `Provisioning.provision/1` is
  still writing the project's own fixture content.

  Only `generator: "llm"` tiers dispatch through this executor
  (`systems/generation.md`'s own scope: agent-dispatch generation).
  `generator: synthesis` tiers (join targets, no `draft:`) are already
  excluded by `ReadyScopes.ready/3`'s own `generation_tier?/1` filter;
  a tier with a `draft:` block under `template`/`git_commit`/`webhook`/
  `external` would not be, and is skipped here explicitly — a
  different generator-type executor's ticket, not this one's
  (`systems/generation.md`'s "executor-profile routing" is Target,
  not Initial).

  **`generator: supplied` is a third case, mint rather than dispatch**
  (ORC-236, `systems/core_dsl.md`'s ORC-236 entry): `design_system`
  carries no `draft:` for `dispatchable?/1` to match at all, and its
  content is already final the moment its pinned intake document
  exists — there is nothing to render a prompt for and nothing an
  agent run would ever be asked to author. `mint_supplied/2` below
  is this tier's own write, beside the dispatch loop rather than
  through it: `Store.mint_node/1`'s own idempotency (`on_conflict:
  :nothing` on `{project_id, tier, scope_key}`) is what makes "mints
  at most one, never revisited" true of a step that this sweep still
  calls every tick — the second and every later call is a no-op
  against the row the first one wrote.

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
  alias Catapult.Delivery
  alias Catapult.Dsl
  alias Catapult.Dsl.ContextWalk
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
        project_ids = Enum.uniq(Store.list_project_ids() ++ Delivery.list_bound_project_ids())
        Enum.each(project_ids, &sweep_project(loaded.chain, &1))

      {:error, reason} ->
        Logger.warning(
          "generation sweeper skipped a tick: bundle unloadable (#{inspect(reason)})",
          component: :generation
        )
    end
  end

  defp sweep_project(chain, project_id) do
    if Delivery.sweepable_project?(project_id) do
      mint_supplied(chain, project_id)
      sweep_tiers(chain, project_id)
    end

    :ok
  end

  # `generator: supplied` (`chain.md` #8, #17) mints straight from its
  # own pinned `input.<role>` document — no draft, no dispatch. Only an
  # `input.<role>`-sourced supplied tier mints this way (`design_system`);
  # a `write`-sourced one (`ref`) is an outside write path's own tier and
  # is never minted here. A role with no pinned documents yet mints
  # nothing this tick — the ordinary "not pinned yet" case, not an error.
  defp mint_supplied(chain, project_id) do
    for {tier_name, %{generator: "supplied", source_raw: source_raw}} <- chain.tiers,
        role = supplied_role(source_raw),
        not is_nil(role) do
      case Delivery.get_input_documents(project_id, role) do
        [] ->
          :ok

        [_ | _] ->
          Store.mint_node(%{
            id: tier_name,
            project_id: project_id,
            tier: tier_name,
            scope_key: %{},
            status: :approved,
            fields: %{}
          })
      end
    end

    :ok
  end

  defp supplied_role(source_raw) do
    case ContextWalk.parse(source_raw) do
      {:ok, %ContextWalk{source: :input, role: role}} when is_binary(role) -> role
      _other -> nil
    end
  end

  defp sweep_tiers(chain, project_id) do
    for {tier_name, tier} <- chain.tiers do
      if generation_dispatchable?(tier), do: sweep_generation(chain, project_id, tier_name)
      if review_dispatchable?(tier), do: sweep_review(chain, project_id, tier_name)
    end

    :ok
  end

  defp sweep_generation(chain, project_id, tier_name) do
    for node <- ReadyScopes.ready(chain, project_id, tier_name) do
      enqueue(project_id, tier_name, node.scope_key)
    end
  end

  defp sweep_review(chain, project_id, tier_name) do
    review_tier_name = ReadyScopes.review_tier_name(tier_name)

    for node <- ReadyScopes.ready_review(chain, project_id, review_tier_name) do
      enqueue(project_id, review_tier_name, node.scope_key)
    end
  end

  defp generation_dispatchable?(%{draft: draft, generator: "llm"}) when not is_nil(draft),
    do: true

  defp generation_dispatchable?(_tier), do: false

  defp review_dispatchable?(%{review: review}), do: not is_nil(review)

  defp enqueue(project_id, tier, scope_key) do
    %{project_id: project_id, tier: tier, scope_key: scope_key}
    |> DispatchWorker.new()
    |> Oban.insert()
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, Config.fetch!(:generation, :sweep_interval_ms))
  end
end
