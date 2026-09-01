defmodule Catapult.Repo.Migrations.AddDeliveryInputDocuments do
  use Ecto.Migration

  # The intake raft's own storage (ORC-107, `systems/delivery.md`): a
  # pinned copy of every file discovered under the bound repo's
  # registered raft path at intake, keyed so an extension-stem
  # collision under one role (`project_doc.md` and `project_doc.txt`)
  # is legal rather than rejected. `content` is the verbatim copy a
  # render-time walk reads; `source_ref` is the commit SHA intake read
  # it at, provenance only and never dereferenced again — a later walk
  # always reads this table's own `content`, never `source_ref`, which
  # is the whole of what "frozen at intake" (v5 §1.1) means at the
  # storage layer.
  def change do
    create table(:delivery_input_documents, primary_key: false) do
      add :project_id, :string, primary_key: true
      add :role, :string, primary_key: true
      add :filename, :string, primary_key: true
      add :content, :text, null: false
      add :source_ref, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    # Both read paths (`get_input_documents/2`'s per-role query,
    # `get_raft/1`'s whole-project query) order by filename — the
    # index makes that order cheap for both rather than merely correct.
    create index(:delivery_input_documents, [:project_id, :role, :filename])
  end
end
