defmodule Catapult.Foundation.FailureLogTest do
  @moduledoc """
  Exercises `handle_event/4` directly rather than through
  `:telemetry.execute/3` — the event names this module attaches to
  (`[:phoenix, :endpoint, :stop]`, `[:phoenix, :error_rendered]`) are a
  global `:telemetry` bus, so firing them for real would also reach the
  application's own already-running `:foundation_failure_log` singleton
  and pollute it for every other test. Calling the handler function is
  calling the identical code `:telemetry.attach_many/4` wires up in
  production, without the dispatch's global side effect.
  """
  use ExUnit.Case, async: true

  alias Catapult.Foundation.FailureLog

  setup do
    name = :"failure_log_test_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({FailureLog, name: name})
    {:ok, name: name}
  end

  defp stop_metadata(status, path, resp_body \\ nil) do
    %{conn: %Plug.Conn{status: status, request_path: path, resp_body: resp_body}}
  end

  defp error_rendered_metadata(status, path) do
    %{
      conn: %Plug.Conn{request_path: path},
      status: status,
      kind: :error,
      reason: %RuntimeError{message: "boom"},
      stacktrace: [{__MODULE__, :fake, 0, [file: ~c"test.ex", line: 1]}]
    }
  end

  test "a 5xx on :stop is recorded", %{name: name} do
    Logger.metadata(request_id: "req-1")

    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(502, "/dispatch/x"),
      name
    )

    assert [%{status: 502, path: "/dispatch/x", stacktrace: nil}] = FailureLog.list(name)
  after
    Logger.metadata(request_id: nil)
  end

  test "a 2xx/3xx/4xx on :stop is not recorded", %{name: name} do
    for status <- [200, 302, 404] do
      FailureLog.handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: 0},
        stop_metadata(status, "/ok"),
        name
      )
    end

    assert FailureLog.list(name) == []
  end

  test "error_rendered alone creates a record (the raise-with-no-:stop path)", %{name: name} do
    Logger.metadata(request_id: "req-2")

    FailureLog.handle_event(
      [:phoenix, :error_rendered],
      %{duration: 0},
      error_rendered_metadata(500, "/board/p1"),
      name
    )

    assert [%{status: 500, path: "/board/p1", stacktrace: stacktrace}] = FailureLog.list(name)
    assert stacktrace =~ "boom"
  after
    Logger.metadata(request_id: nil)
  end

  test "a swallowed NoRouteError's 404 through error_rendered is not recorded", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :error_rendered],
      %{duration: 0},
      error_rendered_metadata(404, "/nope"),
      name
    )

    assert FailureLog.list(name) == []
  end

  test ":stop then error_rendered for the same request enrich one record, not two", %{name: name} do
    Logger.metadata(request_id: "req-3")

    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x"),
      name
    )

    FailureLog.handle_event(
      [:phoenix, :error_rendered],
      %{duration: 0},
      error_rendered_metadata(500, "/x"),
      name
    )

    assert [%{status: 500, path: "/x", stacktrace: stacktrace}] = FailureLog.list(name)
    assert stacktrace =~ "boom"
  after
    Logger.metadata(request_id: nil)
  end

  test "requests with no request id never merge with each other", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/a"),
      name
    )

    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/b"),
      name
    )

    assert length(FailureLog.list(name)) == 2
  end

  # The reason a deliberate 5xx gives is in its body and nowhere else:
  # it never raises, so there is no trace, and App Platform replaces an
  # upstream 502's body before any caller sees it.
  test ":stop records the response body, which is where a deliberate 5xx says why", %{name: name} do
    Logger.metadata(request_id: "req-body")

    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(502, "/dispatch/test-project", ~s({"error":"{:reset_failed, 403}"})),
      name
    )

    assert [%{status: 502, body: ~s({"error":"{:reset_failed, 403}"})}] = FailureLog.list(name)
  after
    Logger.metadata(request_id: nil)
  end

  test ":stop accepts an iodata body, which is what resp_body holds", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x", ["one", ?-, ["two"]]),
      name
    )

    assert [%{body: "one-two"}] = FailureLog.list(name)
  end

  test "an oversized body is truncated rather than held whole", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x", String.duplicate("a", 9_000)),
      name
    )

    assert [%{body: body}] = FailureLog.list(name)
    assert byte_size(body) == 2_048
  end

  # A body cut mid-codepoint would make `Jason.encode!` raise in
  # `Catapult.Foundation.Failures.list/1` and take the whole read
  # surface down — so an invalid binary is dropped, not stored.
  test "a body that is not valid UTF-8 is dropped rather than stored", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x", <<0xFF, 0xFE>>),
      name
    )

    assert [%{body: nil}] = FailureLog.list(name)
  end

  test "truncation never splits a codepoint", %{name: name} do
    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x", String.duplicate("é", 4_000)),
      name
    )

    assert [%{body: body}] = FailureLog.list(name)
    assert String.valid?(body)
    assert Jason.encode!(%{body: body})
  end

  test "error_rendered has no body, and a later :stop supplies one", %{name: name} do
    Logger.metadata(request_id: "req-enrich")

    FailureLog.handle_event(
      [:phoenix, :error_rendered],
      %{duration: 0},
      error_rendered_metadata(500, "/x"),
      name
    )

    assert [%{body: nil}] = FailureLog.list(name)

    FailureLog.handle_event(
      [:phoenix, :endpoint, :stop],
      %{duration: 0},
      stop_metadata(500, "/x", "the body"),
      name
    )

    assert [%{body: "the body", stacktrace: stacktrace}] = FailureLog.list(name)
    assert stacktrace =~ "boom"
  after
    Logger.metadata(request_id: nil)
  end

  test "the buffer drops the oldest past 50 records", %{name: name} do
    for i <- 1..51 do
      Logger.metadata(request_id: "req-#{i}")

      FailureLog.handle_event(
        [:phoenix, :endpoint, :stop],
        %{duration: 0},
        stop_metadata(500, "/#{i}"),
        name
      )
    end

    records = FailureLog.list(name)
    assert length(records) == 50
    assert Enum.map(records, & &1.path) |> hd() == "/51"
    refute Enum.any?(records, &(&1.path == "/1"))
  after
    Logger.metadata(request_id: nil)
  end
end
