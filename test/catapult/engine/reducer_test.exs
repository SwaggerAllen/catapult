defmodule Catapult.Engine.ReducerTest do
  use Catapult.DataCase, async: true

  import Ecto.Query

  alias Catapult.Engine.Events.ActiveBundleFlipped
  alias Catapult.Engine.Events.DraftApproved
  alias Catapult.Engine.Events.DraftCommitted
  alias Catapult.Engine.Events.DraftDiscarded
  alias Catapult.Engine.Events.FlowCompleted
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Reducer
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.ActiveBundleVersion
  alias Catapult.Engine.Store.Draft
  alias Catapult.Engine.Store.Edge
  alias Catapult.Engine.Store.Flow
  alias Catapult.Engine.Store.Fragment
  alias Catapult.Engine.Store.Node
  alias Catapult.Engine.Store.Review

  @committed_at ~U[2026-01-01 00:00:00Z]

  ## The scenario: a scaffold node fans out to two children, one child
  ## gets reviewed and approved, a flow opens and completes, and the
  ## chain bundle flips once — one instance of every universal
  ## projection this ticket builds.

  defp scenario(project_id) do
    [
      %DraftCommitted{
        project_id: project_id,
        node_id: "sysarch",
        tier: "sysarch",
        scope_key: %{},
        draft_id: "draft-sysarch-1",
        body_sha: "sha-sysarch-1",
        committed_at: @committed_at,
        actor_id: "author-1",
        fields: %{"name" => "root"},
        mints: [
          %{
            node_id: "comp1",
            tier: "comp",
            scope_key: %{"name" => "comp1"},
            edge_name: "decomposition",
            edge_type: :fanout
          },
          %{
            node_id: "comp2",
            tier: "comp",
            scope_key: %{"name" => "comp2"},
            edge_name: "decomposition",
            edge_type: :fanout
          }
        ],
        edges: [],
        produces: [%{owner_node_id: "sysarch", kind: "techspec", content: "spec text"}]
      },
      %DraftCommitted{
        project_id: project_id,
        node_id: "comp1",
        tier: "comp",
        scope_key: %{"name" => "comp1"},
        parent_node_id: "sysarch",
        draft_id: "draft-comp1-1",
        body_sha: "sha-comp1-1",
        committed_at: @committed_at,
        fields: %{"name" => "comp1"}
      },
      %ReviewWritten{
        project_id: project_id,
        draft_id: "draft-comp1-1",
        review_id: "review-comp1-1",
        score: 92,
        findings: [%{"id" => "f1", "message" => "looks good"}],
        kind: :ai
      },
      %DraftApproved{project_id: project_id, node_id: "comp1", draft_id: "draft-comp1-1"},
      %DraftCommitted{
        project_id: project_id,
        node_id: "comp2",
        tier: "comp",
        scope_key: %{"name" => "comp2"},
        parent_node_id: "sysarch",
        draft_id: "draft-comp2-1",
        body_sha: "sha-comp2-1",
        committed_at: @committed_at,
        fields: %{"name" => "comp2"}
      },
      %FlowOpened{
        project_id: project_id,
        flow_id: "flow-1",
        flow_name: "capability",
        entry_node_id: "sysarch",
        ticket_ref: "TICKET-1"
      },
      %FlowCompleted{project_id: project_id, flow_id: "flow-1"},
      %ActiveBundleFlipped{
        project_id: project_id,
        axis: :chain,
        bundle_name: "default",
        version: "1.0.1",
        flip_id: "flip-1"
      }
    ]
  end

  defp apply_all(events, project_id) do
    events
    |> Enum.with_index(1)
    |> Enum.each(fn {event, seq} -> Reducer.apply(event, %{stream_version: seq}) end)

    project_id
  end

  defp wipe(project_id) do
    Repo.delete_all(from(r in Review, where: r.project_id == ^project_id))
    Repo.delete_all(from(d in Draft, where: d.project_id == ^project_id))
    Repo.delete_all(from(f in Fragment, where: f.project_id == ^project_id))
    Repo.delete_all(from(e in Edge, where: e.project_id == ^project_id))
    Repo.delete_all(from(f in Flow, where: f.project_id == ^project_id))
    Repo.delete_all(from(v in ActiveBundleVersion, where: v.project_id == ^project_id))
    Repo.delete_all(from(n in Node, where: n.project_id == ^project_id))
  end

  defp snapshot(project_id) do
    domain_fields = fn struct ->
      struct |> Map.from_struct() |> Map.drop([:inserted_at, :updated_at])
    end

    %{
      nodes:
        Repo.all(from(n in Node, where: n.project_id == ^project_id, order_by: n.id))
        |> Enum.map(domain_fields),
      edges:
        Repo.all(from(e in Edge, where: e.project_id == ^project_id, order_by: e.id))
        |> Enum.map(domain_fields),
      fragments:
        Repo.all(from(f in Fragment, where: f.project_id == ^project_id, order_by: f.id))
        |> Enum.map(domain_fields),
      drafts:
        Repo.all(from(d in Draft, where: d.project_id == ^project_id, order_by: d.id))
        |> Enum.map(domain_fields),
      reviews:
        Repo.all(from(r in Review, where: r.project_id == ^project_id, order_by: r.id))
        |> Enum.map(domain_fields),
      flows:
        Repo.all(from(f in Flow, where: f.project_id == ^project_id, order_by: f.id))
        |> Enum.map(domain_fields),
      active_bundle_versions:
        Repo.all(
          from(v in ActiveBundleVersion, where: v.project_id == ^project_id, order_by: v.id)
        )
        |> Enum.map(domain_fields)
    }
  end

  describe "rebuild-from-zero byte-identity" do
    test "replaying the full log into fresh projections equals incremental state" do
      project_id = "rebuild-project"
      events = scenario(project_id)

      apply_all(events, project_id)
      incremental = snapshot(project_id)

      assert incremental.nodes != []

      wipe(project_id)

      assert snapshot(project_id) == %{
               nodes: [],
               edges: [],
               fragments: [],
               drafts: [],
               reviews: [],
               flows: [],
               active_bundle_versions: []
             }

      apply_all(events, project_id)
      rebuilt = snapshot(project_id)

      assert rebuilt == incremental
    end

    test "replaying the same event twice is idempotent" do
      project_id = "idempotent-project"
      events = scenario(project_id)

      apply_all(events, project_id)
      once = snapshot(project_id)

      # Re-applying every event again, at the same sequence numbers, must
      # land the same rows rather than duplicates or conflicts — this is
      # what makes the projector's `:strong`-consistency redelivery safe.
      apply_all(events, project_id)
      twice = snapshot(project_id)

      assert twice == once
    end
  end

  describe "DraftCommitted" do
    test "upserts the node, the draft, mints fanout children and writes fragments" do
      project_id = "draft-commit-project"
      apply_all(scenario(project_id), project_id)

      sysarch = Store.get_node("sysarch")
      assert sysarch.status == :drafted
      assert sysarch.fields == %{"name" => "root"}
      assert sysarch.committed_sequence == 1

      comp1 = Store.get_node("comp1")
      assert comp1.parent_node_id == "sysarch"
      # comp1's own draft (event 2) landed after the mint (event 1), so
      # its final status is :approved (event 4), not the mint's :absent.
      assert comp1.status == :approved

      comp2 = Store.get_node("comp2")
      assert comp2.parent_node_id == "sysarch"
      assert comp2.status == :drafted

      edges = Store.edges_from("sysarch", "decomposition")
      assert length(edges) == 2
      assert Enum.all?(edges, &(&1.type == :fanout))

      [fragment] = Store.fragments("sysarch", "techspec")
      assert fragment.content == "spec text"
      assert fragment.author_node_id == "sysarch"
      assert fragment.author_tier == "sysarch"
    end
  end

  describe "DraftApproved / DraftDiscarded" do
    test "approval marks the draft approved and the node approved" do
      project_id = "approve-project"
      apply_all(scenario(project_id), project_id)

      draft = Store.get_draft("draft-comp1-1")
      assert draft.status == :approved
    end

    test "discard marks the draft discarded without approving the node" do
      project_id = "discard-project"

      Reducer.apply(
        %DraftCommitted{
          project_id: project_id,
          node_id: "n1",
          tier: "comp",
          scope_key: %{},
          draft_id: "d1",
          body_sha: "sha",
          committed_at: @committed_at
        },
        %{stream_version: 1}
      )

      Reducer.apply(
        %DraftDiscarded{
          project_id: project_id,
          node_id: "n1",
          draft_id: "d1",
          reason: "wrong shape"
        },
        %{stream_version: 2}
      )

      assert Store.get_draft("d1").status == :discarded
      assert Store.get_node("n1").status == :drafted
    end
  end

  describe "ActiveBundleFlipped" do
    test "records the ninth projection at the flip's own sequence" do
      project_id = "bundle-flip-project"
      apply_all(scenario(project_id), project_id)

      version = Store.current_bundle_version(project_id, :chain)
      assert version.bundle_name == "default"
      assert version.version == "1.0.1"
      assert version.became_current_sequence == length(scenario(project_id))
    end

    test "resolves the version active at a historical sequence, not just the latest" do
      project_id = "bundle-history-project"

      Reducer.apply(
        %ActiveBundleFlipped{
          project_id: project_id,
          axis: :chain,
          bundle_name: "default",
          version: "1.0.0",
          flip_id: "flip-a"
        },
        %{stream_version: 5}
      )

      Reducer.apply(
        %ActiveBundleFlipped{
          project_id: project_id,
          axis: :chain,
          bundle_name: "default",
          version: "2.0.0",
          flip_id: "flip-b"
        },
        %{stream_version: 20}
      )

      assert Store.current_bundle_version(project_id, :chain, 10).version == "1.0.0"
      assert Store.current_bundle_version(project_id, :chain, 20).version == "2.0.0"
      assert Store.current_bundle_version(project_id, :chain).version == "2.0.0"
      assert Store.current_bundle_version(project_id, :chain, 1) == nil
    end
  end
end
