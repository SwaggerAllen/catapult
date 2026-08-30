defmodule Catapult.Repo.Migrations.AddDeliveryFeatureLifecycleStatusName do
  use Ecto.Migration

  # A status entry's own bundle-authored `name:`, beside its kind
  # (dsl-syntax.md §15.12, ORC-155) — `status_kind`/`status_gate` are
  # unaffected in shape and meaning, still the closed vocabulary every
  # downstream branch reads; this is read for display alone, nil
  # whenever `status_kind`/`status_gate` are (`resting` unresolved).
  def change do
    alter table(:delivery_feature_lifecycles) do
      add :status_name, :string, null: true
    end
  end
end
