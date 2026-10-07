defmodule Catapult.Delivery.ProvisioningTest do
  @moduledoc """
  `remaining` (`Catapult.Delivery.Provisioning`'s ORC-230 read) against
  a real committed draft, rather than the shape-only assertion
  `Catapult.Foundation.DispatchPlugTest` makes of it.

  The case pinned here is the review axis. A review is a block on the
  tier it reviews, dispatched under `ReadyScopes.review_tier_name/1`'s
  synthetic name, and `remaining` once asked `ready_review/3` with the
  bare tier name instead — which answers `[]` for every tier. It read
  zero for a committed, unreviewed draft, so the live suite's walk
  approved drafts nobody had reviewed and could stop before their
  reviews ever ran. A shape assertion (`remaining >= 0`) passes either
  way; only a count does not.
  """

  use Catapult.DataCase, async: false

  import Plug.Conn
  import Plug.Test

  alias Catapult.Delivery
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Foundation.DispatchPlug
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed

  setup do
    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
  end

  test "remaining counts a committed draft's pending review, under the review's own dispatch name" do
    project_id = "provisioning-#{System.unique_integer([:positive])}"
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

    # The toy chain's two entry tiers, both singletons and both ready
    # off intake alone. Committed and not approved, nothing downstream
    # of either is ready yet — so the only outstanding work is the two
    # reviews their commits made ready.
    for tier <- ["feature_expansion", "non_goals"] do
      assert [node] = ReadyScopes.ready(chain, project_id, tier)
      assert {:ok, request} = ContextAssembly.build(chain, project_id, tier, node)
      assert {:ok, _run} = FakeHostPort.dispatch_run(request)
    end

    conn =
      :get
      |> conn("/dispatch/test-project/#{project_id}/runs")
      |> put_req_header("authorization", "Bearer test-token")
      |> DispatchPlug.call(DispatchPlug.init([]))

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)

    assert Enum.map(body["runs"], &{&1["tier"], &1["status"]}) == [
             {"feature_expansion", "completed"},
             {"non_goals", "completed"}
           ]

    assert body["remaining"] == 2
  end
end
