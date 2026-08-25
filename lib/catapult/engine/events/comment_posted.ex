defmodule Catapult.Engine.Events.CommentPosted do
  @moduledoc """
  A human left a review comment against a node's committed body (v5
  §7.4, `systems/engine.md`'s ORC-34 design pass). Version 1.

  Mirrors `Catapult.Engine.Commands.PostComment` verbatim — every
  field, including `posted_at`, is copied off the command rather than
  produced here, per this system's purity floor. `locator` is nullable
  and always `nil` before `docs/ui-spec.md` §5's v2 per-sentence
  anchoring ships; nothing reads it to decide what folds into
  `Catapult.Engine.Projections.CommentFeedback`, only how to render an
  entry once folded.
  """

  @enforce_keys [:project_id, :node_id, :body_sha, :author_id, :body, :posted_at]
  @derive Jason.Encoder
  defstruct [
    :project_id,
    :node_id,
    :body_sha,
    :locator,
    :author_id,
    :body,
    :posted_at
  ]

  @type t :: %__MODULE__{
          project_id: binary(),
          node_id: binary(),
          body_sha: String.t(),
          locator: String.t() | nil,
          author_id: binary() | nil,
          body: String.t(),
          posted_at: DateTime.t()
        }
end
