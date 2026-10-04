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
  the workflow's `entry:` names. Individual tests overlay/replace
  entries with `write!/2` afterward.

  `comparch` is a `scope: singleton` generating tier so it needs no
  scope-parent chain, with its own schema (`comparch.xsd`, written
  alongside) carrying the `<catapult:identity>` annotation chain.md
  #32 requires — the loader now reads identity off the schema, not off
  a chain.yaml key.
  """
  @spec minimal!(String.t()) :: :ok
  def minimal!(dir) do
    write!(dir, %{
      "catapult.yaml" => """
      chain: default
      workflow: default-flow
      """,
      "bundles/default/chain.yaml" => """
      name: default
      version: "1.0.0"
      kind: chain
      tiers:
        comparch:
          scope: singleton
          prompt: prompts/comparch.md.liquid
      edges: {}
      """,
      "bundles/default/schemas/comparch.xsd" => """
      <?xml version="1.0" encoding="UTF-8"?>
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:catapult="urn:catapult:dsl">
        <xs:element name="comparch">
          <xs:annotation><xs:appinfo><catapult:identity>id</catapult:identity></xs:appinfo></xs:annotation>
          <xs:complexType>
            <xs:sequence>
              <xs:element name="name" type="xs:string"/>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
      """,
      "bundles/default/prompts/comparch.md.liquid" => "Write a comparch.\n",
      "bundles/default-flow/workflow.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      entry: project
      types:
        project:
          statuses:
            - { status: build-out, flow: feature }
        feature:
          skeleton: ticket
          serves: no_delta
          statuses:
            - status: generation
              tiers: [comparch]
            - status: critique
            - review: product-review
            - status: checks
            - status: reconcile
            - status: merge
            - status: deploy
            - status: terminal
      gates:
        product-review: { role: design, escalation: author }
      environments: {}
      """
    })
  end
end
