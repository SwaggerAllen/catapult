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

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false
  @foreign_key_type :string

  schema "engine_flows" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :flow_name, :string
    belongs_to :entry_node, Catapult.Engine.Store.Node
    field :ticket_ref, :string
    # Membership by reference (ORC-104, systems/engine.md): which
    # container this work item belongs to and which of that container's
    # declared queues it is assigned to, both set once at open. A
    # queue's population is these two columns plus `status`, queried —
    # never a bucket (`Catapult.Engine.Projections.ContainerQueues`).
    # Archival never touches either, so a container stays a path to its
    # own history for free (v5 §7.8).
    field :container_id, :string
    field :queue, :string
    field :status, Ecto.Enum, values: [:open, :completed], default: :open
    field :opened_sequence, :integer
    field :completed_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
