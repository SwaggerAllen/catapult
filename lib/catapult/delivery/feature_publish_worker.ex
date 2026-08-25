defmodule Catapult.Delivery.FeaturePublishWorker do
  @moduledoc """
  The outbox worker for a flow's feature branch and PR
  (`systems/delivery.md`'s ORC-33 entry) — enqueued by
  `Catapult.Delivery.FeaturePublisher` on every `DraftCommitted`, the
  same "intent already in the log, effect via Oban retry-safe" shape
  `Catapult.Delivery.FlagSetWorker` already takes, adapted to this
  effect's own completion fact: whether a node's body has reached git
  is `Catapult.Delivery.Store.ArtifactPush`'s own bookkeeping, never an
  engine command — nothing on the other side of the aggregate boundary
  reasons about it (`Catapult.Delivery.FeaturePublisher`'s own
  moduledoc).

  **Re-validates before acting**, the same discipline
  `Catapult.Generation.DispatchWorker` already applies to a sweeper's
  hint: a node already pushed at the exact `body_sha` this job carries
  is a no-op, so a re-enqueue (a retried job, or a second commit
  landing before the first job ran) never re-pushes identical content.

  **Idempotency, and its accepted edge**: `body_sha` is the one this
  job's own triggering event carried, not re-read from the store at
  execution time — the current draft body is always re-read fresh
  (`fetch_body/2`, so the content pushed is never stale), but a node
  committed twice in quick succession, while the first job for it is
  still `incomplete`, collapses into one job under this worker's own
  `unique` key. That job pushes whatever the store holds when it
  finally runs — the second commit's content, not the first's — so
  nothing is lost; only the intermediate state's own row in
  `delivery_artifact_pushes` is never separately observed. The
  identical simplification `Catapult.Generation.DispatchWorker`'s own
  moduledoc already names for a re-swept scope.

  **Branch/PR creation is serialized** (`config/config.exs`'s
  `delivery_feature_publish: 1` queue concurrency, the same choice
  already made for `Catapult.Delivery.FlagSetWorker`'s queue): two
  nodes in the same flow committing close together must not each find
  no `Catapult.Delivery.Store.FeaturePublication` row and each open a
  branch and a PR. A concurrency-1 queue is cheap here — pushing
  artifacts is not latency-sensitive — and avoids the alternative,
  which is a database-level compare-and-swap this ticket does not need
  to build.
  """

  use Oban.Worker,
    queue: :delivery_feature_publish,
    unique: [period: :infinity, keys: [:project_id, :node_id], states: :incomplete]

  require Logger

  alias Catapult.Config
  alias Catapult.Delivery.Store
  alias Catapult.Delivery.Store.ArtifactPush
  alias Catapult.Delivery.Store.FeaturePublication

  @base_ref "main"
  @slug_length 40

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    job = %{
      project_id: Map.fetch!(args, "project_id"),
      flow_id: Map.fetch!(args, "flow_id"),
      ticket_ref: Map.fetch!(args, "ticket_ref"),
      flow_name: Map.fetch!(args, "flow_name"),
      node_id: Map.fetch!(args, "node_id"),
      tier: Map.fetch!(args, "tier"),
      scope_key: Map.fetch!(args, "scope_key"),
      body_sha: Map.fetch!(args, "body_sha")
    }

    if already_pushed?(job) do
      :ok
    else
      publish(job)
    end
  end

  @doc "Enqueues the push for a freshly committed draft."
  @spec enqueue(map()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(args), do: args |> new() |> Oban.insert()

  defp already_pushed?(%{project_id: project_id, node_id: node_id, body_sha: body_sha}) do
    match?(%ArtifactPush{body_sha: ^body_sha}, Store.get_artifact_push(project_id, node_id))
  end

  defp publish(job) do
    with {:ok, publication} <- ensure_publication(job),
         {:ok, body} <- fetch_body(job.project_id, job.node_id),
         path = artifact_path(job.tier, job.node_id),
         :ok <- push_file(job, publication.branch_name, path, body),
         _push <-
           Store.upsert_artifact_push(%{
             project_id: job.project_id,
             node_id: job.node_id,
             flow_id: job.flow_id,
             tier: job.tier,
             scope_key: job.scope_key,
             path: path,
             body_sha: job.body_sha
           }),
         :ok <- regenerate_pr_body(job.project_id, job.flow_id, publication) do
      :ok
    else
      {:error, reason} = error ->
        Logger.warning(
          "feature publish did not complete for #{job.project_id}/#{job.node_id}: #{inspect(reason)}",
          component: :delivery
        )

        error
    end
  end

  defp ensure_publication(%{project_id: project_id, flow_id: flow_id} = job) do
    case Store.get_feature_publication(project_id, flow_id) do
      %FeaturePublication{} = publication -> {:ok, publication}
      nil -> open_publication(job)
    end
  end

  defp open_publication(%{project_id: project_id, flow_id: flow_id} = job) do
    adapter = Config.fetch!(:delivery, :host_port_adapter)
    branch = branch_name(job.ticket_ref, flow_id)

    with :ok <- create_branch(adapter, project_id, branch),
         {:ok, pr} <- open_pr(adapter, project_id, branch, job) do
      {:ok,
       Store.upsert_feature_publication(%{
         id: flow_id,
         project_id: project_id,
         branch_name: branch,
         base_ref: @base_ref,
         pr_number: pr.number
       })}
    end
  end

  # A retry that lands after `create_branch/3` already succeeded (but
  # before the publication row was written) must not fail loudly on
  # GitHub's own "reference already exists" — this is the one place
  # that retry gap is visible, and it is absorbed rather than treated
  # as a new failure.
  defp create_branch(adapter, project_id, branch) do
    case adapter.create_branch(project_id, @base_ref, branch) do
      :ok -> :ok
      {:error, {:create_branch_failed, 422, _body}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_pr(adapter, project_id, branch, job) do
    request = %{
      head: branch,
      base: @base_ref,
      title: pr_title(job.ticket_ref, job.flow_name),
      body: "_No artifacts committed yet._"
    }

    adapter.open_pr(project_id, request)
  end

  defp pr_title(nil, flow_name), do: "#{flow_name} artifact set"
  defp pr_title(ticket_ref, flow_name), do: "#{ticket_ref}: #{flow_name} artifact set"

  defp branch_name(ticket_ref, flow_id), do: "feature/#{slugify(ticket_ref)}-#{flow_id}"

  defp slugify(nil), do: "flow"

  defp slugify(text) do
    case text |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-") do
      "" -> "flow"
      slug -> String.slice(slug, 0, @slug_length)
    end
  end

  defp fetch_body(project_id, node_id) do
    case Store.get_draft_body(project_id, node_id) do
      nil -> {:error, {:no_draft_body, project_id, node_id}}
      body -> {:ok, body}
    end
  end

  # The named placeholder `systems/delivery.md`'s ORC-33 entry records:
  # no tier declares a target-repo location for its own draft yet, so
  # this is namespaced to collide with nothing a hand-authored project
  # file would ever be named, mechanically derivable from fields this
  # worker already has in hand.
  defp artifact_path(tier, node_id), do: ".catapult/artifacts/#{tier}/#{node_id}.xml"

  defp push_file(job, branch, path, body) do
    adapter = Config.fetch!(:delivery, :host_port_adapter)
    message = "catapult: commit #{job.tier} #{job.node_id}"
    adapter.commit_files(job.project_id, branch, %{path => body}, message)
  end

  # Regenerated whole, never appended to (`systems/delivery.md`'s
  # ORC-33 entry): a full rewrite means a re-processed event or a
  # retried push can never leave a duplicate or a stale line.
  defp regenerate_pr_body(project_id, flow_id, publication) do
    adapter = Config.fetch!(:delivery, :host_port_adapter)
    body = render_body(Store.artifact_pushes_for_flow(project_id, flow_id))
    adapter.update_pr_body(project_id, publication.pr_number, body)
  end

  defp render_body([]), do: "_No artifacts committed yet._"

  defp render_body(pushes) do
    Enum.map_join(pushes, "\n", fn push ->
      "- `#{push.tier}` #{scope_summary(push.scope_key)} → [`#{push.path}`](#{push.path})"
    end)
  end

  defp scope_summary(scope_key) when scope_key == %{}, do: ""
  defp scope_summary(scope_key), do: "(`#{inspect(scope_key)}`)"
end
