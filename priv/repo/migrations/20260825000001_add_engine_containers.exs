defmodule Catapult.Repo.Migrations.AddEngineContainers do
  use Ecto.Migration

  # Containers as plane state (ORC-104; systems/engine.md's design
  # pass, `workflow.md` #16 through #19). Two new tables and two new
  # columns on an existing one, all keyed `(project_id, id)` like every
  # other engine table post-ORC-87.
  #
  # No per-queue table, deliberately: a queue is a query over the work
  # items themselves (v5 §7.8, §1.2), so what a queue needs from
  # storage is a *reference on each work item*, which is what the
  # `engine_flows` columns below are — never a bucket written and read
  # back.
  def change do
    create table(:engine_containers, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, primary_key: true
      # The declared `types/<name>.yaml` this instance is one of
      # (`workflow.md` #4). Carried on the row rather than resolved
      # on read: the reducer folds under the bundle semantics active
      # when the event was committed, never whatever core_dsl currently
      # has loaded.
      add :type_name, :string, null: false
      # Null for the outermost instance — the project's own, minted
      # from the workflow bundle's `entry:` type with nothing above it.
      add :parent_container_id, :string, null: true
      add :parent_queue, :string, null: true
      # minted -> active -> closed. Mint is not activation
      # (`workflow.md` #19): an instance accepts groomed work into
      # its own future queues long before its parent's position reaches
      # it, which is what makes grooming next milestone's `prep` during
      # this milestone's `main` legal.
      add :state, :string, null: false, default: "minted"
      # Which *declared entry* the instance stands at — one name, not a
      # population. The population is a query (see below).
      add :current_queue, :string, null: true
      # "The sequence it became current" — the same second fact the
      # ninth projection records beside a current bundle version.
      add :current_queue_sequence, :bigint, null: true
      add :minted_sequence, :bigint, null: true
      add :activated_sequence, :bigint, null: true
      add :closed_sequence, :bigint, null: true
      # The aggregated flag set (v5 §7.8) through §7.1's intent ->
      # idempotent effect -> observed completion. A row sitting at
      # "requested" is an intent without an effect: visible, and
      # escalates.
      add :flag_set, {:array, :string}, null: false, default: []
      add :flag_set_state, :string, null: false, default: "none"
      add :flag_set_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    # "Which instances exist under this parent" is how a parent's queue
    # finds the child it is waiting on.
    create index(:engine_containers, [:project_id, :parent_container_id, :parent_queue])

    create table(:engine_container_findings, primary_key: false) do
      add :id, :string, primary_key: true
      add :project_id, :string, primary_key: true
      add :container_id, :string, null: false
      # filed | declined. Both carry their evidence — filed_key or
      # reason — and the aggregate rejects a disposition without it, so
      # neither column is nullable-in-practice for its own disposition.
      add :disposition, :string, null: false
      add :filed_key, :string, null: true
      add :reason, :text, null: true
      add :adjudicated_sequence, :bigint, null: true

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:engine_container_findings, [:project_id, :container_id])

    # Membership by reference, never a stored list (systems/engine.md):
    # a work item's own container_id and queue, set once at open. Both
    # nullable — a work item may belong to no container, which is every
    # flow opened before this migration — and neither is ever touched
    # by archival, which is what keeps a container a path to its own
    # history for free (v5 §7.8).
    alter table(:engine_flows) do
      add :container_id, :string, null: true
      add :queue, :string, null: true
    end

    # The queue-as-query's own index: "unresolved work items in this
    # container assigned to this queue" is this index plus a status
    # filter. `status` is included so the common case is answered
    # without touching the heap.
    create index(:engine_flows, [:project_id, :container_id, :queue, :status])
  end
end
