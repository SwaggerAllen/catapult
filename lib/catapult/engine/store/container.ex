defmodule Catapult.Engine.Store.Container do
  @moduledoc """
  Container instances (`engine_containers`, `systems/engine.md`'s
  ORC-104 design pass): one row per minted instance, at whatever
  nesting depth it sits. Composite primary key `(project_id, id)`
  (ORC-87), the same shape every other engine table takes.

  **This is the projection that distinguishes "instances that exist"
  from "the instance that is current"** (dsl-syntax.md §15.8) — the
  storage question `systems/delivery.md`'s ORC-105 entries left open,
  answered here rather than in a second delivery-owned table. It is
  deliberately the same two-fact shape the ninth projection
  (`Catapult.Engine.Store.ActiveBundleVersion`) already gives current
  bundle version: one row per instance, the fact and the sequence it
  became true, mint recorded once and activation a later, separate
  write to the same row.

  **What is *not* here is the point.** There is no per-queue bucket
  and no membership list: a queue's population is a query over
  `engine_flows`'s own `container_id`/`queue`
  (`Catapult.Engine.Projections.ContainerQueues`), for the identical
  reason `ready_scopes` refuses to materialize — a stale ordering is
  worse than none, because it is the kind of thing a dispatcher acts
  on (v5 §1.2, §7.8). `current_queue` is not that bucket: it is which
  *declared entry* the instance stands at, one name, which nothing can
  derive from the work items alone.

  `flag_set`/`flag_set_state` carry the aggregated flip (v5 §7.8)
  through §7.1's intent → effect → completion: `:requested` is intent
  recorded, `:flipped` is the world's confirmation, and a row sitting
  at `:requested` is an intent-without-effect, which is visible and
  escalates rather than silently reading as done.
  """

  use Ecto.Schema

  # Composite primary key `(project_id, id)` (ORC-87, systems/engine.md).
  @primary_key false

  schema "engine_containers" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :type_name, :string
    field :parent_container_id, :string
    field :parent_queue, :string
    field :state, Ecto.Enum, values: [:minted, :active, :closed], default: :minted
    field :current_queue, :string
    field :current_queue_sequence, :integer
    field :minted_sequence, :integer
    field :activated_sequence, :integer
    field :closed_sequence, :integer
    field :flag_set, {:array, :string}, default: []
    field :flag_set_state, Ecto.Enum, values: [:none, :requested, :flipped], default: :none
    field :flag_set_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end

  @type t :: %__MODULE__{}
end
