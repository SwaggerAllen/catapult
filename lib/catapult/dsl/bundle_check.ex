defmodule Mix.Tasks.Catapult.Bundle.Check do
  @moduledoc """
  `bundle.md` #14's acceptance test: loads `bundles/default/chain.yaml`
  and `bundles/default-flow/workflow.yaml` through the ordinary loader
  path (`Catapult.Dsl.Loader`, reached here via the boundary export
  `Catapult.Dsl.load/2` exactly as every other consumer reaches it),
  which exercises every load rule the two files are held to for free,
  and then measures both files against the readability bound: the
  chain file at most 800 lines with comments at most a fifth of that,
  the workflow file at most 240 lines. Red on either file exceeding
  its bound or failing to load at all.

  This is a built-in of the task itself, not a `Catapult.Audit.Check`
  (`systems/substrate.md`'s registry is `components/substrate`'s own
  gate suite, rooted at the working directory it runs from — this task
  gains nothing from it) and not a port of `docs/dsl/example/check.py`'s
  other three jobs, which are load-time rules the loader now owns
  (`chain.md` #20, #21; `workflow.md` #22, #23, #40; `bundle.md` #11) —
  reimplementing those here would be a second implementation of the
  same load rules (`systems/core_dsl.md`'s #ORC-249-1 entry).
  `docs/dsl/example/` stays that checker's own worked example; this
  task reads the shipped bundle, never that folder.
  """

  use Mix.Task
  use Boundary, classify_to: Catapult

  @shortdoc "Loads bundles/default + bundles/default-flow and checks bundle.md #14's line-count bound"

  @chain_path "bundles/default/chain.yaml"
  @workflow_path "bundles/default-flow/workflow.yaml"
  @chain_limit 800
  @chain_comment_limit div(@chain_limit, 5)
  @workflow_limit 240

  @impl Mix.Task
  def run(_args) do
    root = File.cwd!()

    case Catapult.Dsl.load(root) do
      {:ok, _loaded} ->
        problems = measure(root)
        report(problems)

      {:error, error} ->
        Mix.shell().error("mix catapult.bundle.check: the shipped bundle failed to load:")

        for problem <- error.details[:problems] || [] do
          Mix.shell().error("  - #{problem}")
        end

        Mix.raise("bundle.md #14's acceptance test failed: the shipped bundle does not load")
    end
  end

  defp measure(root) do
    chain_problems = measure_file(root, @chain_path, @chain_limit, @chain_comment_limit)
    workflow_problems = measure_file(root, @workflow_path, @workflow_limit, nil)
    chain_problems ++ workflow_problems
  end

  # sobelow_skip ["Traversal.FileModule"]
  #
  # `relative_path` is always one of this module's own two `@`
  # constants (`@chain_path`, `@workflow_path`) — never bundle content
  # or any other external input — so there is no traversal for `root`
  # to combine with.
  defp measure_file(root, relative_path, line_limit, comment_limit) do
    path = Path.join(root, relative_path)
    lines = path |> File.read!() |> String.split("\n")
    total = length(lines)
    comments = Enum.count(lines, &(String.trim(&1) |> String.starts_with?("#")))

    Mix.shell().info(
      "#{relative_path}: #{total} lines (limit #{line_limit}), #{comments} comment lines"
    )

    line_problem =
      if total > line_limit do
        ["#{relative_path} is #{total} lines, over bundle.md #14's #{line_limit}-line bound"]
      else
        []
      end

    comment_problem =
      if comment_limit && comments > comment_limit do
        [
          "#{relative_path} has #{comments} comment lines, over bundle.md #14's " <>
            "#{comment_limit}-line bound (a fifth of #{line_limit})"
        ]
      else
        []
      end

    line_problem ++ comment_problem
  end

  defp report([]), do: Mix.shell().info("bundle.md #14's acceptance test: OK")

  defp report(problems) do
    Mix.shell().error("mix catapult.bundle.check: bundle.md #14's acceptance test failed:")
    for problem <- problems, do: Mix.shell().error("  - #{problem}")
    Mix.raise("bundle.md #14's acceptance test failed")
  end
end
