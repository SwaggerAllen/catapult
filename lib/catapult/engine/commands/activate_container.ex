defmodule Catapult.Engine.Commands.ActivateContainer do
  @moduledoc """
  Makes a minted container instance the current one at its parent's
  queue, starting it at `queue` — its own first declared entry
  (dsl-syntax.md §15.8). Aggregate id: `project_id`.
  """

  @enforce_keys [:project_id, :container_id, :queue]
  defstruct [:project_id, :container_id, :queue, :actor_id]
end
