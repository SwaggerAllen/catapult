defmodule Catapult.Repo.Migrations.AddEngineStore do
  use Ecto.Migration

  # The engine's own projection tables (systems/engine.md): universal
  # read models the reducer writes and the plane queries. Table prefix
  # on the slug spine (conventions §3): `engine_*`. Every id below is
  # caller-supplied (a command-edge value, never generated here) —
  # the purity floor holds at the schema too: nothing in this tree
  # calls `Ecto.UUID.generate/0` to produce one.
  #
  # Ids are `:string`, not `:binary_id` — a Postgres `uuid` column
  # rejects anything not shaped like a UUID, and nothing about "the
  # command edge supplies it" requires a UUID specifically (a
  # deterministic, content-addressed slug is an equally legal id).
  # Fixing the type at `:string` keeps that choice open for whichever
  # scheme a later ticket's command edge actually mints.
  #
  # `staleness` and `ready_scopes` are deliberately absent: both are
  # pure queries over these tables (v5 §7.11's standing decision — "a
  # projection, never stored state"), computed by
  # `Catapult.Engine.Projections.{Staleness,ReadyScopes}` rather than
  # materialized here.
  def change do
    create table(:engine_nodes, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :tier, :string, null: false
      add :scope_key, :map, null: false, default: %{}
      add :parent_node_id, references(:engine_nodes, type: :string), null: true
      # absent | drafted | approved — never `stale`: staleness is
      # derived, not stored (systems/engine.md).
      add :status, :string, null: false, default: "absent"
      add :fields, :map, null: false, default: %{}
      add :current_draft_id, :string, null: true
      add :body_sha, :string, null: true
      # The project-stream sequence number the current draft committed
      # at — read off the recorded event's own metadata at projection
      # time, never generated here — kept denormalized on the node so
      # staleness comparisons (`Catapult.Engine.Projections.Staleness`)
      # are an index lookup rather than a join through drafts.
      add :committed_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create unique_index(:engine_nodes, [:project_id, :tier, :scope_key])
    create index(:engine_nodes, [:project_id, :parent_node_id])
    create index(:engine_nodes, [:parent_node_id])

    create table(:engine_edges, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :edge_name, :string, null: false
      add :type, :string, null: false
      add :source_node_id, references(:engine_nodes, type: :string), null: false
      add :target_node_id, references(:engine_nodes, type: :string), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:engine_edges, [:edge_name, :source_node_id, :target_node_id])
    create index(:engine_edges, [:project_id, :source_node_id])
    create index(:engine_edges, [:project_id, :target_node_id])

    create table(:engine_fragments, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :owner_node_id, references(:engine_nodes, type: :string), null: false
      add :kind, :string, null: false
      add :content, :text, null: false
      add :author_tier, :string, null: false
      add :author_node_id, references(:engine_nodes, type: :string), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:engine_fragments, [:project_id, :owner_node_id, :kind])

    create table(:engine_drafts, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :node_id, references(:engine_nodes, type: :string), null: false
      add :body_sha, :string, null: false
      add :committed_sequence, :bigint, null: false
      # pending | approved | discarded
      add :status, :string, null: false, default: "pending"
      add :actor_id, :string, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create index(:engine_drafts, [:project_id, :node_id])
    # At most one pending draft per node (v4 §A.3.3, carried forward).
    create unique_index(:engine_drafts, [:node_id],
             where: "status = 'pending'",
             name: :engine_drafts_one_pending_per_node
           )

    create table(:engine_reviews, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :draft_id, references(:engine_drafts, type: :string), null: false
      add :score, :integer, null: false
      add :findings, {:array, :map}, null: false, default: []
      add :body_sha, :string, null: true
      # ai | human (ReviewWritten v2 — v1 carried no `kind`, upcast to
      # `:ai`, systems/engine.md's versioning discipline)
      add :kind, :string, null: false, default: "ai"

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:engine_reviews, [:project_id, :draft_id])

    create table(:engine_flows, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      add :flow_name, :string, null: false
      add :entry_node_id, references(:engine_nodes, type: :string), null: false
      add :ticket_ref, :string, null: true
      # open | completed
      add :status, :string, null: false, default: "open"
      add :opened_sequence, :bigint, null: false
      add :completed_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create index(:engine_flows, [:project_id, :status])

    # The ninth projection (systems/engine.md's design pass): the
    # active bundle version per project per axis, in log order — what
    # lets the reducer resolve bundle semantics from the log at every
    # event instead of from whatever `core_dsl` currently has loaded,
    # and what delivery's Phase 7 blocked-ticket re-resolution joins
    # against.
    create table(:engine_active_bundle_versions, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, null: false
      # chain | workflow
      add :axis, :string, null: false
      add :bundle_name, :string, null: false
      add :version, :string, null: false
      add :became_current_sequence, :bigint, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:engine_active_bundle_versions, [:project_id, :axis, :became_current_sequence],
             name: :engine_active_bundle_versions_project_axis_sequence_index
           )
  end
end
