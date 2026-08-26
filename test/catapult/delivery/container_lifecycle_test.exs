defmodule Catapult.Delivery.ContainerLifecycleTest do
  @moduledoc """
  The dispatcher's decision, taken synchronously
  (`ContainerLifecycle.next_commands/2`) rather than by driving the
  process manager and waiting for its convergence loop to settle.

  That is a deliberate testing choice, not a shortcut. The manager
  dispatches with `consistency: :eventual` — it has to; a strongly
  consistent dispatch from inside its own `handle/2` deadlocks against
  itself — so an end-to-end cascade test would have to sleep or poll,
  and conventions §9 makes determinism a protocol requirement: the
  pipeline escalates two CI reds to a human, so a flaky suite
  mechanically defeats the automation. `next_commands/2` is the whole
  decision and is exercised here against real rows; the manager around
  it is the thin part.

  Loads the shipped `bundles/default-flow`, so a change to the declared
  `project`/`milestone` types is caught here too.
  """

  use Catapult.DataCase, async: true

  alias Catapult.Delivery.ContainerLifecycle
  alias Catapult.Delivery.ContainerLifecycle.Ids
  alias Catapult.Dsl.Workflow
  alias Catapult.Engine.Commands.ActivateContainer
  alias Catapult.Engine.Commands.AdvanceContainerQueue
  alias Catapult.Engine.Commands.CloseContainer
  alias Catapult.Engine.Commands.MintContainer
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.RequestFlagSetFlip
  alias Catapult.Engine.Store
  alias Commanded.Serialization.JsonSerializer
  alias Commanded.Serialization.ModuleNameTypeProvider

  @project "cl-project"

  setup do
    assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
    %{workflow: workflow}
  end

  defp container!(id, type_name, opts) do
    attrs =
      Map.merge(
        %{
          id: id,
          project_id: @project,
          type_name: type_name,
          state: :active,
          minted_sequence: 1,
          activated_sequence: 2
        },
        Map.new(opts)
      )

    Store.mint_container(attrs)
    Store.get_container(@project, id)
  end

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
      opened_sequence: 3
    })
  end

  describe "nothing runs for an instance that is not active" do
    test "a merely minted instance issues nothing", %{workflow: workflow} do
      container = container!("c-minted", "milestone", state: :minted, current_queue: nil)

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "a closed instance issues nothing", %{workflow: workflow} do
      container = container!("c-closed", "milestone", state: :closed, current_queue: "terminal")

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end
  end

  describe "dispatch is uniform: what happens follows from the resolved declaration (§15.7)" do
    test "a queue whose flow: nests mints a child instance", %{workflow: workflow} do
      # The project's `build-out` entry names `flow: milestone`, which
      # is a container-skeleton type.
      container = container!("c-project", "project", current_queue: "build-out")

      assert [%MintContainer{} = cmd] = ContainerLifecycle.next_commands(workflow, container)
      assert cmd.type_name == "milestone"
      assert cmd.parent_container_id == "c-project"
      assert cmd.parent_queue == "build-out"
      assert cmd.container_id == Ids.container_id(@project, "c-project", "build-out")
    end

    test "an already-minted child is activated rather than joined by a second", %{
      workflow: workflow
    } do
      # Grooming ahead: the instance exists before the parent's
      # position reached it (§15.8).
      container = container!("c-project-2", "project", current_queue: "build-out")

      Store.mint_container(%{
        id: "c-groomed",
        project_id: @project,
        type_name: "milestone",
        parent_container_id: container.id,
        parent_queue: "build-out",
        state: :minted,
        minted_sequence: 5
      })

      assert [%ActivateContainer{} = cmd] = ContainerLifecycle.next_commands(workflow, container)
      assert cmd.container_id == "c-groomed"
      # Its own first declared entry, never a value carried on the
      # parent's dispatching entry (§15.8).
      assert cmd.queue == "setup"
    end

    test "an active child neither re-mints nor re-activates", %{workflow: workflow} do
      container = container!("c-project-3", "project", current_queue: "build-out")

      Store.mint_container(%{
        id: "c-running",
        project_id: @project,
        type_name: "milestone",
        parent_container_id: container.id,
        parent_queue: "build-out",
        state: :active,
        minted_sequence: 5
      })

      # The parent's queue does not complete until the minted instance
      # closes (§15.7), so nothing moves either.
      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "a singleton queue opens its one work item", %{workflow: workflow} do
      container = container!("c-setup", "milestone", current_queue: "setup")

      assert [%OpenFlow{} = cmd] = ContainerLifecycle.next_commands(workflow, container)
      assert cmd.container_id == "c-setup"
      assert cmd.queue == "setup"
      assert cmd.flow_name == "setup"
      assert cmd.flow_id == Ids.work_item_id(@project, "c-setup", "setup")
    end

    test "a singleton queue whose work item is already terminal opens nothing more", %{
      workflow: workflow
    } do
      # A closed singleton queue is what the declaration asked for.
      container = container!("c-setup-done", "milestone", current_queue: "setup")
      work_item!(container.id, "setup", "w-setup", :completed)

      commands = ContainerLifecycle.next_commands(workflow, container)

      refute Enum.any?(commands, &match?(%OpenFlow{}, &1))
    end

    test "an ordinary ticket queue manufactures no work", %{workflow: workflow} do
      # `prep` holds whatever grooming assigned to it. A dispatcher
      # that invented entries for it would be inventing scope.
      container = container!("c-prep", "milestone", current_queue: "prep")

      refute Enum.any?(
               ContainerLifecycle.next_commands(workflow, container),
               &match?(%OpenFlow{}, &1)
             )
    end
  end

  describe "the position moves only when the declaration lets it" do
    test "an empty, unblocked queue advances to the next entry", %{workflow: workflow} do
      container = container!("c-advance", "milestone", current_queue: "prep")

      assert [%AdvanceContainerQueue{} = cmd] =
               ContainerLifecycle.next_commands(workflow, container)

      assert cmd.from_queue == "prep"
      assert cmd.to_queue == "main"
      assert cmd.reason == :resolved
    end

    test "a queue carrying unresolved work does not advance", %{workflow: workflow} do
      container = container!("c-busy", "milestone", current_queue: "main")
      work_item!(container.id, "main", "w-main")

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "the plane stops at a gate — the author's transition is a human's command", %{
      workflow: workflow
    } do
      # `milestone`'s array puts `milestone-signoff` after `main`: "my
      # manual pass is finished" (v5 §7.8).
      container = container!("c-gate", "milestone", current_queue: "main")

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "a container at retro while main refilled is walked back to main, not started", %{
      workflow: workflow
    } do
      # `main` sits earlier in `milestone`'s array than `retro`, so the
      # blocking relation and the refill rule point the same way and
      # the refill rule is the sharper one: the container does not
      # merely wait at `retro`, it is no longer past `main` at all
      # (§15.8). What matters for the hold is what does *not* happen —
      # `retro`'s singleton work item is not opened.
      held = container!("c-held", "milestone", current_queue: "retro")
      work_item!(held.id, "main", "w-still-open")

      commands = ContainerLifecycle.next_commands(workflow, held)

      assert [%AdvanceContainerQueue{to_queue: "main", reason: :repopulated}] = commands
      refute Enum.any?(commands, &match?(%OpenFlow{}, &1))
    end

    test "retro opens its one work item once main has emptied", %{workflow: workflow} do
      released = container!("c-released", "milestone", current_queue: "retro")
      work_item!(released.id, "main", "w-finished", :completed)

      assert [%OpenFlow{queue: "retro"}] =
               ContainerLifecycle.next_commands(workflow, released)
    end

    test "a blocker later in the array holds without a backward move", %{workflow: _workflow} do
      # `blocks:` may name any sibling, not only an earlier one. When
      # the blocker sits later, there is nothing to walk back to and the
      # hold is the whole answer — the branch the shipped bundle's own
      # `main`/`retro` pair never reaches.
      workflow = blocking_workflow()
      container = container!("c-held-late", "held-type", current_queue: "first")
      work_item!(container.id, "second", "w-blocking")

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "a refilled earlier queue moves the position back (§15.8)", %{workflow: workflow} do
      # No gate, no throwback, no separate event: a queue is a query, so
      # a resolved queue un-resolves the moment its population refills.
      container = container!("c-back", "milestone", current_queue: "cleanup")
      work_item!(container.id, "prep", "w-late")

      assert [%AdvanceContainerQueue{} = cmd] =
               ContainerLifecycle.next_commands(workflow, container)

      assert cmd.from_queue == "cleanup"
      assert cmd.to_queue == "prep"
      assert cmd.reason == :repopulated
    end
  end

  # `second` blocks `first` while carrying work, and `first` is a
  # singleton — so a bug that opened work in a held queue would show up
  # as an OpenFlow here.
  defp blocking_workflow do
    type = %Catapult.Dsl.Type{
      name: "held-type",
      file: "types/held-type.yaml",
      skeleton: nil,
      statuses: [
        %Catapult.Dsl.Status{status: "first", flow: "feature", singleton: true},
        %Catapult.Dsl.Status{status: "second", flow: "feature", blocks: ["first"]}
      ]
    }

    %Workflow{
      name: "test",
      entry: "held-type",
      gates: %{},
      environments: %{},
      types: %{"held-type" => type}
    }
  end

  describe "closing" do
    test "a container at its last entry requests the flag flip and closes", %{workflow: workflow} do
      container = container!("c-close", "milestone", current_queue: "cleanup")

      commands = ContainerLifecycle.next_commands(workflow, container)

      assert [%RequestFlagSetFlip{} = flip, %CloseContainer{} = close] = commands
      assert close.container_id == "c-close"
      assert flip.request_id == Ids.flag_request_id(@project, "c-close")
      # Empty today: nothing in this tree declares a feature flag yet
      # (conventions §13 defers flag consumption).
      assert flip.flags == []
    end

    test "a flip already requested is not requested again", %{workflow: workflow} do
      container =
        container!("c-close-2", "milestone",
          current_queue: "cleanup",
          flag_set_state: :requested
        )

      assert [%CloseContainer{}] = ContainerLifecycle.next_commands(workflow, container)
    end

    test "a skeleton-less instance closes on its own last declared entry (§15.6)", %{
      workflow: workflow
    } do
      # A project has no universal terminal, because it has no
      # universal sequence to end.
      container = container!("c-project-end", "project", current_queue: "sunsetting")

      assert [%RequestFlagSetFlip{}, %CloseContainer{}] =
               ContainerLifecycle.next_commands(workflow, container)
    end
  end

  describe "no container closes over an unadjudicated finding (v5 §7.8)" do
    setup %{workflow: workflow} do
      container = container!("c-findings", "milestone", current_queue: "cleanup")

      Store.upsert_node(%{
        id: "n-reviewed",
        project_id: @project,
        tier: "sysarch",
        scope_key: %{},
        status: :drafted
      })

      Store.insert_draft(%{
        id: "d-reviewed",
        project_id: @project,
        node_id: "n-reviewed",
        body_sha: "sha",
        committed_sequence: 5,
        status: :pending
      })

      Store.insert_review(%{
        id: "r1",
        project_id: @project,
        draft_id: "d-reviewed",
        score: 70,
        findings: [%{"id" => "f1", "message" => "the thing"}],
        body_sha: "sha",
        kind: :ai
      })

      %{workflow: workflow, container: container}
    end

    test "the close is held while a carried finding is unread", %{
      workflow: workflow,
      container: container
    } do
      assert ContainerLifecycle.next_commands(workflow, container) == []
    end

    test "adjudicating it releases the close", %{workflow: workflow, container: container} do
      Store.adjudicate_finding(%{
        id: "f1",
        project_id: @project,
        container_id: container.id,
        disposition: :declined,
        reason: "already fixed by the rewrite",
        adjudicated_sequence: 7
      })

      assert [%RequestFlagSetFlip{}, %CloseContainer{}] =
               ContainerLifecycle.next_commands(workflow, container)
    end

    test "filed and declined both count as read — neither is deferral", %{
      workflow: workflow,
      container: container
    } do
      Store.adjudicate_finding(%{
        id: "f1",
        project_id: @project,
        container_id: container.id,
        disposition: :filed,
        filed_key: "ORC-200",
        adjudicated_sequence: 7
      })

      assert [%RequestFlagSetFlip{}, %CloseContainer{}] =
               ContainerLifecycle.next_commands(workflow, container)
    end
  end

  describe "a container whose type was retired mid-flight stands still" do
    test "no steps, no commands", %{workflow: workflow} do
      container = container!("c-retired", "no-longer-declared", current_queue: "main")

      assert ContainerLifecycle.next_commands(workflow, container) == []
    end
  end

  describe "JSON round trip (ORC-120)" do
    # `Commanded.ProcessManagers.ProcessManagerInstance` calls
    # `persist_state/2` after every handled event, serializing this
    # exact struct through `Commanded.Serialization.JsonSerializer` —
    # the same round trip proven against `FeatureLifecycle`. `state` is
    # this struct's own hazard: `Jason` encodes the atom to a JSON
    # string, and `struct/2` restores it as that bare string unless the
    # `JsonDecoder` implementation reconstructs it.
    test "a process manager instance round-trips through Commanded's own serializer, for every declared state" do
      for state <- [:minted, :active, :closed] do
        pm = %ContainerLifecycle{
          project_id: "proj-1",
          container_id: "container-1",
          type_name: "milestone",
          queue: "main",
          state: state
        }

        type = ModuleNameTypeProvider.to_string(pm)

        assert pm
               |> JsonSerializer.serialize()
               |> JsonSerializer.deserialize(type: type) == pm
      end
    end
  end
end
