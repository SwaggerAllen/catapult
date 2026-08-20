defmodule Catapult.Engine.Store.Draft do
  @moduledoc """
  Draft lifecycle records (`engine_drafts`, v4 §A.3.3): at most one
  `:pending` draft per node (enforced by
  `engine_drafts_one_pending_per_node`). `committed_sequence` is the
  project-stream sequence the commit landed at, read off the recorded
  event rather than generated here — what
  `Catapult.Engine.Projections.Staleness` compares against.
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false
  @foreign_key_type :string

  schema "engine_drafts" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    belongs_to :node, Catapult.Engine.Store.Node
    field :body_sha, :string
    field :committed_sequence, :integer
    field :status, Ecto.Enum, values: [:pending, :approved, :discarded], default: :pending
    field :actor_id, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
