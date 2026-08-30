defmodule CatapultWeb.TicketLiveTest do
  use CatapultWeb.ConnCase, async: false

  alias Catapult.Delivery.Store, as: DeliveryStore
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

  defp block(project_id) do
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
  end

  test "a missing ticket renders a not-found message", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects/no-such-project/tickets/nope")

    assert html =~ "No ticket"
  end

  test "a ticket resting at a gate shows the sequence rail and a pointer into document-review", %{
    conn: conn
  } do
    project_id = "ticket-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/tickets/flow-1")

    assert html =~ "ORC-flow-1"
    assert html =~ "Awaiting sign-off"
    assert html =~ "/projects/#{project_id}/tickets/flow-1/review"
  end

  test "a blocked ticket offers the origin as the default return, earlier positions behind it", %{
    conn: conn
  } do
    project_id = "ticket-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")
    block(project_id)

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/tickets/flow-1")

    assert html =~ "Blocked"
    assert html =~ "usage_limit"
    assert html =~ "Return to ux-review"
    assert html =~ "Return to Pending"
  end

  test "resuming a blocked ticket dispatches ResumeFlow and clears the block", %{conn: conn} do
    project_id = "ticket-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")
    block(project_id)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1")
    html = render_click(view, "resume", %{"target" => "gate:ux-review"})

    refute html =~ "Blocked"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "ux-review"
    assert row.status_kind == nil
  end

  test "a stale resume renders a synchronous conflict rather than silently applying", %{
    conn: conn
  } do
    project_id = "ticket-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")
    block(project_id)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1")
    render_click(view, "resume", %{"target" => "gate:ux-review"})

    html = render_click(view, "resume", %{"target" => "kind:pending"})

    assert html =~ "Rejected"
  end

  test "the rail groups feature's own leading sub-array with the derived-throwback badge", %{
    conn: conn
  } do
    project_id = "ticket-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/tickets/flow-1")

    # `pending`/`generation`/`critique`/`ux-review`/`engineering-review`
    # (`types/feature.yaml`'s own sub-array) render inside one bounded
    # box on the rail, with `generation` — the derived-throwback anchor
    # — badged (`screens/ticket.md`'s own grouping, ORC-116).
    assert html =~ "rounded-box border border-dashed border-primary/40"
    assert html =~ "Default throwback landing point for this group"
  end
end
