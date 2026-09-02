defmodule Catapult.Delivery.Dispatch do
  @moduledoc """
  The inbound half of the host port's dispatch-facing slice
  (`systems/generation.md`, `systems/delivery.md`; v5 §7.12.1):
  context-fetch and result-report, both OIDC-authenticated and
  correlated against `Catapult.Delivery.Store`'s dispatch-run record.
  Called from `Catapult.Foundation.DispatchPlug`'s hand-wired path
  dispatch — plain functions, not a router, so nothing here adds a
  macro-time dependency between foundation and this component
  (`systems/foundation.md`'s design note).

  `report_result/2`'s domain half (`simulate_result/2`) is shared with
  `Catapult.Delivery.HostPort.Fake`, which calls it directly with no
  `conn` and no OIDC round trip — the offline chain a real inbound
  call would otherwise be the only way to exercise.
  """

  import Plug.Conn

  alias Catapult.Delivery.Oidc
  alias Catapult.Delivery.Store

  @doc "Serves the rendered context for `run_key` — GET, OIDC-authenticated."
  @spec fetch_context(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def fetch_context(conn, run_key) do
    with {:ok, run} <- find_run(run_key),
         {:ok, token} <- bearer_token(conn),
         {:ok, claims} <- Oidc.verify(token, run.repo_owner, run.repo_name, run.github_run_id),
         :ok <- bind_run_id(run, claims) do
      body = Jason.encode!(%{root_tag: run.root_tag, prompt: run.rendered_prompt})
      json_response(conn, 200, body)
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  @doc "Accepts a run's result — POST, OIDC-authenticated. See `simulate_result/2` for the shared payload shape."
  @spec report_result(Plug.Conn.t(), binary()) :: Plug.Conn.t()
  def report_result(conn, run_key) do
    with {:ok, run} <- find_run(run_key),
         {:ok, token} <- bearer_token(conn),
         {:ok, claims} <- Oidc.verify(token, run.repo_owner, run.repo_name, run.github_run_id),
         :ok <- bind_run_id(run, claims),
         {:ok, raw, conn} <- read_body(conn),
         {:ok, payload} <- Jason.decode(raw),
         {:ok, result} <- validate_result(atomize_result(payload)) do
      case simulate_result(run_key, result) do
        :ok -> json_response(conn, 200, Jason.encode!(%{ok: true}))
        {:error, reason} -> error_response(conn, reason)
      end
    else
      {:error, reason} -> error_response(conn, reason)
    end
  end

  @doc """
  The domain half of a result-report, independent of any `conn` or
  OIDC round trip — what `report_result/2` calls after authenticating,
  and what `Catapult.Delivery.HostPort.Fake` calls directly to drive
  the exact same commit path offline (conventions §9).
  """
  @spec simulate_result(binary(), Catapult.Delivery.ResultHandler.payload()) ::
          :ok | {:error, term()}
  def simulate_result(run_key, result) do
    with {:ok, run} <- find_run(run_key) do
      payload =
        result
        |> Map.take([:status, :body, :reason, :credential_used])
        |> Map.merge(%{
          project_id: run.project_id,
          node_id: run.node_id,
          tier: run.tier,
          scope_key: run.scope_key,
          run_key: run_key
        })

      case result_handler().handle_result(payload) do
        :ok -> mark_terminal(run_key, payload)
        {:error, _reason} = error -> mark_failure(run_key, payload, error)
      end
    end
  end

  # A successful commit is terminal; a successfully *recorded*
  # limit-class/other failure is terminal too — there is no
  # same-run retry for either, only the readiness query redispatching
  # the scope later. Only a `:success` report that the handler
  # rejected (grammar-invalid) stays in flight: that is the "typed
  # error the agent retries with, bounded within the same run"
  # (`systems/generation.md`) — a further `report_result/2` call for
  # the same `run_key` is expected next, so the record is left exactly
  # as `bind_run_id/2` already left it.
  defp mark_terminal(run_key, payload) do
    Store.complete_dispatch_run(run_key, :completed, payload.status, payload.credential_used)
    :ok
  end

  defp mark_failure(_run_key, %{status: :success}, error), do: error

  defp mark_failure(run_key, payload, error) do
    Store.complete_dispatch_run(run_key, :failed, payload.status, payload.credential_used)
    error
  end

  defp result_handler do
    Application.fetch_env!(:catapult, :generation_result_handler)
  end

  defp find_run(run_key) do
    case Store.get_dispatch_run(run_key) do
      nil -> {:error, :run_not_found}
      run -> {:ok, run}
    end
  end

  defp bind_run_id(%{github_run_id: nil} = run, claims) do
    Store.bind_github_run_id(run.id, Map.fetch!(claims, "run_id"))
  end

  defp bind_run_id(_run, _claims), do: :ok

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> {:ok, token}
      _other -> {:error, :missing_bearer}
    end
  end

  # Picks only the known result fields — an untrusted POST body naming
  # anything else is ignored rather than fed to `to_existing_atom`,
  # which would otherwise crash the request instead of failing it
  # cleanly.
  defp atomize_result(%{} = payload) do
    %{
      status: status_atom(Map.get(payload, "status")),
      body: Map.get(payload, "body"),
      reason: Map.get(payload, "reason"),
      credential_used: Map.get(payload, "credential_used")
    }
  end

  defp status_atom("success"), do: :success
  defp status_atom("limit_class_failure"), do: :limit_class_failure
  defp status_atom("other_failure"), do: :other_failure
  defp status_atom(other), do: {:invalid_status, other}

  defp validate_result(%{status: status} = result)
       when status in [:success, :limit_class_failure, :other_failure],
       do: {:ok, result}

  defp validate_result(%{status: invalid}), do: {:error, invalid}

  defp json_response(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end

  defp error_response(conn, reason) do
    json_response(conn, status_for(reason), Jason.encode!(%{error: inspect(reason)}))
  end

  defp status_for(:run_not_found), do: 404
  defp status_for(:missing_bearer), do: 401
  defp status_for({:repository_mismatch, _}), do: 403
  defp status_for({:run_id_mismatch, _}), do: 403
  defp status_for({:schema_invalid, _}), do: 422
  defp status_for({:root_tag_mismatch, _}), do: 422
  defp status_for({:malformed_xml, _}), do: 422
  defp status_for({:schema_not_found, _}), do: 422
  defp status_for(_other), do: 400
end
