defmodule Catapult.Engine.ContainerReducerTest do
  @moduledoc """
  ORC-104's container events folded into engine's own projections
  (`systems/engine.md`), replayed twice to prove the same property the
  chain-axis reducer test already proves: applying an event twice lands
  the same rows, which is what makes rebuild-from-zero a property
  rather than a hope.
  """

  use Catapult.DataCase, async: true

  alias Catapult.Engine.Events.ContainerActivated
  alias Catapult.Engine.Events.ContainerClosed
  alias Catapult.Engine.Events.ContainerMinted
  alias Catapult.Engine.Events.ContainerQueueAdvanced
  alias Catapult.Engine.Events.FindingAdjudicated
  alias Catapult.Engine.Events.FlagSetFlipped
  alias Catapult.Engine.Events.FlagSetFlipRequested
  alias Catapult.Engine.Events.FlowOpened
  alias Catapult.Engine.Reducer
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Container

  defp scenario(project_id) do
    [
      %ContainerMinted{
        project_id: project_id,
        container_id: "root",
        type_name: "project"
      },
      %ContainerActivated{project_id: project_id, container_id: "root", queue: "build-out"},
      %ContainerMinted{
        project_id: project_id,
        container_id: "m1",
        type_name: "milestone",
        parent_container_id: "root",
        parent_queue: "build-out"
      },
      %ContainerActivated{project_id: project_id, container_id: "m1", queue: "setup"},
      %ContainerQueueAdvanced{
        project_id: project_id,
        container_id: "m1",
        from_queue: "setup",
        to_queue: "prep",
        reason: :resolved
      },
      %FindingAdjudicated{
        project_id: project_id,
        container_id: "m1",
        finding_id: "f1",
        disposition: :filed,
        filed_key: "ORC-200"
      },
      %FindingAdjudicated{
        project_id: project_id,
        container_id: "m1",
        finding_id: "f2",
        disposition: :declined,
        reason: "not a defect"
      },
      %FlagSetFlipRequested{
        project_id: project_id,
        container_id: "m1",
        request_id: "r1",
        flags: ["alpha"]
      },
      %FlagSetFlipped{
        project_id: project_id,
        container_id: "m1",
        request_id: "r1",
        flags: ["alpha"]
      },
      %ContainerClosed{project_id: project_id, container_id: "m1"}
    ]
  end

  defp replay(project_id, events) do
    events
    |> Enum.with_index(1)
    |> Enum.each(fn {event, index} -> Reducer.apply(event, %{stream_version: index}) end)

    project_id
  end

  describe "the projection distinguishes what exists from what is current" do
    setup do
      project_id = "cr-#{System.unique_integer([:positive])}"
      replay(project_id, scenario(project_id))
      %{project_id: project_id}
    end

    test "mint and activation are separate writes to the same row", %{project_id: project_id} do
      root = Store.get_container(project_id, "root")

      assert %Container{state: :active, current_queue: "build-out"} = root
      assert root.minted_sequence == 1
      assert root.activated_sequence == 2
      assert root.type_name == "project"
    end

    test "a nested instance records its parent and the queue that opened it", %{
      project_id: project_id
    } do
      assert %Container{parent_container_id: "root", parent_queue: "build-out"} =
               Store.get_container(project_id, "m1")
    end

    test "an advance moves current_queue and records the sequence it became current", %{
      project_id: project_id
    } do
      container = Store.get_container(project_id, "m1")

      assert container.current_queue == "prep"
      assert container.current_queue_sequence == 5
    end

    test "closing records state and sequence without erasing position", %{
      project_id: project_id
    } do
      container = Store.get_container(project_id, "m1")

      assert container.state == :closed
      assert container.closed_sequence == 10
      assert container.current_queue == "prep"
    end

    test "both dispositions land with their evidence", %{project_id: project_id} do
      assert [filed, declined] = Store.container_findings(project_id, "m1")

      assert %{id: "f1", disposition: :filed, filed_key: "ORC-200"} = filed
      assert %{id: "f2", disposition: :declined, reason: "not a defect"} = declined
    end

    test "the flag set moves intent then completion, on one row", %{project_id: project_id} do
      container = Store.get_container(project_id, "m1")

      assert container.flag_set == ["alpha"]
      assert container.flag_set_state == :flipped
      assert container.flag_set_sequence == 9
    end

    test "child_containers/3 finds the instance a parent's queue is waiting on", %{
      project_id: project_id
    } do
      assert [%Container{id: "m1"}] = Store.child_containers(project_id, "root", "build-out")
      assert Store.child_containers(project_id, "root", "iteration") == []
    end

    test "the outermost instance is found by a nil parent", %{project_id: project_id} do
      assert [%Container{id: "root"}] = Store.child_containers(project_id, nil, nil)
    end
  end

  describe "rebuild-from-zero" do
    test "replaying the same events twice lands the same rows" do
      project_id = "cr-replay-#{System.unique_integer([:positive])}"
      events = scenario(project_id)

      replay(project_id, events)
      first = {Store.get_container(project_id, "m1"), Store.container_findings(project_id, "m1")}

      replay(project_id, events)
      second = {Store.get_container(project_id, "m1"), Store.container_findings(project_id, "m1")}

      assert elem(first, 0).id == elem(second, 0).id
      assert elem(first, 0).state == elem(second, 0).state
      assert length(elem(second, 1)) == 2
    end
  end

  describe "membership rides the opening event" do
    test "FlowOpened's container_id and queue land on the flow row" do
      project_id = "cr-flow-#{System.unique_integer([:positive])}"

      Store.upsert_node(%{
        id: "entry",
        project_id: project_id,
        tier: "sysarch",
        scope_key: %{},
        status: :absent
      })

      event = %FlowOpened{
        project_id: project_id,
        flow_id: "w1",
        flow_name: "feature",
        entry_node_id: "entry",
        container_id: "m1",
        queue: "main"
      }

      Reducer.apply(event, %{stream_version: 1})

      assert %{container_id: "m1", queue: "main"} = Store.get_flow(project_id, "w1")
    end

    test "a work item belonging to no container carries nils, not a guess" do
      project_id = "cr-unowned-#{System.unique_integer([:positive])}"

      Store.upsert_node(%{
        id: "entry",
        project_id: project_id,
        tier: "sysarch",
        scope_key: %{},
        status: :absent
      })

      event = %FlowOpened{
        project_id: project_id,
        flow_id: "w1",
        flow_name: "feature",
        entry_node_id: "entry"
      }

      Reducer.apply(event, %{stream_version: 1})

      assert %{container_id: nil, queue: nil} = Store.get_flow(project_id, "w1")
    end
  end
end
