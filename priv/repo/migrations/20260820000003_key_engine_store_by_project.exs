defmodule Catapult.Repo.Migrations.KeyEngineStoreByProject do
  use Ecto.Migration

  # ORC-87 (systems/engine.md): a node id is a per-project slug, not
  # globally unique — `scope_key`/`handle` are already how a node is
  # addressed *within* a project (dsl-syntax.md §3), and nothing about
  # the command edge or a bundle's own vocabulary promises more than
  # that. The primary key `AddEngineStore` fixed at `id` alone was the
  # one legal shape that assumption doesn't support; this migration
  # widens it to `(project_id, id)` on every one of the seven tables,
  # and every foreign key into `engine_nodes`/`engine_drafts` becomes
  # composite in the same change — a fix confined to `engine_nodes`
  # alone leaves those foreign keys referencing a key that no longer
  # exists.
  #
  # `engine_edges`' own natural key — the unique index
  # `Store.insert_edge/1` upserts against — is a second, non-primary
  # key that is not project-scoped either (systems/engine.md): two
  # projects declaring the same-named edge between identically-spelled
  # node ids collide on it today, silently, because the upsert is
  # `on_conflict: :nothing`. Folded into `project_id` in the same
  # migration. `engine_fragments` carries no equivalent second index —
  # it upserts on its own `id` — so the primary-key widening alone
  # closes its gap.
  #
  # `up`/`down` rather than `change`: dropping a primary or foreign key
  # constraint by name is not something Ecto can auto-reverse (it does
  # not record the dropped definition), so `change/0` would raise on
  # rollback.

  @composite_pk_tables ~w(
    engine_nodes engine_edges engine_fragments engine_drafts
    engine_reviews engine_flows engine_active_bundle_versions
  )a

  # The auto-computed name for a 4-column index on this table exceeds
  # Postgres' 63-byte identifier limit; named explicitly so `up` and
  # `down` agree on it rather than relying on silent truncation.
  @edges_natural_key_index :engine_edges_project_edge_source_target_index

  # `{table, constraint_name, column, references_table}`
  @foreign_keys [
    {:engine_nodes, "engine_nodes_parent_node_id_fkey", :parent_node_id, :engine_nodes},
    {:engine_edges, "engine_edges_source_node_id_fkey", :source_node_id, :engine_nodes},
    {:engine_edges, "engine_edges_target_node_id_fkey", :target_node_id, :engine_nodes},
    {:engine_fragments, "engine_fragments_owner_node_id_fkey", :owner_node_id, :engine_nodes},
    {:engine_fragments, "engine_fragments_author_node_id_fkey", :author_node_id, :engine_nodes},
    {:engine_drafts, "engine_drafts_node_id_fkey", :node_id, :engine_nodes},
    {:engine_reviews, "engine_reviews_draft_id_fkey", :draft_id, :engine_drafts},
    {:engine_flows, "engine_flows_entry_node_id_fkey", :entry_node_id, :engine_nodes}
  ]

  def up do
    Enum.each(@foreign_keys, fn {table, name, _column, _references} ->
      drop constraint(table, name)
    end)

    Enum.each(@composite_pk_tables, fn table ->
      drop constraint(table, "#{table}_pkey")
      execute("ALTER TABLE #{table} ADD PRIMARY KEY (project_id, id)")
    end)

    Enum.each(@foreign_keys, fn {table, name, column, references} ->
      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{name} " <>
          "FOREIGN KEY (project_id, #{column}) REFERENCES #{references} (project_id, id)"
      )
    end)

    drop unique_index(:engine_edges, [:edge_name, :source_node_id, :target_node_id])

    create unique_index(:engine_edges, [:project_id, :edge_name, :source_node_id, :target_node_id],
             name: @edges_natural_key_index
           )
  end

  def down do
    drop unique_index(:engine_edges, [:project_id, :edge_name, :source_node_id, :target_node_id],
           name: @edges_natural_key_index
         )

    create unique_index(:engine_edges, [:edge_name, :source_node_id, :target_node_id])

    Enum.each(@foreign_keys, fn {table, name, _column, _references} ->
      drop constraint(table, name)
    end)

    Enum.each(@composite_pk_tables, fn table ->
      drop constraint(table, "#{table}_pkey")
      execute("ALTER TABLE #{table} ADD PRIMARY KEY (id)")
    end)

    Enum.each(@foreign_keys, fn {table, name, column, references} ->
      execute(
        "ALTER TABLE #{table} ADD CONSTRAINT #{name} " <>
          "FOREIGN KEY (#{column}) REFERENCES #{references} (id)"
      )
    end)
  end
end
