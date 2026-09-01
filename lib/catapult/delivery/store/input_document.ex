defmodule Catapult.Delivery.Store.InputDocument do
  @moduledoc """
  One file pinned from the intake raft (`delivery_input_documents`,
  ORC-107, `systems/delivery.md`) — the same "a Liquid variable needs
  a stable string and the thing underneath is allowed to keep moving"
  shape `Catapult.Delivery.Store.DraftBody` already established one
  tier over.

  Keyed `(project_id, role, filename)`: `role` is the filename's own
  stem (Discovery, `systems/delivery.md`) rather than a declared
  attribute, so an extension-stem collision under one role
  (`project_doc.md` and `project_doc.txt`) is two rows, not a
  collision. `content` is the verbatim copy a walk reads; `source_ref`
  is the commit SHA intake read it at, carried for provenance only and
  never dereferenced again — resolving a later walk *from* `source_ref`
  would be the live re-read v5 §1.1 refuses, one hop removed.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_input_documents" do
    field :project_id, :string, primary_key: true
    field :role, :string, primary_key: true
    field :filename, :string, primary_key: true
    field :content, :string
    field :source_ref, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
