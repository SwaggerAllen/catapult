defmodule Catapult.Foundation.FailureLog do
  @moduledoc """
  The last 50 unhandled exceptions and 5xx responses this listener has
  answered, held in memory and lost on restart by design (ORC-218,
  `systems/foundation.md`'s own entry — read that first for the argument;
  this module is the mechanism it describes).

  Fed off two telemetry events `CatapultWeb.Endpoint` already emits,
  never by instrumenting a call site: `[:phoenix, :endpoint, :stop]`
  (`Plug.Telemetry`, fires on every response as it is sent, whatever
  produced its status) and `[:phoenix, :error_rendered]`
  (`Phoenix.Endpoint.RenderErrors`, fires on anything that raised, with
  the stack trace). Both are attached here, in `init/1`, rather than at
  the call sites the design bullet already argues against re-deriving.

  **Whichever fires first for a given request creates the record; the
  other, if it fires at all, enriches it rather than pushing a second**
  — correlated by `Logger.metadata()[:request_id]`
  (`Plug.RequestId`, ahead of `Plug.Telemetry` in the same pipeline, so
  both handlers run in the request's own process and read the same id
  back). A raise inside a function plug ahead of `CatapultWeb.Router`
  never reaches `:stop` at all (`systems/foundation.md`'s own proof), so
  `:error_rendered` has to be able to create a record alone; a
  non-raising 5xx (`Catapult.Delivery.Provisioning`'s own 502s) never
  raises, so it never reaches `:error_rendered` and `:stop` is its only
  event. The predicate on both is `status >= 500` — never a grep for how
  the status got there.

  A record carries the response body when `:stop` supplied one, capped
  at `@body_limit`. That is the only place a deliberate 5xx says *why*:
  it has no stack trace, and the reason it writes into its own body
  never reaches a caller, because the platform replaces the body of an
  upstream 502 with its own error page.

  No `max_heap_size:` guardrail: there is no default to fall back on
  (`Catapult.Guardrails.enforceable/0` applies only what a `processes/0`
  entry names), and 50 small records bounded in count is not the case
  the incident this ticket answers argues needs one.
  """
  use GenServer

  require Logger

  alias Catapult.Config

  @limit 50
  @name :foundation_failure_log
  @events [[:phoenix, :endpoint, :stop], [:phoenix, :error_rendered]]

  # A 5xx the plane produced deliberately carries its reason in the
  # response body and nowhere else: `Catapult.Delivery.Provisioning`'s
  # own 502 answers `{"error": inspect(reason)}` and never raises, so
  # there is no stack trace to fall back on. App Platform replaced the
  # body of an upstream 502 with its own error page before a caller
  # sees it, which makes the reason unreachable from outside the
  # container — five live-suite runs were spent reading "App Platform
  # failed to forward this request to the application" as an
  # infrastructure fault while the plane had in fact answered and said
  # why. Measured on App Platform; nobody has read whether Render's edge
  # does the same, and the rule stands either way — `:stop` costs nothing
  # if the body survives, and the reason is unreachable if it does not. The body is only readable on `:stop`, and only because
  # `Plug.Telemetry` fires it from a `register_before_send` callback:
  # `Plug.Conn.send_resp/1` runs those before handing the body to the
  # adapter, then sets `resp_body` to whatever the adapter returns —
  # `nil` under `Plug.Cowboy`. Reading it anywhere later would find
  # nothing in production while still passing under `Plug.Test`'s
  # adapter, which returns the body instead.
  @body_limit 2_048

  @doc "Starts the buffer, registered under `:foundation_failure_log` (`Catapult.Foundation.processes/0`) unless `opts` names a different `:name`."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc "The buffer's current records, most recent first."
  @spec list(GenServer.server()) :: [map()]
  def list(server \\ @name), do: GenServer.call(server, :list)

  @impl GenServer
  def init(name) do
    :telemetry.attach_many(handler_id(name), @events, &__MODULE__.handle_event/4, name)
    {:ok, %{name: name, records: []}}
  end

  @impl GenServer
  def terminate(_reason, %{name: name}), do: :telemetry.detach(handler_id(name))

  @impl GenServer
  def handle_call(:list, _from, state), do: {:reply, state.records, state}

  @impl GenServer
  def handle_cast({:record, request_id, path, status, stacktrace, body, occurred_at}, state) do
    records = store(state.records, request_id, path, status, stacktrace, body, occurred_at)
    {:noreply, %{state | records: records}}
  end

  defp store(records, request_id, path, status, stacktrace, body, occurred_at) do
    case find_index(records, request_id) do
      nil ->
        record = %{
          request_id: request_id,
          path: path,
          status: status,
          stacktrace: stacktrace,
          body: body,
          occurred_at: occurred_at
        }

        Enum.take([record | records], @limit)

      index ->
        List.update_at(
          records,
          index,
          &%{&1 | stacktrace: &1.stacktrace || stacktrace, body: &1.body || body}
        )
    end
  end

  # A `nil` request id (no `Plug.RequestId` metadata to correlate by)
  # never matches another `nil` — each such event is its own record
  # rather than an arbitrary merge of unrelated failures.
  defp find_index(_records, nil), do: nil

  defp find_index(records, request_id) do
    Enum.find_index(records, &(&1.request_id == request_id))
  end

  defp handler_id(name), do: {__MODULE__, name}

  @doc false
  def handle_event([:phoenix, :endpoint, :stop], _measurements, %{conn: conn}, name) do
    maybe_record(name, conn.status, conn.request_path, nil, response_body(conn))
  end

  # `:error_rendered` fires before the error response is built, so
  # there is no body to read on this event — the trace is what it
  # carries, and the body arrives from `:stop` when that fires too.
  def handle_event([:phoenix, :error_rendered], _measurements, metadata, name) do
    stacktrace = Exception.format(metadata.kind, metadata.reason, metadata.stacktrace)
    maybe_record(name, metadata.status, metadata.conn.request_path, stacktrace, nil)
  end

  # `resp_body` is iodata, and nil on a chunked response — nothing was
  # buffered for a before_send callback to read. Truncated by
  # graphemes rather than bytes, and only once the binary is known to
  # be valid UTF-8: a body cut mid-codepoint would make `Jason.encode!`
  # raise in `Catapult.Foundation.Failures.list/1` and take the whole
  # read surface down with it, which is the opposite of this record's
  # job.
  defp response_body(%{resp_body: nil}), do: nil

  defp response_body(%{resp_body: body}) do
    binary = IO.iodata_to_binary(body)

    cond do
      not String.valid?(binary) -> nil
      byte_size(binary) > @body_limit -> String.slice(binary, 0, @body_limit)
      true -> binary
    end
  rescue
    ArgumentError -> nil
  end

  defp response_body(_conn), do: nil

  defp maybe_record(name, status, path, stacktrace, body)
       when is_integer(status) and status >= 500 do
    request_id = Logger.metadata()[:request_id]
    occurred_at = Config.fetch!(:foundation, :clock).utc_now()
    GenServer.cast(name, {:record, request_id, path, status, stacktrace, body, occurred_at})
  end

  defp maybe_record(_name, _status, _path, _stacktrace, _body), do: :ok
end
