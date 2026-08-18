defmodule Catapult.Dsl.Flow do
  @moduledoc """
  One `flows/<flow>/flow.yaml` declaration (dsl-syntax.md §6): the
  schema delta while the flow is open, its walk primitive, the ticket
  face (v5 §7.10 — opening a ticket is opening a flow instance), and
  its completion predicate.

  Scaffolding is not a flow — it is the base schema with a ticket face
  and an empty delta — so an empty `delta.tiers` / `delta.edges` is
  legal and not specially cased here; it is the ordinary shape a
  scaffold's `flow.yaml` takes.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file]
  defstruct [
    :name,
    :file,
    :walk,
    :completion,
    delta_tiers: [],
    delta_edges: [],
    ticket_entry: nil,
    ticket_labels: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          delta_tiers: [String.t()],
          delta_edges: [String.t()],
          walk: String.t() | nil,
          ticket_entry: String.t() | nil,
          ticket_labels: [String.t()],
          completion: String.t() | nil
        }

  @walks ~w(downward_cascade up_then_down)
  @core_keys ~w(flow delta walk ticket completion)

  @doc "Parses one flow declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "flow declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "flow", where)
    flow_where = if name, do: "flow #{inspect(name)} (#{file})", else: where

    {delta_tiers, delta_edges, delta_problems} = parse_delta(raw, flow_where)
    {walk, walk_problems} = Fields.require_one_of(raw, "walk", @walks, flow_where)
    {entry, labels, ticket_problems} = parse_ticket(raw, flow_where)
    {completion, completion_problems} = Fields.require_string(raw, "completion", flow_where)

    unknown = Fields.unknown_keys(raw, @core_keys, flow_where)

    problems =
      name_problems ++
        delta_problems ++
        walk_problems ++
        ticket_problems ++
        completion_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         delta_tiers: delta_tiers,
         delta_edges: delta_edges,
         walk: walk,
         ticket_entry: entry,
         ticket_labels: labels,
         completion: completion
       }}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["flow declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_delta(raw, where) do
    case Fields.require_map(raw, "delta", where) do
      {nil, problems} ->
        {[], [], problems}

      {delta, []} ->
        dw = "#{where}'s delta"
        {tiers, tp} = Fields.optional_string_list(delta, "tiers", dw)
        {edges, ep} = Fields.optional_string_list(delta, "edges", dw)
        unknown = Fields.unknown_keys(delta, ["tiers", "edges"], dw)
        {tiers, edges, tp ++ ep ++ unknown}
    end
  end

  defp parse_ticket(raw, where) do
    case Fields.require_map(raw, "ticket", where) do
      {nil, problems} ->
        {nil, [], problems}

      {ticket, []} ->
        tw = "#{where}'s ticket"
        {entry, ep} = Fields.require_string(ticket, "entry", tw)
        {labels, lp} = Fields.optional_string_list(ticket, "labels", tw)
        unknown = Fields.unknown_keys(ticket, ["entry", "labels"], tw)
        {entry, labels, ep ++ lp ++ unknown}
    end
  end
end
