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
  def handle_cast({:record, request_id, path, status, stacktrace, occurred_at}, state) do
    {:noreply,
     %{state | records: store(state.records, request_id, path, status, stacktrace, occurred_at)}}
  end

  defp store(records, request_id, path, status, stacktrace, occurred_at) do
    case find_index(records, request_id) do
      nil ->
        record = %{
          request_id: request_id,
          path: path,
          status: status,
          stacktrace: stacktrace,
          occurred_at: occurred_at
        }

        Enum.take([record | records], @limit)

      index ->
        List.update_at(records, index, &%{&1 | stacktrace: &1.stacktrace || stacktrace})
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
    maybe_record(name, conn.status, conn.request_path, nil)
  end

  def handle_event([:phoenix, :error_rendered], _measurements, metadata, name) do
    stacktrace = Exception.format(metadata.kind, metadata.reason, metadata.stacktrace)
    maybe_record(name, metadata.status, metadata.conn.request_path, stacktrace)
  end

  defp maybe_record(name, status, path, stacktrace) when is_integer(status) and status >= 500 do
    request_id = Logger.metadata()[:request_id]
    occurred_at = Config.fetch!(:foundation, :clock).utc_now()
    GenServer.cast(name, {:record, request_id, path, status, stacktrace, occurred_at})
  end

  defp maybe_record(_name, _status, _path, _stacktrace), do: :ok
end
