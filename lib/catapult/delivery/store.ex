defmodule Catapult.Delivery.Store do
  @moduledoc """
  Delivery's persistence subcomponent (conventions §4/§6): project
  repo bindings and in-flight dispatch-run correlation. Function-shaped
  exports, never generic CRUD.
  """

  import Ecto.Query

  alias Catapult.Delivery.Store.DispatchRun
  alias Catapult.Delivery.Store.DraftBody
  alias Catapult.Delivery.Store.FeatureLifecycle
  alias Catapult.Delivery.Store.ProjectBinding
  alias Catapult.Engine.Store.Flow, as: EngineFlow
  alias Catapult.Repo

  ## Project bindings

  @doc "The repo `project_id` dispatches against, or `nil` if unbound."
  @spec get_project_binding(binary()) :: ProjectBinding.t() | nil
  def get_project_binding(project_id), do: Repo.get(ProjectBinding, project_id)

  @doc "Binds `project_id` to a GitHub repo (upsert — a project has exactly one binding at a time)."
  @spec put_project_binding(binary(), String.t(), String.t()) :: ProjectBinding.t()
  def put_project_binding(project_id, repo_owner, repo_name) do
    %ProjectBinding{project_id: project_id}
    |> Ecto.Changeset.change(%{repo_owner: repo_owner, repo_name: repo_name})
    |> Repo.insert!(
      on_conflict: {:replace, [:repo_owner, :repo_name]},
      conflict_target: [:project_id]
    )
  end

  ## Dispatch runs

  @doc "Opens a run correlation record at dispatch time. `attrs.id` is the plane-minted run_key."
  @spec insert_dispatch_run(map()) :: DispatchRun.t()
  def insert_dispatch_run(attrs) do
    %DispatchRun{}
    |> Ecto.Changeset.change(Map.put_new(attrs, :status, :dispatched))
    |> Repo.insert!()
  end

  @doc "The run correlation record for `run_key`, or `nil` — including for a `run_key` that isn't even UUID-shaped (untrusted path-segment input, never a reason to crash)."
  @spec get_dispatch_run(binary()) :: DispatchRun.t() | nil
  def get_dispatch_run(run_key) do
    case Ecto.UUID.cast(run_key) do
      {:ok, valid} -> Repo.get(DispatchRun, valid)
      :error -> nil
    end
  end

  @doc """
  Records GitHub's own numeric run id against `run_key`, the first
  time an authenticated call names it — a no-op once already set, so
  a second call cannot silently rebind a run's identity.
  """
  @spec bind_github_run_id(binary(), String.t()) :: :ok
  def bind_github_run_id(run_key, github_run_id) do
    Repo.update_all(
      from(r in DispatchRun, where: r.id == ^run_key and is_nil(r.github_run_id)),
      set: [github_run_id: github_run_id, status: :context_fetched]
    )

    :ok
  end

  @spec complete_dispatch_run(binary(), :completed | :failed) :: :ok
  def complete_dispatch_run(run_key, status) when status in [:completed, :failed] do
    Repo.update_all(from(r in DispatchRun, where: r.id == ^run_key), set: [status: status])
    :ok
  end

  ## Draft bodies (the review-tier `draft` variable's own cache — see the owning migration)

  @spec put_draft_body(binary(), binary(), String.t(), String.t()) :: :ok
  def put_draft_body(project_id, node_id, body, body_sha) do
    %DraftBody{project_id: project_id, node_id: node_id}
    |> Ecto.Changeset.change(%{body: body, body_sha: body_sha})
    |> Repo.insert!(
      on_conflict: {:replace, [:body, :body_sha]},
      conflict_target: [:project_id, :node_id]
    )

    :ok
  end

  @spec get_draft_body(binary(), binary()) :: String.t() | nil
  def get_draft_body(project_id, node_id) do
    case Repo.get_by(DraftBody, project_id: project_id, node_id: node_id) do
      nil -> nil
      %DraftBody{body: body} -> body
    end
  end

  ## Feature lifecycle (systems/delivery.md, ORC-32 design pass)

  @doc """
  The most recently opened, still-`:open` flow for `project_id` — a
  read of engine's own `engine_flows` (`Catapult.Engine.Store.Flow`),
  state of record for flow instances (`systems/delivery.md`'s own
  "Depends on: engine (state of record)"). Phase 4 has no dispatch or
  mutex machinery yet, so at most one flow is realistically open on a
  project at a time; this is the process manager's own routing lookup
  for an event (`DraftCommitted`, `RunFailed`, …) that carries no
  `flow_id` of its own, not a claim that a project can never hold more
  than one open flow.
  """
  @spec current_open_flow_id(binary()) :: binary() | nil
  def current_open_flow_id(project_id) do
    Repo.one(
      from f in EngineFlow,
        where: f.project_id == ^project_id and f.status == :open,
        order_by: [desc: f.opened_sequence],
        limit: 1,
        select: f.id
    )
  end

  @doc "Upserts a flow's projected lifecycle status — idempotent on `(project_id, id)`, safe under process-manager replay."
  @spec upsert_feature_lifecycle(map()) :: FeatureLifecycle.t()
  def upsert_feature_lifecycle(attrs) do
    id = Map.fetch!(attrs, :id)
    project_id = Map.fetch!(attrs, :project_id)
    replace = attrs |> Map.delete(:id) |> Map.delete(:project_id) |> Map.keys()

    %FeatureLifecycle{id: id, project_id: project_id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: {:replace, replace}, conflict_target: [:project_id, :id])
  end

  @spec get_feature_lifecycle(binary(), binary()) :: FeatureLifecycle.t() | nil
  def get_feature_lifecycle(project_id, id) do
    Repo.get_by(FeatureLifecycle, project_id: project_id, id: id)
  end
end
