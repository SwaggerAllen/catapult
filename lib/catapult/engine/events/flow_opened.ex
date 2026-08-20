defmodule Catapult.Engine.Events.FlowOpened do
  @moduledoc """
  A flow instance was opened — the ticket face (v5 §7.10): opening a
  ticket IS opening a flow instance. Version 1. Scaffolding is not a
  flow; it is the base schema with a ticket face and an empty delta
  (dsl-syntax.md §6), and it opens the same way.
  """

  @enforce_keys [:project_id, :flow_id, :flow_name, :entry_node_id]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :flow_name, :entry_node_id, :ticket_ref, :actor_id]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          flow_name: String.t(),
          entry_node_id: binary(),
          ticket_ref: String.t() | nil,
          actor_id: binary() | nil
        }
end
