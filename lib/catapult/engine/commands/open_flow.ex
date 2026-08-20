defmodule Catapult.Engine.Commands.OpenFlow do
  @moduledoc "Opens a flow instance (v5 §7.10). Aggregate id: `project_id`."

  @enforce_keys [:project_id, :flow_id, :flow_name, :entry_node_id]
  defstruct [:project_id, :flow_id, :flow_name, :entry_node_id, :ticket_ref, :actor_id]
end
