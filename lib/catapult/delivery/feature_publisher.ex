defmodule Catapult.Delivery.FeaturePublisher do
  @moduledoc """
  The write side of Phase 4's PR management (`systems/delivery.md`'s
  ORC-33 entry, v5 §7.5): a Commanded process manager that reacts to
  the same `FlowOpened`/`DraftCommitted` events `Catapult.Delivery
  .FeatureLifecycle` already projects, and, on the flow's first
  successful `DraftCommitted`, enqueues the branch/PR/push side effect
  through `Catapult.Delivery.FeaturePublishWorker`.

  **A new process manager, not a wing bolted onto `FeatureLifecycle`.**
  Both are `application: Catapult.Engine.Application`-subscribed to the
  identical events and identified the same composite way
  (`project_id <> ":" <> flow_id`, ORC-87) `FeatureLifecycle` already
  establishes. What is not reused is the module:
  `FeatureLifecycle` is pure projection, and wiring outbound GitHub
  calls into its own `apply/2` would mean a GitHub outage or a bad
  credential risking the one component every status column and every
  gate already depends on. A stalled `FeaturePublisher` leaves ticket
  status exactly as readable as it always was.

  **Dispatches through an Oban outbox, never inline** — the identical
  shape `Catapult.Delivery.ContainerLifecycle` already uses for
  `Catapult.Delivery.FlagSetWorker`: the event is already durable
  before the job is enqueued, so a stalled or retrying job never blocks
  or corrupts this manager's own (minimal) state. Unlike that worker,
  completion is never recorded back onto the aggregate — whether a
  node's body has reached git is not a fact engine's own domain reasons
  about, so it stays local to `Catapult.Delivery.Store.ArtifactPush`
  (`systems/delivery.md`'s ORC-33 entry).

  **`ticket_ref`/`flow_name` are read once, at `FlowOpened`, and never
  re-read** — the same "read once at open" shape `FeatureLifecycle`
  already takes for `entry_node_id`. This is what lets a branch name
  survive a ticket title edited after the fact: the slug is derived
  once, here, and the branch/PR record itself
  (`Catapult.Delivery.Store.FeaturePublication`) is read back rather
  than recomputed on every later push.
  """

  use Commanded.ProcessManagers.ProcessManager,
    application: Catapult.Engine.Application,
    name: :delivery_feature_publisher,
    consistency: :strong

  alias Catapult.Delivery.FeaturePublishWorker
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened

  @enforce_keys [:project_id, :flow_id]
  defstruct [:project_id, :flow_id, :ticket_ref, :flow_name]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          ticket_ref: String.t() | nil,
          flow_name: String.t() | nil
        }

  ## Routing — identical shape to `FeatureLifecycle`'s own, see its moduledoc.

  def interested?(%FlowOpened{project_id: project_id, flow_id: flow_id}) do
    {:start, identity(project_id, flow_id)}
  end

  def interested?(%DraftCommitted{project_id: project_id}) do
    continue_current_flow(project_id)
  end

  def interested?(%FlowCompleted{project_id: project_id, flow_id: flow_id}) do
    {:stop, identity(project_id, flow_id)}
  end

  def interested?(_event), do: false

  defp continue_current_flow(project_id) do
    case DeliveryStore.current_open_flow_id(project_id) do
      nil -> false
      flow_id -> {:continue, identity(project_id, flow_id)}
    end
  end

  defp identity(project_id, flow_id), do: project_id <> ":" <> flow_id

  ## State — just enough to enqueue the effect; the worker re-reads
  ## everything else fresh from the store (re-validate before acting).

  def apply(%__MODULE__{} = pm, %FlowOpened{} = event) do
    %{
      pm
      | project_id: event.project_id,
        flow_id: event.flow_id,
        ticket_ref: event.ticket_ref,
        flow_name: event.flow_name
    }
  end

  def apply(%__MODULE__{} = pm, %DraftCommitted{}), do: pm

  ## Dispatch

  def handle(%__MODULE__{} = pm, %DraftCommitted{} = event) do
    FeaturePublishWorker.enqueue(%{
      project_id: pm.project_id,
      flow_id: pm.flow_id,
      ticket_ref: pm.ticket_ref,
      flow_name: pm.flow_name,
      node_id: event.node_id,
      tier: event.tier,
      scope_key: event.scope_key,
      body_sha: event.body_sha
    })

    []
  end

  def handle(%__MODULE__{}, _event), do: []
end
