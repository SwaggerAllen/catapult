defmodule Catapult.Engine.Store.Review do
  @moduledoc """
  Review records (`engine_reviews`, dsl-syntax.md §10): the
  platform-wide review grammar's `<score>` and `<finding id>` list,
  landed with the run's result event. `kind` defaults to `:ai` —
  `ReviewWritten` v1 carried no `kind` at all (every review was the
  chain's own auto-review); v2 adds it for human review states
  (systems/engine.md), and the v1 fixture upcasts to `:ai`.
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false
  @foreign_key_type :string

  schema "engine_reviews" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    belongs_to :draft, Catapult.Engine.Store.Draft
    field :score, :integer
    field :findings, {:array, :map}, default: []
    field :body_sha, :string
    field :kind, Ecto.Enum, values: [:ai, :human], default: :ai

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
