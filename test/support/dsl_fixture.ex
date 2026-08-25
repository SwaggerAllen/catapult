defmodule Catapult.Dsl.Fixture do
  @moduledoc """
  Writes a `%{relative_path => content}` map into `dir` as real files,
  for `Catapult.Dsl.Loader` tests that need an on-disk bundle tree
  rather than a unit-level struct.
  """

  @doc "Writes every entry in `files` under `dir`, creating directories as needed."
  @spec write!(String.t(), %{String.t() => String.t()}) :: :ok
  def write!(dir, files) do
    Enum.each(files, fn {relative, content} ->
      path = Path.join(dir, relative)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end)
  end

  @doc """
  A minimal, valid chain+workflow project under `dir`: one tier
  (`comparch`), no edges, no flows, and a default workflow with one
  gate, one ticket-skeleton type citing it, and a skeleton-less root
  the bundle's `entry:` names. Individual tests overlay/replace entries
  with `write!/2` afterward.

  The workflow half carries `types:`/`entry:` and no `after:` anywhere
  as of ORC-104 (dsl-syntax.md §15.2-§15.4): a gate's position is the
  citing type's own array index, and `entry:` is a required key naming
  the queue-shaped root a fresh project dispatches from.
  """
  @spec minimal!(String.t()) :: :ok
  def minimal!(dir) do
    write!(dir, %{
      "catapult.yaml" => """
      chain: default
      workflow: default-flow
      """,
      "bundles/default/bundle.yaml" => """
      name: default
      version: "1.0.0"
      kind: chain
      tiers: [tiers/*.yaml]
      edges: [edges/*.yaml]
      fragments: [techspec]
      flows: [flows/*/flow.yaml]
      """,
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      fields:
        name: draft.name
      handle:
        fields: [id, name]
        fragments: [techspec]
      draft:
        root_tag: comparch
        grammar: schemas/comparch.xsd
      generator: llm
      prompt: prompts/comparch.md.liquid
      """,
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      gates: [gates/*.yaml]
      environments: [environments/*.yaml]
      types: [types/*.yaml]
      entry: project
      """,
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      """,
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: feature
      """,
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: pending
        - status: generation
        - review: product-review
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })
  end
end
