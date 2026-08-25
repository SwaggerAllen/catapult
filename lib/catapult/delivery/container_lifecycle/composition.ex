defmodule Catapult.Delivery.ContainerLifecycle.Composition do
  @moduledoc """
  What the next container's `prep` should hold — computed, proposed,
  never committed (v5 §7.8, `systems/delivery.md`'s ORC-104 design
  pass).

  **The defect this is written against, named rather than
  reproduced.** Orchestration's backlog view carries a work item's key,
  title, priority and gating state and nothing else, so a work item
  whose own *description* argues it should not be scheduled yet gets
  proposed anyway — every close, until something changes — because
  nothing in that view can see the argument. The fix is not a better
  reader of prose. It is to propose off signals that are already
  structured:

  * **`stubbed`** (v5 §7.6, "committed work deliberately waiting") — a
    work item parked on an external timeline by choice. This is the
    exact case the flat view kept re-proposing, and it is a status,
    not a sentence.
  * **An unresolved blocking edge** — a work item still waiting on
    something the engine already computes. Proposing it means proposing
    work that cannot start.
  * **Already resolved, or already a member of some container's
    queue** — proposing work that is done, or that already has a home,
    is noise of the same kind.

  A candidate that survives all three is proposed *with the reason it
  survived*, so accepting or declining is a judgement about a stated
  claim rather than about a bare key.

  **This never creates a ticket.** `propose/3` writes rows to
  `Catapult.Delivery.Store.ContainerProposal` and returns them; opening
  a work item into a real `prep` entry is the author's act, out of
  ORC-104's scope by the ticket record's own words, and the milestone
  screen that renders these arrives with dashboard v3.
  """

  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Store, as: EngineStore
  alias Catapult.Engine.Store.Container

  @typedoc "One computed candidate, before it is written."
  @type candidate :: %{
          work_item_id: binary(),
          work_item_ref: String.t() | nil,
          flow_name: String.t() | nil,
          rationale: String.t()
        }

  @doc """
  Computes and records what `source`'s close proposes for the next
  container's `target_queue`.

  `sequence` is the log position the computation was made at, carried
  so a proposal can be told from a later recomputation rather than
  guessed at by timestamp. It defaults to the sequence `source`'s
  current queue became current at, which is the position a close is
  actually computed from.
  """
  @spec propose(Workflow.t(), Container.t(), keyword()) :: [
          DeliveryStore.ContainerProposal.t()
        ]
  def propose(%Workflow{} = workflow, %Container{} = source, opts \\ []) do
    target_queue = Keyword.get(opts, :target_queue, default_target_queue(workflow, source))
    sequence = Keyword.get(opts, :sequence, source.current_queue_sequence)

    if is_nil(target_queue) do
      []
    else
      workflow
      |> candidates(source)
      |> Enum.map(fn candidate ->
        DeliveryStore.upsert_container_proposal(%{
          id: proposal_id(source, candidate),
          project_id: source.project_id,
          source_container_id: source.id,
          target_container_id: Keyword.get(opts, :target_container_id),
          target_queue: target_queue,
          work_item_id: candidate.work_item_id,
          work_item_ref: candidate.work_item_ref,
          flow_name: candidate.flow_name,
          rationale: candidate.rationale,
          computed_sequence: sequence
        })
      end)
    end
  end

  @doc """
  The candidates `source`'s close would propose — the filter, without
  the write. Exposed separately because "what would this propose, and
  why" is a question worth being able to ask without recording an
  answer.
  """
  @spec candidates(Workflow.t(), Container.t()) :: [candidate()]
  def candidates(%Workflow{}, %Container{} = source) do
    source.project_id
    |> DeliveryStore.unscheduled_work_items()
    |> Enum.reject(&(stubbed?(&1) or blocked?(source.project_id, &1)))
    |> Enum.map(&to_candidate/1)
  end

  # The next container's `prep` is the first queue-shaped entry of the
  # same declared type this container is an instance of — "the next
  # container" is another instance of this one's own type, so its
  # `prep` is this one's `prep` by declaration. Read off the array
  # rather than hard-coded to the word `prep`: the anchor's *position*
  # is platform-fixed (§15.1), its name is not something this module
  # should be asserting.
  defp default_target_queue(%Workflow{} = workflow, %Container{} = source) do
    workflow.types
    |> Map.get(source.type_name)
    |> case do
      nil ->
        nil

      type ->
        type.statuses
        |> Enum.filter(&Status.queue_shaped?/1)
        |> Enum.reject(& &1.singleton)
        |> List.first()
        |> case do
          nil -> nil
          entry -> entry.status
        end
    end
  end

  # Deterministic and stable across recomputation: the same candidate
  # proposed at two successive closes updates one row rather than
  # accumulating a second copy of the same suggestion.
  defp proposal_id(%Container{} = source, candidate) do
    source.id <> ":" <> candidate.work_item_id
  end

  defp stubbed?(work_item), do: work_item.status_kind == "stubbed"

  defp blocked?(project_id, work_item) do
    EngineStore.blocking_edges_unresolved?(project_id, work_item.id)
  end

  defp to_candidate(work_item) do
    %{
      work_item_id: work_item.id,
      work_item_ref: work_item.ticket_ref,
      flow_name: work_item.flow_name,
      rationale:
        "unscheduled, not stubbed, and no unresolved blocking edge as of this container's close"
    }
  end
end
