defmodule Catapult.Engine.Events.ReviewWritten do
  @moduledoc """
  A review was recorded against a draft (`chain.md` #14).
  Version 2, current.

  `score` is the platform-wide review grammar's 0-100 integer scale
  (the review schema's buckets) — version 1 stored a 0.0-1.0
  float, corrected here rather than silently reinterpreted, because a
  reducer branch reading an unconverted float against a `>= 61`
  threshold would silently mis-grade every historical review.
  `Catapult.Engine.Events.ReviewWrittenV1` is the frozen historical
  shape; `Commanded.Event.Upcaster` converts it to this struct on read
  (`score * 100` rounded, `kind: :ai` — v1 predates human review
  states, so every v1-era review was the chain's own auto-review).
  """

  @enforce_keys [:project_id, :draft_id, :review_id, :score]
  @derive Jason.Encoder
  defstruct [
    :project_id,
    :draft_id,
    :review_id,
    :score,
    :body_sha,
    findings: [],
    kind: :ai
  ]

  @type finding :: %{id: String.t(), message: String.t()}

  @type t :: %__MODULE__{
          project_id: binary(),
          draft_id: binary(),
          review_id: binary(),
          score: 0..100,
          body_sha: String.t() | nil,
          findings: [finding()],
          kind: :ai | :human
        }
end
