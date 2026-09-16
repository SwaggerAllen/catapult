defmodule Catapult.Dsl.TypeTest do
  @moduledoc """
  `namespaced_positions/1` and `anchor_index/2` (dsl-syntax.md §15.12,
  ORC-116) at the struct grain — the one place §15.10/§15.12's
  bare/qualified/ambiguity computation lives, shared by
  `Catapult.Dsl.Workflow` (ticket axis) and `Catapult.Delivery
  .ContainerLifecycle.Sequence` (container axis). No shipped
  `types/*.yaml` recurs a bare name across two sub-arrays today
  (`workflow.md` #7, and `types/milestone.yaml`'s own asymmetry), so the ambiguous case below is exercised only here,
  against a hand-built struct.
  """

  use ExUnit.Case, async: true

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type

  describe "anchor_index/2" do
    test "the one non-review-shaped agent-balled entry in the range" do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{status: "critique"},
        %Status{review: "ux-review"}
      ]

      type = %Type{name: "t", file: "types/t.yaml", statuses: statuses, groups: [0..3//1]}

      assert Type.anchor_index(type, 0..3//1) == 1
    end
  end

  describe "namespaced_positions/1 — the ordinary, unambiguous case" do
    test "a group's own anchor is top-level; every other member is <anchor>.<name>" do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{review: "ux-review"},
        %Status{status: "checks"}
      ]

      type = %Type{name: "t", file: "types/t.yaml", statuses: statuses, groups: [0..2//1]}

      assert type
             |> Type.namespaced_positions()
             |> Enum.map(&{&1.bare, &1.namespace, &1.canonical}) == [
               {"pending", "generation", "pending"},
               {"generation", :top_level, "generation"},
               {"ux-review", "generation", "ux-review"},
               {"checks", :top_level, "checks"}
             ]
    end
  end

  describe "namespaced_positions/1 — a bare name recurring across two sub-arrays" do
    test "canonical qualifies only the recurring name, leaving every other bare name alone" do
      # `[[pending, setup], [pending, retro]]` — the exact shape
      # `types/milestone.yaml` avoids today by omitting `retro`'s own
      # leading `pending`. Built here
      # because nothing shipped recurs a name, and the ambiguity rule
      # needs a case that does.
      statuses = [
        %Status{status: "pending"},
        %Status{status: "setup"},
        %Status{status: "pending"},
        %Status{status: "retro"}
      ]

      type = %Type{
        name: "t",
        file: "types/t.yaml",
        statuses: statuses,
        groups: [0..1//1, 2..3//1]
      }

      positions = Type.namespaced_positions(type)

      assert Enum.map(positions, &{&1.bare, &1.canonical}) == [
               {"pending", "setup.pending"},
               {"setup", "setup"},
               {"pending", "retro.pending"},
               {"retro", "retro"}
             ]
    end
  end

  describe "namespaced_positions/1 — kind_ambiguous diverges from canonical/bare ambiguity (ORC-198)" do
    test "two same-kind entries with distinct name: overrides are kind_ambiguous but not bare-ambiguous" do
      # `name:` (ORC-155) lets two `status: pending` occurrences carry
      # distinct authored names — each resolves as a reference
      # unambiguously (`canonical == bare` for both), but
      # `Catapult.Delivery.FeatureLifecycle.Sequence.to_position/1`
      # reads `status:` alone and cannot tell them apart at runtime.
      statuses = [
        %Status{status: "pending", name: "alpha"},
        %Status{status: "setup"},
        %Status{status: "pending", name: "beta"},
        %Status{status: "retro"}
      ]

      type = %Type{
        name: "t",
        file: "types/t.yaml",
        statuses: statuses,
        groups: [0..1//1, 2..3//1]
      }

      positions = Type.namespaced_positions(type)

      assert Enum.map(positions, &{&1.bare, &1.canonical, &1.kind_ambiguous}) == [
               {"alpha", "alpha", true},
               {"setup", "setup", false},
               {"beta", "beta", true},
               {"retro", "retro", false}
             ]
    end

    test "a bare name recurring with distinct kinds is reference-ambiguous but not kind_ambiguous" do
      # `status: pending` in one sub-array beside `status: checks, name:
      # pending` in another: the two share one `bare` (a real reference
      # ambiguity — `blocks: [pending]` cannot pick one), but resolve to
      # distinct `{:kind, atom}` shapes, so there is no runtime
      # collision at all.
      statuses = [
        %Status{status: "pending"},
        %Status{status: "setup"},
        %Status{status: "checks", name: "pending"},
        %Status{status: "retro"}
      ]

      type = %Type{
        name: "t",
        file: "types/t.yaml",
        statuses: statuses,
        groups: [0..1//1, 2..3//1]
      }

      positions = Type.namespaced_positions(type)

      assert Enum.map(positions, &{&1.bare, &1.canonical, &1.kind_ambiguous}) == [
               {"pending", "setup.pending", false},
               {"setup", "setup", false},
               {"pending", "retro.pending", false},
               {"retro", "retro", false}
             ]
    end
  end
end
