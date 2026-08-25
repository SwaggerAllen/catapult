defmodule Catapult.Engine.Projections.GateComments do
  @moduledoc """
  Where `Catapult.Engine.Commands.DeclineGate`'s `since_sequence` comes
  from — a query against the raw event log, never a held value (v5
  §7.4, `systems/engine.md`'s ORC-34 design pass, fourth design-review
  correction).

  Called at the command-construction boundary, outside the aggregate:
  `Catapult.Engine.Aggregate`'s own purity floor forbids `execute/2`
  reading the log, so whatever builds a `DeclineGate` command calls
  `last_resolution_sequence/2` first and copies the result onto
  `since_sequence` — the same "inject at the command edge" shape
  `posted_at` already uses on `PostComment`. The aggregate's own
  accept/reject check for a decline (at least one comment since the
  gate's last resolution) is a separate, pure read of its own state,
  not this query — `GateComments.any_since_last_resolution?/2`, the
  first design-review pass's version of that check, is retired: its
  only caller read the log from inside `execute/2`, which broke this
  system's purity floor, and the aggregate now keeps the identical fact
  as state instead.
  """

  alias Catapult.Engine.Application
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined

  @doc """
  The log position of `gate`'s most recent `GateApproved` or
  `GateDeclined` in `project_id`'s stream, or `nil` if neither has
  happened yet — in which case `Catapult.Engine.Projections
  .CommentFeedback` folds from the start of the log, the same "no
  resolution has happened yet" case it already gives when the project
  has no `GateApproved`/`GateDeclined` at all.
  """
  @spec last_resolution_sequence(binary(), String.t()) :: non_neg_integer() | nil
  def last_resolution_sequence(project_id, gate) do
    case Commanded.EventStore.stream_forward(Application, stream_id(project_id)) do
      {:error, :stream_not_found} -> nil
      stream -> Enum.reduce(stream, nil, &fold(&1, gate, &2))
    end
  end

  defp fold(%{data: %GateApproved{gate: gate}, stream_version: seq}, gate, _acc), do: seq
  defp fold(%{data: %GateDeclined{gate: gate}, stream_version: seq}, gate, _acc), do: seq
  defp fold(_recorded_event, _gate, acc), do: acc

  # Matches `Catapult.Engine.Router`'s own `identify(@aggregate, by:
  # :project_id, prefix: "project-")` — Commanded's stream identity is
  # `"<identity_prefix><aggregate_uuid>"` (its own `identify/2` doc).
  defp stream_id(project_id), do: "project-" <> project_id
end
