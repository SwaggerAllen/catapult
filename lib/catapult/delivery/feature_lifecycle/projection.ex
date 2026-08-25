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
  bare integer bump (a fresh commit) always reopens it. **Dormant by
  construction today**: nothing in this phase's event vocabulary ever
  calls `pass/2` (no gate-approval command exists until Phase 7 —
  `systems/delivery.md`'s own "what advancing past a gate on a
  human's word dispatches to stays open" bullet), so every resting
  walk in Phase 4 stops at the first declared gate and stays there.
  `pass/2` is exercised directly by this module's own tests so the
  skip semantics are proven correct ahead of the command that will
  call it.

  **Blocked carries no new mechanism** (`systems/delivery.md`): `
  block/2` records the position the ticket was standing at when a
  limit-class failure arrived (`RunFailed`) as `blocked_from` — the
  flavor and the origin the work surface will want are simply that
  position, read off this projection rather than stamped onto a
  comment. `commit/2` (any subsequent `DraftCommitted`, i.e. a retry)
  clears it and resumes the ordinary walk.

  **`GateDeclined` pins the resting position the identical way**
  (ORC-34): `decline/2` records `throwback_to`'s own resolved position
  as `thrown_back_to`, and `resting/2` reads it back before the
  ordinary `passed`-based walk, the same precedence `blocked_from`
  already gets — a decline is otherwise invisible until the next
  commit, since nothing about `passed` changes the moment it lands
  (the declined gate itself was never marked passed). `commit/2`
  clears it exactly as it clears `blocked_from`: once a fresh commit
  bumps `commit_signature`, the ordinary walk already lands back on
  the thrown-back-to position on its own (any gate `passed` at the
  now-stale signature reopens per the skip-on-no-diff rule above), so
  the pin has nothing left to do.
  """

  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Dsl.Workflow

  defstruct commit_signature: nil, passed: %{}, blocked_from: nil, thrown_back_to: nil

  @type t :: %__MODULE__{
          commit_signature: integer() | nil,
          passed: %{Sequence.position() => integer()},
          blocked_from: Sequence.position() | nil,
          thrown_back_to: Sequence.position() | nil
        }

  @doc "A fresh projection, before anything has committed."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Folds a `DraftCommitted` at project-stream sequence `sequence`: bumps the high-water mark and clears any block or throwback pin."
  @spec commit(t(), integer()) :: t()
  def commit(%__MODULE__{} = state, sequence) when is_integer(sequence) do
    %{state | commit_signature: sequence, blocked_from: nil, thrown_back_to: nil}
  end

  @doc "Marks `position` passed as of the projection's current commit signature — the gate-approval command's own call, once one exists (Phase 7)."
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
    %{state | thrown_back_to: position}
  end

  @doc """
  The position `workflow`'s `type_name` type and `state` resolve to
  right now: `{:kind, :blocked}` while a block is recorded, the pinned
  throwback target while a decline is recorded and no fresher commit
  has landed, otherwise the first position in `Sequence.positions/2`
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

  def resting(%Workflow{}, _type_name, %__MODULE__{thrown_back_to: position})
      when not is_nil(position) do
    position
  end

  def resting(%Workflow{} = workflow, type_name, %__MODULE__{} = state) do
    case Sequence.positions(workflow, type_name) do
      [] ->
        nil

      positions ->
        last = List.last(positions)
        Enum.find(positions, last, &(&1 != last and not passable?(&1, state)))
    end
  end

  @doc "The position the ticket was standing at when it was last kicked to `:blocked`, or `nil` if it never has been."
  @spec blocked_origin(t()) :: Sequence.position() | nil
  def blocked_origin(%__MODULE__{blocked_from: from}), do: from

  defp passable?({:kind, kind}, %__MODULE__{commit_signature: sig})
       when kind in [:pending, :generation, :critique] do
    not is_nil(sig)
  end

  defp passable?({:gate, _name} = position, %__MODULE__{commit_signature: sig} = state) do
    not is_nil(sig) and Map.get(state.passed, position) == sig
  end
end
