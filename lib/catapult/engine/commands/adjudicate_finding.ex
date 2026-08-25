defmodule Catapult.Engine.Commands.AdjudicateFinding do
  @moduledoc """
  Records how one carried finding left: filed under its own key, or
  declined with a reason (v5 §7.8). Aggregate id: `project_id`.
  """

  @enforce_keys [:project_id, :container_id, :finding_id, :disposition]
  defstruct [
    :project_id,
    :container_id,
    :finding_id,
    :disposition,
    :filed_key,
    :reason,
    :actor_id
  ]
end
