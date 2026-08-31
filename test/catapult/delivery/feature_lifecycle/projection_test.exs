defmodule Catapult.Delivery.FeatureLifecycle.ProjectionTest do
  @moduledoc """
  Rewritten at ORC-104: the fixture is a `types/<name>.yaml`
  declaration rather than a bundle-wide gate chain, since `after:` is
  retired (dsl-syntax.md §15.3) and a gate's position is now the citing
  type's own array index.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Projection
  alias Catapult.Delivery.FeatureLifecycle.Sequence
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

  defp resting(state), do: state |> resting_pair() |> position_of()

  defp resting_pair(state), do: Projection.resting(workflow(), "feature", state)

  defp position_of(nil), do: nil
  defp position_of({position, _anchor}), do: position

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
    defp resting_setup(state) do
      state |> then(&Projection.resting(workflow(), "setup", &1)) |> position_of()
    end

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

  describe "passable?/2 over the generation-shaped and checks/reconcile kinds (ORC-182)" do
    # `design`/`architecture`/`implementation` sub-arrays, each with its
    # own `checks`, mirroring dsl-syntax.md §15.2's revised
    # `feature.yaml` closely enough to exercise every kind `passable?/2`
    # now has to answer for.
    defp multi_phase_workflow do
      type = %Type{
        name: "feature",
        file: "types/feature.yaml",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{status: "design"},
          %Status{status: "checks"},
          %Status{status: "pending"},
          %Status{status: "architecture"},
          %Status{status: "checks"},
          %Status{status: "reconcile"},
          %Status{status: "pending"},
          %Status{status: "implementation"},
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

    defp multi_phase_resting(state),
      do: Projection.resting(multi_phase_workflow(), "feature", state) |> position_of()

    test "design is passable once anything has committed, so the walk reaches its own :checks" do
      # If `design` were still unrecognized by `passable?/2` (the
      # pre-ORC-182 clause named only pending/generation/critique), this
      # would raise `FunctionClauseError` instead of landing here.
      state = Projection.new() |> Projection.commit(1)

      assert multi_phase_resting(state) == {:kind, :checks}
    end

    test "checks halts the walk at its first occurrence, even though later kinds are passable" do
      # `take_through_boundary/1` anchors the *sequence's own* boundary
      # on the last :checks, but every occurrence still stops
      # `resting/3`'s walk (systems/delivery.md's ORC-182 design-review
      # entry: this projection has no event reporting an intermediate
      # checks run's own outcome). Widening the passable set to include
      # design/architecture/implementation must not let the walk sail
      # past design's own :checks to land further down the array.
      state = Projection.new() |> Projection.commit(1)

      assert multi_phase_resting(state) == {:kind, :checks}

      assert Enum.at(Sequence.positions(multi_phase_workflow(), "feature"), 2) ==
               multi_phase_resting(state)
    end

    test "reconcile is never passable either" do
      type = %Type{
        name: "feature",
        file: "types/feature.yaml",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{status: "generation"},
          %Status{status: "reconcile"},
          %Status{status: "merge"}
        ]
      }

      workflow = %Workflow{
        name: "test",
        entry: "feature",
        environments: %{},
        gates: %{},
        types: %{"feature" => type}
      }

      state = Projection.new() |> Projection.commit(1)

      assert Projection.resting(workflow, "feature", state) |> position_of() ==
               {:kind, :reconcile}
    end
  end

  describe "resting/3 carries a qualifying anchor for a bare kind that recurs (dsl-syntax.md §15.12, ORC-171)" do
    # `pending` recurs twice: once as `generation`'s own leading entry
    # (qualified `generation.pending`, since its group has a second
    # member to share a namespace with) and once top-level, ungrouped
    # (stays bare — a top-level entry's `qualified` is always its own
    # bare name, dsl-syntax.md §15.12). `generation` is the only
    # agent-balled, non-review-shaped kind `passable?/2` already treats
    # as "always walked through once committed" (the real
    # `types/feature.yaml`'s own shape), which is what keeps every test
    # below inside the ordinary walk's own reach rather than a kind
    # this projection was never asked to pass through.
    defp ambiguous_workflow do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{status: "pending"},
        %Status{review: "review"},
        %Status{status: "checks"}
      ]

      type = %Type{
        name: "t",
        file: "types/t.yaml",
        skeleton: "ticket",
        statuses: statuses,
        groups: [0..1//1]
      }

      %Workflow{name: "test", entry: "t", gates: %{}, environments: %{}, types: %{"t" => type}}
    end

    defp resting_t(state), do: Projection.resting(ambiguous_workflow(), "t", state)

    test "a fresh projection rests at the group-qualified pending, not the bare top-level one" do
      # `passable?/2` only ever waives `:pending`/`:generation`/
      # `:critique` once a commit exists, so the *first* entry — landed
      # on unconditionally, before any commit — is the only kind
      # position the ordinary walk can rest at directly; this fixture
      # puts the group's own qualified `pending` there on purpose.
      assert resting_t(Projection.new()) == {{:kind, :pending}, "generation"}
    end

    test "a block recorded before any commit records the same qualified occurrence" do
      state = Projection.new() |> Projection.block(ambiguous_workflow(), "t")

      assert resting_t(state) == {{:kind, :blocked}, nil}
      assert Projection.blocked_origin(state) == {:kind, :pending}
    end

    test "decline pins the exact occurrence resolve_position/3 resolved, not whichever comes first" do
      {position, anchor} =
        Sequence.resolve_position(ambiguous_workflow(), "t", "generation.pending")

      state = Projection.new() |> Projection.commit(1) |> Projection.decline(position, anchor)

      assert resting_t(state) == {{:kind, :pending}, "generation"}
    end

    test "a bare decline target resolves to the unambiguous, top-level occurrence" do
      {position, anchor} = Sequence.resolve_position(ambiguous_workflow(), "t", "pending")
      state = Projection.new() |> Projection.commit(1) |> Projection.decline(position, anchor)

      assert resting_t(state) == {{:kind, :pending}, nil}
    end

    test "resume pins no anchor — the accepted, named limitation for the ambiguous case" do
      state =
        Projection.new()
        |> Projection.block(ambiguous_workflow(), "t")
        |> Projection.resume({:kind, :pending})

      assert resting_t(state) == {{:kind, :pending}, nil}
    end
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

    test "a decline pinned with a real qualifying anchor round-trips it too (ORC-171)" do
      state =
        Projection.new()
        |> Projection.commit(1)
        |> Projection.decline({:kind, :generation}, "setup")

      assert state.pinned_to_anchor == "setup"
      assert roundtrip(Projection.to_wire(state)) == state
    end

    test "a snapshot written before ORC-171 decodes with no anchor rather than raising" do
      pre_orc_171_wire =
        Projection.new()
        |> Projection.commit(1)
        |> Projection.decline({:kind, :generation})
        |> Projection.to_wire()
        |> Map.drop([:blocked_from_anchor, :pinned_to_anchor])

      assert Projection.from_wire(pre_orc_171_wire) ==
               Projection.new()
               |> Projection.commit(1)
               |> Projection.decline({:kind, :generation})
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
