defmodule Catapult.Engine.Events.FlowOpenedV1 do
  @moduledoc """
  `FlowOpened` version 1, frozen (`systems/engine.md` — replay fixtures
  retain every historical shape; the log is never rewritten).

  Never constructed by current code. The `events/0` entry for
  `{:flow_opened, 1}` exists so this module and the
  `Commanded.Event.Upcaster` implementation below stay in the tree for
  as long as a v1 event could still be in a project's log. Version 2
  adds `container_id` and `queue` — see
  `Catapult.Engine.Events.FlowOpened`'s moduledoc for why membership
  had to become a fact the opening event carries.
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

defimpl Commanded.Event.Upcaster, for: Catapult.Engine.Events.FlowOpenedV1 do
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.FlowOpenedV1

  @doc """
  Pure: every value is copied from `event`, and the two new fields
  upcast to `nil` rather than to a guessed container.

  `nil` is the honest answer and not a placeholder: a v1 event was
  written before containers existed, so the work item it opened was
  genuinely a member of nothing. `Catapult.Engine.Projections
  .ContainerQueues`'s query filters on a container id, so an unowned
  work item is invisible to every queue rather than silently counted
  into one — which is the behaviour a backfill guess would have
  destroyed.
  """
  def upcast(%FlowOpenedV1{} = event, _metadata) do
    %FlowOpened{
      project_id: event.project_id,
      flow_id: event.flow_id,
      flow_name: event.flow_name,
      entry_node_id: event.entry_node_id,
      ticket_ref: event.ticket_ref,
      actor_id: event.actor_id,
      container_id: nil,
      queue: nil
    }
  end
end
