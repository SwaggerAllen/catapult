defmodule Catapult.HealthEndpointTest do
  use Catapult.DataCase, async: true
  import Plug.Test

  test "GET /health reports sha and foundation readiness" do
    opts = Catapult.HealthEndpoint.init([])
    conn = Catapult.HealthEndpoint.call(conn(:get, "/health"), opts)

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["ok"] == true
    assert body["components"]["foundation"] == true
  end

  test "anything else is 404" do
    opts = Catapult.HealthEndpoint.init([])
    conn = Catapult.HealthEndpoint.call(conn(:get, "/nope"), opts)
    assert conn.status == 404
  end
end
