defmodule Catapult.Engine.Commands.WriteReview do
  @moduledoc "Records a review against a draft (dsl-syntax.md §10). `score` is 0-100."

  @enforce_keys [:project_id, :draft_id, :review_id, :score]
  defstruct [:project_id, :draft_id, :review_id, :score, :body_sha, findings: [], kind: :ai]
end
