defmodule Catapult.Delivery.Store do
  @moduledoc """
  Delivery's persistence subcomponent (conventions §4/§6): project
  repo bindings and in-flight dispatch-run correlation. Function-shaped
  exports, never generic CRUD.
  """

  import Ecto.Query

  alias Catapult.Delivery.Store.ArtifactPush
  alias Catapult.Delivery.Store.ContainerProposal
  alias Catapult.Delivery.Store.DispatchRun
  alias Catapult.Delivery.Store.DraftBody
  alias Catapult.Delivery.Store.FeatureLifecycle
  alias Catapult.Delivery.Store.FeaturePublication
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

  ## Feature publication (systems/delivery.md, ORC-33 design pass)

  @doc "The flow's own feature branch/PR record, or `nil` before the first successful `DraftCommitted`."
  @spec get_feature_publication(binary(), binary()) :: FeaturePublication.t() | nil
  def get_feature_publication(project_id, flow_id) do
    Repo.get_by(FeaturePublication, project_id: project_id, id: flow_id)
  end

  @doc "Records a flow's branch/PR once opened — upsert on `(project_id, id)`, so a re-observed `DraftCommitted` for a flow that already has a row is a no-op write of the same facts."
  @spec upsert_feature_publication(map()) :: FeaturePublication.t()
  def upsert_feature_publication(attrs) do
    id = Map.fetch!(attrs, :id)
    project_id = Map.fetch!(attrs, :project_id)
    replace = attrs |> Map.delete(:id) |> Map.delete(:project_id) |> Map.keys()

    %FeaturePublication{id: id, project_id: project_id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: {:replace, replace}, conflict_target: [:project_id, :id])
  end

  @doc "Whether `node_id`'s draft at `body_sha` has already been pushed — the idempotency check `Catapult.Delivery.FeaturePublishWorker` runs before doing anything."
  @spec get_artifact_push(binary(), binary()) :: ArtifactPush.t() | nil
  def get_artifact_push(project_id, node_id) do
    Repo.get_by(ArtifactPush, project_id: project_id, node_id: node_id)
  end

  @doc "Records a node's push — upsert on `(project_id, node_id)`, so a node whose draft is regenerated and re-pushed updates its one row rather than accumulating a stale one."
  @spec upsert_artifact_push(map()) :: ArtifactPush.t()
  def upsert_artifact_push(attrs) do
    project_id = Map.fetch!(attrs, :project_id)
    node_id = Map.fetch!(attrs, :node_id)
    replace = attrs |> Map.delete(:project_id) |> Map.delete(:node_id) |> Map.keys()

    %ArtifactPush{project_id: project_id, node_id: node_id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: {:replace, replace}, conflict_target: [:project_id, :node_id])
  end

  @doc "Every node pushed for `flow_id` so far, tier then path — the PR body's own table of contents (`systems/delivery.md`'s ORC-33 entry)."
  @spec artifact_pushes_for_flow(binary(), binary()) :: [ArtifactPush.t()]
  def artifact_pushes_for_flow(project_id, flow_id) do
    ArtifactPush
    |> where([p], p.project_id == ^project_id and p.flow_id == ^flow_id)
    |> order_by([p], asc: p.tier, asc: p.path)
    |> Repo.all()
  end

  ## Composition proposals (ORC-104, systems/delivery.md)

  @doc """
  Records one computed proposal. Upsert on `(project_id, id)`: the same
  candidate proposed at two successive closes updates one row rather
  than accumulating a duplicate suggestion, which is the failure mode
  the flat backlog view this replaces actually had.
  """
  @spec upsert_container_proposal(map()) :: ContainerProposal.t()
  def upsert_container_proposal(attrs) do
    id = Map.fetch!(attrs, :id)
    project_id = Map.fetch!(attrs, :project_id)
    replace = Map.keys(Map.delete(attrs, :id))

    %ContainerProposal{id: id, project_id: project_id}
    |> Ecto.Changeset.change(attrs)
    |> Repo.insert!(on_conflict: {:replace, replace}, conflict_target: [:project_id, :id])
  end

  @doc "Every proposal computed at `source_container_id`'s close, oldest first."
  @spec container_proposals(binary(), binary()) :: [ContainerProposal.t()]
  def container_proposals(project_id, source_container_id) do
    ContainerProposal
    |> where(
      [p],
      p.project_id == ^project_id and p.source_container_id == ^source_container_id
    )
    |> order_by([p], asc: p.computed_sequence, asc: p.id)
    |> Repo.all()
  end

  @doc """
  Open work items on this project that belong to no container — the
  candidate pool composition filters (v5 §7.8).

  Each is returned with the lifecycle status the feature-ticket
  projection currently holds for it, because `stubbed` is one of the
  structured signals the filter turns on and reading it here is what
  keeps the filter from having to re-derive a status this system
  already projects.
  """
  @spec unscheduled_work_items(binary()) :: [map()]
  def unscheduled_work_items(project_id) do
    EngineFlow
    |> where([f], f.project_id == ^project_id and f.status == :open and is_nil(f.container_id))
    |> join(:left, [f], l in FeatureLifecycle, on: l.project_id == f.project_id and l.id == f.id)
    |> order_by([f, _l], asc: f.opened_sequence, asc: f.id)
    |> select([f, l], %{
      id: f.id,
      ticket_ref: f.ticket_ref,
      flow_name: f.flow_name,
      status_kind: l.status_kind
    })
    |> Repo.all()
  end
end
