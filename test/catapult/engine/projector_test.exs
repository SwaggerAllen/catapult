defmodule Catapult.Engine.ProjectorTest do
  @moduledoc """
  The fast path end to end (`systems/engine.md`): a real command,
  dispatched through the real router, lands in the projections *and*
  triggers a broadcast on the project's `ready_scopes` topic — proving
  the wiring inside `Catapult.Engine.Projector.handle/2`, not just
  `Catapult.Engine.Scheduler.trigger/2` in isolation
  (`scheduler_test.exs` already covers that half against a fixture
  chain). Loads the real `bundles/default` chain this repo ships with
  (`ENGINE_BUNDLES_ROOT`'s default, `.`), the same reference-deployment
  assumption `Catapult.Engine.Sweeper` makes.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Router
  alias Catapult.Engine.Topics
  alias Ecto.Adapters.SQL.Sandbox

  # Same reason as router_test.exs: the projector is a real,
  # already-started process sharing the caller's `:strong`-consistency
  # write through its own connection checkout.
  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  test "committing a draft triggers a ready_scopes broadcast for its project" do
    project_id = "projector-fast-path-#{System.unique_integer([:positive])}"
    :ok = Topics.subscribe(Topics.ready_scopes(project_id))

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

    assert_receive {:ready_scopes, ^project_id, _pairs}, 1_000
  end
end
