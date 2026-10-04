defmodule Catapult.Engine.Projections.CommentFeedback do
  @moduledoc """
  What a declined generation tier's `feedback` prompt variable renders
  — a query against the raw event log, never a held cache (v5 §7.4,
  `systems/engine.md`'s ORC-34 design pass, corrected on design
  review — the first draft's `Catapult.Delivery.Store.FeedbackBucket`
  cache reopened the exact silent-blank ambiguity this ticket exists
  to close, since its writer raced the sweeper that reads readiness).

  Shaped like `Catapult.Engine.Projections.RunFailures
  .count_since_commit/2` — a synchronous `Commanded.EventStore
  .stream_forward/2` read, so there is no ordering gap for a sweep tick
  to land in whatever the reset boundary turns out to be.

  **The reset boundary is not `DraftCommitted`, and not inferred from
  position in the resolution sequence.** Both of those were tried and
  found wrong on design review: a comment posted mid-regeneration must
  not be discarded by that regeneration's own commit before it ever
  renders, and a workflow declaring more than one gate (the shipped
  `bundles/default-flow/workflow.yaml`'s `delta` type already does)
  makes "the resolution before the most recent one" land on the wrong
  event the moment a
  decline-then-approve-elsewhere-then-decline-again path happens,
  which it ordinarily does. The boundary that survives both
  findings: the most recent `GateApproved`/`GateDeclined` in the
  project's log, **unfiltered by which gate it names** (Phase 4's one
  pre-gate `generation` status is what makes "whichever gate" safe
  here — every resolution in the project necessarily reviews the same
  scope). If that event is a `GateDeclined`, folds every `CommentPosted`
  for `node_id` posted after its own `since_sequence` — a log position
  the event already carries, stamped by whoever built the `DeclineGate`
  command from `Catapult.Engine.Projections.GateComments
  .last_resolution_sequence/2`, never re-derived here. If it is a
  `GateApproved`, or no resolution has happened yet, `feedback` is
  empty: nothing is outstanding once a gate has passed, independent of
  what triggers a later re-dispatch.
  """

  alias Catapult.Engine.Application
  alias Catapult.Engine.Events.CommentPosted
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined

  @type entry :: %{
          body: String.t(),
          locator: String.t() | nil,
          author_id: binary() | nil,
          posted_at: DateTime.t()
        }

  @doc """
  Every `CommentPosted` for `node_id` that should feed its next
  regeneration — `[]` once the most recent gate resolution in the
  project is a `GateApproved`, or once none has happened yet.
  """
  @spec since_last_resolution(binary(), binary()) :: [entry()]
  def since_last_resolution(project_id, node_id) do
    case Commanded.EventStore.stream_forward(Application, stream_id(project_id)) do
      {:error, :stream_not_found} ->
        []

      stream ->
        {resolution, comments} = Enum.reduce(stream, {nil, []}, &fold(&1, node_id, &2))
        render(resolution, comments)
    end
  end

  defp fold(%{data: %GateApproved{}}, _node_id, {_resolution, comments}) do
    {:approved, comments}
  end

  defp fold(
         %{data: %GateDeclined{since_sequence: since_sequence}},
         _node_id,
         {_resolution, comments}
       ) do
    {{:declined, since_sequence}, comments}
  end

  defp fold(
         %{data: %CommentPosted{node_id: node_id} = event, stream_version: seq},
         node_id,
         {resolution, comments}
       ) do
    entry = %{
      body: event.body,
      locator: event.locator,
      author_id: event.author_id,
      posted_at: event.posted_at
    }

    {resolution, [{seq, entry} | comments]}
  end

  defp fold(_recorded_event, _node_id, acc), do: acc

  defp render({:declined, since_sequence}, comments) do
    comments
    |> Enum.reverse()
    |> Enum.filter(fn {seq, _entry} -> after_boundary?(seq, since_sequence) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp render(_resolution, _comments), do: []

  # `nil` means the gate that declined had never resolved before —
  # fold from the start of the log, the identical "no resolution has
  # happened yet" case this module already gives one level up.
  defp after_boundary?(_seq, nil), do: true
  defp after_boundary?(seq, since_sequence), do: seq > since_sequence

  defp stream_id(project_id), do: "project-" <> project_id
end
