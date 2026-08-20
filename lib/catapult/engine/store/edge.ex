defmodule Catapult.Engine.Store.Edge do
  @moduledoc """
  One row per edge instance (`engine_edges`, v4 §A.3.3): the reducer's
  fanout/dependency/reference/policy_application/synthesis facts,
  authored-only (dsl-syntax.md §4) and never derived at read time —
  derived views are context walks over these rows, not fragments.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "engine_edges" do
    field :project_id, :string
    field :edge_name, :string

    field :type, Ecto.Enum,
      values: [:fanout, :reference, :dependency, :policy_application, :synthesis]

    belongs_to :source, Catapult.Engine.Store.Node, foreign_key: :source_node_id
    belongs_to :target, Catapult.Engine.Store.Node, foreign_key: :target_node_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
