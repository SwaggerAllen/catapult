defmodule Catapult.Foundation.DispatchPlugTest do
  use Catapult.DataCase, async: true
  import Plug.Conn
  import Plug.Test

  alias Catapult.Foundation.DispatchPlug

  test "GET /health keeps Catapult.HealthEndpoint's own behavior" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/health"), opts)

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["ok"] == true
    assert conn.halted
  end

  test "GET /dispatch/context/:run_key forwards to delivery, 404s on an unknown run" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/dispatch/context/no-such-run"), opts)

    assert conn.status == 404
    assert conn.halted
  end

  test "POST /dispatch/report/:run_key forwards to delivery, 401s with no bearer" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:post, "/dispatch/report/no-such-run", "{}"), opts)

    assert conn.status in [401, 404]
  end

  test "anything else passes through unhalted, for CatapultWeb.Router to own" do
    opts = DispatchPlug.init([])
    conn = DispatchPlug.call(conn(:get, "/nope"), opts)

    refute conn.halted
    assert conn.status == nil
  end

  describe "the provisioning surface (ORC-216)" do
    test "POST /dispatch/test-project 401s with no bearer" do
      opts = DispatchPlug.init([])
      conn = DispatchPlug.call(conn(:post, "/dispatch/test-project", "{}"), opts)

      assert conn.status == 401
    end

    test "POST /dispatch/test-project 401s with the wrong bearer" do
      opts = DispatchPlug.init([])

      conn =
        conn(:post, "/dispatch/test-project", "{}")
        |> put_req_header("authorization", "Bearer not-the-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 401
    end

    test "POST /dispatch/test-project 400s on a body missing files, even authenticated" do
      opts = DispatchPlug.init([])

      conn =
        conn(:post, "/dispatch/test-project", "{}")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 400
    end

    test "POST /dispatch/test-project/:project_id/release 401s with no bearer" do
      opts = DispatchPlug.init([])

      conn =
        DispatchPlug.call(conn(:post, "/dispatch/test-project/no-such-project/release"), opts)

      assert conn.status == 401
    end

    test "POST /dispatch/test-project/:project_id/release 200s authenticated, even for an unknown project" do
      opts = DispatchPlug.init([])

      conn =
        :post
        |> conn("/dispatch/test-project/no-such-project/release", "")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body)["ok"] == true
    end

    test "GET /dispatch/test-project/:project_id/status/:tier 401s with no bearer" do
      opts = DispatchPlug.init([])

      conn =
        DispatchPlug.call(conn(:get, "/dispatch/test-project/no-such-project/status/comp"), opts)

      assert conn.status == 401
    end

    test "GET /dispatch/test-project/:project_id/status/:tier 404s authenticated, on a project/tier with no dispatch run" do
      opts = DispatchPlug.init([])

      conn =
        :get
        |> conn("/dispatch/test-project/no-such-project/status/comp")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 404
    end
  end
end
