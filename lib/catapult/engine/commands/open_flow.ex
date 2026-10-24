defmodule Catapult.Engine.Commands.OpenFlow do
  @moduledoc """
  Opens a flow instance (v5 §7.10). Aggregate id: `project_id`.

  `container_id`/`queue` record membership at open — the one moment it
  is knowable without a second write (`Catapult.Engine.Events
  .FlowOpened`'s moduledoc). Both `nil` opens a work item belonging to
  no container, which is every flow opened before ORC-104 and every
  one opened outside a container since.

  `entry_node_id` is `nil` for a flow covering whole tiers, which has
  no single entry node (`systems/engine.md` #ORC-269-2).
  """

  @enforce_keys [:project_id, :flow_id, :flow_name]
  defstruct [
    :project_id,
    :flow_id,
    :flow_name,
    :entry_node_id,
    :ticket_ref,
    :actor_id,
    :container_id,
    :queue
  ]
end
