defmodule Catapult.Engine.Aggregate do
  @moduledoc """
  The per-project aggregate (`systems/engine.md`): one instance per
  `project_id`, both bundle axes' events land in its stream (v4 §C.3
  carried forward — one EventStore stream per project, decided
  explicitly in the design pass even though it was already implied by
  "per-project aggregates").

  Validates commands against the minimal state needed to reject a
  malformed sequence with a typed error (v5 §7.16's validate-or-revert)
  — never against bundle content, which the command edge already
  validated before dispatch. `Commanded.Application`'s own
  `expected_version` dispatch option is the concurrent-writer guard
  (v5 §7.16); this module adds nothing on top of it.

  **Pure floor.** `execute/2` and `apply/2` read only their own
  arguments; every id, timestamp and sequence number a resulting event
  carries is already present on the command. Checked by
  `Catapult.Engine.Policies.PurityFloor`.
  """

  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.CompleteFlow
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Commands.FlipActiveBundle
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.WriteReview
  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.DraftDiscarded
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.ReviewWritten

  defstruct project_id: nil, nodes: %{}, flows: %{}

  @typedoc "`nodes` and `flows` are keyed by id, tracking only what a command needs validated against."
  @type t :: %__MODULE__{
          project_id: binary() | nil,
          nodes: %{binary() => %{pending_draft_id: binary() | nil}},
          flows: %{binary() => :open | :completed}
        }

  ## execute/2 — command validation

  def execute(%__MODULE__{}, %OpenFlow{} = cmd) do
    %FlowOpened{
      project_id: cmd.project_id,
      flow_id: cmd.flow_id,
      flow_name: cmd.flow_name,
      entry_node_id: cmd.entry_node_id,
      ticket_ref: cmd.ticket_ref,
      actor_id: cmd.actor_id
    }
  end

  def execute(%__MODULE__{}, %CompleteFlow{} = cmd) do
    %FlowCompleted{project_id: cmd.project_id, flow_id: cmd.flow_id}
  end

  def execute(%__MODULE__{nodes: nodes}, %CommitDraft{} = cmd) do
    case Map.get(nodes, cmd.node_id) do
      %{pending_draft_id: pending} when not is_nil(pending) ->
        # A plain internal tagged tuple, not `Catapult.Engine.Error`
        # (conventions §8 — that vocabulary governs what crosses
        # `defexport`, never every internal reject; this component
        # exposes no command-dispatch boundary yet, so there is
        # nothing for it to cross). Also sidesteps a real compile
        # cycle: `Catapult.Engine.Error` names its owning component by
        # atom, and everything Commanded starts is reachable from
        # `Catapult.Engine.children/0`, so any module in that closure
        # constructing it closes a loop back through `Catapult.Engine`
        # itself.
        #
        # The reason is a 2-tuple nested inside `:error`, not a bare
        # 3-tuple: `Commanded.Aggregates.Aggregate.execute_command/2`
        # pattern-matches `{:error, _error} = reply` on whatever
        # `execute/2` returns, and a `{:error, kind, details}` triple
        # misses that clause entirely — it falls through to the
        # pending-events branch instead, which then tries to `apply/2`
        # the error tuple as if it were an event.
        {:error, {:engine_draft_conflict, node_id: cmd.node_id, pending_draft_id: pending}}

      _absent_or_no_pending ->
        %DraftCommitted{
          project_id: cmd.project_id,
          node_id: cmd.node_id,
          tier: cmd.tier,
          scope_key: cmd.scope_key,
          parent_node_id: cmd.parent_node_id,
          draft_id: cmd.draft_id,
          body_sha: cmd.body_sha,
          committed_at: cmd.committed_at,
          actor_id: cmd.actor_id,
          fields: cmd.fields,
          mints: cmd.mints,
          edges: cmd.edges,
          produces: cmd.produces
        }
    end
  end

  def execute(%__MODULE__{}, %ApproveDraft{} = cmd) do
    %DraftApproved{
      project_id: cmd.project_id,
      node_id: cmd.node_id,
      draft_id: cmd.draft_id,
      actor_id: cmd.actor_id
    }
  end

  def execute(%__MODULE__{}, %DiscardDraft{} = cmd) do
    %DraftDiscarded{
      project_id: cmd.project_id,
      node_id: cmd.node_id,
      draft_id: cmd.draft_id,
      actor_id: cmd.actor_id,
      reason: cmd.reason
    }
  end

  def execute(%__MODULE__{}, %WriteReview{} = cmd) do
    %ReviewWritten{
      project_id: cmd.project_id,
      draft_id: cmd.draft_id,
      review_id: cmd.review_id,
      score: cmd.score,
      body_sha: cmd.body_sha,
      findings: cmd.findings,
      kind: cmd.kind
    }
  end

  def execute(%__MODULE__{}, %FlipActiveBundle{} = cmd) do
    %ActiveBundleFlipped{
      project_id: cmd.project_id,
      axis: cmd.axis,
      bundle_name: cmd.bundle_name,
      version: cmd.version,
      flip_id: cmd.flip_id
    }
  end

  ## apply/2 — aggregate state rehydration

  def apply(%__MODULE__{} = agg, %FlowOpened{} = event) do
    %__MODULE__{
      agg
      | project_id: event.project_id,
        flows: Map.put(agg.flows, event.flow_id, :open)
    }
  end

  def apply(%__MODULE__{} = agg, %FlowCompleted{} = event) do
    %__MODULE__{agg | flows: Map.put(agg.flows, event.flow_id, :completed)}
  end

  def apply(%__MODULE__{} = agg, %DraftCommitted{} = event) do
    nodes =
      agg.nodes
      |> Map.put(event.node_id, %{pending_draft_id: event.draft_id})
      |> mint_placeholders(event.mints)

    %__MODULE__{agg | project_id: event.project_id, nodes: nodes}
  end

  def apply(%__MODULE__{} = agg, %DraftApproved{} = event) do
    %__MODULE__{agg | nodes: Map.put(agg.nodes, event.node_id, %{pending_draft_id: nil})}
  end

  def apply(%__MODULE__{} = agg, %DraftDiscarded{} = event) do
    %__MODULE__{agg | nodes: Map.put(agg.nodes, event.node_id, %{pending_draft_id: nil})}
  end

  def apply(%__MODULE__{} = agg, %ReviewWritten{}), do: agg
  def apply(%__MODULE__{} = agg, %ActiveBundleFlipped{}), do: agg

  defp mint_placeholders(nodes, mints) do
    Enum.reduce(mints, nodes, fn mint, acc ->
      Map.put_new(acc, mint.node_id, %{pending_draft_id: nil})
    end)
  end
end
