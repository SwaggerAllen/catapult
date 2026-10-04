defmodule CatapultWeb.BoardLiveTest do
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
      flow_name: "delta",
      ticket_ref: "ORC-#{flow_id}",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)
    approve = %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"}
    assert :ok = Router.dispatch(approve, consistency: :strong)
    assert :ok = Router.dispatch(commit(project_id, "d1"), consistency: :strong)
  end

  test "features's own sub-array renders as a collapsed group by default, badged with its anchor",
       %{conn: conn} do
    project_id = "board-#{System.unique_integer([:positive])}"

    {:ok, _view, html} = live(conn, "/projects/#{project_id}/board")

    # No ticket exists yet, so the board falls back to the first
    # `skeleton: ticket` type in name order — `delta` sorts before
    # `scaffold`. `delta`'s own `features` sub-array (`generation`,
    # `critique`, `review: features-review`) renders as one bounded
    # box, collapsed — `screens/board.md`'s "A group is collapsible,
    # and collapsed is the default," ORC-116 — badged with the group's
    # own derived-throwback anchor, `generation`. Individual lane
    # headers inside the group (its `critique`, unlike `generation`
    # itself which no longer has a leading `pending` entry to hide —
    # `workflow.yaml`'s own "`pending` is an engine flag, not an
    # entry") do not render until the group is expanded.
    assert html =~ "3 lanes"
    assert html =~ "Generation"
    refute html =~ "<h2 class=\"font-semibold text-sm\">Critique</h2>"

    # `checks` sits outside any sub-array and renders as an ordinary
    # lane throughout.
    assert html =~ "Checks"
  end

  test "expanding the group reveals every declared lane, in sequence order", %{conn: conn} do
    project_id = "board-#{System.unique_integer([:positive])}"

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/board")
    html = render_click(view, "toggle_group", %{"key" => "features"})

    # Unlike `types/feature.yaml`'s retired single sub-array (two
    # reviews stacked behind one `generation`), `delta`'s `features`
    # group carries exactly one review — `critique` then
    # `features-review` are the only two lanes the collapsed box was
    # hiding.
    assert html =~ "Critique"
    assert html =~ "features-review"
  end

  test "a ticket resting at a gate shows in the collapsed group's own ticket strip", %{
    conn: conn
  } do
    project_id = "board-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/board")
    html = render(view)

    assert html =~ "ORC-flow-1"
  end

  test "expanding the group shows the card in its own gate lane, linking to document-review", %{
    conn: conn
  } do
    project_id = "board-#{System.unique_integer([:positive])}"
    open_at_gate(project_id, "flow-1")

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/board")
    html = render_click(view, "toggle_group", %{"key" => "features"})

    assert html =~ "ORC-flow-1"
    assert html =~ "Review (design) →"
    assert html =~ "/projects/#{project_id}/tickets/flow-1/review"
  end

  test "a blocked ticket groups under its origin lane with a flavor badge", %{conn: conn} do
    project_id = "board-#{System.unique_integer([:positive])}"
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

    {:ok, view, _html} = live(conn, "/projects/#{project_id}/board")
    html = render_click(view, "toggle_group", %{"key" => "features"})

    assert html =~ "Blocked (usage_limit)"
    assert html =~ "from features-review"
  end
end
