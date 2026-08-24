defmodule Catapult.Delivery.FeatureLifecycle.ProjectionTest do
  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Projection
  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Workflow

  # No critique, one gate — the smallest fixture that still exercises
  # queue -> generation -> gate -> fanout.
  defp workflow do
    %Workflow{
      name: "test",
      critique: nil,
      environments: %{},
      gates: %{
        "review" => %Gate{
          name: "review",
          file: "gates/review.yaml",
          after: "generation",
          role: "engineering",
          escalation: "author"
        }
      }
    }
  end

  test "a fresh projection rests at queue" do
    assert Projection.resting(workflow(), Projection.new()) == {:kind, :queue}
  end

  test "a commit walks it through to the first gate, and no further" do
    state = Projection.commit(Projection.new(), 1)

    assert Projection.resting(workflow(), state) == {:gate, "review"}
  end

  test "a gate marked passed at the current signature is skipped" do
    state = Projection.new() |> Projection.commit(1) |> Projection.pass({:gate, "review"})

    assert Projection.resting(workflow(), state) == {:kind, :fanout}
  end

  test "skip-on-no-diff: a pass recorded at a stale signature reopens the gate" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.pass({:gate, "review"})
      # A later commit bumps the signature past what was recorded at
      # pass-time — "reviewed scope has committed something new since
      # the ticket last stood at it" (systems/delivery.md).
      |> Projection.commit(2)

    assert Projection.resting(workflow(), state) == {:gate, "review"}
  end

  test "block records the position the ticket was standing at, and resolves to :blocked" do
    state = Projection.new() |> Projection.commit(1) |> Projection.block(workflow())

    assert Projection.resting(workflow(), state) == {:kind, :blocked}
    assert Projection.blocked_origin(state) == {:gate, "review"}
  end

  test "a subsequent commit clears the block and resumes the ordinary walk" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.block(workflow())
      |> Projection.commit(2)

    assert Projection.resting(workflow(), state) == {:gate, "review"}
    assert Projection.blocked_origin(state) == nil
  end
end
