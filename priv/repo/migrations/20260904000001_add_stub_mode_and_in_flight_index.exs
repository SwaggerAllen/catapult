defmodule Catapult.Repo.Migrations.AddStubModeAndInFlightIndex do
  use Ecto.Migration

  # ORC-223 (`systems/delivery.md`, `systems/generation.md`): the
  # in-flight guard's own lookup — `Store.in_flight_dispatch?/4` reads
  # `delivery_dispatch_runs` by `(project_id, tier, scope_key, status)`,
  # which the existing `(project_id, node_id)` index doesn't cover,
  # since the guard runs before a node id is ever resolved — and the
  # per-project stub-mode opt-in, a fact of the project's own row,
  # never inferred from row presence (the deliberate mirror of
  # `sweepable_project?/1`'s no-row `true`).
  def change do
    alter table(:delivery_projects) do
      add :stub_mode, :boolean, null: false, default: true
    end

    create index(:delivery_dispatch_runs, [:project_id, :tier, :scope_key, :status])
  end
end
