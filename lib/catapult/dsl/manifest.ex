defmodule Catapult.Dsl.Manifest do
  @moduledoc """
  One `bundle.yaml` (dsl-syntax.md §2): name, version, kind, `extends:`,
  and the per-kind glob lists — `tiers:`/`edges:`/`fragments:`/`flows:`
  for a chain, `gates:`/`environments:` for a workflow. A `tiers:` key
  in a workflow manifest (or the reverse) is an unknown field, per §2's
  own text: the file-list keys are per-kind.

  Fragment kinds are a closed vocabulary *per bundle* (§2): a kind used
  in any `handle:`/`produces:` must appear in `fragments:` here, which
  `Catapult.Dsl.Bundle` checks once every tier is loaded.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file, :kind, :version]
  defstruct [
    :name,
    :file,
    :kind,
    :version,
    :extends,
    tier_globs: [],
    edge_globs: [],
    flow_globs: [],
    fragments: [],
    gate_globs: [],
    environment_globs: []
  ]

  @type kind :: String.t()

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          kind: kind(),
          version: String.t(),
          extends: String.t() | nil,
          tier_globs: [String.t()],
          edge_globs: [String.t()],
          flow_globs: [String.t()],
          fragments: [String.t()],
          gate_globs: [String.t()],
          environment_globs: [String.t()]
        }

  @kinds ~w(chain workflow)
  @chain_keys ~w(name version kind extends tiers edges fragments flows)
  @workflow_keys ~w(name version kind extends gates environments)

  @doc "Parses a bundle.yaml file."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "bundle manifest #{file}"
    {name, name_problems} = Fields.require_string(raw, "name", where)
    {version, version_problems} = Fields.require_string(raw, "version", where)
    {kind, kind_problems} = Fields.require_one_of(raw, "kind", @kinds, where)
    {extends, extends_problems} = Fields.optional_string(raw, "extends", where)

    {lists, list_problems, unknown} = parse_lists(raw, kind, where)

    problems =
      name_problems ++
        version_problems ++ kind_problems ++ extends_problems ++ list_problems ++ unknown

    if problems == [] do
      {:ok,
       struct!(
         __MODULE__,
         [name: name, file: file, kind: kind, version: version, extends: extends] ++ lists
       )}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["bundle manifest #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_lists(_raw, nil, _where), do: {[], [], []}

  defp parse_lists(raw, "chain", where) do
    {tiers, tp} = Fields.optional_string_list(raw, "tiers", where)
    {edges, ep} = Fields.optional_string_list(raw, "edges", where)
    {flows, flp} = Fields.optional_string_list(raw, "flows", where)
    {fragments, frp} = Fields.optional_string_list(raw, "fragments", where)
    unknown = Fields.unknown_keys(raw, @chain_keys, where)

    lists = [tier_globs: tiers, edge_globs: edges, flow_globs: flows, fragments: fragments]
    {lists, tp ++ ep ++ flp ++ frp, unknown}
  end

  defp parse_lists(raw, "workflow", where) do
    {gates, gp} = Fields.optional_string_list(raw, "gates", where)
    {environments, envp} = Fields.optional_string_list(raw, "environments", where)
    unknown = Fields.unknown_keys(raw, @workflow_keys, where)

    lists = [gate_globs: gates, environment_globs: environments]
    {lists, gp ++ envp, unknown}
  end
end
