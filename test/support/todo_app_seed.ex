defmodule Catapult.TodoAppSeed do
  @moduledoc """
  Fixture-file access for Waypoint, the todo-app raft Phase 5's exit
  criterion runs (ORC-112, `docs/build-plan.md`'s Phase 5 section): the
  per-role input documents and the bound repo's workflow file, read
  from disk on every call rather than embedded as string literals, so
  a reviewer reads the actual fixture content in its own file under
  `test/catapult/generation/fixtures/todo_app/` (generation's file
  map — this module itself lives in `test/support/**`, foundation's,
  the same split `Catapult.ToySeed`'s own moduledoc draws).

  A second fixture beside `toy_seed`, deliberately: same file-per-role
  shape (`role: Path.rootname(filename)`,
  `Store.pin_input_documents/3`), same seven roles
  (`project_doc`, `non_goals` and `mocks` are platform roles per
  `dsl-syntax.md` §7; `behavior_docs`, `invariants`,
  `capability_inventories`, `forward_strategies` are project-declared
  names, legal and simply never walked by anything that doesn't read
  them). It carries no canned tier bodies — `toy_seed` stays the
  offline fixture, untouched, and this one only ever runs live
  (`test/catapult/generation/todo_app_proof_live_test.exs`).
  """

  @fixture_dir Path.join([__DIR__, "..", "catapult", "generation", "fixtures", "todo_app"])

  @roles ~w(
    project_doc non_goals behavior_docs mocks invariants
    capability_inventories forward_strategies
  )

  @doc "Every registered input role's fixture document, keyed by role name."
  @spec role_docs() :: %{String.t() => String.t()}
  def role_docs, do: for(role <- @roles, into: %{}, do: {role, File.read!(doc_path(role))})

  @doc """
  Repo-relative path => content for `Catapult.Delivery.Provisioning
  .provision/1`'s own `files` body: the workflow file at the path
  GitHub itself requires, plus every role doc filed under
  `docs/raft/`, the intake raft's registered discovery path (ORC-107,
  `systems/delivery.md`) — fixture content only, the same contract
  `Catapult.ToySeed.reset_files/0` already fulfills for its own raft.
  """
  @spec reset_files() :: %{String.t() => String.t()}
  def reset_files do
    role_files =
      for {role, content} <- role_docs(), into: %{}, do: {"docs/raft/#{role}.md", content}

    Map.put(role_files, ".github/workflows/catapult-dispatch.yml", File.read!(workflow_path()))
  end

  defp doc_path(role), do: Path.join(@fixture_dir, "#{role}.md")
  defp workflow_path, do: Path.join(@fixture_dir, "catapult-dispatch.yml")
end
