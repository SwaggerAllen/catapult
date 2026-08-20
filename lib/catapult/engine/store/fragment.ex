defmodule Catapult.Engine.Store.Fragment do
  @moduledoc """
  One row per authored fragment (`engine_fragments`, v4 §A.3.3): the
  `produces:` mechanism (dsl-syntax.md §3) — a draft writing content
  onto another node's fragment surface. Authored-only; a downstream
  tier reads it via `handle.fragments[<kind>]`, a context-walk
  projection, never a second write path.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "engine_fragments" do
    field :project_id, :string
    belongs_to :owner, Catapult.Engine.Store.Node, foreign_key: :owner_node_id
    field :kind, :string
    field :content, :string
    field :author_tier, :string
    belongs_to :author, Catapult.Engine.Store.Node, foreign_key: :author_node_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
