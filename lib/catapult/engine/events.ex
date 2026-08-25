defmodule Catapult.Engine.Events do
  @moduledoc """
  The `events/0` registry (conventions §3, v5 §2.4): every event type
  this component may emit, with its version. No bare-atom form and no
  default version (`docs/non-goals.md`) — every entry below is
  `{type, version}`, spelled explicitly.

  `{:flow_opened, 1}` beside `{:flow_opened, 2}` is the same permanent
  pair `review_written` already models: ORC-104 added `container_id`
  and `queue` to the opening event, so v1 stays registered — and
  `Catapult.Engine.Events.FlowOpenedV1` stays in the tree — for as long
  as a v1 event could still be in a project's log.

  Registering `{:review_written, 1}` beside `{:review_written, 2}` is
  the ordinary, permanent case (`Catapult.Component`'s own doc): the
  claimed name is the type, so this is one component declaring the
  same type at two versions, not a collision. Version 1's module,
  `Catapult.Engine.Events.ReviewWrittenV1`, stays in the tree for as
  long as a v1 event could still be in a project's log — never
  constructed by current code, only upcast on read.
  """

  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.ContainerActivated
  alias Catapult.Engine.Events.ContainerClosed
  alias Catapult.Engine.Events.ContainerMinted
  alias Catapult.Engine.Events.ContainerQueueAdvanced
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.DraftDiscarded
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.FlagSetFlipped
  alias Catapult.Engine.Events.FlagSetFlipRequested
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.FlowOpenedV1
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Events.ReviewWrittenV1
  alias Catapult.Engine.Events.RunFailed

  @doc "The `events/0` registry entries."
  @spec registry() :: [{atom(), pos_integer()}]
  def registry do
    [
      {:flow_opened, 1},
      {:flow_opened, 2},
      {:flow_completed, 1},
      {:draft_committed, 1},
      {:draft_approved, 1},
      {:draft_discarded, 1},
      {:review_written, 1},
      {:review_written, 2},
      {:active_bundle_flipped, 1},
      {:run_failed, 1},
      {:container_minted, 1},
      {:container_activated, 1},
      {:container_queue_advanced, 1},
      {:container_closed, 1},
      {:finding_adjudicated, 1},
      {:flag_set_flip_requested, 1},
      {:flag_set_flipped, 1}
    ]
  end

  @doc "The struct module registered for `{type, version}`, for tests and fixtures."
  @spec module(atom(), pos_integer()) :: module()
  def module(:flow_opened, 1), do: FlowOpenedV1
  def module(:flow_opened, 2), do: FlowOpened
  def module(:flow_completed, 1), do: FlowCompleted
  def module(:draft_committed, 1), do: DraftCommitted
  def module(:draft_approved, 1), do: DraftApproved
  def module(:draft_discarded, 1), do: DraftDiscarded
  def module(:review_written, 1), do: ReviewWrittenV1
  def module(:review_written, 2), do: ReviewWritten
  def module(:active_bundle_flipped, 1), do: ActiveBundleFlipped
  def module(:run_failed, 1), do: RunFailed
  def module(:container_minted, 1), do: ContainerMinted
  def module(:container_activated, 1), do: ContainerActivated
  def module(:container_queue_advanced, 1), do: ContainerQueueAdvanced
  def module(:container_closed, 1), do: ContainerClosed
  def module(:finding_adjudicated, 1), do: FindingAdjudicated
  def module(:flag_set_flip_requested, 1), do: FlagSetFlipRequested
  def module(:flag_set_flipped, 1), do: FlagSetFlipped
end
