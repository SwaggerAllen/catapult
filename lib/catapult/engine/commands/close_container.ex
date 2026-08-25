defmodule Catapult.Engine.Commands.CloseContainer do
  @moduledoc """
  Closes an active container instance (dsl-syntax.md §15.6). Aggregate
  id: `project_id`.
  """

  @enforce_keys [:project_id, :container_id]
  defstruct [:project_id, :container_id, :actor_id]
end
