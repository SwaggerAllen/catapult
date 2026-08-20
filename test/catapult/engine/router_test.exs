defmodule Catapult.Engine.RouterTest do
  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Ecto.Adapters.SQL.Sandbox

  # The projector runs as a separate, already-started process shared
  # across the whole test run (it subscribes once, at application
  # boot) — a `:strong`-consistency dispatch blocks the *caller* until
  # the projector applies the resulting event, but the projector still
  # writes through its own connection checkout, which the (default,
  # non-shared) sandbox mode would refuse. Shared mode is what a test
  # exercising a real cross-process write needs; it is why this module
  # docs itself out of `async: true` (conventions §9).
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  test "dispatching a command end to end lands in the projections, synchronously" do
    project_id = "router-e2e-#{System.unique_integer([:positive])}"

    commit = %CommitDraft{
      project_id: project_id,
      node_id: "sysarch",
      tier: "sysarch",
      scope_key: %{},
      draft_id: "d1",
      body_sha: "sha1",
      committed_at: ~U[2026-01-01 00:00:00Z]
    }

    assert :ok = Router.dispatch(commit, consistency: :strong)

    cmd = %OpenFlow{
      project_id: project_id,
      flow_id: "flow-1",
      flow_name: "capability",
      entry_node_id: "sysarch"
    }

    assert :ok = Router.dispatch(cmd, consistency: :strong)

    flow = Store.get_flow("flow-1")
    assert flow.project_id == project_id
    assert flow.status == :open
  end

  test "a rejected command surfaces the aggregate's own reason" do
    project_id = "router-conflict-#{System.unique_integer([:positive])}"

    first = %CommitDraft{
      project_id: project_id,
      node_id: "n1",
      tier: "comp",
      scope_key: %{},
      draft_id: "d1",
      body_sha: "sha1",
      committed_at: ~U[2026-01-01 00:00:00Z]
    }

    second = %{first | draft_id: "d2", body_sha: "sha2"}

    assert :ok = Router.dispatch(first, consistency: :strong)

    assert {:error, {:engine_draft_conflict, _details}} =
             Router.dispatch(second, consistency: :strong)
  end
end
