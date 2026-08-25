defmodule Catapult.Repo.Migrations.AddDeliveryContainerProposals do
  use Ecto.Migration

  # Composition's proposal read model (ORC-104, systems/delivery.md):
  # what the plane computed the next container's `prep` should hold.
  # Purely computed — nothing here is a work item, nothing here opens a
  # flow, and committing a proposal stays the author's act.
  #
  # Keyed `(project_id, id)` like every other table in this codebase
  # post-ORC-87; `id` is caller-supplied and derived from the proposal's
  # own subject, so recomputing at a later close updates the row rather
  # than accumulating duplicates of the same suggestion.
  def change do
    create table(:delivery_container_proposals, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, primary_key: true
      # The container whose close computed this.
      add :source_container_id, :string, null: false
      # The container and queue it is proposed into — null target
      # container while the next instance has not been minted yet,
      # which is the ordinary case at a close.
      add :target_container_id, :string, null: true
      add :target_queue, :string, null: false
      add :work_item_id, :string, null: false
      add :work_item_ref, :string, null: true
      add :flow_name, :string, null: true
      # Why this candidate survived the filter — the sentence a human
      # reads before accepting or declining.
      add :rationale, :text, null: true
      add :computed_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create index(:delivery_container_proposals, [:project_id, :source_container_id])
  end
end
