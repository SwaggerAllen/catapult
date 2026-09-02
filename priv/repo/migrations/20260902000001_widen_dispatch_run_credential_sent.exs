defmodule Catapult.Repo.Migrations.WidenDispatchRunCredentialSent do
  use Ecto.Migration

  # `HostPort.request`'s `credential_names` widens to the bindings
  # tunable's full ordered pair (`systems/delivery.md`'s ORC-215
  # entry): ORC-9's single-credential no-failover workaround retires
  # now that Catapult's own runner harness classifies limit-class
  # failures itself, so `credential_sent` records every name the
  # dispatch offered, not just the one sent.
  def change do
    alter table(:delivery_dispatch_runs) do
      remove :credential_sent, :string
      add :credential_sent, {:array, :string}, null: false, default: []
    end
  end
end
