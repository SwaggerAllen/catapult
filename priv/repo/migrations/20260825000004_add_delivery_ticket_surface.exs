defmodule Catapult.Repo.Migrations.AddDeliveryTicketSurface do
  use Ecto.Migration

  # The write side of ORC-114's protocol change — the working surface's
  # own read/write gaps, closed together because they share one
  # argument (`systems/delivery.md`'s design pass).
  def change do
    # Draft body history, one previous rather than a log
    # (`systems/delivery.md`): `document-review`'s per-sentence diff
    # needs the prior committed body beside the current one, and a
    # fresh visit always starts from the latest committed body — never
    # a second-oldest version. Both nullable: absent on a first commit.
    alter table(:delivery_draft_bodies) do
      add :previous_body, :text, null: true
      add :previous_body_sha, :string, null: true
    end

    # Runs linked back to their ticket (`systems/delivery.md`):
    # nullable because a run's flow is resolved the same way
    # `FeatureLifecycle` already resolves a `DraftCommitted`/`RunFailed`'s
    # flow — `Store.current_open_flow_id/1` — which can answer `nil`.
    alter table(:delivery_dispatch_runs) do
      add :flow_id, :string, null: true
    end

    create index(:delivery_dispatch_runs, [:project_id, :flow_id])
  end
end
