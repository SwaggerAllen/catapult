defmodule Catapult.Delivery.ContainerLifecycle.SequenceTest do
  @moduledoc """
  Array-index navigation (dsl-syntax.md §15.3): "what comes next" is
  literally the next element. Run against the shipped
  `bundles/default-flow`, so a change to the declared types is caught
  here.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.ContainerLifecycle.Sequence
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Workflow

  setup do
    assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
    %{workflow: workflow}
  end

  test "a container's steps are its required backbone plus whatever else it declares", %{
    workflow: workflow
  } do
    names = workflow |> Sequence.steps("milestone") |> Enum.map(&Sequence.name/1)

    assert names == [
             "pending",
             "setup",
             "kickoff-review",
             "prep",
             "main",
             "milestone-signoff",
             "pending",
             "retro",
             "proposals-read",
             "cleanup",
             "deploy",
             "terminal"
           ]
  end

  test "terminal is a step of its own, never a queue", %{workflow: workflow} do
    assert Sequence.step(workflow, "milestone", "terminal") == :terminal
    assert {:queue, %Status{status: "main"}} = Sequence.step(workflow, "milestone", "main")

    assert Sequence.step(workflow, "milestone", "milestone-signoff") ==
             {:gate, "milestone-signoff"}
  end

  test "a skeleton-less type ends on its own last declared entry", %{workflow: workflow} do
    names = workflow |> Sequence.steps("project") |> Enum.map(&Sequence.name/1)

    assert List.last(names) == "sunsetting"
    refute "terminal" in names
    assert Sequence.next_step(workflow, "project", "sunsetting") == nil
  end

  test "first_step/2 is what an activation starts at", %{workflow: workflow} do
    assert Sequence.first_step(workflow, "milestone") |> Sequence.name() == "pending"
    assert Sequence.first_step(workflow, "project") |> Sequence.name() == "initialization"
  end

  test "next_step/3 walks by index, gates included", %{workflow: workflow} do
    assert Sequence.next_step(workflow, "milestone", "main") == {:gate, "milestone-signoff"}

    assert {:queue, %Status{status: "pending"}} =
             Sequence.next_step(workflow, "milestone", "milestone-signoff")

    assert {:queue, %Status{status: "deploy"}} =
             Sequence.next_step(workflow, "milestone", "cleanup")
  end

  test "earlier?/4 is the live half of the throwback check", %{workflow: workflow} do
    # §15.8's worked case: a milestone sign-off gate between `main` and
    # `retro` rejecting back to `main`.
    assert Sequence.earlier?(workflow, "milestone", "milestone-signoff", "main")
    refute Sequence.earlier?(workflow, "milestone", "main", "milestone-signoff")
    refute Sequence.earlier?(workflow, "milestone", "main", "main")
    refute Sequence.earlier?(workflow, "milestone", "main", "no-such-entry")
  end

  test "a type that does not resolve has no steps rather than raising", %{workflow: workflow} do
    assert Sequence.steps(workflow, "no-such-type") == []
    assert Sequence.first_step(workflow, "no-such-type") == nil
    assert Sequence.next_step(workflow, "no-such-type", "anything") == nil
  end

  describe "a bare name recurring across two sub-arrays (dsl-syntax.md §15.2, ORC-116)" do
    # `types/milestone.yaml` avoids this today by omitting `retro`'s own
    # leading `pending`, precisely because this module's own bare-name
    # lookup used to have no namespace awareness (`docs/dsl-syntax.md`
    # §15.2's own note). Built here as a struct — the loader accepts
    # this shape (§15.12 only refuses a collision *within* one
    # sub-array) — to prove the fix rather than the workaround.
    setup do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "setup"},
        %Status{status: "pending"},
        %Status{status: "retro"},
        %Status{status: "terminal"}
      ]

      type = %Catapult.Dsl.Type{
        name: "t",
        file: "types/t.yaml",
        skeleton: "container",
        statuses: statuses,
        groups: [0..1//1, 2..3//1]
      }

      workflow = %Workflow{name: "test", entry: "t", types: %{"t" => type}}
      %{workflow: workflow}
    end

    test "a bare, ambiguous lookup resolves nothing rather than guessing an occurrence", %{
      workflow: workflow
    } do
      # The bug this fix retires: `next_step/3` used to walk `pending`
      # backward to `setup`'s own successor for a container that had
      # actually reached `retro`'s own `pending` (`docs/dsl-syntax.md`
      # §15.2's own reproduction). Resolving nothing is the safe
      # failure — the qualified name below is what a caller needs once
      # a bare one is ambiguous.
      assert Sequence.step(workflow, "t", "pending") == nil
      assert Sequence.next_step(workflow, "t", "pending") == nil
    end

    test "a namespace-qualified lookup resolves the correct occurrence, not whichever comes first",
         %{workflow: workflow} do
      assert {:queue, %Status{status: "pending"}} = Sequence.step(workflow, "t", "setup.pending")
      assert {:queue, %Status{status: "pending"}} = Sequence.step(workflow, "t", "retro.pending")

      # Both occurrences are structurally identical `pending` entries —
      # what proves the *right* one resolved is what comes next.
      assert Sequence.next_step(workflow, "t", "setup.pending") ==
               {:queue, %Status{status: "setup"}}

      assert Sequence.next_step(workflow, "t", "retro.pending") ==
               {:queue, %Status{status: "retro"}}
    end

    test "earlier?/4 distinguishes the two occurrences once qualified", %{workflow: workflow} do
      assert Sequence.earlier?(workflow, "t", "retro", "retro.pending")
      refute Sequence.earlier?(workflow, "t", "setup", "retro.pending")
      assert Sequence.earlier?(workflow, "t", "retro.pending", "setup.pending")
    end
  end
end
