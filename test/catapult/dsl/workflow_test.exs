defmodule Catapult.Dsl.WorkflowTest do
  @moduledoc """
  `Catapult.Dsl.Workflow`'s throwback resolution (`workflow.md`
  #34), at the struct grain. Loading a bundle off disk is
  `Catapult.Dsl.LoaderTest`'s job and stays there; what needs a
  hand-built `%Workflow{}` is the one shape the loader cannot yet
  accept — see the milestone-shape test below.
  """

  use ExUnit.Case, async: true

  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  ## §15.10 — the derived default is the citing sub-array's own
  ## earliest entry, never the array position before the gate. `retro`
  ## is this shape's own non-review-shaped agent step and its own
  ## earliest entry alike, since its group carries no leading `pending`
  ## of its own — see `Catapult.Dsl.LoaderTest`'s own end-to-end test
  ## for the generation-shaped shape where the two diverge.

  describe "throwback_default/3 on the shape the two rules disagree about" do
    setup do
      # `[milestone-signoff, retro, proposals-read]` — §15.2's own
      # `types/milestone.yaml` example, grouped. This is the shape
      # §15.10 argues the rule from, and it is built here as a struct
      # rather than written as YAML **because the loader refuses it
      # today**: `retro` is a queue-shaped anchor (`flow: retro`, its
      # own singleton flow) and §15.10's third check refuses one inside
      # a sub-array until "singleton flows retire into sub-arrays of
      # their parent container" lands. §15.10 says as much itself — the
      # reasoning argues from the shape ORC-104 committed to in prose,
      # not from a sub-array the grammar accepts.
      #
      # Nothing the default bundle *can* form distinguishes the two
      # rules: `types/feature.yaml`'s group has `generation` as both its
      # one agent step and its first entry, so a naive first-element
      # rule passes there too. Leaning on the bundle would prove
      # nothing about why the rule is what it is.
      statuses = [
        %Status{status: "setup", flow: "setup"},
        %Status{status: "prep", flow: "feature"},
        %Status{status: "main", flow: "feature"},
        %Status{review: "milestone-signoff"},
        %Status{status: "retro", flow: "retro"},
        %Status{review: "proposals-read"},
        %Status{status: "cleanup", flow: "feature"},
        %Status{status: "terminal"}
      ]

      type = %Type{
        name: "milestone",
        file: "types/milestone.yaml",
        skeleton: "container",
        statuses: statuses,
        groups: [3..5//1]
      }

      workflow = %Workflow{
        name: "default-flow",
        entry: "project",
        types: %{"milestone" => type},
        gates: %{
          "milestone-signoff" => gate("milestone-signoff"),
          "proposals-read" => gate("proposals-read")
        }
      }

      {:ok, workflow: workflow}
    end

    test "a gate after its group's agent step falls back to that step, not to the entry before it",
         %{workflow: workflow} do
      # The entry immediately before `proposals-read` in the array is
      # `retro`'s own preceding gate, `milestone-signoff`. Falling back
      # there would re-ask the author a question they already answered
      # instead of re-running the agent that produced the thing they
      # are declining — the whole reason the rule is the group's agent
      # step rather than the previous position.
      assert Workflow.throwback_default(workflow, "milestone", "proposals-read") == "retro"

      refute Workflow.throwback_default(workflow, "milestone", "proposals-read") ==
               "milestone-signoff"
    end

    test "a declared throwback: overrides the derivation", %{workflow: workflow} do
      workflow = put_in(workflow.gates["proposals-read"].throwback, "main")

      assert Workflow.throwback_default(workflow, "milestone", "proposals-read") == "main"
    end

    test "a gate before its group's agent step derives nothing", %{workflow: workflow} do
      # `milestone-signoff` sits at index 3, `retro` at 4: the
      # derivation would name a target *later* than the gate, which the
      # legality rule rejects. §15.10 does not reach this case — the
      # shipped `milestone-signoff` declares `throwback: main` and never
      # derives — so nothing is derived rather than something illegal
      # being offered.
      assert Workflow.throwback_default(workflow, "milestone", "milestone-signoff") == nil
      refute "retro" in Workflow.throwback_targets(workflow, "milestone", "milestone-signoff")
    end

    test "legality is the earlier prefix, and is not bounded by any declared target", %{
      workflow: workflow
    } do
      assert Workflow.throwback_targets(workflow, "milestone", "proposals-read") ==
               ["setup", "prep", "main", "milestone-signoff", "retro"]

      # Declaring one target does not narrow the rest away.
      workflow = put_in(workflow.gates["proposals-read"].throwback, "main")

      assert Workflow.throwback_legal?(workflow, "milestone", "proposals-read", "retro")
      assert Workflow.throwback_legal?(workflow, "milestone", "proposals-read", "setup")
      refute Workflow.throwback_legal?(workflow, "milestone", "proposals-read", "cleanup")
      refute Workflow.throwback_legal?(workflow, "milestone", "proposals-read", "no-such-status")
    end

    test "a gate is not legal to throw back to itself", %{workflow: workflow} do
      refute Workflow.throwback_legal?(workflow, "milestone", "proposals-read", "proposals-read")
    end

    test "throwback_target_details/3 marks a target outside the gate's own group as leaving it",
         %{workflow: workflow} do
      details = Workflow.throwback_target_details(workflow, "milestone", "proposals-read")

      assert details == [
               %{target: "setup", leaves_group: true},
               %{target: "prep", leaves_group: true},
               %{target: "main", leaves_group: true},
               %{target: "milestone-signoff", leaves_group: false},
               %{target: "retro", leaves_group: false}
             ]
    end

    test "a type or gate that does not resolve yields no targets and no default", %{
      workflow: workflow
    } do
      assert Workflow.throwback_targets(workflow, "no-such-type", "proposals-read") == []
      assert Workflow.throwback_targets(workflow, "milestone", "no-such-gate") == []
      assert Workflow.throwback_default(workflow, "no-such-type", "proposals-read") == nil
      assert Workflow.throwback_default(workflow, "milestone", "no-such-gate") == nil
      refute Workflow.throwback_legal?(workflow, "milestone", "no-such-gate", "setup")
    end

    # `approve_leaves_group?/3` (ORC-229): the same group's two gates,
    # `milestone-signoff` (index 3) and `proposals-read` (index 5), read
    # forward instead of backward.
    test "approving the group's own earlier gate does not leave it — the next entry is still inside",
         %{workflow: workflow} do
      refute Workflow.approve_leaves_group?(workflow, "milestone", "milestone-signoff")
    end

    test "approving the group's own last gate leaves it — the next entry is outside", %{
      workflow: workflow
    } do
      assert Workflow.approve_leaves_group?(workflow, "milestone", "proposals-read")
    end

    test "a type or gate that does not resolve reads false, never true", %{workflow: workflow} do
      refute Workflow.approve_leaves_group?(workflow, "no-such-type", "proposals-read")
      refute Workflow.approve_leaves_group?(workflow, "milestone", "no-such-gate")
    end
  end

  describe "throwback_default/3 outside any sub-array" do
    test "a gate in no group derives nothing but stays declinable" do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{review: "product-review"},
        %Status{status: "checks"}
      ]

      type = %Type{
        name: "feature",
        file: "types/feature.yaml",
        skeleton: "ticket",
        statuses: statuses,
        groups: []
      }

      workflow = %Workflow{
        name: "default-flow",
        entry: "project",
        types: %{"feature" => type},
        gates: %{"product-review" => gate("product-review")}
      }

      assert Workflow.throwback_default(workflow, "feature", "product-review") == nil

      assert Workflow.throwback_targets(workflow, "feature", "product-review") ==
               ["pending", "generation"]

      assert Workflow.throwback_legal?(workflow, "feature", "product-review", "generation")

      # A gate outside every sub-array has no group of its own to
      # leave, so nothing it can decline back to reads `leaves_group`.
      assert Workflow.throwback_target_details(workflow, "feature", "product-review") == [
               %{target: "pending", leaves_group: false},
               %{target: "generation", leaves_group: false}
             ]

      # The forward reading takes the opposite default for the
      # identical "no group" case: there is no group left to still be
      # inside, so this gate is always the group's own last one.
      assert Workflow.approve_leaves_group?(workflow, "feature", "product-review")
    end
  end

  defp gate(name) do
    %Gate{name: name, file: "gates/#{name}.yaml", role: "author", escalation: "author"}
  end
end
