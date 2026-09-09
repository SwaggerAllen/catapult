defmodule Catapult.Foundation.DispatchPlugTest do
  use Catapult.DataCase, async: true
  import Plug.Conn
  import Plug.Test

  alias Catapult.Delivery.Store
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

    test "GET /dispatch/test-project/:project_id/runs 401s with no bearer" do
      opts = DispatchPlug.init([])

      conn = DispatchPlug.call(conn(:get, "/dispatch/test-project/no-such-project/runs"), opts)

      assert conn.status == 401
    end

    test "GET /dispatch/test-project/:project_id/runs 200s authenticated with an empty list, on a project with no dispatch runs" do
      opts = DispatchPlug.init([])

      conn =
        :get
        |> conn("/dispatch/test-project/no-such-project/runs")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert body["runs"] == []
      # `remaining` (ORC-230) is not zero even here: the toy raft's own
      # `scope: singleton` tiers read ready off a virtual, never-persisted
      # candidate, independent of whether this project has any engine
      # rows at all.
      assert is_integer(body["remaining"]) and body["remaining"] >= 0
    end

    test "GET /dispatch/test-project/:project_id/runs 200s authenticated with every run, oldest first" do
      Store.insert_dispatch_run(%{
        id: Ecto.UUID.generate(),
        project_id: "p1",
        node_id: "n1",
        tier: "comp",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "comparch",
        rendered_prompt: "hello",
        credential_sent: ["claude_code_oauth_token"]
      })

      second_run_key = Ecto.UUID.generate()

      Store.insert_dispatch_run(%{
        id: second_run_key,
        project_id: "p1",
        node_id: "n2",
        tier: "review",
        scope_key: %{},
        repo_owner: "acme",
        repo_name: "widgets",
        root_tag: "review",
        rendered_prompt: "hello again",
        credential_sent: ["claude_code_oauth_token"]
      })

      Store.complete_dispatch_run(second_run_key, :completed, :success, "claude_code_oauth_token")

      opts = DispatchPlug.init([])

      conn =
        :get
        |> conn("/dispatch/test-project/p1/runs")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 200
      body = Jason.decode!(conn.resp_body)
      assert is_integer(body["remaining"]) and body["remaining"] >= 0

      assert [
               %{"tier" => "comp", "root_tag" => "comparch", "status" => "dispatched"},
               %{
                 "tier" => "review",
                 "root_tag" => "review",
                 "status" => "completed",
                 "outcome" => "success",
                 "credential_used" => "claude_code_oauth_token"
               }
             ] = body["runs"]
    end

    test "POST /dispatch/test-project/:project_id/approve-drafts 401s with no bearer" do
      opts = DispatchPlug.init([])

      conn =
        DispatchPlug.call(
          conn(:post, "/dispatch/test-project/no-such-project/approve-drafts", ""),
          opts
        )

      assert conn.status == 401
    end

    test "POST /dispatch/test-project/:project_id/approve-drafts 200s authenticated with zero approvals, on a project with no drafted nodes" do
      opts = DispatchPlug.init([])

      conn =
        :post
        |> conn("/dispatch/test-project/no-such-project/approve-drafts", "")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 200
      assert Jason.decode!(conn.resp_body) == %{"approved" => 0}
    end
  end

  describe "GET /failures (ORC-218)" do
    test "401s with no bearer" do
      opts = DispatchPlug.init([])
      conn = DispatchPlug.call(conn(:get, "/failures"), opts)

      assert conn.status == 401
    end

    test "401s with the wrong bearer" do
      opts = DispatchPlug.init([])

      conn =
        conn(:get, "/failures")
        |> put_req_header("authorization", "Bearer not-the-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 401
    end

    test "200s authenticated, with the buffer's current records" do
      opts = DispatchPlug.init([])

      conn =
        conn(:get, "/failures")
        |> put_req_header("authorization", "Bearer test-token")
        |> DispatchPlug.call(opts)

      assert conn.status == 200
      assert conn.halted
      assert %{"failures" => failures} = Jason.decode!(conn.resp_body)
      assert is_list(failures)
    end
  end
end
