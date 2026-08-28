defmodule Catapult.Engine.Projections.ContainerQueuesTest do
  @moduledoc """
  The queue-as-query (dsl-syntax.md §15.7, v5 §7.8): a queue's
  population is computed from the work items themselves, and the three
  things that hold a queue open — its own population, a nested
  instance still running, and a sibling that `blocks:` it — are checked
  here against real rows rather than a stubbed projection.
  """

  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Projections.ContainerQueues
  alias Catapult.Engine.Store

  @project "cq-project"

  # A container type shaped like the shipped milestone: `main` blocks
  # `retro`, and `setup`/`retro` are non-queue-shaped inline dispatch
  # points (no `flow:`, ORC-148's replacement for the retired
  # `singleton:` field).
  defp workflow do
    milestone = %Type{
      name: "milestone",
      file: "types/milestone.yaml",
      skeleton: "container",
      statuses: [
        %Status{status: "setup"},
        %Status{status: "prep", flow: "feature"},
        %Status{status: "main", flow: "feature", blocks: ["retro"]},
        %Status{status: "retro"},
        %Status{status: "cleanup", flow: "feature"},
        %Status{status: "terminal"}
      ]
    }

    nesting = %Type{
      name: "epic",
      file: "types/epic.yaml",
      skeleton: "container",
      statuses: [
        %Status{status: "setup", flow: "setup"},
        %Status{status: "prep", flow: "feature"},
        %Status{status: "main", flow: "milestone"},
        %Status{status: "retro", flow: "retro"},
        %Status{status: "cleanup", flow: "feature"},
        %Status{status: "terminal"}
      ]
    }

    %Workflow{
      name: "test",
      entry: "epic",
      gates: %{},
      environments: %{},
      types: %{"milestone" => milestone, "epic" => nesting}
    }
  end

  defp container!(id, type_name \\ "milestone", opts \\ []) do
    Store.mint_container(
      %{
        id: id,
        project_id: @project,
        type_name: type_name,
        state: :active,
        minted_sequence: 1
      }
      |> Map.merge(Map.new(opts))
    )

    Store.get_container(@project, id)
  end

  # `engine_flows.entry_node_id` is a non-null foreign key into
  # `engine_nodes`, so a work item needs a real node to point at. One
  # shared node is enough: nothing here reads the node itself.
  defp entry_node! do
    Store.upsert_node(%{
      id: "entry",
      project_id: @project,
      tier: "sysarch",
      scope_key: %{},
      status: :absent
    })

    "entry"
  end

  defp work_item!(container_id, queue, id, status \\ :open) do
    Store.insert_flow(%{
      id: id,
      project_id: @project,
      flow_name: "feature",
      entry_node_id: entry_node!(),
      container_id: container_id,
      queue: queue,
      status: status,
      opened_sequence: 2
    })
  end

  describe "population/2 — the query, never a bucket" do
    test "an empty queue has an empty population" do
      container = container!("c-empty")

      assert ContainerQueues.population(container, "main") == []
    end

    test "counts only unresolved work items in this container at this queue" do
      container = container!("c-pop")
      other = container!("c-other")

      work_item!(container.id, "main", "w-open")
      work_item!(container.id, "main", "w-done", :completed)
      work_item!(container.id, "prep", "w-elsewhere")
      work_item!(other.id, "main", "w-other-container")

      assert [%{id: "w-open"}] = ContainerQueues.population(container, "main")
    end
  end

  describe "resolution/3" do
    test "a queue carrying unresolved work is open" do
      container = container!("c-open")
      work_item!(container.id, "main", "w1")

      assert ContainerQueues.resolution(workflow(), container, "main") == :open
    end

    test "an empty queue with nothing blocking it resolves" do
      container = container!("c-resolved")

      assert ContainerQueues.resolution(workflow(), container, "prep") == :resolved
    end

    test "main holds retro open while main still carries work (§15.7)" do
      container = container!("c-blocks")
      work_item!(container.id, "main", "w1")

      assert ContainerQueues.resolution(workflow(), container, "retro") ==
               {:held, ["main"]}
    end

    test "retro resolves once main has emptied" do
      container = container!("c-blocks-cleared")
      work_item!(container.id, "main", "w1", :completed)

      assert ContainerQueues.resolution(workflow(), container, "retro") == :resolved
    end

    test "a resolved queue un-resolves when its population refills (§15.8's first backward move)" do
      container = container!("c-refill")

      assert ContainerQueues.resolution(workflow(), container, "prep") == :resolved

      work_item!(container.id, "prep", "w-late")

      assert ContainerQueues.resolution(workflow(), container, "prep") == :open
    end

    test "a nesting queue does not resolve while a minted instance is still open" do
      parent = container!("c-parent", "epic")

      Store.mint_container(%{
        id: "c-child",
        project_id: @project,
        type_name: "milestone",
        parent_container_id: parent.id,
        parent_queue: "main",
        state: :active,
        minted_sequence: 3
      })

      assert ContainerQueues.resolution(workflow(), parent, "main") == :open

      Store.close_container(@project, "c-child", 9)

      assert ContainerQueues.resolution(workflow(), parent, "main") == :resolved
    end

    test "a gate citation is never resolved by a population emptying" do
      # A gate is resolved by a human's transition. Reporting it open is
      # what keeps the dispatcher from advancing past a human.
      container = container!("c-gate")

      assert ContainerQueues.resolution(workflow(), container, "some-gate") == :open
    end

    test "terminal is not a queue and never reports resolved" do
      container = container!("c-terminal")

      assert ContainerQueues.resolution(workflow(), container, "terminal") == :open
    end
  end

  describe "admits?/3 — singleton is a lifetime bound, not a population bound (§15.7)" do
    test "an untouched singleton queue admits its one work item" do
      container = container!("c-singleton")

      assert {:ok, %Status{status: "setup"}} =
               ContainerQueues.admits?(workflow(), container, "setup")
    end

    test "a singleton queue holding an unresolved work item is closed" do
      container = container!("c-singleton-busy")
      work_item!(container.id, "setup", "w-setup")

      assert {:error, :singleton_closed} =
               ContainerQueues.admits?(workflow(), container, "setup")
    end

    test "a singleton queue stays closed once its work item is terminal" do
      # The sixth-pass correction: emptiness here is closure, not room.
      # A population-scoped bound would read this as an opening.
      container = container!("c-singleton-done")
      work_item!(container.id, "setup", "w-setup", :completed)

      assert ContainerQueues.population(container, "setup") == []

      assert {:error, :singleton_closed} =
               ContainerQueues.admits?(workflow(), container, "setup")
    end

    test "a non-singleton queue admits work after earlier work resolved" do
      container = container!("c-plain")
      work_item!(container.id, "prep", "w-done", :completed)

      assert {:ok, %Status{status: "prep"}} =
               ContainerQueues.admits?(workflow(), container, "prep")
    end

    test "an unknown queue is reported as such rather than admitted" do
      container = container!("c-unknown")

      assert {:error, :unknown_queue} =
               ContainerQueues.admits?(workflow(), container, "no-such-queue")
    end
  end

  describe "entries/2" do
    test "a container whose type no longer resolves yields no entries" do
      # A workflow cutover can retire a type out from under a live
      # instance; the answer is to leave it standing, not to crash.
      container = container!("c-retired", "no-longer-declared")

      assert ContainerQueues.entries(workflow(), container) == []
    end
  end

  describe "membership survives resolution — a container is a path to its own history" do
    test "container_work_items/2 returns resolved work too" do
      container = container!("c-history")
      work_item!(container.id, "main", "w-open")
      work_item!(container.id, "main", "w-done", :completed)

      ids = @project |> Store.container_work_items(container.id) |> Enum.map(& &1.id)

      assert Enum.sort(ids) == ["w-done", "w-open"]
    end
  end
end
