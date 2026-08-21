defmodule Catapult.Dsl.Gate do
  @moduledoc """
  One `gates/<gate>.yaml` declaration (dsl-syntax.md §15.2): a
  declared review status. `after:` names its predecessor by reference
  rather than by index (§15.3) — a system status or another review in
  the loaded union — so an org layer can insert a review without
  renumbering the platform layer's files.

  Structural parsing only; whether `after:`/`throwback:` resolve to
  real statuses, and the total-order and cycle checks over the
  declared set, are `Catapult.Dsl.Bundle`'s job (dsl-syntax.md §13,
  §15.3).
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file, :after]
  defstruct [
    :name,
    :file,
    :after,
    :role,
    :depth,
    :escalation,
    ticket_types: :all,
    throwback: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          after: String.t(),
          role: String.t() | nil,
          ticket_types: :all | [String.t()],
          depth: Fields.depth(),
          throwback: [String.t()],
          escalation: String.t() | nil
        }

  @core_keys ~w(review after role ticket_types depth throwback escalation)

  @doc "Parses one gate declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "gate declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "review", where)
    gate_where = if name, do: "gate #{inspect(name)} (#{file})", else: where

    {after_, after_problems} = Fields.require_string(raw, "after", gate_where)
    {role, role_problems} = Fields.require_string(raw, "role", gate_where)
    {ticket_types, tt_problems} = parse_ticket_types(raw, gate_where)
    {depth, depth_problems} = Fields.depth(raw, gate_where)
    {throwback, tb_problems} = Fields.optional_string_list(raw, "throwback", gate_where)
    {escalation, esc_problems} = Fields.require_string(raw, "escalation", gate_where)

    unknown = Fields.unknown_keys(raw, @core_keys, gate_where)

    problems =
      name_problems ++
        after_problems ++
        role_problems ++
        tt_problems ++
        depth_problems ++
        tb_problems ++
        esc_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         after: after_,
         role: role,
         ticket_types: ticket_types,
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

  defp parse_ticket_types(raw, where) do
    case Fields.optional_string_list(raw, "ticket_types", where) do
      {[], []} -> if Map.has_key?(raw, "ticket_types"), do: {[], []}, else: {:all, []}
      {values, problems} -> {values, problems}
    end
  end
end
