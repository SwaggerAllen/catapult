defmodule CatapultWeb.ExplainWhyLiveTest do
  use CatapultWeb.ConnCase, async: true

  alias Catapult.Engine.Store

  test "a node that doesn't exist renders a not-found message", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects/no-such-project/explain-why/nope")

    assert html =~ "No node"
  end

  test "a review tier renders the caveat instead of claiming readiness", %{conn: conn} do
    project_id = "explain-#{System.unique_integer([:positive])}"

    # `sysarch` carries `review: default` in the new single-tier
    # grammar (`chain.md` #14) — the retired bundle's separate
    # `sysarch_review` tier no longer exists, since a review is now a
    # block on the tier it reviews rather than a tier of its own.
    Store.upsert_node(%{
      id: "sysarch:root",
      project_id: project_id,
      tier: "sysarch",
      scope_key: %{},
      status: :absent
    })

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/explain-why/sysarch:root")

    assert html =~ "review tier"
    assert html =~ "Nothing in scope is blocking this node."
  end
end
