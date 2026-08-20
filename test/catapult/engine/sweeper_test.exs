defmodule Catapult.Engine.SweeperTest do
  @moduledoc """
  The convergence floor's own tick, isolated from the 30s production
  cadence: starts a second instance under a throwaway registered name
  (the already-running `:engine_sweeper` is this application's,
  ticking on its own schedule) and drives one sweep directly, rather
  than waiting out a real interval.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Router
  alias Catapult.Engine.Topics
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  test "a tick re-broadcasts every project the store has heard from" do
    project_id = "sweeper-#{System.unique_integer([:positive])}"
    :ok = Topics.subscribe(Topics.ready_scopes(project_id))

    # A committed draft is the sweeper's own project-enumeration
    # source (`Store.list_project_ids/0`) — nothing else has told the
    # store this project exists yet.
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

    # Drain the fast path's own broadcast from the projector before
    # asking the sweeper for a second one.
    assert_receive {:ready_scopes, ^project_id, _pairs}, 1_000

    {:ok, pid} = start_supervised({Catapult.Engine.Sweeper, name: __MODULE__})
    send(pid, :tick)

    assert_receive {:ready_scopes, ^project_id, _pairs}, 1_000
  end
end
