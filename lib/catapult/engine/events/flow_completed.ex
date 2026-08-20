defmodule Catapult.Engine.Events.FlowCompleted do
  @moduledoc """
  A flow instance's completion predicate resolved true (dsl-syntax.md
  §6, §8). Version 1.
  """

  @enforce_keys [:project_id, :flow_id]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id]

  @type t :: %__MODULE__{project_id: binary(), flow_id: binary()}
end
