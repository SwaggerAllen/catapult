defmodule Catapult.Engine.Commands.AdvanceContainerQueue do
  @moduledoc """
  Moves an active container's current queue, forward or backward
  (dsl-syntax.md §15.7-§15.8). Aggregate id: `project_id`.

  `from_queue` is not decoration: the aggregate rejects the command
  when it does not match the container's current queue, which is v5
  §7.16's optimistic concurrency spelled at the command edge — first
  writer wins, a stale `from` is rejected rather than applied. Several
  people may hold a sign-off role and race each other on a container's
  transitions; this is what makes the loser's click an error rather
  than a silent double advance.
  """

  @enforce_keys [:project_id, :container_id, :from_queue, :to_queue, :reason]
  defstruct [:project_id, :container_id, :from_queue, :to_queue, :reason, :actor_id]
end
