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
             "checks",
             "reconcile",
             "merge",
             "deploy",
             "prep",
             "main",
             "milestone-signoff",
             "retro",
             "proposals-read",
             "checks",
             "reconcile",
             "merge",
             "deploy",
             "cleanup",
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

    assert {:queue, %Status{status: "retro"}} =
             Sequence.next_step(workflow, "milestone", "milestone-signoff")

    assert Sequence.next_step(workflow, "milestone", "cleanup") == :terminal
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
end
