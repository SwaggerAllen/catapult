defmodule Catapult.Delivery.FeaturePublisherTest do
  @moduledoc """
  End to end, the same shape `Catapult.Delivery.FeatureLifecycleTest`
  already proves for the read side (`systems/delivery.md`'s ORC-33
  entry): real commands through the real router, a real
  `Catapult.Delivery.FeaturePublisher` reacting and enqueueing, the
  enqueued `Catapult.Delivery.FeaturePublishWorker` drained
  synchronously (`Oban.Testing`'s own `:manual` mode, conventions §9 —
  deterministic, no timing) and its effect read back off `Fake.Forge`
  and this system's own store.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.FeaturePublishWorker
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Delivery.Store
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Router
  alias Ecto.Adapters.SQL.Sandbox

  # Same reason as `feature_lifecycle_test.exs`: a scaffolding commit
  # has to exist before a flow can name it as its entry node, and it
  # lands before any flow is open — `FeaturePublisher` is not yet
  # `interested?` in it, which the first test below asserts directly.
  defp commit(project_id, node_id, draft_id, body_sha) do
    %CommitDraft{
      project_id: project_id,
      node_id: node_id,
      tier: node_id,
      scope_key: %{},
      draft_id: draft_id,
      body_sha: body_sha,
      committed_at: ~U[2026-01-01 00:00:00Z]
    }
  end

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    {:ok, _pid} = start_supervised({Forge, name: Forge})
    :ok
  end

  test "the flow's first DraftCommitted opens a branch and a PR, and pushes the artifact" do
    project_id = "feature-publisher-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d0", "sha-d0"), consistency: :strong)

    open = %OpenFlow{
      project_id: project_id,
      flow_id: flow_id,
      flow_name: "feature",
      entry_node_id: "sysarch",
      ticket_ref: "ORC-77"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    # No open flow existed yet when the scaffolding commit landed, so
    # nothing was enqueued for it.
    assert %{success: 0, failure: 0, discard: 0} =
             Oban.drain_queue(queue: :delivery_feature_publish)

    assert :ok =
             Router.dispatch(
               %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"},
               consistency: :strong
             )

    :ok = Delivery.put_draft_body(project_id, "sysarch", "<sysarch>real</sysarch>", "sha-d1")

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d1", "sha-d1"), consistency: :strong)

    assert %{success: 1, failure: 0, discard: 0} =
             Oban.drain_queue(queue: :delivery_feature_publish)

    publication = Store.get_feature_publication(project_id, flow_id)
    assert publication.branch_name == "feature/orc-77-#{flow_id}"
    assert publication.base_ref == "main"
    assert is_integer(publication.pr_number)

    assert {:ok, files} = Forge.branch_files(Forge, publication.branch_name)
    assert files[".catapult/artifacts/sysarch/sysarch.xml"] == "<sysarch>real</sysarch>"

    pr = Forge.get_pr(Forge, publication.pr_number)
    assert pr.head == publication.branch_name
    assert pr.base == "main"
    assert pr.body =~ "sysarch"
    assert pr.body =~ ".catapult/artifacts/sysarch/sysarch.xml"

    push = Store.get_artifact_push(project_id, "sysarch")
    assert push.flow_id == flow_id
    assert push.tier == "sysarch"
    assert push.path == ".catapult/artifacts/sysarch/sysarch.xml"
    assert push.body_sha == "sha-d1"
  end

  test "a second DraftCommitted on a different node reuses the same branch and PR" do
    project_id = "feature-publisher-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d0", "sha-d0"), consistency: :strong)

    assert :ok =
             Router.dispatch(
               %OpenFlow{
                 project_id: project_id,
                 flow_id: flow_id,
                 flow_name: "feature",
                 entry_node_id: "sysarch",
                 ticket_ref: "ORC-77"
               },
               consistency: :strong
             )

    assert :ok =
             Router.dispatch(
               %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"},
               consistency: :strong
             )

    :ok = Delivery.put_draft_body(project_id, "sysarch", "<sysarch>real</sysarch>", "sha-d1")

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d1", "sha-d1"), consistency: :strong)

    assert %{success: 1} = Oban.drain_queue(queue: :delivery_feature_publish)

    first_publication = Store.get_feature_publication(project_id, flow_id)

    :ok = Delivery.put_draft_body(project_id, "impl", "<impl>real</impl>", "sha-impl")

    assert :ok =
             Router.dispatch(commit(project_id, "impl", "d2", "sha-impl"), consistency: :strong)

    assert %{success: 1} = Oban.drain_queue(queue: :delivery_feature_publish)

    second_publication = Store.get_feature_publication(project_id, flow_id)
    assert second_publication.branch_name == first_publication.branch_name
    assert second_publication.pr_number == first_publication.pr_number

    assert {:ok, files} = Forge.branch_files(Forge, first_publication.branch_name)
    assert files[".catapult/artifacts/sysarch/sysarch.xml"] == "<sysarch>real</sysarch>"
    assert files[".catapult/artifacts/impl/impl.xml"] == "<impl>real</impl>"

    pr = Forge.get_pr(Forge, first_publication.pr_number)
    assert pr.body =~ "sysarch"
    assert pr.body =~ "impl"
  end

  test "a re-drained job for an already-pushed body_sha is a no-op" do
    project_id = "feature-publisher-#{System.unique_integer([:positive])}"
    flow_id = "flow-1"

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d0", "sha-d0"), consistency: :strong)

    assert :ok =
             Router.dispatch(
               %OpenFlow{
                 project_id: project_id,
                 flow_id: flow_id,
                 flow_name: "feature",
                 entry_node_id: "sysarch",
                 ticket_ref: "ORC-77"
               },
               consistency: :strong
             )

    assert :ok =
             Router.dispatch(
               %ApproveDraft{project_id: project_id, node_id: "sysarch", draft_id: "d0"},
               consistency: :strong
             )

    :ok = Delivery.put_draft_body(project_id, "sysarch", "<sysarch>real</sysarch>", "sha-d1")

    assert :ok =
             Router.dispatch(commit(project_id, "sysarch", "d1", "sha-d1"), consistency: :strong)

    assert %{success: 1} = Oban.drain_queue(queue: :delivery_feature_publish)

    publication = Store.get_feature_publication(project_id, flow_id)

    assert {:ok, _job} =
             FeaturePublishWorker.enqueue(%{
               project_id: project_id,
               flow_id: flow_id,
               ticket_ref: "ORC-77",
               flow_name: "feature",
               node_id: "sysarch",
               tier: "sysarch",
               scope_key: %{},
               body_sha: "sha-d1"
             })

    assert %{success: 1} = Oban.drain_queue(queue: :delivery_feature_publish)

    # The publication and push rows are unchanged — no second branch,
    # no second PR, no duplicate push.
    assert Store.get_feature_publication(project_id, flow_id) == publication
  end
end
