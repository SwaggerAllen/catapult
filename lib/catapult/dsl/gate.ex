defmodule Catapult.Dsl.Gate do
  @moduledoc """
  One `gates.<name>` entry of `workflow.yaml` (`workflow.md` #32): a
  declared review status — `role`, `escalation`, and an optional
  `throwback` target. Position, and now depth too, are not part of
  this declaration: a citing type's own `statuses:` array places its
  `review:` entry wherever the author wants it to run, and `depth:` is
  a property of that same citation (`workflow.md` #33), not of the
  gate.

  `throwback:` is a single optional target, never a list (#34, #35): a
  decline's legal targets are "earlier in the citing type's own
  effective sequence," and a gate outside a sub-array may declare none
  at all — the decline then lands on a human-chosen earlier position.

  Structural parsing only; whether `throwback:` resolves to a position
  in a citing type's own array is `Catapult.Dsl.Workflow`'s job.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :role, :escalation]
  defstruct [:name, :role, :escalation, :throwback]

  @type t :: %__MODULE__{
          name: String.t(),
          role: String.t(),
          throwback: String.t() | nil,
          escalation: String.t()
        }

  @core_keys ~w(role throwback escalation)

  @doc "Parses one `gates.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "gate #{inspect(name)}"

    {role, role_problems} = Fields.require_string(raw, "role", where)
    {throwback, tb_problems} = Fields.optional_string(raw, "throwback", where)
    {escalation, esc_problems} = Fields.require_string(raw, "escalation", where)

    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems = role_problems ++ tb_problems ++ esc_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{name: name, role: role, throwback: throwback, escalation: escalation}}
    else
      {:error, problems}
    end
  end

  def parse(name, other) do
    {:error, ["gate #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end
end
