defmodule Catapult.Delivery.FeatureLifecycle.SequenceTest do
  @moduledoc """
  Built against the real `bundles/default-flow` this repo ships with —
  "checked, not assumed" (`systems/delivery.md`'s own standard for this
  ticket) — rather than a synthetic fixture, so a change to the shipped
  gates is caught here too.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Workflow

  describe "positions/1 against the shipped default-flow bundle" do
    setup do
      assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
      %{workflow: workflow}
    end

    test "queue, generation, critique, both gates in order, then fanout", %{workflow: workflow} do
      assert Sequence.positions(workflow) == [
               {:kind, :queue},
               {:kind, :generation},
               {:kind, :critique},
               {:gate, "ux-review"},
               {:gate, "engineering-review"},
               {:kind, :fanout}
             ]
    end
  end

  describe "positions/1 without a declared critique" do
    test "omits the :critique position" do
      workflow = %Workflow{name: "test", critique: nil, gates: %{}, environments: %{}}

      assert Sequence.positions(workflow) == [
               {:kind, :queue},
               {:kind, :generation},
               {:kind, :fanout}
             ]
    end
  end

  describe "positions/1 with a gate chain" do
    test "orders gates by walking after: from generation" do
      gates = %{
        "second" => gate("second", after: "first"),
        "first" => gate("first", after: "generation")
      }

      workflow = %Workflow{name: "test", critique: nil, gates: gates, environments: %{}}

      assert Sequence.positions(workflow) == [
               {:kind, :queue},
               {:kind, :generation},
               {:gate, "first"},
               {:gate, "second"},
               {:kind, :fanout}
             ]
    end

    test "a gate anchored beyond generation's chain is not reachable" do
      gates = %{"orphan" => gate("orphan", after: "checks")}
      workflow = %Workflow{name: "test", critique: nil, gates: gates, environments: %{}}

      assert Sequence.positions(workflow) == [
               {:kind, :queue},
               {:kind, :generation},
               {:kind, :fanout}
             ]
    end
  end

  defp gate(name, after: after_) do
    %Gate{
      name: name,
      file: "gates/#{name}.yaml",
      after: after_,
      role: "engineering",
      escalation: "author"
    }
  end
end
