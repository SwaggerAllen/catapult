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
      flow_name: "delta",
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

  test "the current gate's node renders its sentences and its one throwback landing point", %{
    conn: conn
  } do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    assert html =~ "sysarch"
    assert html =~ "The system uses a single event store."

    # One button, not one per declared exit: `throwback:` narrowed to a
    # single target at §15.10 because a decline lands on exactly one
    # status. `features-review` (the first gate `delta`'s own sequence
    # reaches, opened at the `sysarch` node) declares no `throwback:`
    # of its own — none of the ordinary review gates in the new bundle
    # do — so the primary button is the plain derived default: the
    # citing `features` sub-array's own `generation` anchor.
    assert html =~ "Throw back to features"
    refute html =~ "Throw back to plan-features"

    # The secondary "choose a different target" disclosure offers
    # every other legal target — `features.critique`, earlier than
    # `features-review` in `delta`'s own array — behind the primary
    # button rather than as an equally-weighted one (`screens/document-
    # review.md`'s own picker, ORC-116). `features.critique` sits in
    # the gate's own leading sub-array, so it renders with no "leaves
    # this loop" note; `plan-features` sits before the sub-array
    # begins, so it is offered too but marked as leaving it — `delta`
    # gives this picker an earlier position to reach for that
    # `feature.yaml`'s single sub-array never had.
    assert html =~ "Choose a different target"
    assert html =~ "features.critique"
    assert html =~ "leaves this loop"
  end

  test "a target outside the earlier prefix is refused at the command edge", %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    # `deploy` sits *after* `features-review` in `delta`'s own
    # sequence, so it is not a legal landing point (`workflow.md` #34:
    # earlier in the citing type's effective sequence, and nothing
    # else). No button offers it — which is exactly why the check has
    # to exist: `target` arrives from a client-controlled
    # `phx-value-target`, and validating bundle content before
    # dispatch is the command edge's job, never the aggregate's
    # (`Commands.DeclineGate`).
    html = render_click(view, "decline", %{"target" => "deploy"})

    assert html =~ "not a legal throwback target"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "features-review"
  end

  test "an earlier target the gate does not declare is still legal", %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")
    render_click(view, "open_comment_form", %{"index" => "0"})

    view
    |> form("form", %{"body" => "The second sentence needs regenerating, not rewriting."})
    |> render_submit()

    # `features-review` declares no `throwback:` of its own, so its
    # derived default is `features` — but a derived default bounds
    # nothing (§15.10): `features.critique` is earlier in the array
    # too, and therefore reachable, and the command edge admits it.
    assert {:error, {:live_redirect, %{to: _to}}} =
             render_click(view, "decline", %{"target" => "features.critique"})

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_kind == "critique"
    assert row.status_gate == nil
  end

  test "declining before any comment lands is rejected by the aggregate, rendered synchronously",
       %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")
    html = render_click(view, "decline", %{"target" => "features"})

    assert html =~ "at least one comment"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "features-review"
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
             render_click(view, "decline", %{"target" => "features"})

    assert to == "/projects/#{project_id}/tickets/flow-1"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_kind == "generation"
    assert row.status_gate == nil
  end

  test "approving advances the ticket to the next gate", %{conn: conn} do
    project_id = "docreview-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1", @body)

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/tickets/flow-1/review")

    assert {:error, {:live_redirect, %{to: to}}} = render_click(view, "approve", %{})
    assert to == "/projects/#{project_id}/tickets/flow-1"

    row = DeliveryStore.get_feature_lifecycle(project_id, "flow-1")
    assert row.status_gate == "ux-review"
  end
end
