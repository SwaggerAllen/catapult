defmodule Catapult.Engine.Projections.RunFailuresTest do
  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Projections.RunFailures
  alias Catapult.Engine.Router
  alias Ecto.Adapters.SQL.Sandbox

  # `:strong` consistency touches the projector's own DB write
  # (`Catapult.Engine.Reducer`), which needs shared sandbox mode —
  # `Catapult.Engine.RouterTest`'s own precedent.
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  defp fail!(project_id, node_id, run_id) do
    Router.dispatch(
      %RecordRunFailure{
        project_id: project_id,
        node_id: node_id,
        tier: "comp",
        scope_key: %{},
        run_id: run_id,
        reason: "usage_limit",
        occurred_at: ~U[2026-01-01 00:00:00Z]
      },
      consistency: :strong
    )
  end

  defp commit!(project_id, node_id) do
    Router.dispatch(
      %CommitDraft{
        project_id: project_id,
        node_id: node_id,
        tier: "comp",
        scope_key: %{},
        draft_id: "d-#{System.unique_integer([:positive])}",
        body_sha: "sha",
        committed_at: ~U[2026-01-01 00:00:00Z]
      },
      consistency: :strong
    )
  end

  test "a project with no events has no failures" do
    assert RunFailures.count_since_commit("no-such-project", "n1") == 0
  end

  test "counts limit-class failures accrued since the node's last commit" do
    project_id = "run-failures-#{System.unique_integer([:positive])}"

    assert :ok = fail!(project_id, "n1", "run-1")
    assert :ok = fail!(project_id, "n1", "run-2")

    assert RunFailures.count_since_commit(project_id, "n1") == 2
  end

  test "a commit resets the count for that node" do
    project_id = "run-failures-#{System.unique_integer([:positive])}"

    assert :ok = fail!(project_id, "n1", "run-1")
    assert :ok = commit!(project_id, "n1")
    assert :ok = fail!(project_id, "n1", "run-2")

    assert RunFailures.count_since_commit(project_id, "n1") == 1
  end

  test "failures on a different node in the same project don't count" do
    project_id = "run-failures-#{System.unique_integer([:positive])}"

    assert :ok = fail!(project_id, "n1", "run-1")
    assert :ok = fail!(project_id, "n2", "run-2")

    assert RunFailures.count_since_commit(project_id, "n1") == 1
    assert RunFailures.count_since_commit(project_id, "n2") == 1
  end
end
