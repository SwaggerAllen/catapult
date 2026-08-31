defmodule Catapult.Dsl.Gate do
  @moduledoc """
  One `gates/<gate>.yaml` declaration (dsl-syntax.md §15.4): a declared
  review status — role, throwback exits, escalation policy, fan-out
  depth. Position is not part of this declaration: a citing type's own
  `statuses:` array places its `review:` entry wherever the author
  wants it to run (§15.3), so the identical gate may run at different
  relative positions across two types without either being wrong.

  No `ticket_types:` field, and none is missing (§15.4): that fact is
  now which types' own `statuses:` arrays cite this gate's name, and
  there is exactly one place it lives — the citing type, not the gate.

  **`throwback:` is a single optional target, not a list** (§15.10). It
  never bounded legality and there was never any shipped enforcement of
  it as an allow-list: a decline's legal targets are "earlier in the
  citing type's effective sequence," one rule shared with §7.19's
  Blocked-return, and every target a declared list could name is
  earlier and therefore legal regardless. What the field keeps is its
  other job — naming *where a decline lands* — and a decline lands on
  exactly one status, so a list stopped meaning anything the moment it
  stopped bounding. Omitted, the landing point is derived from the
  citing sub-array's own earliest entry
  (`Catapult.Dsl.Workflow.throwback_default/3`).

  Structural parsing only; whether `throwback:` resolves to a position
  in the citing type's own array is `Catapult.Dsl.Workflow`'s job
  (dsl-syntax.md §13), since that resolution is per citing type, not a
  fact about the gate declaration alone.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file, :role, :escalation]
  defstruct [:name, :file, :role, :escalation, :throwback, depth: 0]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          role: String.t(),
          depth: Fields.depth(),
          throwback: String.t() | nil,
          escalation: String.t()
        }

  @core_keys ~w(review role depth throwback escalation)

  @doc "Parses one gate declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "gate declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "review", where)
    gate_where = if name, do: "gate #{inspect(name)} (#{file})", else: where

    {role, role_problems} = Fields.require_string(raw, "role", gate_where)
    {depth, depth_problems} = Fields.depth(raw, gate_where)
    {throwback, tb_problems} = Fields.optional_string(raw, "throwback", gate_where)
    {escalation, esc_problems} = Fields.require_string(raw, "escalation", gate_where)

    unknown = Fields.unknown_keys(raw, @core_keys, gate_where)

    problems =
      name_problems ++ role_problems ++ depth_problems ++ tb_problems ++ esc_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         role: role,
         depth: depth,
         throwback: throwback,
         escalation: escalation
       }}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["gate declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end
end
