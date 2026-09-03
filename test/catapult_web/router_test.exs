defmodule CatapultWeb.RouterTest do
  @moduledoc """
  The two mechanisms sharing one listener (`systems/foundation.md`'s
  design pass), exercised through the real endpoint pipeline rather
  than `Catapult.Foundation.DispatchPlug` standalone
  (`DispatchPlugTest`'s own job): health and dispatch routes still
  answer, and a path neither mechanism claims is the router's own
  terminal 404, not `DispatchPlug`'s.
  """
  use CatapultWeb.ConnCase, async: true

  test "GET /health is served through the full endpoint pipeline", %{conn: conn} do
    conn = get(conn, "/health")

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["ok"] == true
  end

  test "a path neither DispatchPlug nor the router claims is a 404", %{conn: conn} do
    conn = get(conn, "/nope")

    assert conn.status == 404
  end

  describe "HSTS is on the browser surface and only there (ORC-131)" do
    test "a :browser route carries it", %{conn: conn} do
      conn = get(conn, "/my-queue")

      assert conn.status == 200
      assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
    end

    # The load-bearing half. HSTS lives on the `:browser` pipeline
    # rather than the endpoint precisely so that App Platform's own
    # health probe — which hits the container's port directly rather
    # than through the edge that terminates TLS — is untouched. Moving
    # it to an endpoint-wide `force_ssl:` would put `Plug.SSL` ahead of
    # `DispatchPlug`, answer that probe with a 301 and fail the
    # rollout. This test is what turns that from a comment into a
    # tripwire, so assert the absence, not merely the presence above.
    test "the health probe's path does not", %{conn: conn} do
      conn = get(conn, "/health")

      assert conn.status == 200
      assert get_resp_header(conn, "strict-transport-security") == []
    end
  end

  describe "the failure buffer (ORC-218)" do
    test "GET /failures is reachable through the full endpoint pipeline, bearer-authenticated", %{
      conn: conn
    } do
      conn = get(conn, "/failures")
      assert conn.status == 401

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer test-token")
        |> get("/failures")

      assert conn.status == 200
      assert %{"failures" => failures} = Jason.decode!(conn.resp_body)
      assert is_list(failures)
    end

    test "an ordinary 200 leaves no trace of its own path in the buffer", %{conn: conn} do
      get(conn, "/health")

      assert %{"failures" => failures} = current_failures()
      refute Enum.any?(failures, &(&1["path"] == "/health"))
    end

    test "the router's own terminal 404 leaves no trace of its path in the buffer", %{conn: conn} do
      get(conn, "/nope")

      assert %{"failures" => failures} = current_failures()
      refute Enum.any?(failures, &(&1["path"] == "/nope"))
    end
  end

  defp current_failures do
    build_conn()
    |> put_req_header("authorization", "Bearer test-token")
    |> get("/failures")
    |> then(& &1.resp_body)
    |> Jason.decode!()
  end
end
