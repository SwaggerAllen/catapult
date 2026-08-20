defmodule Catapult.Delivery.Store.ProjectBinding do
  @moduledoc """
  Which GitHub repository a project's generation dispatches against
  (`delivery_project_bindings`). The smallest seam that makes the
  Actions adapter's `workflow_dispatch` call and OIDC's `repository`
  claim match possible at all — no `projects` entity exists anywhere
  in this store yet (`systems/engine.md`'s own scheduler/store
  moduledocs: "a different, not-yet-built concern"), and this ticket
  does not build one; it binds exactly the one fact dispatch needs.
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
