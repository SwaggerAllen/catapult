defmodule Catapult.Delivery.ContainerLifecycle.Ids do
  @moduledoc """
  The ids this dispatcher mints things under — deterministic,
  computed the same way every time the same subject is asked about.

  **Determinism is what makes re-entry safe.**
  `Catapult.Delivery.ContainerLifecycle` re-evaluates a container's
  whole position on every event that could change an answer, so the
  same decision is reached many times over a container's life. With a
  derived id, a second `MintContainer` for the same parent queue is the
  aggregate's own "already exists" rejection and a re-delivered job is
  the same job; with a generated one it would be a duplicate instance
  and a duplicate work item. Same reasoning
  `Catapult.Generation.NodeId` gives for the chain axis, one grain up.

  It also keeps the ids out of the aggregate: "every id a resulting
  event carries is already present on the command"
  (`Catapult.Engine.Aggregate`'s pure floor), so the command edge —
  this dispatcher — is where they are computed, not the fold.

  The shapes are readable rather than hashed, because every component
  is already an opaque id or a declared name and a human reading a
  stream should be able to see what a row is without a lookup.
  """

  @doc """
  The instance a parent's queue mints. One per `(parent, queue)`: a
  queue whose `flow:` nests holds one child instance at a time.
  """
  @spec container_id(binary(), binary(), String.t()) :: binary()
  def container_id(project_id, parent_container_id, queue) do
    Enum.join([project_id, parent_container_id, queue], ":")
  end

  @doc """
  The one work item a non-queue-shaped inline dispatch point holds
  (`setup`/`retro`, ORC-148). Derived from the container and the queue
  precisely because there is at most one, ever — which is what lets the
  dispatcher address *the* retro or *the* setup work item directly,
  permanently, rather than iterating a set that structurally never
  holds more than one (§15.7).
  """
  @spec work_item_id(binary(), binary(), String.t()) :: binary()
  def work_item_id(project_id, container_id, queue) do
    Enum.join([project_id, container_id, queue, "work"], ":")
  end

  @doc """
  The flag-flip request. One per container: the aggregate admits one
  intent (v5 §7.1), so a derived id makes a re-request the rejection it
  should be, and makes `Catapult.Delivery.FlagSetWorker`'s own job
  uniqueness collapse a re-enqueue onto the same job.
  """
  @spec flag_request_id(binary(), binary()) :: binary()
  def flag_request_id(project_id, container_id) do
    Enum.join([project_id, container_id, "flags"], ":")
  end
end
