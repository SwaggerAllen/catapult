defmodule Catapult.Engine.Events.ReviewWrittenV1 do
  @moduledoc """
  `ReviewWritten` version 1, frozen (`systems/engine.md` — replay
  fixtures retain every historical shape; the log is never rewritten).

  Never constructed by current code — the reducer's `events/0` entry
  for `{:review_written, 1}` exists so this module, and the
  `Commanded.Event.Upcaster` implementation below, stay in the tree
  for as long as a v1 event could still be in a project's log.
  `score` here is the pre-correction 0.0-1.0 float; see
  `Catapult.Engine.Events.ReviewWritten`'s moduledoc for why version 2
  exists.
  """

  @enforce_keys [:project_id, :draft_id, :review_id, :score]
  @derive Jason.Encoder
  defstruct [:project_id, :draft_id, :review_id, :score, :body_sha, findings: []]

  @type t :: %__MODULE__{
          project_id: binary(),
          draft_id: binary(),
          review_id: binary(),
          score: float(),
          body_sha: String.t() | nil,
          findings: [Catapult.Engine.Events.ReviewWritten.finding()]
        }
end

defimpl Commanded.Event.Upcaster, for: Catapult.Engine.Events.ReviewWrittenV1 do
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Events.ReviewWrittenV1

  @doc """
  Pure: no clock, no randomness, no id generation — every value this
  produces is either copied from `event` or a deterministic function
  of it (`round/1`), which is exactly what a version bump's upcaster
  may do (systems/engine.md's purity floor).
  """
  def upcast(%ReviewWrittenV1{} = event, _metadata) do
    %ReviewWritten{
      project_id: event.project_id,
      draft_id: event.draft_id,
      review_id: event.review_id,
      score: round(event.score * 100),
      body_sha: event.body_sha,
      findings: event.findings,
      kind: :ai
    }
  end
end
