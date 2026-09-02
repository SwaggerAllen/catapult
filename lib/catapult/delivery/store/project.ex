defmodule Catapult.Delivery.Store.Project do
  @moduledoc """
  The plane's first project-level record (`delivery_projects`, ORC-216
  design pass, `systems/delivery.md`). A project is a test project iff
  `test_project_state` is set — `:active` (the one the sweeper
  dispatches for), `:released` (held for a debugging session, never
  swept again) or `:deleted` (terminal; the row survives as a
  tombstone so a project id is never reused). A project no test flow
  ever minted gets no row here at all.
  """

  use Ecto.Schema

  @primary_key {:project_id, :string, autogenerate: false}

  schema "delivery_projects" do
    field :test_project_state, Ecto.Enum, values: [:active, :released, :deleted]

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
