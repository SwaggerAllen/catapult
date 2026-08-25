defmodule Catapult.Delivery.Store.FeaturePublication do
  @moduledoc """
  One row per flow instance's feature branch and PR
  (`delivery_feature_publications`, `systems/delivery.md`'s ORC-33
  entry): the branch name and PR number `Catapult.Delivery
  .FeaturePublishWorker` opened on the flow's first successful
  `DraftCommitted`, so every later push resolves back to the same
  branch and the same PR rather than opening a second one. Composite
  primary key `(project_id, id)` — `id` is the flow id, the identical
  pair `Catapult.Delivery.Store.FeatureLifecycle` is already keyed on
  (ORC-87).

  `branch_name` is recorded rather than recomputed from `base_ref`/the
  flow's ticket reference on every read, so a ticket edited after the
  fact can't disagree with what GitHub already holds.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_feature_publications" do
    field :id, :string, primary_key: true
    field :project_id, :string, primary_key: true
    field :branch_name, :string
    field :base_ref, :string
    field :pr_number, :integer

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
