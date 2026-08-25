defmodule Catapult.Delivery.FeatureLifecycle.Sequence do
  @moduledoc """
  The feature-ticket lifecycle's effective sequence (v5 §7.10,
  `systems/delivery.md`'s ORC-32 design pass): `pending → generation →
  [critique] → [gate] → … → checks`, read directly off a loaded
  `Catapult.Dsl.Workflow.t()`'s named `types/<name>.yaml` declaration
  (dsl-syntax.md §15.2) rather than resolved by this module — the same
  "take the loaded bundle as a parameter" shape `Catapult.Engine
  .Projections.ReadyScopes.ready/3` and `Catapult.Engine.Scheduler
  .trigger/2` already establish for the chain axis.

  **Position is the citing type's own array index, not a named
  `after:` predecessor** (ORC-104, dsl-syntax.md §15.3): `after:` is
  retired from this grammar entirely, so this module walks the named
  type's `statuses:` array directly instead of following `gate.after`
  chains from `"generation"`.

  **Reachability, settled** (`systems/delivery.md`, ORC-32 design
  pass, carried forward at ORC-104): `checks` is this phase's last
  reachable position — included as the sequence's own trailing
  sentinel, the same role the retired `:fanout` played before this
  ticket's bundle migration removed it from the shipped `feature` type
  (dsl-syntax.md §15.2's worked example has no `fanout` anchor at all).
  `merge`, `deploy` and `terminal` are real positions in the loaded
  type's own array but sit behind the child lifecycle/mutex/dispatch/
  reconciliation machinery Phase 7 builds, so this module never places
  one in the sequence it returns — a type declaring them still loads
  and validates (dsl-syntax.md §13); this module simply never reaches
  them. An `environment:` citation is absent for a different reason,
  which outlives the reachability boundary: it is not a resting
  position at all (see `to_position/1`).
  """

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Workflow

  @typedoc "One stop in the effective sequence: a fixed system-status kind, or a declared gate by its own name."
  @type position :: {:kind, atom()} | {:gate, String.t()}

  # The first position gated behind machinery Phase 4 doesn't have yet
  # (`systems/delivery.md`'s reachability bullet) — everything at or
  # after this kind is dropped from the sequence this module returns.
  @reachable_boundary :checks

  @doc """
  The ordered, reachable positions for the type named `type_name` in
  `workflow`: every entry in that type's own `statuses:` array, up to
  and including `#{inspect(@reachable_boundary)}` — the first position
  this phase's machinery cannot yet advance past.

  Returns `[]` if `type_name` does not resolve in `workflow` (logged
  and skipped by the caller, `Catapult.Delivery.FeatureLifecycle`,
  exactly as an unloadable bundle already is).
  """
  @spec positions(Workflow.t(), String.t()) :: [position()]
  def positions(%Workflow{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, type} ->
        type.statuses
        |> Enum.map(&to_position/1)
        |> Enum.reject(&is_nil/1)
        |> take_through_boundary()

      :error ->
        []
    end
  end

  # `String.to_existing_atom/1`, never `to_atom/1` (`Catapult.Dsl
  # .Fields`'s own discipline): `Catapult.Dsl.Workflow` has already
  # checked, at load time, that a ticket-skeleton type's `status:`
  # names come from `Catapult.Dsl.SystemStatus`'s closed set, whose
  # atoms are compile-time literals — already in the atom table by the
  # time any bundle content reaches here.
  defp to_position(%Status{status: name}) when not is_nil(name),
    do: {:kind, String.to_existing_atom(name)}

  defp to_position(%Status{review: name}) when not is_nil(name), do: {:gate, name}

  # An `environment:` entry is not a resting position and never
  # becomes one: it configures the `deploy` entry that follows it
  # (dsl-syntax.md §15.5's "an environment sits *before* the `deploy`
  # entry it is a promotion target for"), so a ticket rests at
  # `deploy`, never at the environment declaration that told `deploy`
  # where to go. Dropped here rather than filtered by the caller —
  # `position/0` has exactly two shapes and the projection's own two
  # columns (`status_kind`/`status_gate`) are built on that.
  defp to_position(%Status{environment: name}) when not is_nil(name), do: nil

  @doc """
  Resolves a `GateDeclined.throwback_to` name — a status or a cited
  gate, the identical vocabulary `gate_throwback_problems/2` already
  validates it against at load time (ORC-34) — to its `position()`
  shape, the same one `to_position/1` produces from a `%Status{}`
  entry. A gate name is never also a declared status kind (the two
  live in disjoint vocabularies — `@ticket_status_names`'s closed set
  vs. a bundle-authored gate name), so membership in `workflow.gates`
  alone decides which shape a bare string resolves to.
  """
  @spec resolve_position(Workflow.t(), String.t()) :: position()
  def resolve_position(%Workflow{gates: gates}, name) do
    if Map.has_key?(gates, name) do
      {:gate, name}
    else
      {:kind, String.to_existing_atom(name)}
    end
  end

  defp take_through_boundary(positions) do
    {before, at_and_after} =
      Enum.split_while(positions, &(&1 != {:kind, @reachable_boundary}))

    case at_and_after do
      [] -> before
      [boundary | _rest] -> before ++ [boundary]
    end
  end
end
