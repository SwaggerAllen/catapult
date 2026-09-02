defmodule Catapult.Delivery do
  @moduledoc """
  The protocol plane (`systems/delivery.md`): the host port's
  dispatch-facing slice pulled forward into Phase 3 with the
  generation executor (ORC-9) — context-fetch, result-report, OIDC
  validation, run correlation, and the Actions adapter + in-memory
  fake. The rest of the host port (feature-lifecycle PR management,
  decline harvesting) is Phase 4.
  """

  use Catapult.Component, slug: :delivery

  alias Catapult.Config.Secret
  alias Catapult.Delivery.Dispatch
  alias Catapult.Delivery.Provisioning
  alias Catapult.Delivery.Store

  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def config do
    [
      # The operator's own GitHub credential (a fine-grained PAT or
      # GitHub App installation token) for calling the Actions API —
      # distinct from the customer-side model credentials named in v5
      # §7.12.1, which the plane never holds at all.
      {:github_token, "DELIVERY_GITHUB_TOKEN", cast: :string, secret: true},
      {:dispatch_workflow_file, "DELIVERY_DISPATCH_WORKFLOW_FILE",
       cast: :string, default: "catapult-dispatch.yml"},
      {:dispatch_ref, "DELIVERY_DISPATCH_REF", cast: :string, default: "main"},
      # Real-vs-fake adapter selection rides config like every other
      # external in this codebase (v5 §2.12), not a build-shape
      # constant: `Catapult.Delivery.HostPort.Actions` in dev/prod,
      # `.Fake` in test (`config/test.exs`).
      {:host_port_adapter, "DELIVERY_HOST_PORT_ADAPTER",
       cast: &__MODULE__.cast_adapter/1, default: "actions"},
      {:oidc_audience, "DELIVERY_OIDC_AUDIENCE", cast: :string, default: "catapult"},
      # The provisioning surface's bearer secret (ORC-216,
      # `Catapult.Delivery.Provisioning`) — no default, so a build
      # missing it fails at boot naming it, the same shape
      # `:github_token` above already has.
      {:provisioning_token, "DELIVERY_PROVISIONING_TOKEN", cast: :string, secret: true},
      {:oidc_jwks_url, "DELIVERY_OIDC_JWKS_URL",
       cast: :string, default: "https://token.actions.githubusercontent.com/.well-known/jwks"},
      # `false` in test (`config/test.exs`): the strategy process still
      # starts and is structurally exercised, but never fetches over
      # the network — the default suite's chain never reaches it
      # anyway, since the fake host port bypasses HTTP/OIDC entirely
      # (conventions §9).
      {:oidc_jwks_autostart, "DELIVERY_OIDC_JWKS_AUTOSTART", cast: :boolean, default: "true"},
      # Same real-vs-fake selection the host port already rides (v5
      # §2.12), for the flag port a container's aggregated flip goes
      # out through. The default is `deferred`, not a no-op: conventions
      # §13 defers flag consumption, and
      # `Catapult.Delivery.FlagSet.Deferred` records the intent and
      # refuses to claim an effect it did not have, which is what keeps
      # v5 §7.1's "the log never says 'done' on the plane's own word"
      # literal while that deferral stands.
      {:flag_set_adapter, "DELIVERY_FLAG_SET_ADAPTER",
       cast: &__MODULE__.cast_flag_set_adapter/1, default: "deferred"}
    ]
  end

  @doc "Casts the configured flag-set implementation name to its module."
  @spec cast_flag_set_adapter(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_flag_set_adapter("deferred"), do: {:ok, Catapult.Delivery.FlagSet.Deferred}
  def cast_flag_set_adapter("fake"), do: {:ok, Catapult.Delivery.FlagSet.Fake}

  def cast_flag_set_adapter(other),
    do: {:error, "is #{inspect(other)}, expected \"deferred\" or \"fake\""}

  @doc "Casts the configured adapter name to its module."
  @spec cast_adapter(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_adapter("actions"), do: {:ok, Catapult.Delivery.HostPort.Actions}
  def cast_adapter("fake"), do: {:ok, Catapult.Delivery.HostPort.Fake}
  def cast_adapter(other), do: {:error, "is #{inspect(other)}, expected \"actions\" or \"fake\""}

  @impl Catapult.Component
  def api_surface do
    [
      # Collision-checked and shaped like every other route this
      # platform will ever declare (`systems/foundation.md`'s design
      # note) — the general composed router waits for dashboard's
      # Phase 4/7 web layer, so what actually serves these paths today
      # is `Catapult.Foundation.DispatchPlug`'s hand-wired dispatch,
      # not this registry. `:partner` audience: reached by a runner
      # acting on the project's behalf, never end users.
      {{:fetch_context, 2}, :get, "/dispatch/context/:run_key",
       version: "v1", audience: :partner},
      {{:report_result, 2}, :post, "/dispatch/report/:run_key",
       version: "v1", audience: :partner},
      # ORC-216: the provisioning surface — a third, fourth and fifth
      # path on this one listener, `:internal` audience since these
      # are reached only by the milestone boundary's own live-suite
      # job, bearer-authenticated rather than OIDC
      # (`Catapult.Delivery.Provisioning`'s own moduledoc).
      {{:provision_test_project, 1}, :post, "/dispatch/test-project",
       version: "v1", audience: :internal},
      {{:release_test_project, 2}, :post, "/dispatch/test-project/:project_id/release",
       version: "v1", audience: :internal},
      {{:test_project_dispatch_status, 3}, :get,
       "/dispatch/test-project/:project_id/status/:tier", version: "v1", audience: :internal}
    ]
  end

  @impl Catapult.Component
  def processes do
    [
      {:delivery_oidc_strategy, :singleton},
      # Same placement `engine_projector` uses, for the same reason
      # (`Catapult.Delivery.FeatureLifecycle`'s own moduledoc): a
      # Commanded subscription is consumed once, in order, cluster-wide.
      {:delivery_feature_lifecycle, :singleton},
      # `:singleton` for the stronger of the two reasons: this one
      # *writes*. Two instances reading the same stream would each
      # compute a container's next move and each dispatch it — the
      # second losing to the first's compare-and-swap, but only after
      # both had already decided. One consumer, cluster-wide.
      {:delivery_container_lifecycle, :singleton},
      # Same placement and the same reason as its siblings above: a
      # Commanded subscription is consumed once, in order, cluster-wide
      # (`Catapult.Delivery.FeaturePublisher`'s own moduledoc, ORC-33).
      {:delivery_feature_publisher, :singleton}
    ]
  end

  @impl Catapult.Component
  def oban_queues do
    # The outbox queue a container's aggregated flag flip executes on
    # (v5 §7.1's intent -> idempotent effect -> observed completion).
    # Its own queue rather than a shared one: an external effect that
    # retries must not sit behind generation dispatch's concurrency
    # budget, and the queue registry is where an operator looks to see
    # that it exists at all. `delivery_feature_publish` is
    # `Catapult.Delivery.FeaturePublishWorker`'s own outbox for the
    # same reason (ORC-33); its concurrency is set in `config/config
    # .exs`, not here — this list only claims the name.
    [:delivery_flag_flip, :delivery_feature_publish]
  end

  @impl Catapult.Component
  def children do
    [
      {Catapult.Delivery.Oidc.Strategy, []},
      Catapult.Delivery.FeatureLifecycle,
      Catapult.Delivery.ContainerLifecycle,
      Catapult.Delivery.FeaturePublisher
    ]
  end

  @doc "The configured host port adapter — `Catapult.Delivery.HostPort.Actions` or `.Fake`."
  @spec host_port_adapter() :: module()
  def host_port_adapter, do: Catapult.Config.fetch!(:delivery, :host_port_adapter)

  @doc "Unwrapped for the one call site that needs it (`Catapult.Delivery.HostPort.Actions`)."
  @spec github_token() :: Secret.t()
  def github_token, do: Catapult.Config.fetch!(:delivery, :github_token)

  @doc "A committed draft's raw body, cached for the review-tier `draft` variable (`Catapult.Delivery.Store.DraftBody`)."
  @spec get_draft_body(binary(), binary()) :: String.t() | nil
  def get_draft_body(project_id, node_id), do: Store.get_draft_body(project_id, node_id)

  @doc "Caches a committed draft's raw body — see `get_draft_body/2`."
  @spec put_draft_body(binary(), binary(), String.t(), String.t()) :: :ok
  def put_draft_body(project_id, node_id, body, body_sha),
    do: Store.put_draft_body(project_id, node_id, body, body_sha)

  # The intake raft's registered path (`systems/delivery.md`'s
  # Discovery entry) — a fixed platform-wide path, not a per-project
  # setting, on the same footing `reset_repo/2`'s own workflow-dispatch
  # file already stands on.
  @raft_path "docs/raft"

  @doc """
  The raft's registered discovery path — the one fact a future
  base-check sweep needs to recognize "a diff under a registered input
  path" (v5 §1.1's frozen-edit notice, `systems/delivery.md`'s ORC-107
  entry: this ticket delivers the fact, not the sweep). A future
  caller reads this rather than re-deriving the literal path.
  """
  @spec raft_path() :: String.t()
  def raft_path, do: @raft_path

  @doc """
  Intake, the one legal call per project (`systems/delivery.md`'s
  ORC-107 entry): reads every file directly under the raft's
  registered path off the bound repo at `ref` and pins each one via
  `pin_input_documents/3` — a second call for a project that already
  has a pinned raft raises there, rather than silently re-pinning.
  What decides when to call this — a project's creation/scaffold flow
  — is out of this ticket's scope; this is the mechanism a future
  caller drives.
  """
  @spec intake_raft(binary(), String.t()) :: :ok | {:error, term()}
  def intake_raft(project_id, ref) do
    with {:ok, files} <- host_port_adapter().read_directory(project_id, ref, raft_path()) do
      pin_input_documents(project_id, ref, files)
    end
  end

  @doc "Pins `files` (filename => content) as the intake raft — `intake_raft/2`'s own write, see there."
  @spec pin_input_documents(binary(), String.t(), %{String.t() => String.t()}) :: :ok
  def pin_input_documents(project_id, ref, files),
    do: Store.pin_input_documents(project_id, ref, files)

  @doc "A role's pinned intake documents, filename order — `input.<role>`'s own read (ORC-107)."
  @spec get_input_documents(binary(), String.t()) :: [String.t()]
  def get_input_documents(project_id, role), do: Store.get_input_documents(project_id, role)

  @doc "Every pinned intake document on the project, filename order — `input.*`'s own read (ORC-107)."
  @spec get_raft(binary()) :: [String.t()]
  def get_raft(project_id), do: Store.get_raft(project_id)

  @doc """
  Unwrapped for the one call site that needs it — the milestone
  boundary's live suite, sending it as the provisioning surface's own
  bearer token (`Catapult.Generation.ToySeedChainLiveTest`).
  `Catapult.Delivery.Provisioning` itself reads the same declared
  value straight off config rather than through this accessor, since
  it is already the callee of this module's own defexports and a call
  back here would close the cycle `mix xref graph --format cycles
  --fail-above 0` refuses.
  """
  @spec provisioning_token() :: Secret.t()
  def provisioning_token, do: Catapult.Config.fetch!(:delivery, :provisioning_token)

  @doc """
  Every project id this store has ever bound to a repo —
  `Catapult.Generation.Sweeper`'s own union with the engine's
  enumeration (`Catapult.Delivery.Store.list_bound_project_ids/0`, ORC-216).
  """
  @spec list_bound_project_ids() :: [binary()]
  def list_bound_project_ids, do: Store.list_bound_project_ids()

  @doc """
  Whether `Catapult.Generation.Sweeper`/`Catapult.Generation
  .DispatchWorker` may dispatch for `project_id` right now — the
  test-project lifecycle's own read (`Catapult.Delivery.Store
  .sweepable_project?/1`, ORC-216).
  """
  @spec sweepable_project?(binary()) :: boolean()
  def sweepable_project?(project_id), do: Store.sweepable_project?(project_id)

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Dispatch.fetch_context/2`."
  @spec fetch_context(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defexport(fetch_context(conn, run_key), do: Dispatch.fetch_context(conn, run_key))

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Dispatch.report_result/2`."
  @spec report_result(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defexport(report_result(conn, run_key), do: Dispatch.report_result(conn, run_key))

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Provisioning.provision/1`."
  @spec provision_test_project(Plug.Conn.t()) :: Plug.Conn.t()
  defexport(provision_test_project(conn), do: Provisioning.provision(conn))

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Provisioning.release/2`."
  @spec release_test_project(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  defexport(release_test_project(conn, project_id), do: Provisioning.release(conn, project_id))

  @doc "Boundary export backing the `api_surface/0` declaration above — see `Catapult.Delivery.Provisioning.status/3`."
  @spec test_project_dispatch_status(Plug.Conn.t(), binary(), String.t()) :: Plug.Conn.t()
  defexport(test_project_dispatch_status(conn, project_id, tier),
    do: Provisioning.status(conn, project_id, tier)
  )
end
