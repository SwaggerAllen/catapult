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

  describe "resting/3 for an inline dispatch point (ORC-176)" do
    # `setup`/`retro` carry no `types/<name>.yaml` of their own
    # (`Sequence`'s own moduledoc) — `workflow()` above declares none —
    # so this exercises `Sequence.positions/2`'s fixed two-entry
    # fallback rather than a declared array.
    defp resting_setup(state), do: Projection.resting(workflow(), "setup", state)

    test "rests at pending before the first commit" do
      assert resting_setup(Projection.new()) == {:kind, :pending}
    end

    test "a commit walks it to setup, its own last and only further position" do
      state = Projection.commit(Projection.new(), 1)

      assert resting_setup(state) == {:kind, :setup}
    end
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

  test "a resume clears the block and pins the resting position at the chosen target" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.block(workflow(), "feature")
      |> Projection.resume({:kind, :generation})

    assert resting(state) == {:kind, :generation}
    assert Projection.blocked_origin(state) == nil
  end

  test "a subsequent commit clears the resume pin and resumes the ordinary walk" do
    state =
      Projection.new()
      |> Projection.commit(1)
      |> Projection.pass({:gate, "review"})
      |> Projection.block(workflow(), "feature")
      |> Projection.resume({:kind, :generation})
      |> Projection.commit(2)

    assert resting(state) == {:gate, "review"}
  end

  describe "JSON round trip (ORC-120)" do
    # `blocked_from`/`pinned_to`/`passed` all carry or key on a raw
    # `Sequence.position()` tuple `Jason` has no `Encoder` for, so
    # `Jason.encode!/1` on the bare struct is the reproduction this
    # ticket names — proven directly, rather than assumed, before
    # proving `to_wire/1`/`from_wire/1` undo it.
    test "encoding the bare struct with a position-shaped field raises, same as Jason.encode/1 on a tuple" do
      state = %Projection{blocked_from: {:kind, :generation}}

      assert_raise Protocol.UndefinedError, fn -> Jason.encode!(Map.from_struct(state)) end
    end

    test "a fresh projection round-trips" do
      assert Projection.new() |> Projection.to_wire() |> roundtrip() == Projection.new()
    end

    test "a projection with every field populated round-trips" do
      state =
        Projection.new()
        |> Projection.commit(1)
        |> Projection.pass({:gate, "review"})
        |> Projection.commit(2)
        |> Projection.block(workflow(), "feature")

      assert roundtrip(Projection.to_wire(state)) == state
    end

    test "a decline-pinned kind position round-trips" do
      state = Projection.new() |> Projection.commit(1) |> Projection.decline({:kind, :generation})

      assert roundtrip(Projection.to_wire(state)) == state
    end

    test "the struct itself encodes through Jason, not by @derive but by its own Jason.Encoder implementation" do
      state =
        Projection.new()
        |> Projection.commit(1)
        |> Projection.pass({:gate, "review"})

      encoded = Jason.encode!(state)
      assert {:ok, decoded} = Jason.decode(encoded, keys: :atoms)
      assert Projection.from_wire(decoded) == state
    end

    # Round-trips through the identical `Jason.encode!/1` +
    # `Jason.decode!/2, keys: :atoms` shape
    # `Commanded.Serialization.JsonSerializer` actually takes, rather
    # than calling `to_wire/1`/`from_wire/1` directly.
    defp roundtrip(wire) do
      wire |> Jason.encode!() |> Jason.decode!(keys: :atoms) |> Projection.from_wire()
    end
  end
end
