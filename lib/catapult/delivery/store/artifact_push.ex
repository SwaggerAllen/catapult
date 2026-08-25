defmodule Catapult.Delivery.Store.ArtifactPush do
  @moduledoc """
  One row per node whose committed draft has been pushed onto its
  flow's feature branch (`delivery_artifact_pushes`, `systems/delivery
  .md`'s ORC-33 entry) — this system's own idempotency bookkeeping for
  an outbound act, never an engine event: whether a node's body has
  reached git is not a fact `ready_scopes`, dispatch or the lifecycle
  projection reason about, so it stays local to the worker that needs
  it to skip a redundant push. Composite primary key `(project_id,
  node_id)`, the same shape `Catapult.Delivery.Store.DraftBody`
  already takes for the identical pair.

  `flow_id` is carried alongside the key (rather than recomputed from
  engine state on every read) so the PR body's table of contents can
  list one flow's pushes without a second read of `engine_flows` per
  row.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_artifact_pushes" do
    field :project_id, :string, primary_key: true
    field :node_id, :string, primary_key: true
    field :flow_id, :string
    field :tier, :string
    field :scope_key, :map
    field :path, :string
    field :body_sha, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
