defmodule Catapult.Delivery.Store.FeatureLifecycle do
  @moduledoc """
  One row per flow instance (`delivery_feature_lifecycles`): the
  feature-ticket lifecycle projection `Catapult.Delivery
  .FeatureLifecycle` writes, and the work surface reads
  (`systems/delivery.md`, ORC-32 design pass). Composite primary key
  `(project_id, id)` — `id` is the flow id, the identical `(project_id,
  flow_id)` pair that process manager instance is keyed on (ORC-87).

  `status_kind`/`status_gate` are never both non-nil, and never both
  nil: the projected status is exactly one of `Catapult.Dsl
  .SystemStatus.kind()` or a declared gate's own name
  (`Catapult.Delivery.FeatureLifecycle.Sequence.position()`), never a
  rendered label — the work surface renders, this projection doesn't
  (`systems/delivery.md`'s "the label owner" bullet).
  `blocked_origin_kind`/`blocked_origin_gate` carry the same shape for
  the position the ticket was standing at when it was last kicked to
  `:blocked`, read here rather than stamped onto a comment.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_feature_lifecycles" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :entry_node_id, :string
    field :status_kind, :string
    field :status_gate, :string
    field :blocked_origin_kind, :string
    field :blocked_origin_gate, :string
    field :updated_sequence, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
