defmodule Catapult.Engine.Store.ContainerFinding do
  @moduledoc """
  Adjudicated findings (`engine_container_findings`,
  `systems/engine.md`'s ORC-104 design pass): one row per finding a
  container carried, recording how it left — filed under its own key,
  or declined with a reason (v5 §7.8).

  A finding with no row here has not been read, which is precisely the
  state `retro`'s completion gate refuses to resolve over
  (`Catapult.Delivery.ContainerLifecycle`). The table exists so that
  "twelve findings carried, none recorded as read" is a query rather
  than an archaeology exercise.
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false

  schema "engine_container_findings" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :container_id, :string
    field :disposition, Ecto.Enum, values: [:filed, :declined]
    field :filed_key, :string
    field :reason, :string
    field :adjudicated_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
