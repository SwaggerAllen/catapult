defmodule Catapult.ToySeed do
  @moduledoc """
  Fixture-file access for the toy-seed chain tests (ORC-10): the
  per-role input documents and the bound repo's workflow file, read
  from disk on every call rather than embedded as string literals, so
  a reviewer reads the actual fixture content in its own file under
  `test/catapult/generation/fixtures/toy_seed/` (generation's file
  map — this module itself lives in `test/support/**`, foundation's,
  since it is shared harness code rather than fixture content).

  These are exactly the roles named across the design corpus
  (dsl-syntax.md §7.2's examples, v5-design-decisions.md's "the intake
  role list has since grown") — there is no code-level registry yet
  (`docs/non-goals.md`'s ORC-10 entry: `input.<role>` resolution is
  Phase 4), so this list *is* the registry until one exists.
  """

  @fixture_dir Path.join([__DIR__, "..", "catapult", "generation", "fixtures", "toy_seed"])

  @roles ~w(
    project_doc non_goals behavior_docs mocks invariants
    capability_inventories forward_strategies
  )

  @doc "Every registered input role's fixture document, keyed by role name."
  @spec role_docs() :: %{String.t() => String.t()}
  def role_docs, do: for(role <- @roles, into: %{}, do: {role, File.read!(doc_path(role))})

  @doc """
  Repo-relative path => content for `Catapult.Delivery.HostPort.reset_repo/2`:
  the workflow file at the path GitHub itself requires, plus every
  role doc filed under `docs/toy-seed/` — fixture content only, per
  the port's own contract (`lib/catapult/delivery/host_port.ex`).
  """
  @spec reset_files() :: %{String.t() => String.t()}
  def reset_files do
    role_files =
      for {role, content} <- role_docs(), into: %{}, do: {"docs/toy-seed/#{role}.md", content}

    Map.put(role_files, ".github/workflows/catapult-dispatch.yml", File.read!(workflow_path()))
  end

  defp doc_path(role), do: Path.join(@fixture_dir, "#{role}.md")
  defp workflow_path, do: Path.join(@fixture_dir, "catapult-dispatch.yml")
end
