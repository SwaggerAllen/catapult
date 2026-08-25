defmodule Catapult.Engine.Commands.RequestFlagSetFlip do
  @moduledoc """
  Records the intent to flip a container's aggregated flag set (v5
  §7.1, §7.8). Aggregate id: `project_id`. The effect itself is
  `Catapult.Delivery.FlagSetWorker`'s.
  """

  @enforce_keys [:project_id, :container_id, :request_id, :flags]
  defstruct [:project_id, :container_id, :request_id, :flags, :actor_id]
end
