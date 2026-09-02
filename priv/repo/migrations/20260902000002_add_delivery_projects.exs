defmodule Catapult.Repo.Migrations.AddDeliveryProjects do
  use Ecto.Migration

  # The plane's first project-level record (ORC-216, `systems/delivery.md`):
  # a project is a test project iff `test_project_state` is set, and an
  # ordinary project (no test flow ever minted it) gets no row here at
  # all rather than a row reading some `:ordinary` placeholder nothing
  # reads yet.
  def change do
    create table(:delivery_projects, primary_key: false) do
      add :project_id, :string, primary_key: true
      add :test_project_state, :string

      timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
    end
  end
end
