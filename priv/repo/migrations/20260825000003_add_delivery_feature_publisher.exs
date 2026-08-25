defmodule Catapult.Repo.Migrations.AddDeliveryFeaturePublisher do
  use Ecto.Migration

  # The write side of Phase 4's PR management (systems/delivery.md,
  # ORC-33 design pass): where a flow's feature branch/PR is recorded
  # once opened, and this system's own idempotency bookkeeping for
  # each node pushed onto it. Neither table is event-sourced (ordinary
  # Ecto persistence, `add_delivery_store.exs`'s own precedent), and
  # both are keyed `(project_id, id | node_id)` on the identical pairs
  # this system already keys `delivery_feature_lifecycles` and
  # `delivery_draft_bodies` on.
  def change do
    create table(:delivery_feature_publications, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, primary_key: true
      add :branch_name, :string, null: false
      add :base_ref, :string, null: false
      add :pr_number, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create table(:delivery_artifact_pushes, primary_key: false) do
      add :project_id, :string, primary_key: true
      add :node_id, :string, primary_key: true
      add :flow_id, :string, null: false
      add :tier, :string, null: false
      add :scope_key, :map, null: false, default: %{}
      add :path, :string, null: false
      add :body_sha, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create index(:delivery_artifact_pushes, [:project_id, :flow_id])
  end
end
