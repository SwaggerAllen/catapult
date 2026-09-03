defmodule Catapult.Foundation.Failures do
  @moduledoc """
  `GET /failures` (ORC-218, `systems/foundation.md`'s own entry): the
  one read surface beside `/health`, bearer-authenticated against
  `FOUNDATION_OPERATOR_TOKEN` — a foundation-owned secret, not a reuse
  of `Catapult.Delivery`'s `DELIVERY_PROVISIONING_TOKEN`, since that
  token's name says delivery.

  Called from `Catapult.Foundation.DispatchPlug`'s registry-driven
  dispatch over `api_surface/0`, the same mechanism every other route
  on this listener already rides — this is not a second listener.

  Auth is duplicated from `Catapult.Delivery.Provisioning.authenticate/1`
  deliberately, the same reasoning that module's own comment gives: a
  bearer-secret check against a different secret is a different
  operation, not a shared helper away from its one caller.
  """

  import Plug.Conn

  alias Catapult.Config
  alias Catapult.Config.Secret
  alias Catapult.Foundation.FailureLog

  @doc "Renders the buffer's current records as JSON, most recent first — see this module's own moduledoc."
  @spec list(Plug.Conn.t()) :: Plug.Conn.t()
  def list(conn) do
    case authenticate(conn) do
      {:ok, conn} ->
        body = Jason.encode!(%{failures: Enum.map(FailureLog.list(), &render/1)})
        json_response(conn, 200, body)

      {:error, :unauthorized} ->
        json_response(conn, 401, Jason.encode!(%{error: "unauthorized"}))
    end
  end

  defp render(record) do
    %{
      request_id: record.request_id,
      path: record.path,
      status: record.status,
      occurred_at: DateTime.to_iso8601(record.occurred_at),
      stacktrace: record.stacktrace,
      body: record.body
    }
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(token, expected_token()) do
      {:ok, conn}
    else
      _other -> {:error, :unauthorized}
    end
  end

  defp expected_token, do: Secret.unwrap(Config.fetch!(:foundation, :operator_token))

  defp json_response(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, body)
  end
end
