defmodule Catapult.Engine.Commands.MintContainer do
  @moduledoc """
  Creates a container instance (`workflow.md` #19). Aggregate id:
  `project_id`.

  Issued by business logic or a person — never only by the parent's
  own queue reaching it, which is `ActivateContainer`'s job.
  """

  @enforce_keys [:project_id, :container_id, :type_name]
  defstruct [
    :project_id,
    :container_id,
    :type_name,
    :parent_container_id,
    :parent_queue,
    :actor_id
  ]
end
