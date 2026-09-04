defmodule Catapult.ToySeed do
  @moduledoc """
  Fixture-file access for the toy-seed chain tests (ORC-10): the
  per-role input documents, the stub tier bodies and the bound repo's
  workflow file, read from disk on every call rather than embedded as
  string literals, so a reviewer reads the actual fixture content in
  its own file — this raft's own under
  `test/catapult/generation/fixtures/toy_seed/`, the workflow file one
  level up at `test/catapult/generation/fixtures/catapult-dispatch.yml`
  because it is shared with `Catapult.TodoAppSeed` (all of it
  generation's file map — this module itself lives in
  `test/support/**`, foundation's, since it is shared harness code
  rather than fixture content).

  These are exactly the roles named across the design corpus
  (dsl-syntax.md §7.2's examples, v5-design-decisions.md's "the intake
  role list has since grown") — the mechanism itself has no closed
  registry to violate (dsl-syntax.md §7: only a shipped tier reading a
  role makes it platform vocabulary, and a project's own role name is
  legal and simply never walked), so this list is fixture breadth, not
  a registry this module enforces.
  """

  @fixture_dir Path.join([__DIR__, "..", "catapult", "generation", "fixtures", "toy_seed"])

  # The harness is raft-independent — `Catapult.TodoAppSeed` pushes the
  # identical file to the identical path in the identical bound repo —
  # so it lives beside the raft directories rather than inside this
  # one, and both seeds read the single copy (the file's own header
  # carries why duplicating it was a trap).
  @shared_fixture_dir Path.join([__DIR__, "..", "catapult", "generation", "fixtures"])

  @roles ~w(
    project_doc non_goals behavior_docs mocks invariants
    capability_inventories forward_strategies
  )

  # Every tier's own `root_tag` => the fixture file that carries it
  # (ORC-223, `systems/generation.md`'s ORC-223 entry) — keyed by
  # `root_tag`, not by the fixture's own checked-in filename, since the
  # two differ for five of the nine (`bundles/default/tiers/*.yaml`'s
  # own `root_tag:` values). `impl.xml` serves `implementation` for all
  # three `impl_*` tiers, which all declare that same `root_tag`.
  @root_tag_fixtures %{
    "comparch" => "comparch.xml",
    "feature-expansion" => "feature_expansion.xml",
    "implementation" => "impl.xml",
    "reference" => "ref.xml",
    "requirements" => "requirements.xml",
    "review" => "review_approve.xml",
    "subcomparch" => "subcomparch.xml",
    "sysarch" => "sysarch.xml",
    "vocab-entry" => "vocab.xml"
  }

  @doc "Every registered input role's fixture document, keyed by role name."
  @spec role_docs() :: %{String.t() => String.t()}
  def role_docs, do: for(role <- @roles, into: %{}, do: {role, File.read!(doc_path(role))})

  @doc """
  Repo-relative path => content for `Catapult.Delivery.HostPort.reset_repo/2`:
  the workflow file at the path GitHub itself requires, every role doc
  filed under `docs/raft/`, the intake raft's registered discovery path
  (ORC-107, `systems/delivery.md`) — fixture content only, per the
  port's own contract (`lib/catapult/delivery/host_port.ex`) — and, as
  of ORC-223, every stub fixture under `.catapult-stub/<root_tag>.xml`,
  never under `docs/raft/**` so pushed stub content is never mistaken
  for raft input.
  """
  @spec reset_files() :: %{String.t() => String.t()}
  def reset_files do
    role_files =
      for {role, content} <- role_docs(), into: %{}, do: {"docs/raft/#{role}.md", content}

    stub_files =
      for {root_tag, filename} <- @root_tag_fixtures, into: %{} do
        {".catapult-stub/#{root_tag}.xml", File.read!(Path.join(@fixture_dir, filename))}
      end

    role_files
    |> Map.merge(stub_files)
    |> Map.put(".github/workflows/catapult-dispatch.yml", File.read!(workflow_path()))
  end

  defp doc_path(role), do: Path.join(@fixture_dir, "#{role}.md")
  defp workflow_path, do: Path.join(@shared_fixture_dir, "catapult-dispatch.yml")
end
