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

  alias Catapult.Engine.Commands.ActivateContainer
  alias Catapult.Engine.Commands.AdjudicateFinding
  alias Catapult.Engine.Commands.AdvanceContainerQueue
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.CloseContainer
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.CompleteFlow
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.DiscardDraft
  alias Catapult.Engine.Commands.FlipActiveBundle
  alias Catapult.Engine.Commands.MintContainer
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Commands.RecordFlagSetFlip
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Commands.RequestFlagSetFlip
  alias Catapult.Engine.Commands.ResumeFlow
  alias Catapult.Engine.Commands.WriteReview
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

  defstruct project_id: nil,
            nodes: %{},
            flows: %{},
            containers: %{},
            comment_count: 0,
            gate_marks: %{},
            gate_resolutions: %{},
            blocked: false

  @typedoc """
  `nodes`, `flows` and `containers` are keyed by id, tracking only what
  a command needs validated against.

  A container's entry holds four facts and no more, each one because
  some command below rejects on it: `state` (mint, activation and
  close are three distinct transitions, dsl-syntax.md §15.8), `queue`
  (the compare-and-swap `AdvanceContainerQueue` performs), `findings`
  (a second adjudication of the same finding is a conflict, not an
  overwrite) and `flag_flip` (intent and completion may each happen
  once, v5 §7.1). Nothing here mirrors the projection — which queue is
  current is answerable from `Catapult.Engine.Store.Container` for
  readers; this copy exists only so `execute/2` can reject without a
  read.

  A node's entry gained `body_sha` at ORC-34: `PostComment`'s own
  stale-view rejection needs the node's currently committed draft to
  compare against, and the minimal state a command needs validated
  against is exactly this aggregate's own job to keep, the same
  reasoning that already gives it `pending_draft_id`.

  `comment_count` and `gate_marks` are ORC-34's own addition, for
  `DeclineGate`'s "at least one comment since this gate's last
  resolution" check: a project-wide counter bumped on every
  `CommentPosted`, and a per-gate mark of that counter's value as of
  each gate's last `GateApproved`/`GateDeclined` — pure aggregate
  state, so the check needs no store read the way a log-position query
  would (`systems/engine.md`'s fourth design-review correction).

  `gate_resolutions` and `blocked` are ORC-114's own addition.
  `gate_resolutions` is the compare-and-swap `ApproveGate`/
  `DeclineGate` reject a second writer against: absent key means
  "open," and a fresh `DraftCommitted` clears the whole map, the
  identical "reopens every gate" fact `Catapult.Delivery
  .FeatureLifecycle.Projection.commit/2` already encodes on the
  delivery side. Project-wide rather than flow-scoped, on the same
  "nothing yet opens two flows concurrently on one project" call
  `comment_count` already makes, with the identical Phase 7 revisit
  condition. `blocked` is the identical shape scaled down further —
  `ResumeFlow`'s own precondition — set by `RunFailed`, cleared by
  `FlowResumed` and by `DraftCommitted` alongside `gate_resolutions`.
  """
  @type t :: %__MODULE__{
          project_id: binary() | nil,
          nodes: %{binary() => %{pending_draft_id: binary() | nil, body_sha: binary() | nil}},
          flows: %{binary() => :open | :completed},
          containers: %{binary() => container()},
          comment_count: non_neg_integer(),
          gate_marks: %{String.t() => non_neg_integer()},
          gate_resolutions: %{String.t() => :approved | :declined},
          blocked: boolean()
        }

  @typedoc "The per-container validation state — see `t:t/0`."
  @type container :: %{
          state: :minted | :active | :closed,
          queue: String.t() | nil,
          findings: %{binary() => :filed | :declined},
          flag_flip: nil | :requested | :flipped
        }

  ## execute/2 — command validation

  def execute(%__MODULE__{}, %OpenFlow{} = cmd) do
    %FlowOpened{
      project_id: cmd.project_id,
      flow_id: cmd.flow_id,
      flow_name: cmd.flow_name,
      entry_node_id: cmd.entry_node_id,
      ticket_ref: cmd.ticket_ref,
      actor_id: cmd.actor_id,
      container_id: cmd.container_id,
      queue: cmd.queue
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

  def execute(%__MODULE__{}, %RecordRunFailure{} = cmd) do
    %RunFailed{
      project_id: cmd.project_id,
      node_id: cmd.node_id,
      tier: cmd.tier,
      scope_key: cmd.scope_key,
      run_id: cmd.run_id,
      reason: cmd.reason,
      occurred_at: cmd.occurred_at,
      actor_id: cmd.actor_id
    }
  end

  ## Decline-harvesting (v5 §7.4, ORC-34): a human comment as an
  ## original protocol fact, and the two gate sign-off commands
  ## `Catapult.Delivery.FeatureLifecycle`'s own new `interested?`
  ## clauses react to (`systems/delivery.md`). Bundle content — is
  ## `gate` real, does `throwback_to` name a member of its own
  ## `throwback:` list — is the command edge's to check before
  ## dispatch, same as every other command here; `execute/2` validates
  ## only the minimal aggregate-local state each command needs
  ## rejected against.

  def execute(%__MODULE__{nodes: nodes}, %PostComment{} = cmd) do
    case Map.get(nodes, cmd.node_id) do
      %{body_sha: body_sha} when body_sha == cmd.body_sha ->
        %CommentPosted{
          project_id: cmd.project_id,
          node_id: cmd.node_id,
          body_sha: cmd.body_sha,
          locator: cmd.locator,
          author_id: cmd.author_id,
          body: cmd.body,
          posted_at: cmd.posted_at
        }

      %{body_sha: current} ->
        {:error,
         {:engine_stale_comment, node_id: cmd.node_id, current: current, got: cmd.body_sha}}

      nil ->
        {:error, {:engine_comment_unknown_node, node_id: cmd.node_id}}
    end
  end

  # Compare-and-swap at the gate grain (ORC-114, v5 §7.16, closing the
  # defect `systems/engine.md`'s own entry names): `gate_resolutions`
  # rejects a second writer racing the first on this still-open
  # resolution; `body_sha` rejects a resolution whose view is a body
  # the aggregate has already moved past, resolved or not — the two
  # guard different failures, and both run before a `GateApproved` is
  # ever produced. Mirrors `PostComment`'s own three-way case on the
  # node lookup: fresh, stale, unknown.
  def execute(%__MODULE__{nodes: nodes, gate_resolutions: resolutions}, %ApproveGate{} = cmd) do
    with :ok <- reject_if_gate_resolved(resolutions, cmd.gate),
         :ok <- reject_if_stale_gate_view(nodes, cmd.node_id, cmd.body_sha) do
      %GateApproved{
        project_id: cmd.project_id,
        flow_id: cmd.flow_id,
        gate: cmd.gate,
        actor_id: cmd.actor_id
      }
    end
  end

  # The identical compare-and-swap `ApproveGate` above gains, plus the
  # pre-existing "at least one comment since this gate's last
  # resolution" check — there is no free-text override
  # (`docs/ui-spec.md` §3.2's throwback action has a target and
  # nothing else). The comment check is pure aggregate state —
  # `comment_count` past the mark recorded for `cmd.gate` at its last
  # `GateApproved`/`GateDeclined` — never a store read
  # (`systems/engine.md`'s fourth design-review correction: `execute/2`
  # may not read the log).
  def execute(
        %__MODULE__{nodes: nodes, comment_count: count, gate_marks: marks} = agg,
        %DeclineGate{} = cmd
      ) do
    with :ok <- reject_if_gate_resolved(agg.gate_resolutions, cmd.gate),
         :ok <- reject_if_stale_gate_view(nodes, cmd.node_id, cmd.body_sha),
         :ok <- require_comment_since_mark(count, marks, cmd.gate) do
      %GateDeclined{
        project_id: cmd.project_id,
        flow_id: cmd.flow_id,
        gate: cmd.gate,
        throwback_to: cmd.throwback_to,
        since_sequence: cmd.since_sequence,
        actor_id: cmd.actor_id
      }
    end
  end

  # A human resume of a limit-class block (ORC-114) — the compare-and-
  # swap scaled to a single boolean precondition, the same shape
  # `ApproveGate`/`DeclineGate` above take at the gate grain: a stale
  # resume (someone else already resumed it, or a retry already
  # landed) reads identically to "never was blocked," which is enough
  # for the rejection to be correct. `cmd.to` is flattened into the
  # event's own `to_kind`/`to_gate` pair — a deterministic reshape of
  # data already on the command, not a new value (this system's purity
  # floor) — because `FlowResumed`'s own moduledoc explains why the
  # bare tuple can't ride the event.
  def execute(%__MODULE__{blocked: true}, %ResumeFlow{} = cmd) do
    {to_kind, to_gate} = flatten_position(cmd.to)

    %FlowResumed{
      project_id: cmd.project_id,
      flow_id: cmd.flow_id,
      to_kind: to_kind,
      to_gate: to_gate,
      actor_id: cmd.actor_id
    }
  end

  def execute(%__MODULE__{blocked: false}, %ResumeFlow{} = cmd) do
    {:error, {:engine_flow_not_blocked, flow_id: cmd.flow_id}}
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

  ## Containers (dsl-syntax.md §15.6-§15.8) — mint, activate, advance,
  ## close. Never a second aggregate: "a project has one aggregate, not
  ## two" (`systems/engine.md`) already answers where an original fact
  ## about a project lands, and a container instance's existence is
  ## exactly that. Command validation reads only the minimal state
  ## above and never bundle content — which queue may follow which is
  ## the *dispatcher's* reading of a loaded workflow
  ## (`Catapult.Delivery.ContainerLifecycle`), already done before
  ## dispatch, the same division every other command edge here uses.

  def execute(%__MODULE__{containers: containers}, %MintContainer{} = cmd) do
    if Map.has_key?(containers, cmd.container_id) do
      {:error, {:engine_container_exists, container_id: cmd.container_id}}
    else
      %ContainerMinted{
        project_id: cmd.project_id,
        container_id: cmd.container_id,
        type_name: cmd.type_name,
        parent_container_id: cmd.parent_container_id,
        parent_queue: cmd.parent_queue,
        actor_id: cmd.actor_id
      }
    end
  end

  # Only a *minted* instance activates. Re-activating an already-active
  # one is not idempotent housekeeping — `setup` runs once, at
  # activation (§15.8), so admitting a second activation would run it
  # twice.
  def execute(%__MODULE__{containers: containers}, %ActivateContainer{} = cmd) do
    case Map.get(containers, cmd.container_id) do
      %{state: :minted} ->
        %ContainerActivated{
          project_id: cmd.project_id,
          container_id: cmd.container_id,
          queue: cmd.queue,
          actor_id: cmd.actor_id
        }

      nil ->
        {:error, {:engine_container_not_minted, container_id: cmd.container_id}}

      %{state: state} ->
        {:error,
         {:engine_container_not_activatable, container_id: cmd.container_id, state: state}}
    end
  end

  def execute(%__MODULE__{containers: containers}, %AdvanceContainerQueue{} = cmd) do
    case Map.get(containers, cmd.container_id) do
      %{state: :active, queue: current} when current == cmd.from_queue ->
        %ContainerQueueAdvanced{
          project_id: cmd.project_id,
          container_id: cmd.container_id,
          from_queue: cmd.from_queue,
          to_queue: cmd.to_queue,
          reason: cmd.reason,
          actor_id: cmd.actor_id
        }

      # v5 §7.16's optimistic concurrency, at the container grain:
      # first writer wins, a stale `from` is rejected rather than
      # applied. Two sign-off holders racing on a milestone gate land
      # here, and the loser is told.
      %{state: :active, queue: current} ->
        {:error,
         {:engine_container_queue_conflict,
          container_id: cmd.container_id, expected: cmd.from_queue, current: current}}

      nil ->
        {:error, {:engine_container_not_minted, container_id: cmd.container_id}}

      %{state: state} ->
        {:error, {:engine_container_not_active, container_id: cmd.container_id, state: state}}
    end
  end

  def execute(%__MODULE__{containers: containers}, %CloseContainer{} = cmd) do
    case Map.get(containers, cmd.container_id) do
      %{state: :active} ->
        %ContainerClosed{
          project_id: cmd.project_id,
          container_id: cmd.container_id,
          actor_id: cmd.actor_id
        }

      nil ->
        {:error, {:engine_container_not_minted, container_id: cmd.container_id}}

      %{state: state} ->
        {:error, {:engine_container_not_active, container_id: cmd.container_id, state: state}}
    end
  end

  ## Findings (v5 §7.8): filed under its own key, or declined with a
  ## reason. Both halves are validated here rather than trusted,
  ## because the whole point of the event is that a finding cannot
  ## leave without evidence of having been read.

  def execute(%__MODULE__{containers: containers}, %AdjudicateFinding{} = cmd) do
    with :ok <- known_container(containers, cmd.container_id),
         :ok <- unadjudicated(containers, cmd.container_id, cmd.finding_id),
         :ok <- complete_disposition(cmd) do
      %FindingAdjudicated{
        project_id: cmd.project_id,
        container_id: cmd.container_id,
        finding_id: cmd.finding_id,
        disposition: cmd.disposition,
        filed_key: cmd.filed_key,
        reason: cmd.reason,
        actor_id: cmd.actor_id
      }
    end
  end

  ## The aggregated flag set (v5 §7.1, §7.8): intent once, completion
  ## once, and completion only against an intent that exists.

  def execute(%__MODULE__{containers: containers}, %RequestFlagSetFlip{} = cmd) do
    case Map.get(containers, cmd.container_id) do
      %{flag_flip: nil} ->
        %FlagSetFlipRequested{
          project_id: cmd.project_id,
          container_id: cmd.container_id,
          request_id: cmd.request_id,
          flags: cmd.flags,
          actor_id: cmd.actor_id
        }

      nil ->
        {:error, {:engine_container_not_minted, container_id: cmd.container_id}}

      %{flag_flip: state} ->
        {:error,
         {:engine_flag_flip_already_requested, container_id: cmd.container_id, state: state}}
    end
  end

  def execute(%__MODULE__{containers: containers}, %RecordFlagSetFlip{} = cmd) do
    case Map.get(containers, cmd.container_id) do
      %{flag_flip: :requested} ->
        %FlagSetFlipped{
          project_id: cmd.project_id,
          container_id: cmd.container_id,
          request_id: cmd.request_id,
          flags: cmd.flags
        }

      nil ->
        {:error, {:engine_container_not_minted, container_id: cmd.container_id}}

      %{flag_flip: state} ->
        {:error, {:engine_flag_flip_not_requested, container_id: cmd.container_id, state: state}}
    end
  end

  defp known_container(containers, container_id) do
    if Map.has_key?(containers, container_id) do
      :ok
    else
      {:error, {:engine_container_not_minted, container_id: container_id}}
    end
  end

  defp unadjudicated(containers, container_id, finding_id) do
    case get_in(containers, [container_id, :findings, finding_id]) do
      nil ->
        :ok

      disposition ->
        {:error,
         {:engine_finding_already_adjudicated,
          container_id: container_id, finding_id: finding_id, disposition: disposition}}
    end
  end

  # A disposition without its evidence is the silent deferral
  # `FindingAdjudicated` exists to make impossible, so it is a reject
  # rather than a nullable column nobody reads.
  defp complete_disposition(%AdjudicateFinding{disposition: :filed} = cmd) do
    if blank?(cmd.filed_key) do
      {:error, {:engine_finding_filed_without_key, finding_id: cmd.finding_id}}
    else
      :ok
    end
  end

  defp complete_disposition(%AdjudicateFinding{disposition: :declined} = cmd) do
    if blank?(cmd.reason) do
      {:error, {:engine_finding_declined_without_reason, finding_id: cmd.finding_id}}
    else
      :ok
    end
  end

  defp complete_disposition(%AdjudicateFinding{} = cmd) do
    {:error,
     {:engine_finding_disposition_unknown,
      finding_id: cmd.finding_id, disposition: cmd.disposition}}
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_other), do: true

  ## ApproveGate/DeclineGate's shared compare-and-swap helpers (ORC-114) — see their own `execute/2` clauses above.

  defp reject_if_gate_resolved(resolutions, gate) do
    case Map.get(resolutions, gate) do
      nil ->
        :ok

      disposition ->
        {:error, {:engine_gate_already_resolved, gate: gate, disposition: disposition}}
    end
  end

  defp reject_if_stale_gate_view(nodes, node_id, body_sha) do
    case Map.get(nodes, node_id) do
      %{body_sha: ^body_sha} ->
        :ok

      %{body_sha: current} ->
        {:error,
         {:engine_stale_gate_resolution, node_id: node_id, current: current, got: body_sha}}

      nil ->
        {:error, {:engine_stale_gate_resolution, node_id: node_id, current: nil, got: body_sha}}
    end
  end

  defp require_comment_since_mark(count, marks, gate) do
    if count > Map.get(marks, gate, 0) do
      :ok
    else
      {:error, {:engine_gate_decline_without_comment, gate: gate}}
    end
  end

  # `ResumeFlow`'s own helper — see its `execute/2` clause above.
  defp flatten_position({:kind, kind}), do: {to_string(kind), nil}
  defp flatten_position({:gate, name}), do: {nil, name}

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
      |> Map.put(event.node_id, %{pending_draft_id: event.draft_id, body_sha: event.body_sha})
      |> mint_placeholders(event.mints)

    %__MODULE__{
      agg
      | project_id: event.project_id,
        nodes: nodes,
        gate_resolutions: %{},
        blocked: false
    }
  end

  def apply(%__MODULE__{} = agg, %DraftApproved{} = event) do
    %__MODULE__{
      agg
      | nodes: update_node(agg.nodes, event.node_id, &%{&1 | pending_draft_id: nil})
    }
  end

  def apply(%__MODULE__{} = agg, %DraftDiscarded{} = event) do
    %__MODULE__{
      agg
      | nodes: update_node(agg.nodes, event.node_id, &%{&1 | pending_draft_id: nil})
    }
  end

  def apply(%__MODULE__{} = agg, %CommentPosted{}) do
    %__MODULE__{agg | comment_count: agg.comment_count + 1}
  end

  def apply(%__MODULE__{} = agg, %GateApproved{} = event) do
    %__MODULE__{
      agg
      | gate_marks: Map.put(agg.gate_marks, event.gate, agg.comment_count),
        gate_resolutions: Map.put(agg.gate_resolutions, event.gate, :approved)
    }
  end

  def apply(%__MODULE__{} = agg, %GateDeclined{} = event) do
    %__MODULE__{
      agg
      | gate_marks: Map.put(agg.gate_marks, event.gate, agg.comment_count),
        gate_resolutions: Map.put(agg.gate_resolutions, event.gate, :declined)
    }
  end

  def apply(%__MODULE__{} = agg, %RunFailed{}) do
    %__MODULE__{agg | blocked: true}
  end

  def apply(%__MODULE__{} = agg, %FlowResumed{}) do
    %__MODULE__{agg | blocked: false}
  end

  def apply(%__MODULE__{} = agg, %ContainerMinted{} = event) do
    container = %{state: :minted, queue: nil, findings: %{}, flag_flip: nil}

    %__MODULE__{
      agg
      | project_id: event.project_id,
        containers: Map.put(agg.containers, event.container_id, container)
    }
  end

  def apply(%__MODULE__{} = agg, %ContainerActivated{} = event) do
    update_container(agg, event.container_id, &%{&1 | state: :active, queue: event.queue})
  end

  def apply(%__MODULE__{} = agg, %ContainerQueueAdvanced{} = event) do
    update_container(agg, event.container_id, &%{&1 | queue: event.to_queue})
  end

  def apply(%__MODULE__{} = agg, %ContainerClosed{} = event) do
    update_container(agg, event.container_id, &%{&1 | state: :closed})
  end

  def apply(%__MODULE__{} = agg, %FindingAdjudicated{} = event) do
    update_container(agg, event.container_id, fn container ->
      %{container | findings: Map.put(container.findings, event.finding_id, event.disposition)}
    end)
  end

  def apply(%__MODULE__{} = agg, %FlagSetFlipRequested{} = event) do
    update_container(agg, event.container_id, &%{&1 | flag_flip: :requested})
  end

  def apply(%__MODULE__{} = agg, %FlagSetFlipped{} = event) do
    update_container(agg, event.container_id, &%{&1 | flag_flip: :flipped})
  end

  def apply(%__MODULE__{} = agg, %ReviewWritten{}), do: agg
  def apply(%__MODULE__{} = agg, %ActiveBundleFlipped{}), do: agg

  # Every caller is an event whose own command edge already rejected an
  # unknown container, so a missing key here would mean a log this
  # aggregate did not write. Left as a no-op rather than a raise for
  # the reason replay demands: `apply/2` must survive whatever is in
  # the stream, and crashing rehydration is a worse answer than
  # ignoring a fact about a container that does not exist.
  defp update_container(%__MODULE__{} = agg, container_id, fun) do
    case Map.fetch(agg.containers, container_id) do
      {:ok, container} ->
        %__MODULE__{agg | containers: Map.put(agg.containers, container_id, fun.(container))}

      :error ->
        agg
    end
  end

  defp mint_placeholders(nodes, mints) do
    Enum.reduce(mints, nodes, fn mint, acc ->
      Map.put_new(acc, mint.node_id, %{pending_draft_id: nil, body_sha: nil})
    end)
  end

  # A node in `agg.nodes` by construction of every caller here (`apply/2`
  # only ever reaches `DraftApproved`/`DraftDiscarded` for a node that
  # already committed at least once); left as a no-op on a missing key
  # for the identical replay-survival reason `update_container/3`
  # already gives.
  defp update_node(nodes, node_id, fun) do
    case Map.fetch(nodes, node_id) do
      {:ok, node} -> Map.put(nodes, node_id, fun.(node))
      :error -> nodes
    end
  end
end
