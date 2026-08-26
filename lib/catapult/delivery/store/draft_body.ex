defmodule Catapult.Delivery.Store.DraftBody do
  @moduledoc """
  A committed draft's raw body text, cached once (`delivery_draft_bodies`)
  so a review tier's prompt can carry the reviewed tier's `draft`
  variable verbatim (the per-tier triad invariant,
  `systems/generation.md`) without the engine's own event log ever
  holding it — see the owning migration for why that split is
  deliberate.

  `previous_body`/`previous_body_sha` are ORC-114's own addition: one
  prior committed body, not a log — `document-review`'s per-sentence
  diff needs exactly the prior committed body beside the current one,
  never a deeper history. Both nullable: absent before a node's second
  commit.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_draft_bodies" do
    field :project_id, :string, primary_key: true
    field :node_id, :string, primary_key: true
    field :body, :string
    field :body_sha, :string
    field :previous_body, :string
    field :previous_body_sha, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
