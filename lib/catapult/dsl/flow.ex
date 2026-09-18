defmodule Catapult.Dsl.Flow do
  @moduledoc """
  One `flows.<name>` entry of `chain.yaml` (`chain.md` #38, reserved:
  the flow engine): the schema delta while the flow is open, its walk
  primitive, the `entry` tier a cascade enters at, the ticket face
  (labels that select this flow), and a completion predicate.

  Scaffolding is not a flow with special-cased emptiness — it is the
  base schema with an empty delta, which is the ordinary shape a
  `walk: full` flow takes (`chain.md` #38, #41): the shipped `seed`
  flow declares only `walk: full` and nothing else.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :walk]
  defstruct [
    :name,
    :walk,
    :entry,
    :completion,
    delta_tiers: [],
    delta_edges: [],
    ticket_labels: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          walk: String.t(),
          entry: String.t() | nil,
          delta_tiers: [String.t()],
          delta_edges: [String.t()],
          ticket_labels: [String.t()],
          completion: String.t() | nil
        }

  @walks ~w(downward_cascade up_then_down full)
  @core_keys ~w(walk entry delta ticket completion)

  @doc "Parses one `flows.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "flow #{inspect(name)}"

    {walk, walk_problems} = Fields.require_one_of(raw, "walk", @walks, where)
    {entry, entry_problems} = Fields.optional_string(raw, "entry", where)
    {delta_tiers, delta_edges, delta_problems} = parse_delta(raw, where)
    {labels, ticket_problems} = parse_ticket(raw, where)
    {completion, completion_problems} = Fields.optional_string(raw, "completion", where)

    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems =
      walk_problems ++
        entry_problems ++ delta_problems ++ ticket_problems ++ completion_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         walk: walk,
         entry: entry,
         delta_tiers: delta_tiers,
         delta_edges: delta_edges,
         ticket_labels: labels,
         completion: completion
       }}
    else
      {:error, problems}
    end
  end

  def parse(name, other) do
    {:error, ["flow #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_delta(raw, where) do
    case Fields.optional_map(raw, "delta", where) do
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
    case Fields.optional_map(raw, "ticket", where) do
      {nil, problems} ->
        {[], problems}

      {ticket, []} ->
        tw = "#{where}'s ticket"
        {labels, lp} = Fields.optional_string_list(ticket, "labels", tw)
        unknown = Fields.unknown_keys(ticket, ["labels"], tw)
        {labels, lp ++ unknown}
    end
  end
end
