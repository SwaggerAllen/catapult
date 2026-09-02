defmodule Catapult.Repo.Migrations.AddDispatchRunOutcome do
  use Ecto.Migration

  # "The plane recorded it" resolves to two more columns on a dispatch
  # run's own correlation row (ORC-216, `systems/delivery.md`):
  # `outcome` is the fine-grained result a result-report actually
  # carried (`success`/`limit_class_failure`/`other_failure`), beside
  # the coarse `status` this table already has
  # (`dispatched`/`context_fetched`/`completed`/`failed` — unchanged,
  # `:completed` still covers a recorded limit-class/other failure);
  # `credential_used` is the name the harness actually spent, out of
  # the ordered pair `credential_sent` offered.
  def change do
    alter table(:delivery_dispatch_runs) do
      add :outcome, :string
      add :credential_used, :string
    end
  end
end
