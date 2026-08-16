defmodule Catapult.Component.Composer do
  @moduledoc """
  The root composer (conventions §4): aggregates every component's
  registry claims and reports ALL collisions at once (orchestration's
  config-validation style — one round trip per problem is hostile).
  Root artifacts are composed from its output, never edited by hand
  (conventions §4): `children/1` feeds the root supervisor,
  `readiness/1` feeds the health endpoint, `run_seeds/1` the release
  task.

  Enforcement is boot + CI (the audit task calls `validate!/1`): a
  collision fails the build and fails the boot, whichever comes first.

  ## One pass over the roster

  Aggregation, the collision report and `inventory/1` are each one pass
  over `Catapult.Component.Registries.rows/0` rather than a validator
  per registry (systems/substrate.md). Two kinds of duplicate fall out
  of that table: a *claim* held by two components is a collision, and an
  *identity* declared twice inside one component is a duplicate. They
  differ only for `events/0`, where one component declaring one type at
  two versions is ordinary and permanent.

  `config/0` keeps its own report (`Catapult.Config`) and is folded in
  here, which is what makes an env var a claimed name like a queue.
  """

  alias Catapult.Component.Licensing
  alias Catapult.Component.Registries

  defmodule CollisionError do
    defexception [:message]
  end

  @doc "Raises CollisionError listing every problem, or returns :ok."
  def validate!(components) do
    # Registry checks run only over real components; a module that
    # isn't one is its own problem, reported alongside rather than
    # crashing the sweep before it can report.
    real = Enum.filter(components, &component?/1)
    declared = Enum.map(real, fn c -> {c, declarations(c)} end)

    problems =
      missing_behaviour(components) ++
        duplicate_slugs(real) ++
        Enum.flat_map(declared, fn {_c, d} -> d.problems end) ++
        Enum.flat_map(Registries.rows(), &registry_problems(&1, declared)) ++
        Enum.flat_map(declared, fn {c, d} -> cross_registry_problems(c, d.entries) end) ++
        config_collisions(real) ++
        config_declarations(real) ++
        licensing_declarations(real)

    case problems do
      [] ->
        :ok

      _ ->
        raise CollisionError,
          message: "component registry problems:\n  " <> Enum.join(problems, "\n  ")
    end
  end

  @doc """
  Every registry's normalized entries, keyed by callback.

  The census surface: a function returning normalized data, never a
  document (docs/non-goals.md's no-hand-maintained-inventories rule).
  Every roster key is present even when empty, because an empty registry
  is exactly the fact worth seeing — a registry aggregating into nothing
  is this ticket's deliberate state, and that state's failure mode is
  rot rather than collision.

  Entries are the wide form plus their owner: `:component` and `:slug`.
  Malformed entries are absent — `validate!/1` is what reports them.
  """
  def inventory(components) do
    real = Enum.filter(components, &component?/1)
    declared = Enum.map(real, fn c -> {c, declarations(c)} end)

    Map.new(Registries.keys(), fn key ->
      entries =
        for {component, %{entries: entries}} <- declared,
            entry <- Map.fetch!(entries, key),
            do: Map.merge(entry, %{component: component, slug: component.slug()})

      {key, entries}
    end)
  end

  @doc "All components' supervision children, in component order."
  def children(components) do
    Enum.flat_map(components, & &1.children())
  end

  @doc "slug => ready? map for the health endpoint."
  def readiness(components) do
    Map.new(components, &{&1.slug(), &1.ready?()})
  end

  @doc "Runs every component's seeds, in order. Seeds are idempotent by construction."
  def run_seeds(components) do
    Enum.each(components, & &1.seeds())
  end

  defp component?(c) do
    Code.ensure_loaded?(c) and function_exported?(c, :__catapult_component__, 0)
  end

  defp missing_behaviour(components) do
    for c <- components, not component?(c) do
      "#{inspect(c)} does not `use Catapult.Component`"
    end
  end

  defp duplicate_slugs(components) do
    components
    |> Enum.group_by(& &1.slug())
    |> Enum.filter(fn {_slug, cs} -> length(cs) > 1 end)
    |> Enum.map(fn {slug, cs} ->
      "slug #{inspect(slug)} claimed by #{Enum.map_join(cs, ", ", &inspect/1)}"
    end)
  end

  ## Reading the roster

  # One component's whole roster, normalized once: `entries` keyed by
  # callback, `problems` in declaration order. An entry with a shape
  # problem still counts as claimed — reporting the collision and the
  # shape problem in one pass is the point.
  defp declarations(component) do
    Enum.reduce(Registries.rows(), %{entries: %{}, problems: []}, fn row, acc ->
      {entries, problems} = read(component, row)

      %{
        entries: Map.put(acc.entries, row.key, entries),
        problems: acc.problems ++ problems
      }
    end)
  end

  defp read(component, row) do
    case apply(component, row.key, []) do
      declared when is_list(declared) ->
        Enum.reduce(declared, {[], []}, &normalize(&1, &2, component, row))

      other ->
        {[],
         [
           "#{inspect(component)}'s #{row.key}/0 returned #{inspect(other)}, expected a list"
         ]}
    end
  end

  defp normalize(declared, {entries, problems}, component, row) do
    case Registries.normalize(row, declared) do
      {:ok, entry} ->
        {entries ++ [entry], problems ++ Registries.entry_problems(row, component, entry)}

      :error ->
        {entries, problems ++ [malformed(component, row, declared)]}
    end
  end

  defp malformed(component, row, declared) do
    "#{inspect(component)} has a malformed #{row.label} entry #{inspect(declared)} " <>
      "(expected #{Registries.expected_form(row)})"
  end

  ## Duplicates, both kinds

  defp registry_problems(row, declared) do
    Enum.flat_map(declared, &within_component(row, &1)) ++ across_components(row, declared)
  end

  defp within_component(row, {component, %{entries: entries}}) do
    entries
    |> Map.fetch!(row.key)
    |> Enum.group_by(&Registries.identity(row, &1))
    |> Enum.filter(fn {_identity, es} -> length(es) > 1 end)
    |> Enum.map(fn {identity, _es} ->
      "#{inspect(component)} declares #{row.label} #{inspect(identity)} more than once"
    end)
  end

  # Two *components* holding one claim is the collision; one component
  # holding it twice is `within_component/2`'s line, which is why this
  # counts distinct owners rather than entries. `events/0` is the reason
  # the two are separate at all.
  defp across_components(row, declared) do
    claims =
      for {component, %{entries: entries}} <- declared,
          entry <- Map.fetch!(entries, row.key),
          do: {Registries.claim(row, entry), component}

    claims
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {claim, owners} -> {claim, Enum.uniq(owners)} end)
    |> Enum.filter(fn {_claim, owners} -> length(owners) > 1 end)
    |> Enum.map(fn {claim, owners} ->
      "#{row.label} #{inspect(claim)} claimed by #{Enum.map_join(owners, ", ", &inspect/1)}"
    end)
  end

  ## Cross-registry

  # Facts no single row can hold, because each is about two declarations
  # at once. They are the payoff of one table: a row says what an entry
  # *is*, and these say what two of them owe each other.
  defp cross_registry_problems(component, entries) do
    kill_switch_problems(component, entries) ++
      cron_worker_problems(component, entries) ++
      external_contract_problems(component, entries)
  end

  # The first cross-registry check, and what makes v5 §2.2's promise
  # literal: a switch pointing at a flag nobody registered is a switch
  # that does nothing, discovered during the incident it was built for.
  defp kill_switch_problems(component, entries) do
    flags = entries |> Map.fetch!(:feature_flags) |> MapSet.new(& &1.flag)

    for external <- Map.fetch!(entries, :externals),
        {:ok, switch} <- [Keyword.fetch(external.opts, :kill_switch)],
        is_atom(switch) and not is_nil(switch),
        not MapSet.member?(flags, switch) do
      "#{inspect(component)}'s external #{inspect(external.name)} names kill switch " <>
        "#{inspect(switch)}, which it does not declare in feature_flags/0"
    end
  end

  # The cross-fact the `{schedule, worker}` shape buys (ORC-21): a
  # worker's queue comes from its own `use Oban.Worker`, so a scheduled
  # worker whose queue is not the entry it was declared under is a job
  # that will run somewhere nobody declared — invisible in the queue
  # registry, which is the one place an operator would look.
  defp cron_worker_problems(component, entries) do
    for queue <- Map.fetch!(entries, :oban_queues),
        {:ok, crontab} <- [Keyword.fetch(queue.opts, :cron)],
        is_list(crontab),
        {schedule, worker} <- crontab,
        is_binary(schedule),
        is_atom(worker) and not is_nil(worker) and Code.ensure_loaded?(worker),
        reason <- worker_queue_reason(worker, queue.queue) do
      "#{inspect(component)}'s oban queue #{inspect(queue.queue)} schedules " <>
        "#{inspect(worker)}, which #{reason}"
    end
  end

  # `use Oban.Worker` generates `__opts__/0`, which is the worker's own
  # answer and the only one that matters at enqueue time. Substrate takes
  # no Oban dependency to ask (systems/substrate.md), so the question is
  # put to the module rather than to a library.
  defp worker_queue_reason(worker, queue) do
    cond do
      not function_exported?(worker, :__opts__, 0) ->
        ["is not an Oban worker (no __opts__/0)"]

      to_string(Keyword.get(worker.__opts__(), :queue)) == to_string(queue) ->
        []

      true ->
        ["runs on queue #{inspect(Keyword.get(worker.__opts__(), :queue))}"]
    end
  end

  # The one thing `externals/0` still owes the audit, and it needs no new
  # field: both modules already carry the answer in their own attributes.
  # A fake that has drifted off its adapter's contract is a test lying
  # about a system it never called (systems/substrate.md).
  defp external_contract_problems(component, entries) do
    for external <- Map.fetch!(entries, :externals),
        {:ok, adapter} <- [Keyword.fetch(external.opts, :adapter)],
        {:ok, fake} <- [Keyword.fetch(external.opts, :fake)],
        loadable?(adapter) and loadable?(fake),
        MapSet.disjoint?(behaviours(adapter), behaviours(fake)) do
      "#{inspect(component)}'s external #{inspect(external.name)} declares adapter " <>
        "#{inspect(adapter)} and fake #{inspect(fake)}, which share no behaviour"
    end
  end

  defp loadable?(module) do
    is_atom(module) and not is_nil(module) and Code.ensure_loaded?(module)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
    |> MapSet.new()
  end

  ## Config's own report, folded in

  # An env var name is a claimed name like a queue or a topic: two
  # components binding `DATABASE_URL` is the same class of bug as two
  # claiming `:engine_default`, so it is reported in the same breath
  # (systems/substrate.md). This is what makes `config/0` load-bearing
  # rather than descriptive.
  defp config_collisions(components) do
    components
    |> Enum.flat_map(fn c -> Enum.map(Catapult.Config.declared_names(c), &{&1, c}) end)
    |> duplicates("env var")
  end

  # The structural half of the config report — malformed declarations,
  # unknown opts, a name off the slug spine. Checkable with no
  # environment at all, which is why it lives here and not at boot:
  # values are the boot's half, and CI cannot see them.
  defp config_declarations(components) do
    Enum.flat_map(components, &Catapult.Config.declaration_problems/1)
  end

  ## Licensing's shape, and only its shape

  # The other registry outside the table (`Catapult.Component.Licensing`).
  # Shape only, deliberately: this function runs at boot as well as under
  # the audit, and a licensing *verdict* at boot is a node refusing to
  # start over a question with no runtime consequence (LICENSING.md). The
  # policy is `Catapult.Audit.License`'s, which never runs here.
  defp licensing_declarations(components) do
    Enum.flat_map(components, &Licensing.problems/1)
  end

  defp duplicates(claims, what) do
    claims
    |> Enum.group_by(fn {name, _c} -> name end)
    |> Enum.filter(fn {_name, claims} -> length(claims) > 1 end)
    |> Enum.map(fn {name, claims} ->
      owners = Enum.map_join(claims, ", ", fn {_n, c} -> inspect(c) end)
      "#{what} #{inspect(name)} claimed by #{owners}"
    end)
  end
end
