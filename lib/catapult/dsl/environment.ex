defmodule Catapult.Dsl.Environment do
  @moduledoc """
  One `environments.<name>` entry of `workflow.yaml` (`workflow.md`
  #39): a deployment environment and what promotion into it requires —
  never endpoints, credentials or hostnames (those are plane bindings).

  Position is not part of this declaration: a citing type's own
  `statuses:` array places its `environment:` entry wherever the
  author wants it to run, ahead of the `deploy:` entry it configures.

  Structural parsing only; `promote_from:` resolving to a declared
  environment (with its chain acyclic) is `Catapult.Dsl.Workflow`'s job.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name]
  defstruct [:name, :promote_from, lifetime: "persistent"]

  @type t :: %__MODULE__{name: String.t(), promote_from: String.t() | nil, lifetime: String.t()}

  @lifetimes ~w(persistent per_ticket)
  @core_keys ~w(promote_from lifetime)

  @doc "Parses one `environments.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "environment #{inspect(name)}"

    {promote_from, pf_problems} = Fields.optional_string(raw, "promote_from", where)

    {lifetime, lifetime_problems} =
      Fields.optional_one_of(raw, "lifetime", @lifetimes, where, "persistent")

    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems = pf_problems ++ lifetime_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{name: name, promote_from: promote_from, lifetime: lifetime}}
    else
      {:error, problems}
    end
  end

  def parse(name, other) do
    {:error, ["environment #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end
end
