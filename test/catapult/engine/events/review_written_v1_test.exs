defmodule Catapult.Engine.Events.ReviewWrittenV1Test do
  use ExUnit.Case, async: true

  alias Catapult.Engine.Events
  alias Catapult.Engine.Events.ReviewWritten
  alias Catapult.Engine.Events.ReviewWrittenV1
  alias Commanded.Event.Upcaster

  describe "upcast/2" do
    test "converts the historical 0.0-1.0 float score to the current 0-100 integer scale" do
      historical = %ReviewWrittenV1{
        project_id: "proj-1",
        draft_id: "draft-1",
        review_id: "review-1",
        score: 0.92,
        body_sha: "sha-1",
        findings: [%{"id" => "f1", "message" => "nice"}]
      }

      assert %ReviewWritten{
               project_id: "proj-1",
               draft_id: "draft-1",
               review_id: "review-1",
               score: 92,
               body_sha: "sha-1",
               findings: [%{"id" => "f1", "message" => "nice"}],
               kind: :ai
             } == Upcaster.upcast(historical, %{})
    end

    test "rounds rather than truncates" do
      historical = %ReviewWrittenV1{
        project_id: "p",
        draft_id: "d",
        review_id: "r",
        score: 0.605
      }

      assert Upcaster.upcast(historical, %{}).score == 61
    end
  end

  describe "Catapult.Engine.Events.registry/0" do
    test "declares both versions of review_written" do
      assert {:review_written, 1} in Events.registry()
      assert {:review_written, 2} in Events.registry()
    end

    test "module/2 resolves each version to its own struct module" do
      assert Events.module(:review_written, 1) == ReviewWrittenV1
      assert Events.module(:review_written, 2) == ReviewWritten
    end
  end
end
