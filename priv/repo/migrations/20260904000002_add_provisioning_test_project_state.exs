defmodule Catapult.Repo.Migrations.AddProvisioningTestProjectState do
  use Ecto.Migration

  # ORC-224 (`systems/delivery.md`): `test_project_state` gains a
  # fourth value, `:provisioning` — "minted, not yet safe to dispatch
  # against", closing the window between `mint_test_project/2` and the
  # reset/intake writes that `provision/1` promotes it past. The
  # column itself is untyped (`add :test_project_state, :string`, no
  # database-level check constraint — `AddDeliveryProjects`), so
  # widening `Ecto.Enum`'s own `values:` list, in `Project`'s schema,
  # is the whole of what admits the new value; nothing here changes
  # what Postgres accepts. This migration exists anyway, to record the
  # widening as its own dated, reasoned entry alongside every other
  # `delivery_projects` change rather than leaving it undiscoverable
  # from migration history.
  def change do
  end
end
