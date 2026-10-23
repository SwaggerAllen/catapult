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
  alias Catapult.Delivery.DraftResolution
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Events.GateApproved
  alias Catapult.Engine.Events.GateDeclined
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store, as: EngineStore
  alias Catapult.Foundation.DispatchPlug
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    # The `FeatureLifecycle` process manager is a real, already-started
    # process that must see the opening write through its own checkout.
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
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

  defp provision! do
    conn =
      :post
      |> conn("/dispatch/test-project", Jason.encode!(%{files: %{}}))
      |> put_req_header("authorization", "Bearer test-token")
      |> DispatchPlug.call(DispatchPlug.init([]))

    assert conn.status == 200
    Jason.decode!(conn.resp_body)["project_id"]
  end

  defp release!(project_id) do
    conn =
      :post
      |> conn("/dispatch/test-project/#{project_id}/release", "")
      |> put_req_header("authorization", "Bearer test-token")
      |> DispatchPlug.call(DispatchPlug.init([]))

    assert conn.status == 200
  end

  describe "the scaffold ticket (delivery#ORC-269-1)" do
    setup do
      {:ok, _pid} = start_supervised({Forge, name: Forge})
      :ok
    end

    test "provision/1 leaves one open scaffold flow at the type's first position" do
      project_id = provision!()
      flow_id = "scaffold-" <> project_id

      assert %{id: ^flow_id, flow_name: "scaffold", entry_node_id: nil, status: :open} =
               EngineStore.get_flow(project_id, flow_id)

      assert %{entry_node_id: nil} =
               row = DeliveryStore.get_feature_lifecycle(project_id, flow_id)

      assert row.status_kind != nil
    end

    test "reclaiming a released project closes its publication and removes its branch" do
      first = provision!()
      Forge.seed_branch(Forge, "feature/scaffold-#{first}", %{})

      assert {:ok, %{number: number}} =
               Forge.open_pr(Forge, %{
                 head: "feature/scaffold-#{first}",
                 base: "main",
                 title: "t",
                 body: "b"
               })

      DeliveryStore.upsert_feature_publication(%{
        id: "scaffold-" <> first,
        project_id: first,
        branch_name: "feature/scaffold-#{first}",
        base_ref: "main",
        pr_number: number
      })

      release!(first)
      second = provision!()

      assert second != first
      assert %{state: :closed} = Forge.get_pr(Forge, number)
      assert {:error, :no_such_branch} = Forge.branch_files(Forge, "feature/scaffold-#{first}")
      assert DeliveryStore.get_feature_publication(first, "scaffold-" <> first) == nil
    end

    test "a gate resolved on a flow with no entry node dispatches nothing" do
      project_id = provision!()

      pm = %DraftResolution{
        project_id: project_id,
        flow_id: "scaffold-" <> project_id,
        entry_node_id: nil,
        flow_name: "scaffold"
      }

      for event <- [
            %GateApproved{project_id: project_id, flow_id: pm.flow_id, gate: "document-review"},
            %GateDeclined{
              project_id: project_id,
              flow_id: pm.flow_id,
              gate: "document-review",
              throwback_to: nil,
              since_sequence: 0
            }
          ] do
        assert DraftResolution.handle(pm, event) == []
      end
    end
  end
end
