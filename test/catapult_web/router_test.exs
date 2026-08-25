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
end
