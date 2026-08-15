defmodule Mix.Tasks.Catapult.Audit do
  @shortdoc "Runs the structural audit (conventions §2.14 of the v5 decisions)"
  @moduledoc """
  Audit v0 — the checks that exist so far, all-problems-at-once:

    * component registry collisions (via the composer)
    * direct wall-clock reads in lib/ — `utc_now` on the built-in
      date/time modules (the injected-clock rule, conventions §9)
    * processes named after their own module in lib/ — a `name:`
      option handed `__MODULE__` (the placement rule, conventions §5)

  Those two are stated rather than spelled: the greps read this file
  too, and an allow tag on a sentence *about* a ban is a tag spent on
  prose (systems/substrate.md).

  A line may opt out with a `catapult:allow <check>` comment, on the
  offending line **or on the comment line directly above it** — those
  two and no other span, so an escape's extent is never something a
  reader has to work out. Both, because `mix format --check-formatted`
  is itself a hard gate (conventions §2) and the formatter relocates
  every trailing comment onto its own line: the same-line form does not
  survive a formatted tree, so demanding it would be demanding a hatch
  no file here can hold. Visible in review, greppable, never silent.
  The check registry grows with the platform (v5 §2.14); this task is
  the enforcement organ's first organ.

  The globs are rooted at the working directory and stay that way: this
  task ships into every generated project, so the layout of any one tree
  is not a fact it may hold (docs/non-goals.md). Auditing a repo with
  more than one mix project means running it once per project — at the
  root of this one, `mix catapult.audit.all` does exactly that.

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
          "process registered under its own module name (register via processes/0; conventions §5)"
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
    tag = "catapult:allow #{allow_tag}"

    Path.wildcard("lib/**/*.ex")
    |> Enum.flat_map(fn file ->
      lines = file |> File.read!() |> String.split("\n")

      lines
      # Pair each line with its predecessor; `nil` for the first.
      |> Enum.zip([nil | lines])
      |> Enum.with_index(1)
      |> Enum.filter(fn {{line, previous}, _n} ->
        Regex.match?(regex, line) and not allowed?(line, previous, tag)
      end)
      |> Enum.map(fn {_pair, n} -> "#{file}:#{n}: #{label}" end)
    end)
  end

  # The line above must itself be a comment: without that, a tagged
  # violation would silently excuse an untagged one on the next line.
  defp allowed?(line, previous, tag) do
    String.contains?(line, tag) or
      (is_binary(previous) and comment?(previous) and String.contains?(previous, tag))
  end

  defp comment?(line), do: line |> String.trim_leading() |> String.starts_with?("#")
end
