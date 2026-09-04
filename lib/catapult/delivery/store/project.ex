defmodule Catapult.Delivery.Store.Project do
  @moduledoc """
  The plane's first project-level record (`delivery_projects`, ORC-216
  design pass, `systems/delivery.md`). A project is a test project iff
  `test_project_state` is set — `:provisioning` (minted, not yet safe
  to dispatch against — ORC-224), `:active` (the one the sweeper
  dispatches for), `:released` (held for a debugging session, never
  swept again) or `:deleted` (terminal; the row survives as a
  tombstone so a project id is never reused). A project no test flow
  ever minted gets no row here at all.

  `stub_mode` (ORC-223, `systems/generation.md`'s ORC-223 entry) is a
  second, independent question from test-project status: whether this
  project's dispatches skip the model. Defaults `true` at the column,
  set per project at mint time (`Store.mint_test_project/2`).
  """

  use Ecto.Schema

  @primary_key {:project_id, :string, autogenerate: false}

  schema "delivery_projects" do
    field :test_project_state, Ecto.Enum, values: [:provisioning, :active, :released, :deleted]
    field :stub_mode, :boolean, default: true

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
