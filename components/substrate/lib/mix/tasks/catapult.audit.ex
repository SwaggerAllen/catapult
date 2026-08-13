defmodule Mix.Tasks.Catapult.Audit do
  @shortdoc "Runs the structural audit (conventions §2.14 of the v5 decisions)"
  @moduledoc """
  Audit v0 — the checks that exist so far, all-problems-at-once:

    * component registry collisions (via the composer)
    * bare `DateTime.utc_now`/`NaiveDateTime.utc_now` in lib/ (the
      injected-clock rule, conventions §9)
    * bare `name: __MODULE__` process naming in lib/ (the placement
      registry rule, conventions §5)

  A line may opt out with an inline `catapult:allow <check>` comment —
  visible in review, greppable, never silent. The check registry grows
  with the platform (v5 §2.14); this task is the enforcement organ's
  first organ.

  The host app declares its components in config:
      config :catapult, :components, [Catapult.Foundation, ...]
  """

  use Mix.Task

  alias Catapult.Component.Composer

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    app = Mix.Project.config()[:app]
    Application.load(app)
    components = Application.get_env(app, :components, [])

    problems =
      registry_problems(components) ++
        grep_problem(
          "utc_now",
          ~r/(?:Naive)?DateTime\.utc_now/,
          "bare utc_now (inject Catapult.Clock; conventions §9)"
        ) ++
        grep_problem(
          "name_module",
          ~r/name:\s*__MODULE__/,
          "bare `name: __MODULE__` (register via processes/0; conventions §5)"
        )

    case problems do
      [] ->
        Mix.shell().info("catapult.audit: clean (#{length(components)} component(s))")

      _ ->
        Mix.raise("catapult.audit failed:\n  " <> Enum.join(problems, "\n  "))
    end
  end

  defp registry_problems([]), do: []

  defp registry_problems(components) do
    Composer.validate!(components)
    []
  rescue
    e in Composer.CollisionError -> [Exception.message(e)]
  end

  defp grep_problem(allow_tag, regex, label) do
    Path.wildcard("lib/**/*.ex")
    |> Enum.flat_map(fn file ->
      file
      |> File.read!()
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _n} ->
        Regex.match?(regex, line) and not String.contains?(line, "catapult:allow #{allow_tag}")
      end)
      |> Enum.map(fn {_line, n} -> "#{file}:#{n}: #{label}" end)
    end)
  end
end
