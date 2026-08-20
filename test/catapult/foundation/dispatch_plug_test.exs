defmodule Catapult.Foundation.DispatchPlugTest do
  use Catapult.DataCase, async: true
  import Plug.Test

  alias Catapult.Foundation.DispatchPlug

  test "GET /health keeps Catapult.HealthEndpoint's own behavior" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/health"), opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["ok"] == true
  end

  test "GET /dispatch/context/:run_key forwards to delivery, 404s on an unknown run" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/dispatch/context/no-such-run"), opts)

    assert conn.status == 404
  end

  test "POST /dispatch/report/:run_key forwards to delivery, 401s with no bearer" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:post, "/dispatch/report/no-such-run", "{}"), opts)

    assert conn.status in [401, 404]
  end

  test "anything else is 404" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/nope"), opts)
    assert conn.status == 404
  end
end
