defmodule Catapult.Engine.Store.Flow do
  @moduledoc """
  Active flow records (`engine_flows`, v4 §A.3.3): one row per flow
  instance opened on a project — the ticket face (v5 §7.10), its
  entry node and completion state. `Target` per systems/engine.md:
  the cascade walk itself (planning-tier minting, staleness
  provenance) is not built here; this projection only records that a
  flow instance is open or completed.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :string

  schema "engine_flows" do
    field :project_id, :string
    field :flow_name, :string
    belongs_to :entry_node, Catapult.Engine.Store.Node
    field :ticket_ref, :string
    field :status, Ecto.Enum, values: [:open, :completed], default: :open
    field :opened_sequence, :integer
    field :completed_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
