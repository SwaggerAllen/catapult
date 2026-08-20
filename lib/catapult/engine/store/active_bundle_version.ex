defmodule Catapult.Engine.Store.ActiveBundleVersion do
  @moduledoc """
  The ninth projection (`engine_active_bundle_versions`,
  `systems/engine.md`'s design pass): current bundle version per axis
  per project, and the sequence it became current. Two rows per
  project today (`:chain`, `:workflow`); the reducer consults this
  projection, in log order, exactly like every other event — never
  `core_dsl`'s currently-loaded bundle — so rebuild-from-zero applies
  each historical event under the bundle semantics active *when it
  was committed*, a cutover included.
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false

  schema "engine_active_bundle_versions" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :axis, Ecto.Enum, values: [:chain, :workflow]
    field :bundle_name, :string
    field :version, :string
    field :became_current_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
