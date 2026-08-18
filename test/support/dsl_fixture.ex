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
  (`comparch`), no edges, no flows, a default workflow with one gate.
  Individual tests overlay/replace entries with `write!/2` afterward.
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
      """,
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      after: generation
      role: design
      escalation: author
      """
    })
  end
end
