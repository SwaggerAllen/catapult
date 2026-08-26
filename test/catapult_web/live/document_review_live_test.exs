defmodule CatapultWeb.DocumentReviewLiveTest do
  use CatapultWeb.ConnCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
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

  defp open_at_gate(project_id, flow_id, body) do
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
    :ok = Delivery.put_draft_body(project_id, "sysarch", body, "sha-d1")
  end

  @body "The system uses a single event store. Commands validate before dispatch. Every write is idempotent."

  test "a ticket not resting at an open gate renders a not-found message", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/projects/no-such-project/tickets/nope/review")

    assert html =~ "No design gate"
  end

  test "the current gate's node renders its sentences and declared throwback exits", %{
    conn: conn
  } do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    assert html =~ "sysarch"
    assert html =~ "The system uses a single event store."
    assert html =~ "Throw back to pending"
  end

  test "declining before any comment lands is rejected by the aggregate, rendered synchronously",
       %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")
    html = render_click(view, "decline", %{"target" => "pending"})

    assert html =~ "at least one comment"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "ux-review"
  end

  test "posting a comment then declining moves the ticket to the throwback target", %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    render_click(view, "open_comment_form", %{"index" => "0"})

    html =
      view
      |> form("form", %{"body" => "Please tighten the second sentence."})
      |> render_submit()

    assert html =~ "Please tighten the second sentence."

    assert {:error, {:live_redirect, %{to: to}}} =
             render_click(view, "decline", %{"target" => "pending"})

    assert to == "/projects/#{project_id}/tickets/flow-1"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_kind == "pending"
    assert row.status_gate == nil
  end

  test "approving advances the ticket to the next gate", %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    assert {:error, {:live_redirect, %{to: to}}} = render_click(view, "approve", %{})
    assert to == "/projects/#{project_id}/tickets/flow-1"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "engineering-review"
  end
end
