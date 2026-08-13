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
  """

  defmodule CollisionError do
    defexception [:message]
  end

  @doc "Raises CollisionError listing every problem, or returns :ok."
  def validate!(components) do
    # Registry checks run only over real components; a module that
    # isn't one is its own problem, reported alongside rather than
    # crashing the sweep before it can report.
    real = Enum.filter(components, &component?/1)

    problems =
      missing_behaviour(components) ++
        duplicate_slugs(real) ++
        collisions(real, :pubsub_topics, "pubsub topic") ++
        collisions(real, :oban_queues, "oban queue") ++
        collisions(real, :telemetry_events, "telemetry event") ++
        collisions(real, :events, "event type") ++
        process_collisions(real)

    case problems do
      [] ->
        :ok

      _ ->
        raise CollisionError,
          message: "component registry problems:\n  " <> Enum.join(problems, "\n  ")
    end
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

  defp collisions(components, callback, what) do
    components
    |> Enum.flat_map(fn c -> Enum.map(apply(c, callback, []), &{&1, c}) end)
    |> Enum.group_by(fn {name, _c} -> name end)
    |> Enum.filter(fn {_name, claims} -> length(claims) > 1 end)
    |> Enum.map(fn {name, claims} ->
      owners = Enum.map_join(claims, ", ", fn {_n, c} -> inspect(c) end)
      "#{what} #{inspect(name)} claimed by #{owners}"
    end)
  end

  defp process_collisions(components) do
    components
    |> Enum.flat_map(fn c -> Enum.map(c.processes(), fn {name, _placement} -> {name, c} end) end)
    |> Enum.group_by(fn {name, _c} -> name end)
    |> Enum.filter(fn {_name, claims} -> length(claims) > 1 end)
    |> Enum.map(fn {name, claims} ->
      owners = Enum.map_join(claims, ", ", fn {_n, c} -> inspect(c) end)
      "process name #{inspect(name)} claimed by #{owners}"
    end)
  end
end
