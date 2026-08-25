defmodule Catapult.Engine.ContainerAggregateTest do
  @moduledoc """
  Command validation for ORC-104's container edge (dsl-syntax.md
  §15.6-§15.8, v5 §7.1, §7.8) — pure `execute/2`/`apply/2` against the
  same single per-project aggregate every chain-axis command already
  lands on, never a second one.
  """

  use ExUnit.Case, async: true

  alias Catapult.Engine.Aggregate
  alias Catapult.Engine.Commands.ActivateContainer
  alias Catapult.Engine.Commands.AdjudicateFinding
  alias Catapult.Engine.Commands.AdvanceContainerQueue
  alias Catapult.Engine.Commands.CloseContainer
  alias Catapult.Engine.Commands.MintContainer
  alias Catapult.Engine.Commands.RecordFlagSetFlip
  alias Catapult.Engine.Commands.RequestFlagSetFlip
  alias Catapult.Engine.Events.ContainerActivated
  alias Catapult.Engine.Events.ContainerClosed
  alias Catapult.Engine.Events.ContainerMinted
  alias Catapult.Engine.Events.ContainerQueueAdvanced
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.FlagSetFlipped
  alias Catapult.Engine.Events.FlagSetFlipRequested

  defp mint(agg \\ %Aggregate{}, id \\ "c1") do
    cmd = %MintContainer{project_id: "p1", container_id: id, type_name: "milestone"}
    Aggregate.apply(agg, Aggregate.execute(agg, cmd))
  end

  defp activate(agg, id \\ "c1", queue \\ "setup") do
    cmd = %ActivateContainer{project_id: "p1", container_id: id, queue: queue}
    Aggregate.apply(agg, Aggregate.execute(agg, cmd))
  end

  describe "MintContainer" do
    test "produces ContainerMinted" do
      cmd = %MintContainer{
        project_id: "p1",
        container_id: "c1",
        type_name: "milestone",
        parent_container_id: "root",
        parent_queue: "build-out"
      }

      assert %ContainerMinted{
               container_id: "c1",
               type_name: "milestone",
               parent_container_id: "root",
               parent_queue: "build-out"
             } = Aggregate.execute(%Aggregate{}, cmd)
    end

    test "minting the same id twice is a conflict" do
      agg = mint()
      cmd = %MintContainer{project_id: "p1", container_id: "c1", type_name: "milestone"}

      assert {:error, {:engine_container_exists, container_id: "c1"}} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "ActivateContainer" do
    test "a minted instance activates at its own first entry" do
      agg = mint()
      cmd = %ActivateContainer{project_id: "p1", container_id: "c1", queue: "setup"}

      assert %ContainerActivated{container_id: "c1", queue: "setup"} =
               Aggregate.execute(agg, cmd)
    end

    test "an unminted instance cannot activate" do
      cmd = %ActivateContainer{project_id: "p1", container_id: "ghost", queue: "setup"}

      assert {:error, {:engine_container_not_minted, container_id: "ghost"}} =
               Aggregate.execute(%Aggregate{}, cmd)
    end

    test "activating twice is refused — setup runs once, at activation (§15.8)" do
      agg = mint() |> activate()
      cmd = %ActivateContainer{project_id: "p1", container_id: "c1", queue: "setup"}

      assert {:error, {:engine_container_not_activatable, container_id: "c1", state: :active}} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "AdvanceContainerQueue" do
    test "moves the current queue when from_queue matches" do
      agg = mint() |> activate()

      cmd = %AdvanceContainerQueue{
        project_id: "p1",
        container_id: "c1",
        from_queue: "setup",
        to_queue: "prep",
        reason: :resolved
      }

      assert %ContainerQueueAdvanced{from_queue: "setup", to_queue: "prep", reason: :resolved} =
               Aggregate.execute(agg, cmd)
    end

    test "a stale from_queue is rejected, not applied (v5 §7.16)" do
      # Two sign-off holders racing on a milestone gate: first writer
      # wins, and the loser is told rather than silently double-advancing.
      agg = mint() |> activate()

      cmd = %AdvanceContainerQueue{
        project_id: "p1",
        container_id: "c1",
        from_queue: "main",
        to_queue: "retro",
        reason: :resolved
      }

      assert {:error,
              {:engine_container_queue_conflict,
               container_id: "c1", expected: "main", current: "setup"}} =
               Aggregate.execute(agg, cmd)
    end

    test "a merely minted instance has no queue to advance" do
      agg = mint()

      cmd = %AdvanceContainerQueue{
        project_id: "p1",
        container_id: "c1",
        from_queue: "setup",
        to_queue: "prep",
        reason: :resolved
      }

      assert {:error, {:engine_container_not_active, container_id: "c1", state: :minted}} =
               Aggregate.execute(agg, cmd)
    end

    test "a backward move is the same command with a different reason" do
      agg = mint() |> activate("c1", "retro")

      cmd = %AdvanceContainerQueue{
        project_id: "p1",
        container_id: "c1",
        from_queue: "retro",
        to_queue: "main",
        reason: :throwback
      }

      assert %ContainerQueueAdvanced{to_queue: "main", reason: :throwback} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "CloseContainer" do
    test "an active instance closes" do
      agg = mint() |> activate()

      assert %ContainerClosed{container_id: "c1"} =
               Aggregate.execute(agg, %CloseContainer{project_id: "p1", container_id: "c1"})
    end

    test "a closed instance cannot close again" do
      agg = mint() |> activate()
      agg = Aggregate.apply(agg, %ContainerClosed{project_id: "p1", container_id: "c1"})

      assert {:error, {:engine_container_not_active, container_id: "c1", state: :closed}} =
               Aggregate.execute(agg, %CloseContainer{project_id: "p1", container_id: "c1"})
    end
  end

  describe "AdjudicateFinding — every carried finding leaves adjudicated (v5 §7.8)" do
    setup do: %{agg: mint()}

    test "filed under its own key", %{agg: agg} do
      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :filed,
        filed_key: "ORC-200"
      }

      assert %FindingAdjudicated{disposition: :filed, filed_key: "ORC-200"} =
               Aggregate.execute(agg, cmd)
    end

    test "declined with a recorded reason", %{agg: agg} do
      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :declined,
        reason: "superseded by the rewrite in ORC-198"
      }

      assert %FindingAdjudicated{disposition: :declined, reason: "superseded" <> _} =
               Aggregate.execute(agg, cmd)
    end

    test "filed with no key is refused — a disposition without evidence is deferral", %{agg: agg} do
      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :filed
      }

      assert {:error, {:engine_finding_filed_without_key, finding_id: "f1"}} =
               Aggregate.execute(agg, cmd)
    end

    test "declined with a blank reason is refused", %{agg: agg} do
      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :declined,
        reason: "   "
      }

      assert {:error, {:engine_finding_declined_without_reason, finding_id: "f1"}} =
               Aggregate.execute(agg, cmd)
    end

    test "a second adjudication of the same finding is a conflict", %{agg: agg} do
      event = %FindingAdjudicated{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :filed,
        filed_key: "ORC-200"
      }

      agg = Aggregate.apply(agg, event)

      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :declined,
        reason: "changed my mind"
      }

      assert {:error,
              {:engine_finding_already_adjudicated,
               container_id: "c1", finding_id: "f1", disposition: :filed}} =
               Aggregate.execute(agg, cmd)
    end

    test "an unknown disposition is refused", %{agg: agg} do
      cmd = %AdjudicateFinding{
        project_id: "p1",
        container_id: "c1",
        finding_id: "f1",
        disposition: :deferred
      }

      assert {:error,
              {:engine_finding_disposition_unknown, finding_id: "f1", disposition: :deferred}} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "the flag set flips through intent then completion (v5 §7.1)" do
    setup do: %{agg: mint()}

    test "intent is recorded once", %{agg: agg} do
      cmd = %RequestFlagSetFlip{
        project_id: "p1",
        container_id: "c1",
        request_id: "r1",
        flags: ["a", "b"]
      }

      assert %FlagSetFlipRequested{request_id: "r1", flags: ["a", "b"]} =
               Aggregate.execute(agg, cmd)

      agg = Aggregate.apply(agg, Aggregate.execute(agg, cmd))

      assert {:error,
              {:engine_flag_flip_already_requested, container_id: "c1", state: :requested}} =
               Aggregate.execute(agg, cmd)
    end

    test "completion requires an intent to complete", %{agg: agg} do
      cmd = %RecordFlagSetFlip{
        project_id: "p1",
        container_id: "c1",
        request_id: "r1",
        flags: []
      }

      assert {:error, {:engine_flag_flip_not_requested, container_id: "c1", state: nil}} =
               Aggregate.execute(agg, cmd)
    end

    test "completion after intent produces FlagSetFlipped", %{agg: agg} do
      request = %FlagSetFlipRequested{
        project_id: "p1",
        container_id: "c1",
        request_id: "r1",
        flags: ["a"]
      }

      agg = Aggregate.apply(agg, request)

      cmd = %RecordFlagSetFlip{
        project_id: "p1",
        container_id: "c1",
        request_id: "r1",
        flags: ["a"]
      }

      assert %FlagSetFlipped{request_id: "r1", flags: ["a"]} = Aggregate.execute(agg, cmd)
    end

    test "the log never says done twice", %{agg: agg} do
      agg =
        agg
        |> Aggregate.apply(%FlagSetFlipRequested{
          project_id: "p1",
          container_id: "c1",
          request_id: "r1",
          flags: []
        })
        |> Aggregate.apply(%FlagSetFlipped{
          project_id: "p1",
          container_id: "c1",
          request_id: "r1",
          flags: []
        })

      cmd = %RecordFlagSetFlip{
        project_id: "p1",
        container_id: "c1",
        request_id: "r1",
        flags: []
      }

      assert {:error, {:engine_flag_flip_not_requested, container_id: "c1", state: :flipped}} =
               Aggregate.execute(agg, cmd)
    end
  end

  describe "rehydration survives a stream it did not write" do
    test "an event for an unknown container is ignored rather than crashing" do
      event = %ContainerActivated{project_id: "p1", container_id: "ghost", queue: "setup"}

      assert %Aggregate{containers: containers} = Aggregate.apply(%Aggregate{}, event)
      assert containers == %{}
    end
  end
end
