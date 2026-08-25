defmodule Catapult.Delivery.FeatureLifecycle.ProjectionTest do
  @moduledoc """
  Rewritten at ORC-104: the fixture is a `types/<name>.yaml`
  declaration rather than a bundle-wide gate chain, since `after:` is
  retired (dsl-syntax.md §15.3) and a gate's position is now the citing
  type's own array index.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Projection
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  # No critique, one gate — the smallest fixture that still exercises
  # pending -> generation -> gate -> checks.
  defp workflow do
    type = %Type{
      name: "feature",
      file: "types/feature.yaml",
      skeleton: "ticket",
      statuses: [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{review: "review"},
        %Status{status: "checks"}
      ]
    }

    %Workflow{
      name: "test",
      entry: "feature",
      environments: %{},
      gates: %{},
      types: %{"feature" => type}
    }
  end

  defp resting(state), do: Projection.resting(workflow(), "feature", state)

  test "a fresh projection rests at pending" do
    assert resting(Projection.new()) == {:kind, :pending}
  end

  test "a commit walks it through to the first gate, and no further" do
    state = Projection.commit(Projection.new(), 1)

    assert resting(state) == {:gate, "review"}
  end

  test "a gate marked passed at the current signature is skipped" do
    state = Projection.new() |> Projection.commit(1) |> Projection.pass({:gate, "review"})

    assert resting(state) == {:kind, :checks}
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

    assert resting(state) == {:gate, "review"}
  end

  test "block records the position the ticket was standing at, and resolves to :blocked" do
    state =
      Projection.new() |> Projection.commit(1) |> Projection.block(workflow(), "feature")

    assert resting(state) == {:kind, :blocked}
    assert Projection.blocked_origin(state) == {:gate, "review"}
  end

  test "a subsequent commit clears the block and resumes the ordinary walk" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.block(workflow(), "feature")
      |> Projection.commit(2)

    assert resting(state) == {:gate, "review"}
    assert Projection.blocked_origin(state) == nil
  end

  test "a type that does not resolve rests nowhere rather than guessing" do
    assert Projection.resting(workflow(), "no-such-type", Projection.new()) == nil
  end

  test "a decline pins the resting position at its own throwback target" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.pass({:gate, "review"})
      |> Projection.decline({:kind, :generation})

    assert resting(state) == {:kind, :generation}
  end

  test "a subsequent commit clears the throwback pin and resumes the ordinary walk" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.pass({:gate, "review"})
      |> Projection.decline({:kind, :generation})
      |> Projection.commit(2)

    # `passed[{:gate, "review"}]` was recorded at signature 1; the fresh
    # commit bumps the signature to 2, so the ordinary walk reopens the
    # gate on its own — the pin has nothing left to add.
    assert resting(state) == {:gate, "review"}
  end

  test "a block recorded after a decline takes precedence over the throwback pin" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.decline({:kind, :generation})
      |> Projection.block(workflow(), "feature")

    assert resting(state) == {:kind, :blocked}
  end
end
