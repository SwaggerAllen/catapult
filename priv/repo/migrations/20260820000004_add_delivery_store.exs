defmodule Catapult.Repo.Migrations.AddDeliveryStore do
  use Ecto.Migration

  # Delivery's own persistence (systems/delivery.md, ORC-9's
  # dispatch-facing slice): where a project's generated body lands
  # (`project_bindings`) and the in-flight correlation record between
  # a plane-minted dispatch and the runner's OIDC-authenticated calls
  # back (`delivery_dispatch_runs`). Table prefix on the slug spine
  # (conventions §3): `delivery_*`.
  #
  # `delivery_dispatch_runs.id` is `:binary_id` rather than the
  # engine's `:string` scheme: this table is ordinary Ecto persistence
  # outside any event-sourced aggregate (conventions §6's ES-family
  # rules bind `engine_*`, not this), so the purity floor's "no
  # generated ids in aggregate/reducer code" has no purchase here —
  # `Ecto.UUID.generate/0` at the command edge is the ordinary case.
  def change do
    create table(:delivery_project_bindings, primary_key: false) do
      add :project_id, :string, primary_key: true
      add :repo_owner, :string, null: false
      add :repo_name, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create table(:delivery_dispatch_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, :string, null: false
      add :node_id, :string, null: false
      add :tier, :string, null: false
      add :scope_key, :map, null: false, default: %{}
      add :repo_owner, :string, null: false
      add :repo_name, :string, null: false
      add :root_tag, :string, null: false
      # The rendered Liquid prompt (`systems/generation.md`), persisted
      # so context-fetch can serve it back on a call that may land
      # seconds to minutes after dispatch, from any node — never held
      # only in the dispatching process's memory.
      add :rendered_prompt, :text, null: false
      add :credential_sent, :string, null: false
      # GitHub's own numeric run id — unknown at dispatch time (the
      # `workflow_dispatch` REST call returns no run identity), filled
      # in from the first authenticated inbound call's OIDC claim and
      # matched against on every call after (v5 §7.12.1's "matches
      # audience + repository + run_id to its own dispatch record").
      add :github_run_id, :string, null: true
      add :status, :string, null: false, default: "dispatched"

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end

    create index(:delivery_dispatch_runs, [:project_id, :node_id])

    # The one place a committed draft's raw body text survives past
    # its own commit — deliberately not the engine's event log or any
    # of its projections: `DraftCommitted`'s own moduledoc places body
    # extraction "at the command edge... so replay never needs to
    # re-read git content," which is a decision *against* the log ever
    # holding raw bodies, not an oversight this table works around.
    # What it is for: a review tier's prompt needs the reviewed tier's
    # `draft` variable verbatim (the per-tier triad invariant,
    # `systems/generation.md`) after that tier's own dispatch already
    # completed and its result-report body is otherwise gone — this is
    # delivery's own cache of what it already received once, keyed by
    # the same `(project_id, node_id)` every other lookup here uses,
    # not a second copy of engine's log.
    create table(:delivery_draft_bodies, primary_key: false) do
      add :project_id, :string, primary_key: true
      add :node_id, :string, primary_key: true
      add :body, :text, null: false
      add :body_sha, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end
  end
end
