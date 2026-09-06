defmodule Catapult.Delivery.DraftResolution do
  @moduledoc """
  Closes the gap `systems/engine.md`'s ORC-229 design pass names:
  nothing dispatched `Catapult.Engine.Commands.ApproveDraft`/
  `DiscardDraft`, so a drafted node never reached `:approved` and the
  generation chain stalled after its first draft round. A Commanded
  process manager, built beside `Catapult.Delivery.ContainerLifecycle`
  on the identical `application: Catapult.Engine.Application`-
  subscribed, write-back shape (`systems/delivery.md`'s ORC-229 entry)
  — `FeatureLifecycle` only projects engine's events into this
  system's own read models; this is the second process manager that
  also dispatches commands back into `Catapult.Engine.Aggregate`.

  **A second write-side process manager, not a third
  `FeatureLifecycle` clause.** `FeatureLifecycle` dispatches no
  commands, ever — projection only, deliberately, so a fault in a
  write triggered off engine's events never risks the read model every
  status column and gate already depends on. This module is that
  write, kept off `FeatureLifecycle` for the identical reason
  `ContainerLifecycle` is its own module rather than a clause on
  `FeatureLifecycle`.

  **Identity is the pair `(project_id, flow_id)`, composited, never a
  bare id** (ORC-87), the same `project_id <> ":" <> flow_id` shape
  `FeatureLifecycle`/`FeaturePublisher`/`ContainerLifecycle` all use.
  Neither `GateApproved` nor `GateDeclined` carries a node id, and
  `Catapult.Engine.Store.Flow` has no node column to look one up from,
  so this instance holds `entry_node_id` in its own state from
  `FlowOpened` — Phase 4's already-standing "one node per flow"
  simplification (`systems/delivery.md`'s ORC-34 entry) — rather than
  deriving a node from the resolving event.

  **Whether a `GateApproved` approves the draft is computed
  independently of `FeatureLifecycle`'s own status advance, from the
  same loaded `Catapult.Dsl.Workflow.t()`, not read off it** — the
  two-computations-of-one-fact shape this system otherwise avoids,
  paid here for the identical decoupling reason `FeatureLifecycle`/
  `FeaturePublisher` already pay it for `flow_name`/entry-tier
  resolution. `Catapult.Dsl.Workflow.approve_leaves_group?/3` is the
  forward reading of `throwback_target_details/3`'s own `leaves_group`
  computation: a gate's own citing sub-array may hold more than one
  `review:` entry ahead of `checks` (`ux-review` then
  `engineering-review`, both reviewing the same single node), and
  marking the node `:approved` the moment the first of them passes
  would let a downstream context walk dispatch before the ticket's own
  required second sign-off ever ran. So `ApproveDraft` dispatches only
  once the resolving gate is its own group's last one; an earlier
  gate's approval only advances the ticket's projected status, exactly
  as before this ticket.

  **A decline is not the same shape.** Every `review:` entry in a
  `generation`/`critique`/review group falls back to the same leading
  `pending` (§15.10's fourth-pass correction, `screens/document-review
  .md`'s own cite), so any `GateDeclined` against the node dispatches
  `DiscardDraft` unconditionally — there is no partial-decline case
  where the draft should survive.

  Both events' own `actor_id` threads onto the resulting command
  unchanged, so `DraftApproved`/`DraftDiscarded` carry who acted the
  same way `ApproveGate` already does (v5 §7.19).

  ## Why it dispatches itself instead of returning commands

  The identical reason `ContainerLifecycle` gives, restated rather
  than pointed at: `Catapult.Engine.Application` does not compose
  `Catapult.Engine.Router`, so a returned command is unregistered and
  Commanded stops the manager. `handle/2` dispatches through
  `Catapult.Engine.Router` directly and returns `[]`, with
  `consistency: :eventual` on the dispatch (a `:strong` dispatch from
  inside this manager's own `handle/2` would deadlock against itself)
  and a rejection absorbed rather than fatal — `:engine_stale_draft_
  resolution` is exactly the rejection this design produces on
  purpose: a replayed `handle/2` re-deriving a decision this manager,
  or a racing writer, already made.

  **`next_command/4` is the whole decision, public for the identical
  testability reason `ContainerLifecycle.next_commands/2` is.** Driving
  the real process manager end to end and asserting on
  `Catapult.Engine.Store` afterward would have to sleep or poll for the
  `:eventual` dispatch's own downstream `Catapult.Engine.Reducer` write
  to land — conventions §9 makes determinism a protocol requirement,
  and a suite that sleeps to observe a convergence loop is the flaky
  kind. `next_command/4` takes the node row as a parameter rather than
  reading the store itself, so a test constructs one directly; `handle/2`
  is the thin part that reads `Catapult.Engine.Store.get_node/2` and
  dispatches whatever comes back.

  **`@derive Jason.Encoder`** (ORC-120, the identical reason
  `FeatureLifecycle`/`ContainerLifecycle` both carry it):
  `Commanded.ProcessManagers.ProcessManagerInstance` persists this
  struct through `Commanded.Serialization.JsonSerializer`
  unconditionally, and every field here is a plain `String.t() | nil`
  — no atom-typed field, so unlike `ContainerLifecycle` this needs no
  `JsonDecoder` implementation of its own.
  """

  use Commanded.ProcessManagers.ProcessManager,
    application: Catapult.Engine.Application,
    name: :delivery_draft_resolution,
    consistency: :strong

  require Logger

  alias Catapult.Config
  alias Catapult.Dsl
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store, as: EngineStore
  alias Catapult.Engine.Store.Node

  @enforce_keys [:project_id, :flow_id]
  @derive Jason.Encoder
  defstruct [:project_id, :flow_id, :entry_node_id, :flow_name]

  @type t :: %__MODULE__{
          project_id: binary(),
          flow_id: binary(),
          entry_node_id: binary() | nil,
          flow_name: String.t() | nil
        }

  ## Routing

  def interested?(%FlowOpened{project_id: project_id, flow_id: flow_id}) do
    {:start, identity(project_id, flow_id)}
  end

  def interested?(%GateApproved{project_id: project_id, flow_id: flow_id}) do
    {:continue, identity(project_id, flow_id)}
  end

  def interested?(%GateDeclined{project_id: project_id, flow_id: flow_id}) do
    {:continue, identity(project_id, flow_id)}
  end

  def interested?(%FlowCompleted{project_id: project_id, flow_id: flow_id}) do
    {:stop, identity(project_id, flow_id)}
  end

  def interested?(_event), do: false

  defp identity(project_id, flow_id), do: project_id <> ":" <> flow_id

  ## State

  def apply(%__MODULE__{} = pm, %FlowOpened{} = event) do
    %{
      pm
      | project_id: event.project_id,
        flow_id: event.flow_id,
        entry_node_id: event.entry_node_id,
        flow_name: event.flow_name
    }
  end

  def apply(%__MODULE__{} = pm, %GateApproved{}), do: pm
  def apply(%__MODULE__{} = pm, %GateDeclined{}), do: pm

  ## Dispatch

  def handle(%__MODULE__{} = pm, %GateApproved{} = event), do: dispatch_next(pm, event)
  def handle(%__MODULE__{} = pm, %GateDeclined{} = event), do: dispatch_next(pm, event)
  def handle(%__MODULE__{}, _event), do: []

  defp dispatch_next(%__MODULE__{} = pm, event) do
    with {:ok, workflow} <- load_workflow() do
      node = EngineStore.get_node(pm.project_id, pm.entry_node_id)

      case next_command(workflow, pm, node, event) do
        nil -> :ok
        command -> dispatch(command)
      end
    end

    []
  end

  @doc """
  What `handle/2` would dispatch for `event` against `pm`'s own
  `entry_node_id`, given `workflow` and `node` — `node` is `pm`'s own
  entry node, read by the caller (see the moduledoc's testability
  note); this function makes no store call of its own. `nil` when
  nothing should be dispatched: an earlier gate in the review group
  approved (only the ticket's own projected status advances), or the
  node carries no pending draft to resolve.
  """
  @spec next_command(Workflow.t(), t(), Node.t() | nil, GateApproved.t() | GateDeclined.t()) ::
          struct() | nil
  def next_command(%Workflow{} = workflow, %__MODULE__{} = pm, node, %GateApproved{} = event) do
    if Workflow.approve_leaves_group?(workflow, pm.flow_name, event.gate) do
      approve_command(pm, node, event.actor_id)
    end
  end

  def next_command(%Workflow{}, %__MODULE__{} = pm, node, %GateDeclined{} = event) do
    discard_command(pm, node, event.actor_id)
  end

  defp approve_command(%__MODULE__{} = pm, %Node{current_draft_id: draft_id}, actor_id)
       when not is_nil(draft_id) do
    %ApproveDraft{
      project_id: pm.project_id,
      node_id: pm.entry_node_id,
      draft_id: draft_id,
      actor_id: actor_id
    }
  end

  defp approve_command(%__MODULE__{}, _node, _actor_id), do: nil

  defp discard_command(%__MODULE__{} = pm, %Node{current_draft_id: draft_id}, actor_id)
       when not is_nil(draft_id) do
    %DiscardDraft{
      project_id: pm.project_id,
      node_id: pm.entry_node_id,
      draft_id: draft_id,
      actor_id: actor_id
    }
  end

  defp discard_command(%__MODULE__{}, _node, _actor_id), do: nil

  # See the moduledoc: `:eventual`, and the compare-and-swap rejection
  # this design produces on purpose absorbed rather than fatal.
  defp dispatch(command) do
    case Router.dispatch(command, consistency: :eventual) do
      :ok -> :ok
      {:error, reason} -> log_rejection(command, reason)
    end
  end

  defp log_rejection(command, {:engine_stale_draft_resolution, _details} = reason) do
    Logger.debug(
      "draft resolution command already settled: #{inspect(reason)} for #{inspect(command)}",
      component: :delivery
    )
  end

  defp log_rejection(command, reason) do
    Logger.warning(
      "draft resolution command refused: #{inspect(reason)} for #{inspect(command)}",
      component: :delivery
    )
  end

  defp load_workflow do
    case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      {:ok, %{workflow: %Workflow{} = workflow}} ->
        {:ok, workflow}

      {:ok, %{workflow: nil}} ->
        {:error, :no_workflow_bundle}

      {:error, reason} = error ->
        Logger.warning(
          "draft resolution skipped a dispatch: bundle unloadable (#{inspect(reason)})",
          component: :delivery
        )

        error
    end
  end
end
