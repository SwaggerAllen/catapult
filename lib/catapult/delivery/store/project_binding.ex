defmodule Catapult.Delivery.Store.ProjectBinding do
  @moduledoc """
  Which GitHub repository a project's generation dispatches against
  (`delivery_project_bindings`). The smallest seam that makes the
  Actions adapter's `workflow_dispatch` call and OIDC's `repository`
  claim match possible at all — it binds exactly the one fact dispatch
  needs, no more. `Catapult.Delivery.Store.Project` (ORC-216) is the
  first project-level record this store carries; a binding and a
  project record answer different questions (which repo dispatch
  targets, versus whether this project id means anything beyond a
  binding) and neither implies the other.
  """

  use Ecto.Schema

  @primary_key false

  schema "delivery_project_bindings" do
    field :project_id, :string, primary_key: true
    field :repo_owner, :string
    field :repo_name, :string

    timestamps(type: :utc_datetime_usec, updated_at: :updated_at)
  end
end
