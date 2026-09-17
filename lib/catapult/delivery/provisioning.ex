defmodule Catapult.Delivery.Provisioning do
  @moduledoc """
  The milestone boundary's live suite needs a reachable plane to
  provision a test project through, so a dispatched run's context-fetch
  and result-report land in the same database that issued the dispatch
  (`systems/generation.md`'s ORC-216 entry) — this is that surface.

  One authenticated provisioning surface, five operations, a bearer
  secret rather than OIDC (`systems/delivery.md`'s ORC-216 entry: every
  input `Oidc.verify/4` needs comes from a `DispatchRun` row that does
  not exist yet at the moment a provisioning call is made). Each
  operation checks `DELIVERY_PROVISIONING_TOKEN` against the request's
  `Authorization: Bearer` header, constant-time
  (`Plug.Crypto.secure_compare/2`).

  Called from `Catapult.Foundation.DispatchPlug`'s hand-wired path
  dispatch, exactly like `Catapult.Delivery.Dispatch` — a third
  through seventh path on the one listener (`Catapult.Delivery`'s own
  `api_surface/0`).

  - `provision/1` — reclaims every released test project (`systems
    /delivery.md`'s ORC-216 entry: "reset happens before a run, never
    after"), mints a fresh one — `:provisioning`, not yet sweepable
    (ORC-224, `systems/delivery.md`'s companion entry: a test project
    is unsweepable from the moment it is minted) — binds it to the one
    fixture repo this ticket's own scope allows
    (`SwaggerAllen/catapult-test` — "no second bound repo"), resets
    that repo's fixture content from the caller-supplied `files` (the
    live-suite job's own `Catapult.ToySeed.reset_files/0` — this
    module never reads a fixture off its own disk, the same "a fixture
    is the caller's fact, not the port's" rule `HostPort.reset_repo/2`
    already follows), and intakes the raft at the ref reset produced.
    Only once that succeeds does `Store.activate_test_project/1`
    promote the row to `:active` — the point it finally becomes safe
    to sweep. A project that fails to reset or intake is released
    rather than left dangling `:provisioning` — the next `provision/1`
    call reclaims it.
  - `release/2` — releases a test project the caller is done watching.
  - `status/3` — the terminal-status read for a project's most
    recently dispatched run on a tier (`Catapult.Delivery.Store
    .terminal_dispatch_status/2`).
  - `runs/2` — every dispatch run for a project, any tier, oldest
    first (ORC-225, `Catapult.Delivery.Store
    .dispatch_runs_for_project/1`), plus `remaining` (ORC-230): how
    many scopes are still ready to dispatch or already running, read
    directly off the same two readiness queries
    `Catapult.Generation.Sweeper` itself dispatches from
    (`ReadyScopes.ready/3`/`.ready_review/3`) rather than inferred from
    the run set's own shape — the enumerating read the live suite polls
    to tell a chain that finished from one that merely stopped.
  - `approve_drafts/2` — the unattended run's own actor (ORC-230): every
    node currently `:drafted`, across every tier, approved directly via
    `Catapult.Engine.Commands.ApproveDraft` — the only way an unattended
    live-suite run advances past a gate with no human to resolve it. See
    this function's own doc for why it bypasses the ticket-gate path a
    real approval takes.
  """

  import Plug.Conn

  alias Catapult.Config
  alias Catapult.Config.Secret
  alias Catapult.Delivery.Store
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store, as: EngineStore

  # The one fixture repo this ticket's own scope allows binding
  # against (`docs/build-plan.md`'s Phase 4 exit, this ticket's
  # "Explicitly not in scope": "a second bound repo").
  @repo_owner "SwaggerAllen"
  @repo_name "catapult-test"

  # The intake raft's registered discovery path
  # (`Catapult.Delivery.raft_path/0`'s own value) — read here, not
  # through `Catapult.Delivery`, because that module already calls
  # into this one (its `api_surface/0` defexports): a literal
  # reference back would close the cycle `mix xref graph --format
  # cycles --fail-above 0` refuses, the same reasoning
  # `Catapult.Delivery.ResultHandler`'s own moduledoc gives for why
  # `generation` is configured rather than aliased here.
  @raft_path "docs/raft"

  # `approve_drafts/2`'s own actor identity — a literal, not
  # `CatapultWeb.Live.Actor.id/0` (scoped to "every write dispatched
  # from this system's screens", not a boundary surface no screen
  # renders). Reusing `"author"` here would erase the one distinction
  # this ticket exists to keep visible: that an unattended run approved
  # its own drafts.
  @actor_id "live-suite"

  @doc "Mints a fresh test project, bound and reset — see this module's own moduledoc."
  @spec provision(Plug.Conn.t()) :: Plug.Conn.t()
  def provision(conn) do
    with {:ok, conn} <- authenticate(conn),
         {:ok, raw, conn} <- read_body(conn),
         {:ok, files, stub_mode} <- decode_files(raw) do
      Store.list_released_test_projects() |> Enum.each(&Store.delete_test_project/1)

      project_id = Ecto.UUID.generate()
      Store.mint_test_project(project_id, stub_mode)
      Store.put_project_binding(project_id, @repo_owner, @repo_name)

      case reset_and_intake(project_id, files) do
        {:ok, ref} ->
          Store.activate_test_project(project_id)
          json_response(conn, 200, Jason.encode!(%{project_id: project_id, ref: ref}))

        {:error, reason} ->
          # A project that fails to reset or intake is released rather
          # than left dangling `:provisioning` — the next `provision/1`
          # call reclaims it (this module's own moduledoc).
          Store.release_test_project(project_id)
          error_response(conn, 502, reason)
      end
    else
      {:error, reason} -> error_response(conn, status_for(reason), reason)
    end
  end

  defp reset_and_intake(project_id, files) do
    adapter = host_port_adapter()

    with {:ok, ref} <- adapter.reset_repo(project_id, files),
         {:ok, raft_files} <- adapter.read_directory(project_id, ref, @raft_path),
         :ok <- Store.pin_input_documents(project_id, ref, raft_files) do
      {:ok, ref}
    end
  end

  # Same accessor `Catapult.Delivery.host_port_adapter/0` is, read
  # straight off config rather than through that module — see this
  # module's own `@raft_path` note on why.
  defp host_port_adapter, do: Config.fetch!(:delivery, :host_port_adapter)

  # `stub_mode` is optional (ORC-223, `systems/generation.md`'s ORC-223
  # entry): omitting it keeps today's toy-chain behavior — stubbed
  # dispatches — unchanged; `TodoAppProofLiveTest` sends `false`
  # explicitly to run the real model.
  defp decode_files(raw) do
    case Jason.decode(raw) do
      {:ok, %{"files" => files} = payload} when is_map(files) ->
        {:ok, files, Map.get(payload, "stub_mode", true)}

      {:ok, _other} ->
        {:error, :missing_files}

      {:error, _reason} ->
        {:error, :malformed_json}
    end
  end

  @doc "Releases `project_id` — see this module's own moduledoc."
  @spec release(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def release(conn, project_id) do
    case authenticate(conn) do
      {:ok, conn} ->
        Store.release_test_project(project_id)
        json_response(conn, 200, Jason.encode!(%{ok: true}))

      {:error, reason} ->
        error_response(conn, status_for(reason), reason)
    end
  end

  @doc "The terminal-status read for `project_id`'s most recent dispatch run on `tier`."
  @spec status(Plug.Conn.t(), binary(), String.t()) :: Plug.Conn.t()
  def status(conn, project_id, tier) do
    case authenticate(conn) do
      {:ok, conn} ->
        case Store.terminal_dispatch_status(project_id, tier) do
          nil -> error_response(conn, 404, :run_not_found)
          status -> json_response(conn, 200, Jason.encode!(normalize_status(status)))
        end

      {:error, reason} ->
        error_response(conn, status_for(reason), reason)
    end
  end

  defp normalize_status(status) do
    %{
      status: to_string(status.status),
      outcome: status.outcome && to_string(status.outcome),
      credential_used: status.credential_used,
      node_id: status.node_id,
      body_sha: status.body_sha
    }
  end

  @doc "Every dispatch run for `project_id`, any tier, oldest first, plus `remaining` — see this module's own moduledoc."
  @spec runs(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def runs(conn, project_id) do
    case authenticate(conn) do
      {:ok, conn} ->
        runs = project_id |> Store.dispatch_runs_for_project() |> Enum.map(&normalize_run/1)
        body = %{runs: runs, remaining: remaining_count(project_id)}
        json_response(conn, 200, Jason.encode!(body))

      {:error, reason} ->
        error_response(conn, status_for(reason), reason)
    end
  end

  defp normalize_run(run) do
    %{
      run_key: run.run_key,
      tier: run.tier,
      root_tag: run.root_tag,
      status: to_string(run.status),
      outcome: run.outcome && to_string(run.outcome),
      credential_used: run.credential_used,
      node_id: run.node_id,
      body_sha: run.body_sha,
      duration_ms: run.duration_ms
    }
  end

  # `remaining` (ORC-230, this module's own moduledoc): the plane's own
  # current answer to "is there anything left to do", read off the
  # identical two readiness queries `Catapult.Generation.Sweeper`
  # dispatches from (`sweep_tiers/2`) for every tier it would consider —
  # `ReadyScopes.ready/3` (generation-tier readiness) and
  # `.ready_review/3` (review-tier readiness), summed across tiers —
  # minus whatever is already spoken for by an in-flight dispatch (a
  # node still `:absent` while its own run is in flight reads ready
  # exactly as it did before the dispatch fired, so counting it again
  # would double-count the same outstanding work), plus the in-flight
  # count itself. Zero means nothing is dispatchable on either axis and
  # nothing is running. `0` if the bundle fails to load — the sweeper
  # itself skips the tick entirely in that case, so there is nothing
  # this read can answer either.
  defp remaining_count(project_id) do
    case Dsl.load(Config.fetch!(:generation, :bundles_root)) do
      {:ok, %{chain: chain}} ->
        in_flight = Store.in_flight_scope_keys(project_id)

        ready_count =
          chain.tiers
          |> Enum.filter(fn {_name, tier} -> sweeper_dispatchable?(tier) end)
          |> Enum.flat_map(fn {name, _tier} -> ready_scope_keys(chain, project_id, name) end)
          |> Enum.reject(&MapSet.member?(in_flight, &1))
          |> length()

        ready_count + MapSet.size(in_flight)

      {:error, _reason} ->
        0
    end
  end

  # `{tier_name, scope_key}` for every scope `name` would dispatch —
  # `tier_name` is always `name` itself, the same key `Sweeper.enqueue/3`
  # writes into the resulting `DispatchRun` row: for `ready/3` that
  # already matches `node.tier` (a generation-tier candidate's own tier
  # is the tier being asked about), but `ready_review/3` returns nodes
  # off the *reviewed* tier (`Store.list_nodes(project_id, reviewed)`),
  # so its own `node.tier` names the wrong axis — the review dispatch
  # itself runs under `name` (the review tier), never under what it
  # reviews.
  defp ready_scope_keys(chain, project_id, name) do
    (ReadyScopes.ready(chain, project_id, name) ++
       ReadyScopes.ready_review(chain, project_id, name))
    |> Enum.map(&{name, &1.scope_key})
  end

  # Duplicated from `Catapult.Generation.Sweeper`'s own private
  # predicate deliberately — the same "what would the sweeper dispatch"
  # question asked from a different module, on the same footing this
  # file's own `authenticate/1` duplication note already stands on.
  defp sweeper_dispatchable?(%{reviews: reviewed}) when not is_nil(reviewed), do: true
  defp sweeper_dispatchable?(%{draft: draft, generator: "llm"}) when not is_nil(draft), do: true
  defp sweeper_dispatchable?(_tier), do: false

  @doc """
  Approves every node currently `:drafted`, across every tier —
  `ApproveDraft` dispatched directly, bypassing
  `Catapult.Delivery.DraftResolution`'s own `GateApproved` reaction
  entirely (this module's own moduledoc: the unattended run's actor).
  Returns the count approved, so a caller can tell "something moved"
  from "nothing left to approve" — the live suite's own stop condition
  alongside `remaining`.

  Reads no review body and no score: it approves every drafted node it
  finds, unconditionally, so the parked threshold-based-gating
  decision stays parked. Approves; never
  discards — an unattended walk only ever needs to advance.
  """
  @spec approve_drafts(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def approve_drafts(conn, project_id) do
    case authenticate(conn) do
      {:ok, conn} ->
        json_response(conn, 200, Jason.encode!(%{approved: do_approve_drafts(project_id)}))

      {:error, reason} ->
        error_response(conn, status_for(reason), reason)
    end
  end

  defp do_approve_drafts(project_id) do
    case Dsl.load(Config.fetch!(:generation, :bundles_root)) do
      {:ok, %{chain: chain}} ->
        chain.tiers
        |> Map.keys()
        |> Enum.flat_map(&EngineStore.list_nodes(project_id, &1))
        |> Enum.filter(&(&1.status == :drafted))
        |> Enum.count(&approve_node(project_id, &1))

      {:error, _reason} ->
        0
    end
  end

  defp approve_node(project_id, node) do
    command = %ApproveDraft{
      project_id: project_id,
      node_id: node.id,
      draft_id: node.current_draft_id,
      actor_id: @actor_id
    }

    case Router.dispatch(command, consistency: :strong) do
      :ok -> true
      {:error, _reason} -> false
    end
  end

  # Duplicated from `Catapult.Delivery.Dispatch` deliberately — a
  # bearer-secret check and an OIDC verification are different
  # operations reached from different modules, and sharing a helper
  # across them would tangle two auth mechanisms that happen to shape
  # their input the same way.
  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, expected_token()) do
      {:ok, conn}
    else
      _other -> {:error, :unauthorized}
    end
  end

  defp expected_token, do: Secret.unwrap(Config.fetch!(:delivery, :provisioning_token))

  defp json_response(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end

  defp error_response(conn, status, reason) do
    json_response(conn, status, Jason.encode!(%{error: inspect(reason)}))
  end

  defp status_for(:unauthorized), do: 401
  defp status_for(:run_not_found), do: 404
  defp status_for(:missing_files), do: 400
  defp status_for(:malformed_json), do: 400
  defp status_for(_other), do: 400
end
