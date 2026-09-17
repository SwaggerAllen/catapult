defmodule Catapult.Dsl.CatapultYaml do
  @moduledoc """
  `catapult.yaml` (`bundle.md` #2): repo-root, pins one bundle name
  per axis under `bundles/`. The loader's own input, not bundle
  content (`systems/core_dsl.md`) — nothing here is validated against
  a bundle schema, only read to find `bundles/` in the first place.

  `workflow:` is required under the `design` dialect (both axes) and
  forbidden under `runtime` (v5 §7.18: that dialect loads no workflow
  bundle at all, so naming one is a load error rather than a key this
  parser silently ignores).
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:chain]
  defstruct [:chain, :workflow]

  @type t :: %__MODULE__{chain: String.t(), workflow: String.t() | nil}

  @doc "Parses catapult.yaml's map for `dialect` (`Catapult.Dsl.Dialect`)."
  @spec parse(map(), Catapult.Dsl.Dialect.t()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(%{} = raw, dialect) do
    where = "catapult.yaml"
    {chain, chain_problems} = Fields.require_string(raw, "chain", where)
    {workflow, workflow_problems} = workflow_field(raw, dialect, where)
    unknown = Fields.unknown_keys(raw, ["chain", "workflow"], where)

    problems = chain_problems ++ workflow_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{chain: chain, workflow: workflow}}
    else
      {:error, problems}
    end
  end

  def parse(other, _dialect) do
    {:error, ["catapult.yaml is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp workflow_field(raw, %{loads_workflow?: true}, where),
    do: Fields.require_string(raw, "workflow", where)

  defp workflow_field(raw, %{loads_workflow?: false, name: name}, where) do
    case Map.fetch(raw, "workflow") do
      :error ->
        {nil, []}

      {:ok, _value} ->
        {nil,
         [
           "#{where} names a workflow: bundle under the #{name} dialect, which loads no workflow bundle at all"
         ]}
    end
  end
end
