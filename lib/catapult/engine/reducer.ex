defmodule Catapult.Engine.Reducer do
  @moduledoc """
  `(projection_state, event) -> new_projection_state` (v4 §A.3.2),
  generic over bundle semantics: every branch below reads only the
  event's own already-extracted payload plus, where a branch needs
  bundle semantics, `Catapult.Engine.Store.current_bundle_version/3`
  resolved at the event's own sequence — never `core_dsl`'s
  currently-loaded bundle (`systems/engine.md`).

  **Pure floor.** No branch calls `DateTime.utc_now/0`,
  `:rand.*`, `Ecto.UUID.generate/0`, or any other clock/randomness/id
  source — every value written here is either copied from the event
  or derived deterministically from it (string concatenation for a
  natural key, `round/1` in an upcaster). `Catapult.Engine.Policies
  .PurityFloor` checks this by call-graph, not by convention.
  `Catapult.Engine.Store` calls are the reducer's only side effect,
  and they are themselves idempotent on the same input — replaying an
  event twice lands the same rows, which is what makes
  rebuild-from-zero a property rather than a hope (v4 §A.3.2,
  `test/catapult/engine/reducer_test.exs`).

  `metadata.stream_version` is the project-stream sequence Commanded's
  event store already assigned at append time (v4 §A.3.1's "sequence,
  per-project monotonic") — read here, never generated.
  """

  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.CommentPosted
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
  alias Catapult.Engine.Events.FlowResumed
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Events.RunFailed
  alias Catapult.Engine.Store

  @doc "Folds one event into the projection tables. `metadata` carries the recorded event's own `stream_version`."
  @spec apply(struct(), map()) :: :ok
  def apply(%FlowOpened{} = event, metadata) do
    Store.insert_flow(%{
      id: event.flow_id,
      project_id: event.project_id,
      flow_name: event.flow_name,
      entry_node_id: event.entry_node_id,
      ticket_ref: event.ticket_ref,
      container_id: event.container_id,
      queue: event.queue,
      status: :open,
      opened_sequence: sequence(metadata)
    })

    :ok
  end

  def apply(%FlowCompleted{} = event, metadata) do
    Store.complete_flow(event.flow_id, sequence(metadata))
    :ok
  end

  def apply(%DraftCommitted{} = event, metadata) do
    seq = sequence(metadata)

    Store.upsert_node(%{
      id: event.node_id,
      project_id: event.project_id,
      tier: event.tier,
      scope_key: event.scope_key,
      parent_node_id: event.parent_node_id,
      status: :drafted,
      fields: event.fields,
      current_draft_id: event.draft_id,
      body_sha: event.body_sha,
      committed_sequence: seq
    })

    Store.insert_draft(%{
      id: event.draft_id,
      project_id: event.project_id,
      node_id: event.node_id,
      body_sha: event.body_sha,
      committed_sequence: seq,
      status: :pending,
      actor_id: event.actor_id
    })

    Enum.each(event.mints, &apply_mint(event, &1))
    Enum.each(event.edges, &apply_declared_edge(event, &1))
    Enum.each(event.produces, &apply_produced_fragment(event, &1))

    :ok
  end

  def apply(%DraftApproved{} = event, _metadata) do
    Store.set_draft_status(event.draft_id, :approved)
    Store.approve_node(event.project_id, event.node_id)
    :ok
  end

  def apply(%DraftDiscarded{} = event, _metadata) do
    Store.set_draft_status(event.draft_id, :discarded)
    :ok
  end

  def apply(%ReviewWritten{} = event, _metadata) do
    Store.insert_review(%{
      id: event.review_id,
      project_id: event.project_id,
      draft_id: event.draft_id,
      score: event.score,
      findings: event.findings,
      body_sha: event.body_sha,
      kind: event.kind
    })

    :ok
  end

  # No projection table: `Catapult.Engine.Projections.RunFailures`
  # derives the limit-class failure count directly from the raw stream
  # (`Commanded.EventStore.stream_forward/2`), never from a materialized
  # row — the same "projections are derived and disposable" doctrine
  # every other query in this module's sibling projections already
  # follows, applied to a fact that has no natural home in `nodes`/
  # `drafts` (it is neither a node's current status nor a stored
  # artifact).
  def apply(%RunFailed{}, _metadata), do: :ok

  # No projection table for any of the three, for the identical reason:
  # `Catapult.Engine.Projections.CommentFeedback`/`.GateComments` both
  # read the raw stream directly (`systems/engine.md`'s ORC-34 design
  # pass, corrected on design review — the first draft's cache reopened
  # the exact silent-failure risk it claimed to close), and a workflow
  # gate's resolved position is `Catapult.Delivery.FeatureLifecycle`'s
  # own projection to keep, not this system's.
  def apply(%CommentPosted{}, _metadata), do: :ok
  def apply(%GateApproved{}, _metadata), do: :ok
  def apply(%GateDeclined{}, _metadata), do: :ok

  # No projection table, the identical reason as the gate pair above
  # (ORC-114): where a human resume rests the ticket is `Catapult
  # .Delivery.FeatureLifecycle`'s own projection to keep, not this
  # system's.
  def apply(%FlowResumed{}, _metadata), do: :ok

  ## Containers (ORC-104). Each branch writes exactly the fact its own
  ## event carries and nothing derived: which instances exist, which is
  ## current, and where each stands. No branch writes a queue's
  ## population — that is a query (`Catapult.Engine.Store
  ## .queue_population/3`), and materializing it here is the bucket v5
  ## §7.8 refuses.

  def apply(%ContainerMinted{} = event, metadata) do
    Store.mint_container(%{
      id: event.container_id,
      project_id: event.project_id,
      type_name: event.type_name,
      parent_container_id: event.parent_container_id,
      parent_queue: event.parent_queue,
      state: :minted,
      minted_sequence: sequence(metadata)
    })

    :ok
  end

  def apply(%ContainerActivated{} = event, metadata) do
    Store.activate_container(
      event.project_id,
      event.container_id,
      event.queue,
      sequence(metadata)
    )
  end

  def apply(%ContainerQueueAdvanced{} = event, metadata) do
    Store.advance_container_queue(
      event.project_id,
      event.container_id,
      event.to_queue,
      sequence(metadata)
    )
  end

  def apply(%ContainerClosed{} = event, metadata) do
    Store.close_container(event.project_id, event.container_id, sequence(metadata))
  end

  def apply(%FindingAdjudicated{} = event, metadata) do
    Store.adjudicate_finding(%{
      id: event.finding_id,
      project_id: event.project_id,
      container_id: event.container_id,
      disposition: event.disposition,
      filed_key: event.filed_key,
      reason: event.reason,
      adjudicated_sequence: sequence(metadata)
    })

    :ok
  end

  def apply(%FlagSetFlipRequested{} = event, metadata) do
    Store.request_flag_set_flip(
      event.project_id,
      event.container_id,
      event.flags,
      sequence(metadata)
    )
  end

  def apply(%FlagSetFlipped{} = event, metadata) do
    Store.record_flag_set_flip(event.project_id, event.container_id, sequence(metadata))
  end

  def apply(%ActiveBundleFlipped{} = event, metadata) do
    Store.flip_active_bundle_version(%{
      id: event.flip_id,
      project_id: event.project_id,
      axis: event.axis,
      bundle_name: event.bundle_name,
      version: event.version,
      became_current_sequence: sequence(metadata)
    })

    :ok
  end

  defp sequence(%{stream_version: version}), do: version

  defp apply_mint(%DraftCommitted{} = event, mint) do
    Store.mint_node(%{
      id: mint.node_id,
      project_id: event.project_id,
      tier: mint.tier,
      scope_key: mint.scope_key,
      parent_node_id: event.node_id,
      status: mint.status
    })

    Store.insert_edge(%{
      id: edge_id(mint.edge_name, event.node_id, mint.node_id),
      project_id: event.project_id,
      edge_name: mint.edge_name,
      type: mint.edge_type,
      source_node_id: event.node_id,
      target_node_id: mint.node_id
    })
  end

  defp apply_declared_edge(%DraftCommitted{} = event, edge) do
    Store.insert_edge(%{
      id: edge_id(edge.edge_name, event.node_id, edge.target_node_id),
      project_id: event.project_id,
      edge_name: edge.edge_name,
      type: edge.type,
      source_node_id: event.node_id,
      target_node_id: edge.target_node_id
    })
  end

  defp apply_produced_fragment(%DraftCommitted{} = event, fragment) do
    Store.insert_fragment(%{
      id: fragment_id(fragment.owner_node_id, fragment.kind, event.node_id),
      project_id: event.project_id,
      owner_node_id: fragment.owner_node_id,
      kind: fragment.kind,
      content: fragment.content,
      author_tier: event.tier,
      author_node_id: event.node_id
    })
  end

  # Deterministic natural-key ids (a pure function of already-known
  # values, never a generated one — the purity floor applies to
  # derived keys the same way it applies to timestamps).
  defp edge_id(edge_name, source_node_id, target_node_id) do
    edge_name <> "|" <> source_node_id <> "|" <> target_node_id
  end

  defp fragment_id(owner_node_id, kind, author_node_id) do
    owner_node_id <> "|" <> kind <> "|" <> author_node_id
  end
end
