defmodule Catapult.Delivery.FeatureLifecycle.SequenceTest do
  @moduledoc """
  Built against the real `bundles/default-flow` this repo ships with —
  "checked, not assumed" (`systems/delivery.md`'s own standard for this
  ticket) — rather than a synthetic fixture, so a change to the shipped
  types is caught here too.

  Rewritten at ORC-104: `after:` is retired (dsl-syntax.md §15.3), so
  there is no gate chain to walk and no orphan-anchor case to test.
  Position is the citing type's own array index, which is what the
  synthetic cases below now exercise instead.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  describe "positions/2 against the shipped default-flow bundle" do
    setup do
      assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
      %{workflow: workflow}
    end

    test "the feature type's own array, in order, up to the reachable boundary", %{
      workflow: workflow
    } do
      assert Sequence.positions(workflow, "feature") == [
               {:kind, :pending},
               {:kind, :generation},
               {:kind, :critique},
               {:gate, "ux-review"},
               {:gate, "engineering-review"},
               {:kind, :checks}
             ]
    end

    test "merge, deploy and terminal sit past this phase's reach", %{workflow: workflow} do
      positions = Sequence.positions(workflow, "feature")

      refute {:kind, :merge} in positions
      refute {:kind, :deploy} in positions
      refute {:kind, :terminal} in positions
    end

    test "an environment citation is not a resting position", %{workflow: workflow} do
      # `types/feature.yaml` cites `staging` before its `deploy` entry
      # (§15.5). It configures that deploy; nothing rests at it.
      assert Enum.all?(Sequence.positions(workflow, "feature"), &match?({:kind, _}, &1)) or
               Enum.all?(
                 Sequence.positions(workflow, "feature"),
                 &(elem(&1, 0) in [:kind, :gate])
               )
    end

    test "a type name that does not resolve yields no positions", %{workflow: workflow} do
      assert Sequence.positions(workflow, "no-such-type") == []
    end
  end

  describe "positions/2 reads the citing type's own array" do
    test "a type declaring no critique entry has no critique position" do
      workflow = workflow_with(["pending", "generation", "checks"])

      assert Sequence.positions(workflow, "t") == [
               {:kind, :pending},
               {:kind, :generation},
               {:kind, :checks}
             ]
    end

    test "two types may run the same gates in opposite relative order" do
      # The change §15.3 is explicitly about: with position living on
      # the citing type's own array, neither declaration answers to the
      # other's.
      forward = %Type{
        name: "forward",
        file: "types/forward.yaml",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{review: "a"},
          %Status{review: "b"},
          %Status{status: "checks"}
        ]
      }

      backward = %Type{
        name: "backward",
        file: "types/backward.yaml",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{review: "b"},
          %Status{review: "a"},
          %Status{status: "checks"}
        ]
      }

      workflow = %Workflow{
        name: "test",
        entry: "forward",
        gates: %{},
        environments: %{},
        types: %{"forward" => forward, "backward" => backward}
      }

      assert Sequence.positions(workflow, "forward") == [
               {:kind, :pending},
               {:gate, "a"},
               {:gate, "b"},
               {:kind, :checks}
             ]

      assert Sequence.positions(workflow, "backward") == [
               {:kind, :pending},
               {:gate, "b"},
               {:gate, "a"},
               {:kind, :checks}
             ]
    end
  end

  describe "annotated_positions/2 (dsl-syntax.md §15.10, ORC-116)" do
    setup do
      assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
      %{workflow: workflow}
    end

    test "feature's own leading sub-array groups pending through its gates, anchored on generation",
         %{workflow: workflow} do
      annotated = Sequence.annotated_positions(workflow, "feature")

      assert Enum.map(annotated, & &1.position) == Sequence.positions(workflow, "feature")

      assert Enum.map(annotated, & &1.group_key) ==
               ["generation", "generation", "generation", "generation", "generation", nil]

      assert Enum.map(annotated, & &1.group_anchor) ==
               [false, true, false, false, false, false]
    end

    test "a type with no sub-array groups nothing", %{workflow: workflow} do
      annotated = Sequence.annotated_positions(workflow, "seed")

      assert Enum.all?(annotated, &(&1.group_key == nil and &1.group_anchor == false))
    end

    test "a type name that does not resolve yields no positions", %{workflow: workflow} do
      assert Sequence.annotated_positions(workflow, "no-such-type") == []
    end
  end

  describe "annotated_positions/2 over a sub-array that is not the sequence's own head" do
    test "an earlier entry outside the group carries no group_key at all" do
      # `[status, [status, review]]` — the shape §15.10 argues from
      # (`types/milestone.yaml`'s sign-off group), built small enough
      # to exercise "outside the group" without a container skeleton.
      type = %Type{
        name: "t",
        file: "types/t.yaml",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{status: "generation"},
          %Status{review: "product-review"}
        ],
        groups: [1..2//1]
      }

      workflow = %Workflow{
        name: "test",
        entry: "t",
        gates: %{},
        environments: %{},
        types: %{"t" => type}
      }

      annotated = Sequence.annotated_positions(workflow, "t")

      assert [
               %{position: {:kind, :pending}, group_key: nil, group_anchor: false},
               %{position: {:kind, :generation}, group_key: "generation", group_anchor: true},
               %{
                 position: {:gate, "product-review"},
                 group_key: "generation",
                 group_anchor: false
               }
             ] = annotated
    end
  end

  describe "resolve_position/2 against the shipped default-flow bundle" do
    setup do
      assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
      %{workflow: workflow}
    end

    test "a gate name resolves to {:gate, name}", %{workflow: workflow} do
      assert Sequence.resolve_position(workflow, "ux-review") == {:gate, "ux-review"}
    end

    test "a status name resolves to {:kind, atom}", %{workflow: workflow} do
      assert Sequence.resolve_position(workflow, "generation") == {:kind, :generation}
    end
  end

  describe "name/3 (dsl-syntax.md §15.12, ORC-155)" do
    setup do
      assert {:ok, workflow} = Workflow.load("bundles", "default-flow")
      %{workflow: workflow}
    end

    test "a gate's own name is its whole identity", %{workflow: workflow} do
      assert Sequence.name(workflow, "feature", {:gate, "ux-review"}) == "ux-review"
    end

    test "a status kind with no authored name: defaults to the kind", %{workflow: workflow} do
      assert Sequence.name(workflow, "feature", {:kind, :generation}) == "generation"
    end

    test "nil has no name", %{workflow: workflow} do
      assert Sequence.name(workflow, "feature", nil) == nil
    end

    test "a kind absent from the type's own array falls back to the kind itself", %{
      workflow: workflow
    } do
      assert Sequence.name(workflow, "feature", {:kind, :blocked}) == "blocked"
    end
  end

  defp workflow_with(status_names) do
    type = %Type{
      name: "t",
      file: "types/t.yaml",
      skeleton: "ticket",
      statuses: Enum.map(status_names, &%Status{status: &1})
    }

    %Workflow{
      name: "test",
      entry: "t",
      gates: %{},
      environments: %{},
      types: %{"t" => type}
    }
  end
end
