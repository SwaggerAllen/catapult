defmodule Catapult.Repo.Migrations.AddDeliveryFeatureLifecycle do
  use Ecto.Migration

  # The feature-ticket lifecycle projection (systems/delivery.md,
  # ORC-32 design pass): one row per flow instance, keyed
  # `(project_id, id)` on the identical pair the process manager
  # instance is keyed on (ORC-87) — never a bare flow id. Ordinary
  # Ecto persistence outside any event-sourced aggregate, the same
  # shape `add_delivery_store.exs`'s own tables already take: `id` is
  # caller-supplied (the flow's own id, already minted by the command
  # edge that opened it), so no generated-id column is needed here
  # either.
  def change do
    create table(:delivery_feature_lifecycles, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, primary_key: true
      add :entry_node_id, :string, null: true
      # One of `Catapult.Dsl.SystemStatus.kind/0`'s twelve, or nil when
      # the ticket is standing at a declared gate instead
      # (`status_gate`) — the two are never both set, never both nil.
      add :status_kind, :string, null: true
      add :status_gate, :string, null: true
      # The position the ticket was standing at when it was last kicked
      # to `:blocked` (`status_kind` = "blocked" at that point) — nil
      # until the first block.
      add :blocked_origin_kind, :string, null: true
      add :blocked_origin_gate, :string, null: true
      add :updated_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end
  end
end
