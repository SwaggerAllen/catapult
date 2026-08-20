defmodule Catapult.Engine.Projections.RunFailures do
  @moduledoc """
  How many limit-class dispatch-run failures a node has accrued since
  its most recent commit — a query against the raw event log, never a
  held counter (v5 §7.15, `systems/generation.md`'s design note: "the
  count is derived from the log, never held").

  Deliberately not built on `Catapult.Engine.Store`: every other
  projection in this system reads a materialized table the reducer
  maintains, but this fact has no natural row to live in (it is
  neither a node's current status nor a stored artifact), and an Oban
  attempt count or a table row would carry exactly the "memory across
  dispatches" the executor's own design refuses (`systems
  /generation.md`). So this reads `Catapult.Engine.Application`'s
  stream directly, the one place the fact durably exists.
  """

  alias Catapult.Engine.Application
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.RunFailed

  @doc """
  Limit-class `RunFailed` events recorded against `node_id` since its
  most recent `DraftCommitted` (or since the start of the project's
  log, if `node_id` has never committed) — a forward fold that resets
  on every commit rather than a literal backward walk, which lands on
  the identical count for a chronological log and needs no reverse
  read the event store API doesn't offer.
  """
  @spec count_since_commit(binary(), binary()) :: non_neg_integer()
  def count_since_commit(project_id, node_id) do
    case Commanded.EventStore.stream_forward(Application, stream_id(project_id)) do
      # A project with no events yet has recorded no failures either.
      {:error, :stream_not_found} -> 0
      stream -> Enum.reduce(stream, 0, &fold(&1, node_id, &2))
    end
  end

  defp fold(%{data: %DraftCommitted{node_id: node_id}}, node_id, _count), do: 0
  defp fold(%{data: %RunFailed{node_id: node_id}}, node_id, count), do: count + 1
  defp fold(_recorded_event, _node_id, count), do: count

  # Matches `Catapult.Engine.Router`'s own `identify(@aggregate, by:
  # :project_id, prefix: "project-")` — Commanded's stream identity is
  # `"<identity_prefix><aggregate_uuid>"` (its own `identify/2` doc).
  defp stream_id(project_id), do: "project-" <> project_id
end
