defmodule Catapult.Engine.Events.FlowOpened do
  @moduledoc """
  A flow instance was opened — the ticket face (v5 §7.10): opening a
  ticket IS opening a flow instance. Version 2. Scaffolding is not a
  flow; it is the base schema with a ticket face and an empty delta
  (`chain.md` #38), and it opens the same way.

  **Version 2 carries `container_id` and `queue`: membership is
  derived by reference, never a stored list** (ORC-104,
  `systems/engine.md`'s design pass; v5 §7.8's "containers and
  projects alike keep references to their work items even once
  archived"). A container's access path to its own work is answerable
  from each work item's own `container_id` — set once, at open, the
  same way `project_id` already is — and a queue's population is that
  filtered by `queue` and by resolution. Two consequences the shape is
  chosen for:

  * **Archiving never touches either column.** Archiving is policy,
    decided at `systems/delivery.md`, so the reference survives
    archival for free — no membership list to keep in sync, and a
    container stays a path to its own history (v5 §7.8's "that kills
    the retro note outright").
  * **No bucket is written.** "The unresolved work items in this
    container assigned to this queue" is a query over these two
    columns, the identical reason `ready_scopes` refuses to
    materialize and `Catapult.Engine.Scheduler` holds no memory of
    what it last broadcast — a stale ordering is worse than none
    (`workflow.md` #30).

  Both are `nil` for a work item belonging to no container, which is
  what every version-1 event upcasts to
  (`Catapult.Engine.Events.FlowOpenedV1`).
  """

  @enforce_keys [:project_id, :flow_id, :flow_name, :entry_node_id]
  @derive Jason.Encoder
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

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          flow_name: String.t(),
          entry_node_id: binary(),
          ticket_ref: String.t() | nil,
          actor_id: binary() | nil,
          container_id: binary() | nil,
          queue: String.t() | nil
        }
end
