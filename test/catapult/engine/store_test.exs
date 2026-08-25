defmodule Catapult.Engine.StoreTest do
  use Catapult.DataCase, async: true

  alias Catapult.Engine.Store

  describe "reviews_for_node/2" do
    test "a node never reviewed returns nil" do
      assert Store.reviews_for_node("p1", "no-such-node") == nil
    end

    test "returns the node's own most recent review, regardless of which draft it landed against" do
      Store.upsert_node(%{id: "n1", project_id: "p1", tier: "comp", status: :drafted})

      Store.insert_draft(%{
        id: "d1",
        project_id: "p1",
        node_id: "n1",
        body_sha: "sha1",
        committed_sequence: 1,
        status: :approved
      })

      Store.insert_review(%{
        id: "r1",
        project_id: "p1",
        draft_id: "d1",
        score: 80,
        findings: [],
        body_sha: "sha1",
        kind: :ai
      })

      Store.insert_draft(%{
        id: "d2",
        project_id: "p1",
        node_id: "n1",
        body_sha: "sha2",
        committed_sequence: 2,
        status: :pending
      })

      Store.insert_review(%{
        id: "r2",
        project_id: "p1",
        draft_id: "d2",
        score: 92,
        findings: [%{"id" => "f1"}],
        body_sha: "sha2",
        kind: :ai
      })

      assert %{id: "r2", score: 92, body_sha: "sha2"} = Store.reviews_for_node("p1", "n1")
    end

    test "a review for a node in a different project doesn't bleed in" do
      Store.upsert_node(%{id: "n1", project_id: "p1", tier: "comp", status: :drafted})
      Store.upsert_node(%{id: "n1", project_id: "p2", tier: "comp", status: :drafted})

      Store.insert_draft(%{
        id: "d1",
        project_id: "p2",
        node_id: "n1",
        body_sha: "sha1",
        committed_sequence: 1,
        status: :pending
      })

      Store.insert_review(%{
        id: "r1",
        project_id: "p2",
        draft_id: "d1",
        score: 80,
        findings: [],
        body_sha: "sha1",
        kind: :ai
      })

      assert Store.reviews_for_node("p1", "n1") == nil
    end
  end
end
