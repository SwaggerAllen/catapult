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
  alias Catapult.Delivery.Store.InputDocument
  alias Catapult.Delivery.Store.Project
  alias Catapult.Delivery.Store.ProjectBinding
  alias Catapult.Engine.Store.Flow, as: EngineFlow
  alias Catapult.Engine.Store.Node, as: EngineNode
  alias Catapult.Repo

  # Every delivery-owned table keyed by `project_id` — what
  # `delete_test_project/1` purges (`systems/delivery.md`'s ORC-216
  # entry names all eight). `Project` itself is not here: its own row
  # survives deletion as a tombstone.
  @delivery_owned_schemas [
    ProjectBinding,
    DispatchRun,
    InputDocument,
    DraftBody,
    FeatureLifecycle,
    FeaturePublication,
    ContainerProposal,
    ArtifactPush
  ]

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

  @doc """
  Every project id this store has ever bound to a repo — the fact
  `Catapult.Generation.Sweeper` unions with `Catapult.Engine.Store
  .list_project_ids/0` (ORC-216, `systems/generation.md`'s ORC-216
  entry): a freshly provisioned test project has no engine row of its
  own yet (no node has ever been drafted for it), so the engine-only
  enumeration alone would never surface it to a sweep tick.
  """
  @spec list_bound_project_ids() :: [binary()]
  def list_bound_project_ids do
    ProjectBinding |> select([b], b.project_id) |> Repo.all()
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

  @doc """
  Closes out a run correlation record with both the coarse `status`
  this table always had and the two facts ORC-216 added: `outcome`,
  the fine-grained result a result-report actually carried, and
  `credential_used`, the name the harness actually spent
  (`systems/delivery.md`'s ORC-216 entry — "what 'the plane recorded
  it' resolves to, concretely").
  """
  @spec complete_dispatch_run(
          binary(),
          :completed | :failed,
          :success | :limit_class_failure | :other_failure,
          String.t() | nil
        ) :: :ok
  def complete_dispatch_run(run_key, status, outcome, credential_used)
      when status in [:completed, :failed] do
    Repo.update_all(
      from(r in DispatchRun, where: r.id == ^run_key),
      set: [status: status, outcome: outcome, credential_used: credential_used]
    )

    :ok
  end

  @doc """
  `project_id`'s most recently dispatched run on `tier`, terminal-status
  shape — the provisioning surface's own read (ORC-216,
  `systems/delivery.md`'s ORC-216 entry): `status`, `outcome`,
  `credential_used`, `node_id` and the node's own `body_sha` (a plain
  cross-system read through to `Catapult.Engine.Store`, the same shape
  `current_open_flow_id/1` above already uses) — a non-nil `body_sha`
  is what "the committed draft" resolves to. `nil` if `tier` has never
  been dispatched for `project_id`.
  """
  @spec terminal_dispatch_status(binary(), String.t()) :: map() | nil
  def terminal_dispatch_status(project_id, tier) do
    run =
      DispatchRun
      |> where([r], r.project_id == ^project_id and r.tier == ^tier)
      |> order_by([r], desc: r.inserted_at)
      |> limit(1)
      |> Repo.one()

    case run do
      nil ->
        nil

      run ->
        %{
          status: run.status,
          outcome: run.outcome,
          credential_used: run.credential_used,
          node_id: run.node_id,
          body_sha: node_body_sha(project_id, run.node_id)
        }
    end
  end

  defp node_body_sha(_project_id, nil), do: nil

  defp node_body_sha(project_id, node_id) do
    Repo.one(
      from n in EngineNode,
        where: n.project_id == ^project_id and n.id == ^node_id,
        select: n.body_sha
    )
  end

  @doc """
  Every dispatch run for `project_id`, any tier, oldest first — the
  provisioning surface's own enumerating read (ORC-225,
  `systems/delivery.md`'s ORC-225 entry: the live suite's completion
  check needs every run a dispatch window produced, not one tier's).
  `terminal_dispatch_status/2`'s own five keys (`status`, `outcome`,
  `credential_used`, `node_id`, `body_sha`) plus the two facts a
  single-tier caller already knows without asking and an enumerating
  caller does not (`tier`, `root_tag`), and `run_key` — the row's own
  primary key (`insert_dispatch_run/1`'s own doc: "`attrs.id` is the
  plane-minted run_key"), absent from `terminal_dispatch_status/2`'s
  shape because that read is already scoped to one run and never has
  to distinguish it from a sibling; an enumerating caller needs it to
  tell whether the run set it observed has changed between two polls.
  The same rows `dispatch_runs_for_flow/2` already gives one `flow_id`
  at a time, minus the `flow_id` filter.

  `duration_ms` is ORC-230's own addition — `DateTime.diff/3` between
  the row's `updated_at` and `inserted_at`, in milliseconds
  (`systems/delivery.md`'s ORC-230 entry): dispatch-to-terminal, not
  per-phase, since `updated_at` bumps on every status transition and a
  per-phase figure would need columns this ticket does not add. It is
  what turns a flaky boundary run into something measurable rather
  than something re-run by hand.
  """
  @spec dispatch_runs_for_project(binary()) :: [map()]
  def dispatch_runs_for_project(project_id) do
    DispatchRun
    |> where([r], r.project_id == ^project_id)
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(fn run ->
      %{
        run_key: run.id,
        tier: run.tier,
        root_tag: run.root_tag,
        status: run.status,
        outcome: run.outcome,
        credential_used: run.credential_used,
        node_id: run.node_id,
        body_sha: node_body_sha(project_id, run.node_id),
        duration_ms: DateTime.diff(run.updated_at, run.inserted_at, :millisecond)
      }
    end)
  end

  @doc """
  Every `{tier, scope_key}` pair `project_id` currently has an
  in-flight (non-terminal, `status in [:dispatched, :context_fetched]`)
  dispatch run for — `Provisioning.runs/2`'s own `remaining`
  computation (`systems/delivery.md`'s ORC-230 entry): a node still
  `:absent` while its own dispatch is running reads ready per
  `ReadyScopes.ready/3` exactly as it did before the dispatch fired, so
  `remaining` has to know which ready-looking scopes are already
  spoken for rather than counting the same piece of outstanding work
  twice — once as "ready" and once as "running".
  """
  @spec in_flight_scope_keys(binary()) :: MapSet.t({String.t(), map()})
  def in_flight_scope_keys(project_id) do
    DispatchRun
    |> where([r], r.project_id == ^project_id and r.status in [:dispatched, :context_fetched])
    |> select([r], {r.tier, r.scope_key})
    |> Repo.all()
    |> MapSet.new()
  end

  ## Test project lifecycle (ORC-216, systems/delivery.md)

  @doc """
  Mints `project_id` as the one active-or-provisioning test project,
  atomically releasing whichever was active or still provisioning
  before — "at most one active-or-provisioning, by construction of the
  mint operation, not a checked constraint" (`systems/delivery.md`'s
  ORC-216 entry): both halves land in one transaction, so no window
  exists where two rows read `:active` at once, and none where a row a
  crashed provisioning attempt stranded at `:provisioning` survives a
  fresh mint unreleased.

  The new row starts `:provisioning`, not `:active` — ORC-224,
  `systems/delivery.md`'s companion entry: a project is not safe to
  sweep until `activate_test_project/1` promotes it, once whatever
  called this has finished writing it.

  `stub_mode` (ORC-223) is a per-project opt-in, independent of
  test-project status — defaults `true`, the toy-chain's own unchanged
  behavior; the Phase-5 proof run passes `false` explicitly.
  """
  @spec mint_test_project(binary(), boolean()) :: Project.t()
  def mint_test_project(project_id, stub_mode \\ true) do
    {:ok, project} =
      Repo.transaction(fn ->
        Repo.update_all(
          from(p in Project, where: p.test_project_state in [:active, :provisioning]),
          set: [test_project_state: :released]
        )

        %Project{project_id: project_id}
        |> Ecto.Changeset.change(%{test_project_state: :provisioning, stub_mode: stub_mode})
        |> Repo.insert!()
      end)

    project
  end

  @doc """
  Promotes `project_id` from `:provisioning` to `:active` — ORC-224,
  `systems/delivery.md`'s companion entry: `Provisioning.provision/1`
  calls this once `reset_and_intake/2` returns `{:ok, ref}`, the point
  a test project is finally safe to sweep. Matches `project_id` **and**
  `test_project_state == :provisioning`, never `project_id` alone, the
  same transition-names-its-source-state guard `release_test_project/1`
  already carries: a retried or duplicated call finds the row already
  `:released` or `:deleted` and no-ops rather than reviving a terminal
  project.
  """
  @spec activate_test_project(binary()) :: :ok
  def activate_test_project(project_id) do
    Repo.update_all(
      from(p in Project,
        where: p.project_id == ^project_id and p.test_project_state == :provisioning
      ),
      set: [test_project_state: :active]
    )

    :ok
  end

  @doc """
  Releases `project_id` — held for a debugging session, never swept
  again, until the next `delete_test_project/1`. A no-op if
  `project_id` is not currently `:active` or `:provisioning`
  (idempotent — a caller racing its own retry, or releasing a project
  already released, costs nothing). `:provisioning` joins the matched
  set under ORC-224 (`systems/delivery.md`'s companion entry): a
  project that fails to reset or intake is released from whichever
  state `provision/1`'s own failure branch catches it in, and every
  such failure now happens before promotion to `:active`.
  """
  @spec release_test_project(binary()) :: :ok
  def release_test_project(project_id) do
    Repo.update_all(
      from(p in Project,
        where: p.project_id == ^project_id and p.test_project_state in [:active, :provisioning]
      ),
      set: [test_project_state: :released]
    )

    :ok
  end

  @doc """
  Every released test project's id — the boundary's before-run step
  reads this to reclaim them ahead of a fresh mint (`systems/delivery
  .md`'s ORC-216 entry: "reset happens before a run, never after").
  """
  @spec list_released_test_projects() :: [binary()]
  def list_released_test_projects do
    Project
    |> where([p], p.test_project_state == :released)
    |> select([p], p.project_id)
    |> Repo.all()
  end

  @doc """
  Purges every delivery-owned row keyed by `project_id`
  (`@delivery_owned_schemas`) and marks `delivery_projects`'s own row
  `:deleted` — terminal, and the one row not purged, kept as a
  tombstone so a project id is never reused
  (`systems/delivery.md`'s ORC-216 entry). Engine-owned rows and the
  project's own EventStore stream are untouched — a later archive/delete
  design's own scope, not this one's.
  """
  @spec delete_test_project(binary()) :: :ok
  def delete_test_project(project_id) do
    Repo.transaction(fn ->
      Enum.each(@delivery_owned_schemas, fn schema ->
        Repo.delete_all(from(r in schema, where: r.project_id == ^project_id))
      end)

      Repo.update_all(
        from(p in Project, where: p.project_id == ^project_id),
        set: [test_project_state: :deleted]
      )
    end)

    :ok
  end

  @doc """
  Whether `Catapult.Generation.Sweeper` may dispatch for `project_id` —
  `true` for an ordinary project (no row here at all) and for a test
  project whose recorded state is `:active`; `false` for
  `:provisioning`, `:released` or `:deleted` (`systems/generation.md`'s
  ORC-216 and ORC-224 entries — `:provisioning` added by ORC-224, a
  test project reads unsweepable from the moment it is minted, not
  only once released or deleted). A read, not sweeper state: this
  store stays the one state of record for the lifecycle.
  """
  @spec sweepable_project?(binary()) :: boolean()
  def sweepable_project?(project_id) do
    case Repo.get(Project, project_id) do
      nil -> true
      %Project{test_project_state: :active} -> true
      %Project{} -> false
    end
  end

  @doc """
  Whether `project_id`'s dispatches should skip the model (ORC-223,
  `systems/generation.md`'s ORC-223 entry) — a per-project opt-in read
  off the column, never off row presence. `false` for a project with
  no `delivery_projects` row at all: the deliberate mirror of
  `sweepable_project?/1`'s own no-row answer, `true` — the two
  predicates read the same absence in opposite directions, since an
  unbound project is trivially sweepable but must never dispatch
  stubbed.
  """
  @spec stub_mode?(binary()) :: boolean()
  def stub_mode?(project_id) do
    case Repo.get(Project, project_id) do
      nil -> false
      %Project{stub_mode: stub_mode} -> stub_mode
    end
  end

  @doc """
  Whether a non-terminal dispatch already exists for this exact
  `(project_id, tier, scope_key)`, dispatched at or after `cutoff` —
  the in-flight guard's own query (ORC-223, `systems/generation.md`'s
  companion entry: `DispatchWorker`'s fourth re-validation). Age, not
  held state, is what frees a wedged scope: a matching row older than
  `cutoff` answers `false` regardless of its status, with nothing
  writing to it to make that happen.
  """
  @spec in_flight_dispatch?(binary(), String.t(), map(), DateTime.t()) :: boolean()
  def in_flight_dispatch?(project_id, tier, scope_key, cutoff) do
    DispatchRun
    |> where(
      [r],
      r.project_id == ^project_id and r.tier == ^tier and r.scope_key == ^scope_key and
        r.status in [:dispatched, :context_fetched] and r.inserted_at >= ^cutoff
    )
    |> Repo.exists?()
  end

  ## Draft bodies (the review-tier `draft` variable's own cache — see the owning migration)

  @doc """
  Shift-then-write, one previous body rather than a log (ORC-114,
  `systems/delivery.md`): the row's own current `body`/`body_sha` (pre-
  conflict — absent on a first commit) become `previous_body`/
  `previous_body_sha`, then the incoming values become the new current
  ones — one atomic upsert, not a separate read.
  """
  @spec put_draft_body(binary(), binary(), String.t(), String.t()) :: :ok
  def put_draft_body(project_id, node_id, body, body_sha) do
    on_conflict =
      from(d in DraftBody,
        update: [
          set: [
            previous_body: d.body,
            previous_body_sha: d.body_sha,
            body: ^body,
            body_sha: ^body_sha
          ]
        ]
      )

    %DraftBody{project_id: project_id, node_id: node_id}
    |> Ecto.Changeset.change(%{body: body, body_sha: body_sha})
    |> Repo.insert!(on_conflict: on_conflict, conflict_target: [:project_id, :node_id])

    :ok
  end

  @spec get_draft_body(binary(), binary()) :: String.t() | nil
  def get_draft_body(project_id, node_id) do
    case Repo.get_by(DraftBody, project_id: project_id, node_id: node_id) do
      nil -> nil
      %DraftBody{body: body} -> body
    end
  end

  @doc "The prior committed body for `node_id`, or `nil` on a first pass — `document-review`'s own diff source (ORC-114)."
  @spec get_previous_draft_body(binary(), binary()) :: String.t() | nil
  def get_previous_draft_body(project_id, node_id) do
    case Repo.get_by(DraftBody, project_id: project_id, node_id: node_id) do
      nil -> nil
      %DraftBody{previous_body: previous_body} -> previous_body
    end
  end

  ## The intake raft (systems/delivery.md, ORC-107 design pass)

  @doc """
  Pins `files` (filename => content, `HostPort.read_directory/3`'s own
  shape) as `project_id`'s intake raft, tagged per file by its stem
  (Discovery, `systems/delivery.md`) — `project_doc.md` pins under
  role `"project_doc"`. Plain inserts, never an upsert: a project that
  already has a pinned raft raises on the `(project_id, role,
  filename)` primary-key collision rather than silently overwriting a
  frozen document — the entire enforcement behind "at most once per
  project" (v5 §1.1's freeze, `systems/delivery.md`'s intake-pass
  entry). `ref` is `source_ref`, carried for provenance only.
  """
  @spec pin_input_documents(binary(), String.t(), %{String.t() => String.t()}) :: :ok
  def pin_input_documents(project_id, ref, files) do
    Enum.each(files, fn {filename, content} ->
      %InputDocument{project_id: project_id, role: Path.rootname(filename), filename: filename}
      |> Ecto.Changeset.change(%{content: content, source_ref: ref})
      |> Repo.insert!()
    end)

    :ok
  end

  @doc "Every document pinned under `role`, filename order — `input.<role>`'s own read."
  @spec get_input_documents(binary(), String.t()) :: [String.t()]
  def get_input_documents(project_id, role) do
    InputDocument
    |> where([d], d.project_id == ^project_id and d.role == ^role)
    |> order_by([d], asc: d.filename)
    |> select([d], d.content)
    |> Repo.all()
  end

  @doc "Every document pinned on the project, filename order — `input.*`'s own read."
  @spec get_raft(binary()) :: [String.t()]
  def get_raft(project_id) do
    InputDocument
    |> where([d], d.project_id == ^project_id)
    |> order_by([d], asc: d.filename)
    |> select([d], d.content)
    |> Repo.all()
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

  @doc "Every dispatch run correlated to `flow_id` so far, oldest first — `ticket`'s own linked-runs list, beside `get_feature_publication/2`'s linked PR (ORC-114)."
  @spec dispatch_runs_for_flow(binary(), binary()) :: [DispatchRun.t()]
  def dispatch_runs_for_flow(project_id, flow_id) do
    DispatchRun
    |> where([r], r.project_id == ^project_id and r.flow_id == ^flow_id)
    |> order_by([r], asc: r.inserted_at)
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

  ## The work surface's own ticket listing (ORC-114, systems/delivery.md)

  @doc """
  Every open flow on `project_id`, ticket-listing shape — `board`'s
  lanes and `my-queue`'s three action kinds place a ticket from this
  one project-scoped read, not two separate ones. Resolves this
  ticket's own open question in favor of the query landing here and
  the screens staying ORC-75's.

  `argument` is `fields["argument"]` off the node at the flow's own
  `entry_node_id` (the flow's own reserved `fields:` name,
  `chain.md` #38) —
  `nil` until a tier declares it, the same unset-is-empty behavior
  `prior_review` already relies on.
  """
  @spec tickets_for_project(binary()) :: [map()]
  def tickets_for_project(project_id) do
    EngineFlow
    |> where([f], f.project_id == ^project_id and f.status == :open)
    |> join(:left, [f], l in FeatureLifecycle, on: l.project_id == f.project_id and l.id == f.id)
    |> join(:left, [f], n in EngineNode,
      on: n.project_id == f.project_id and n.id == f.entry_node_id
    )
    |> order_by([f, _l, _n], asc: f.opened_sequence, asc: f.id)
    |> select([f, l, n], %{
      id: f.id,
      ticket_ref: f.ticket_ref,
      flow_name: f.flow_name,
      entry_node_id: f.entry_node_id,
      status_kind: l.status_kind,
      status_gate: l.status_gate,
      status_name: l.status_name,
      blocked_origin_kind: l.blocked_origin_kind,
      blocked_origin_gate: l.blocked_origin_gate,
      fields: n.fields
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      argument = row.fields && Map.get(row.fields, "argument")
      row |> Map.delete(:fields) |> Map.put(:argument, argument)
    end)
  end
end
