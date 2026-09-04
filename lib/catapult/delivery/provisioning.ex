defmodule Catapult.Delivery.Provisioning do
  @moduledoc """
  The milestone boundary's live suite needs a reachable plane to
  provision a test project through, so a dispatched run's context-fetch
  and result-report land in the same database that issued the dispatch
  (`systems/generation.md`'s ORC-216 entry) — this is that surface.

  One authenticated provisioning surface, three operations, a bearer
  secret rather than OIDC (`systems/delivery.md`'s ORC-216 entry: every
  input `Oidc.verify/4` needs comes from a `DispatchRun` row that does
  not exist yet at the moment a provisioning call is made). Each
  operation checks `DELIVERY_PROVISIONING_TOKEN` against the request's
  `Authorization: Bearer` header, constant-time
  (`Plug.Crypto.secure_compare/2`).

  Called from `Catapult.Foundation.DispatchPlug`'s hand-wired path
  dispatch, exactly like `Catapult.Delivery.Dispatch` — a third,
  fourth and fifth path on the one listener (`Catapult.Delivery`'s own
  `api_surface/0`).

  - `provision/1` — reclaims every released test project (`systems
    /delivery.md`'s ORC-216 entry: "reset happens before a run, never
    after"), mints a fresh one, binds it to the one fixture repo this
    ticket's own scope allows (`SwaggerAllen/catapult-test` — "no
    second bound repo"), resets that repo's fixture content from the
    caller-supplied `files` (the live-suite job's own
    `Catapult.ToySeed.reset_files/0` — this module never reads a
    fixture off its own disk, the same "a fixture is the caller's
    fact, not the port's" rule `HostPort.reset_repo/2` already
    follows), and intakes the raft at the ref reset produced. A
    project that fails to reset or intake is released rather than left
    dangling `:active` — the next `provision/1` call reclaims it.
  - `release/2` — releases a test project the caller is done watching.
  - `status/3` — the terminal-status read for a project's most
    recently dispatched run on a tier (`Catapult.Delivery.Store
    .terminal_dispatch_status/2`).
  """

  import Plug.Conn

  alias Catapult.Config
  alias Catapult.Config.Secret
  alias Catapult.Delivery.Store

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
          json_response(conn, 200, Jason.encode!(%{project_id: project_id, ref: ref}))

        {:error, reason} ->
          # A project that fails to reset or intake is released rather
          # than left dangling `:active` — the next `provision/1` call
          # reclaims it (this module's own moduledoc).
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
