defmodule Catapult.Engine.Commands.CompleteFlow do
  @moduledoc "Completes an open flow instance."

  @enforce_keys [:project_id, :flow_id]
  defstruct [:project_id, :flow_id]
end
