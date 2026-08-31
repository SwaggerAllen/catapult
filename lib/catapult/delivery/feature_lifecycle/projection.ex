defmodule Catapult.Delivery.FeatureLifecycle.Projection do
  @moduledoc """
  The pure snapshot→actions half of the feature-ticket lifecycle (v5
  §7.13's porting-model citation): folds the raw facts
  `Catapult.Delivery.FeatureLifecycle`'s `apply/2,3` callbacks observe
  into a resting position, given a loaded `Catapult.Dsl.Workflow.t()`
  — never resolved by this module (`systems/delivery.md`'s "the loaded
  workflow is a parameter" bullet).

  **Gate skip-on-no-diff** (`systems/delivery.md`, ORC-32 design
  pass): a gate is offered to the human only once its own reviewed
  scope has committed something new since the ticket last stood at
  it. `commit_signature` is the flow's own high-water mark — the
  latest project-stream sequence a `DraftCommitted` for this flow
  landed at — and `passed` records, per position, the signature that
  was current the last time this process manager walked *past* it.
  `:queue`, `:generation` and `:critique` carry no human ball and are
  always walked through once any commit exists; a gate only counts as
  passed when `passed[position] == commit_signature` exactly — a
  bare integer bump (a fresh commit) always reopens it. `pass/2` is
  called from `Catapult.Delivery.FeatureLifecycle`'s own `apply/2`
  clause for `GateApproved` (ORC-34, `systems/delivery.md`) — the
  gate-approval command's own call, exercised both there and directly
  by this module's own tests.

  **Blocked carries no new mechanism** (`systems/delivery.md`): `
  block/2` records the position the ticket was standing at when a
  limit-class failure arrived (`RunFailed`) as `blocked_from` — the
  flavor and the origin the work surface will want are simply that
  position, read off this projection rather than stamped onto a
  comment. `commit/2` (any subsequent `DraftCommitted`, i.e. a retry)
  clears it and resumes the ordinary walk; so does `resume/2` (a human
  resume, ORC-114).

  **`GateDeclined` pins the resting position the identical way**
  (ORC-34): `decline/2` records `throwback_to`'s own resolved position
  as `pinned_to`, and `resting/2` reads it back before the ordinary
  `passed`-based walk, the same precedence `blocked_from` already
  gets — a decline is otherwise invisible until the next commit, since
  nothing about `passed` changes the moment it lands (the declined
  gate itself was never marked passed). `commit/2` clears it exactly
  as it clears `blocked_from`: once a fresh commit bumps
  `commit_signature`, the ordinary walk already lands back on the
  pinned-to position on its own (any gate `passed` at the now-stale
  signature reopens per the skip-on-no-diff rule above), so the pin
  has nothing left to do.

  **Renamed from `thrown_back_to` at ORC-114**: a second write path —
  `resume/2`, a human resume rather than a gate throwback — now writes
  the same field, and a name that names only the first writer
  misdescribes what it holds the moment a second one exists.

  **`to_wire/1`/`from_wire/1`** (ORC-120): `Commanded.ProcessManagers
  .ProcessManagerInstance` persists `Catapult.Delivery.FeatureLifecycle`'s
  state — this struct nested inside it — through
  `Commanded.Serialization.JsonSerializer` after every handled event,
  and `blocked_from`/`pinned_to` carry a raw `Sequence.position()`
  tuple `Jason` has no `Encoder` for, exactly the shape
  `Catapult.Engine.Events.FlowResumed`'s own moduledoc already
  documents crashing real (non-`InMemory`) persistence over. The fix
  extends that same precedent — two nullable strings instead of a
  tuple — to both fields; `passed` breaks new ground the precedent
  doesn't cover, since it is *keyed* on a position rather than merely
  carrying one, and a JSON object's keys are always strings, so it
  flattens to a list of `{kind, gate, signature}` records instead of a
  map. A custom `Jason.Encoder` (below) calls `to_wire/1` rather than
  `@derive`, since the struct's own field shapes are not what goes over
  the wire; restoring the struct from a snapshot needs `from_wire/1`
  called explicitly, since `Commanded.Serialization.JsonSerializer
  .deserialize/2` builds the enclosing `FeatureLifecycle` struct via
  `struct/2` before any decoder protocol runs, which leaves a nested
  struct field as a bare atom-keyed map rather than reifying it —
  `Catapult.Delivery.FeatureLifecycle`'s own `JsonDecoder`
  implementation is what calls `from_wire/1`.
  """

  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Dsl.Workflow

  defstruct commit_signature: nil, passed: %{}, blocked_from: nil, pinned_to: nil

  @type t :: %__MODULE__{
          commit_signature: integer() | nil,
          passed: %{Sequence.position() => integer()},
          blocked_from: Sequence.position() | nil,
          pinned_to: Sequence.position() | nil
        }

  @doc "A fresh projection, before anything has committed."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Folds a `DraftCommitted` at project-stream sequence `sequence`: bumps the high-water mark and clears any block or pin."
  @spec commit(t(), integer()) :: t()
  def commit(%__MODULE__{} = state, sequence) when is_integer(sequence) do
    %{state | commit_signature: sequence, blocked_from: nil, pinned_to: nil}
  end

  @doc "Marks `position` passed as of the projection's current commit signature — called by `Catapult.Delivery.FeatureLifecycle`'s `apply/2` clause for `GateApproved` (ORC-34)."
  @spec pass(t(), Sequence.position()) :: t()
  def pass(%__MODULE__{commit_signature: sig} = state, position) do
    %{state | passed: Map.put(state.passed, position, sig)}
  end

  @doc "Folds a limit-class `RunFailed`: kicks the ticket to `:blocked`, recording where it was standing."
  @spec block(t(), Workflow.t(), String.t()) :: t()
  def block(%__MODULE__{} = state, %Workflow{} = workflow, type_name) do
    %{state | blocked_from: resting(workflow, type_name, state)}
  end

  @doc "Folds a `GateDeclined`: pins the resting position at `position` (`Sequence.resolve_position/2`'s own shape for `throwback_to`) until the next commit clears it."
  @spec decline(t(), Sequence.position()) :: t()
  def decline(%__MODULE__{} = state, position) do
    %{state | pinned_to: position}
  end

  @doc """
  Folds a `FlowResumed` (ORC-114): clears the `blocked_from` pin a
  human resume is choosing to leave, at the same moment it pins the
  resting position at the chosen `position` — distinct from `decline/2`
  (which never touches `blocked_from`) and from `commit/2` (which
  clears both pins without setting a fresh one; the ordinary walk
  resumes on its own, which a human resume cannot rely on while
  `blocked_from` is what put it there).
  """
  @spec resume(t(), Sequence.position()) :: t()
  def resume(%__MODULE__{} = state, position) do
    %{state | blocked_from: nil, pinned_to: position}
  end

  @doc """
  The position `workflow`'s `type_name` type and `state` resolve to
  right now: `{:kind, :blocked}` while a block is recorded, the pinned
  position while a decline or a human resume is recorded and no
  fresher commit has landed, otherwise the first position in
  `Sequence.positions/2`
  not yet passable, defaulting to the last (`Sequence`'s own trailing
  reachability sentinel) once everything reachable has been — the
  sequence's own final entry is never itself passable, whatever kind
  it turns out to be, since nothing in Phase 4 implements advancing
  past it.
  """
  @spec resting(Workflow.t(), String.t(), t()) :: Sequence.position() | nil
  def resting(%Workflow{}, _type_name, %__MODULE__{blocked_from: from}) when not is_nil(from) do
    {:kind, :blocked}
  end

  def resting(%Workflow{}, _type_name, %__MODULE__{pinned_to: position})
      when not is_nil(position) do
    position
  end

  def resting(%Workflow{} = workflow, type_name, %__MODULE__{} = state) do
    case Sequence.positions(workflow, type_name) do
      [] ->
        nil

      positions ->
        # Excluded by index, not by value (ORC-182): `@reachable_boundary`
        # can now recur in `positions`, so a value comparison against
        # `List.last/1` would treat every earlier occurrence as "the
        # last" too and skip it, exactly the aliasing that would let a
        # non-final `:checks` silently pass instead of halting the walk.
        last_index = length(positions) - 1

        positions
        |> Enum.with_index()
        |> Enum.find(fn {position, index} ->
          index != last_index and not passable?(position, state)
        end)
        |> case do
          nil -> List.last(positions)
          {position, _index} -> position
        end
    end
  end

  @doc "The position the ticket was standing at when it was last kicked to `:blocked`, or `nil` if it never has been."
  @spec blocked_origin(t()) :: Sequence.position() | nil
  def blocked_origin(%__MODULE__{blocked_from: from}), do: from

  @doc "The JSON-safe map this struct's own `Jason.Encoder` (below) writes — see the moduledoc's `to_wire/1`/`from_wire/1` entry."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = projection) do
    {blocked_from_kind, blocked_from_gate} = to_columns(projection.blocked_from)
    {pinned_to_kind, pinned_to_gate} = to_columns(projection.pinned_to)

    %{
      commit_signature: projection.commit_signature,
      blocked_from_kind: blocked_from_kind,
      blocked_from_gate: blocked_from_gate,
      pinned_to_kind: pinned_to_kind,
      pinned_to_gate: pinned_to_gate,
      passed:
        Enum.map(projection.passed, fn {position, signature} ->
          {kind, gate} = to_columns(position)
          %{kind: kind, gate: gate, signature: signature}
        end)
    }
  end

  @doc "The reverse of `to_wire/1`, for `Catapult.Delivery.FeatureLifecycle`'s own `JsonDecoder` implementation."
  @spec from_wire(map()) :: t()
  def from_wire(%{} = wire) do
    %__MODULE__{
      commit_signature: wire.commit_signature,
      blocked_from: from_columns(wire.blocked_from_kind, wire.blocked_from_gate),
      pinned_to: from_columns(wire.pinned_to_kind, wire.pinned_to_gate),
      passed:
        Map.new(wire.passed, fn record ->
          {from_columns(record.kind, record.gate), record.signature}
        end)
    }
  end

  defp passable?({:kind, kind}, %__MODULE__{commit_signature: sig})
       when kind in [:pending, :generation, :design, :architecture, :implementation, :critique] do
    not is_nil(sig)
  end

  defp passable?({:gate, _name} = position, %__MODULE__{commit_signature: sig} = state) do
    not is_nil(sig) and Map.get(state.passed, position) == sig
  end

  # `checks` and `reconcile` stay unpassable at every occurrence, not
  # only the last (systems/delivery.md's ORC-182 design-review entry):
  # this projection has no event reporting an intermediate checks run's
  # own outcome or an intermediate reconcile's own join independently of
  # a fresh `DraftCommitted`/`RunFailed`, so nothing here can tell one
  # apart from the boundary occurrence the clause above already covers.
  # A ticket resting at a non-final `checks`/`reconcile` therefore does
  # not advance into that phase's own `critique`/gates under today's
  # event vocabulary — real on §15.2's multi-phase shape, not on the
  # shipped bundle. Giving this phase a signal for an intermediate
  # outcome is new advancement behaviour, and designing it is not this
  # ticket's scope.
  defp passable?({:kind, _kind}, %__MODULE__{}), do: false

  defp to_columns(nil), do: {nil, nil}
  defp to_columns({:kind, kind}), do: {to_string(kind), nil}
  defp to_columns({:gate, name}), do: {nil, name}

  # `String.to_existing_atom/1`, never `to_atom/1` — the identical
  # discipline `Catapult.Delivery.FeatureLifecycle`'s own
  # `unflatten_position/2` takes for the same reason: a `kind` string
  # here only ever came from a `Sequence.position()` this same struct
  # wrote, itself built off `Catapult.Dsl.SystemStatus`'s closed set,
  # already in the atom table.
  defp from_columns(nil, nil), do: nil
  defp from_columns(kind, nil) when not is_nil(kind), do: {:kind, String.to_existing_atom(kind)}
  defp from_columns(nil, gate) when not is_nil(gate), do: {:gate, gate}
end

defimpl Jason.Encoder, for: Catapult.Delivery.FeatureLifecycle.Projection do
  alias Catapult.Delivery.FeatureLifecycle.Projection

  def encode(%Projection{} = projection, opts) do
    projection |> Projection.to_wire() |> Jason.Encode.map(opts)
  end
end
