defmodule Catapult.Engine.Store.Node do
  @moduledoc """
  One row per scope (`engine_nodes`, v4 §A.3.3 carried forward):
  `nodes.fields` is the per-tier field-projection column the bundle's
  `fields:` declarations write, and `status` is deliberately a closed
  set of *stored* states — `absent | drafted | approved` — because
  `stale` is never one of them (systems/engine.md's standing decision:
  staleness is a projection, never stored state).
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` — a node id is a
  # per-project slug, not globally unique (ORC-87, systems/engine.md).
  @primary_key false
  @foreign_key_type :string

  schema "engine_nodes" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :tier, :string
    field :scope_key, :map, default: %{}
    belongs_to :parent, __MODULE__, foreign_key: :parent_node_id
    field :status, Ecto.Enum, values: [:absent, :drafted, :approved], default: :absent
    field :fields, :map, default: %{}
    field :current_draft_id, :string
    field :body_sha, :string
    field :committed_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
