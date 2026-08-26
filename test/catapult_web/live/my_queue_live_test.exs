defmodule CatapultWeb.MyQueueLiveTest do
  use CatapultWeb.ConnCase, async: false

  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Router
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  defp commit(project_id, draft_id) do
    %CommitDraft{
      project_id: project_id,
      node_id: "sysarch",
      tier: "sysarch",
      scope_key: %{},
      draft_id: draft_id,
      body_sha: "sha-" <> draft_id,
      committed_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  defp open_at_gate(project_id, flow_id) do
    assert :ok = Router.dispatch(commit(project_id, "d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      ticket_ref: "ORC-#{flow_id}",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)
    approve = %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"}
    assert :ok = Router.dispatch(approve, consistency: :strong)
    assert :ok = Router.dispatch(commit(project_id, "d1"), consistency: :strong)
  end

  test "an actor with nothing to do sees the empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/my-queue")

    assert html =~ "machine has the ball"
  end

  test "a ticket resting at a gate shows as a sign_off row linking to document-review", %{
    conn: conn
  } do
    project_id = "myqueue-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, _view, html} = live(conn, "/my-queue")

    assert html =~ "sign off"
    assert html =~ "/projects/#{project_id}/tickets/flow-1/review"
  end

  test "a blocked ticket shows as an unblock row linking to the ticket screen", %{conn: conn} do
    project_id = "myqueue-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    failure = %RecordRunFailure{
      project_id: project_id,
      node_id: "sysarch",
      tier: "sysarch",
      scope_key: %{},
      run_id: "run-1",
      reason: "usage_limit",
      occurred_at: ~U[2026-01-02 00:00:00Z]
    }

    assert :ok = Router.dispatch(failure, consistency: :strong)

    {:ok, _view, html} = live(conn, "/my-queue")

    assert html =~ "unblock"
    assert html =~ "/projects/#{project_id}/tickets/flow-1\""
    refute html =~ "sign off"
  end

  test "the my_roles tab reads the identical set in Phase 4", %{conn: conn} do
    project_id = "myqueue-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, _view, html} = live(conn, "/my-queue?tab=my_roles")

    assert html =~ "sign off"
  end
end
