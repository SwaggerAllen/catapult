defmodule Catapult.Generation.CommitPathTest do
  @moduledoc """
  A commit whose events are appended is committed, whether or not the
  strongly consistent handlers caught up inside Commanded's wait.

  `Router.dispatch(cmd, consistency: :strong)` answers
  `{:error, :consistency_timeout}` *after* the events are durably in
  the store (`Commanded.Middleware.ConsistencyGuarantee.after_dispatch/1`)
  — the write happened, only the read-your-writes wait gave up.
  `CommitPath` used to pass that through as a failed commit, and
  `Catapult.Delivery.Dispatch` leaves a `:success` report the handler
  rejected in flight, waiting for a resubmission. So a draft that had
  committed, and whose children the walk went on to dispatch, held
  its run at `:context_fetched` for good, and the live suite's
  `remaining` with it: run 32 timed out with 21 runs in exactly that
  state, every one from the later, burstier half of the walk where
  reports land several to a second.

  The default wait is five seconds, which this suite never exceeds
  sequentially, so these tests shrink it to zero to make the wait
  give up deterministically.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed

  setup do
    previous = Application.get_env(:commanded, :dispatch_consistency_timeout)
    Application.put_env(:commanded, :dispatch_consistency_timeout, 0)

    on_exit(fn ->
      Application.delete_env(:catapult, :fake_dispatch_result)

      if previous,
        do: Application.put_env(:commanded, :dispatch_consistency_timeout, previous),
        else: Application.delete_env(:commanded, :dispatch_consistency_timeout)
    end)
  end

  test "a draft and its review each mark their run terminal when the consistency wait gives up" do
    project_id = "commit-path-#{System.unique_integer([:positive])}"
    {:ok, %{chain: chain}} = Dsl.load(".")
    {:ok, _pid} = start_supervised({Forge, name: Forge})

    files = ToySeed.reset_files()
    Forge.seed_branch(Forge, "main", files)
    assert :ok = Delivery.intake_raft(project_id, "main")

    Application.put_env(:catapult, :fake_dispatch_result, fn request ->
      %{
        status: :success,
        body: files[".catapult-stub/#{request.root_tag}.xml"],
        credential_used: "stub"
      }
    end)

    assert [node] = ReadyScopes.ready(chain, project_id, "feature_expansion")
    assert {:ok, request} = ContextAssembly.build(chain, project_id, "feature_expansion", node)
    assert {:ok, %{run_key: draft_run}} = FakeHostPort.dispatch_run(request)
    assert %{status: :completed, outcome: :success} = Delivery.Store.get_dispatch_run(draft_run)

    review_tier = ReadyScopes.review_tier_name("feature_expansion")

    assert [reviewed] =
             eventually(fn -> ReadyScopes.ready_review(chain, project_id, review_tier) end)

    assert {:ok, review_request} = ContextAssembly.build(chain, project_id, review_tier, reviewed)
    assert {:ok, %{run_key: review_run}} = FakeHostPort.dispatch_run(review_request)
    assert %{status: :completed, outcome: :success} = Delivery.Store.get_dispatch_run(review_run)

    assert Delivery.Store.in_flight_scope_keys(project_id) == MapSet.new()

    # Let the projector apply the review before the sandbox owner
    # exits, so no strongly consistent handler outlives this test.
    assert [] =
             eventually(
               fn -> ReadyScopes.ready_review(chain, project_id, review_tier) end,
               &(&1 != [])
             )
  end

  # With the wait at zero the caller returns before the projector has
  # applied the commit, so a read that depends on it polls briefly —
  # the projection is what lags here, not the commit.
  defp eventually(fun, retry? \\ &(&1 == []), attempts \\ 50) do
    result = fun.()

    if retry?.(result) and attempts > 0 do
      Process.sleep(20)
      eventually(fun, retry?, attempts - 1)
    else
      result
    end
  end
end
