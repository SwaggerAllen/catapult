defmodule Catapult.Dsl.Environment do
  @moduledoc """
  One `environments/<env>.yaml` declaration (dsl-syntax.md §15.4): a
  deployment environment — which environments exist and what promotion
  into one requires, never endpoints, credentials or hostnames (those
  are plane bindings, v5 §7.10's store test).

  Structural parsing only; `after:` resolving to a system status and
  `promote_from:` resolving to a declared environment (with its chain
  acyclic) are `Catapult.Dsl.Bundle`'s job.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file, :after]
  defstruct [:name, :file, :after, :promote_from, depth: 0, lifetime: "persistent"]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          after: String.t(),
          promote_from: String.t() | nil,
          depth: Fields.depth(),
          lifetime: String.t()
        }

  @lifetimes ~w(persistent per_ticket)
  @core_keys ~w(environment after promote_from depth lifetime)

  @doc "Parses one environment declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "environment declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "environment", where)
    env_where = if name, do: "environment #{inspect(name)} (#{file})", else: where

    {after_, after_problems} = Fields.require_string(raw, "after", env_where)
    {promote_from, pf_problems} = Fields.optional_string(raw, "promote_from", env_where)
    {depth, depth_problems} = Fields.depth(raw, env_where)

    {lifetime, lifetime_problems} =
      Fields.optional_one_of(raw, "lifetime", @lifetimes, env_where, "persistent")

    unknown = Fields.unknown_keys(raw, @core_keys, env_where)

    problems =
      name_problems ++
        after_problems ++ pf_problems ++ depth_problems ++ lifetime_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         after: after_,
         promote_from: promote_from,
         depth: depth,
         lifetime: lifetime
       }}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["environment declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end
end
