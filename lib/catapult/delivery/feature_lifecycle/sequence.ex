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
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  @typedoc "One stop in the effective sequence: a fixed system-status kind, or a declared gate by its own name."
  @type position :: {:kind, atom()} | {:gate, String.t()}

  @typedoc """
  One `positions/2` entry, paired with the sub-array it belongs to
  (dsl-syntax.md §15.10, ORC-116). `group_key` is shared by every
  entry a declared sub-array spans — the group's own anchor's bare
  name — and `nil` for an entry no sub-array cites. `group_anchor`
  marks the group's own non-review-shaped agent step — not always
  where `Catapult.Dsl.Workflow.throwback_default/3` derives a decline
  back to, since a generation-shaped anchor's own derivation lands on
  its leading `pending` instead (§15.10's fourth-pass correction).
  """
  @type annotated_position :: %{
          position: position(),
          group_key: String.t() | nil,
          group_anchor: boolean()
        }

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
  def positions(%Workflow{} = workflow, type_name) do
    workflow |> annotated_positions(type_name) |> Enum.map(& &1.position)
  end

  @doc """
  `positions/2`, each entry paired with the sub-array it belongs to
  (§15.10) — `board`/`ticket` render the grouping this produces
  (`screens/board.md`'s "Sub-arrays render as a bounded box around
  their own lanes," ORC-116). Resolved off the true `statuses:` index,
  never off this list's own filtered position — an `environment:`
  entry ahead of a group would otherwise misalign one against the
  other, the identical hazard `systems/delivery.md`'s own ORC-116 entry
  records for the container axis.
  """
  @spec annotated_positions(Workflow.t(), String.t()) :: [annotated_position()]
  def annotated_positions(%Workflow{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, type} ->
        type.statuses
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} -> {to_position(entry), index} end)
        |> Enum.reject(fn {position, _index} -> is_nil(position) end)
        |> take_through_boundary()
        |> Enum.map(fn {position, index} -> annotate(type, position, index) end)

      :error ->
        []
    end
  end

  defp annotate(type, position, index) do
    case Type.group_at(type, index) do
      nil ->
        %{position: position, group_key: nil, group_anchor: false}

      range ->
        anchor_index = Type.anchor_index(type, range)

        %{
          position: position,
          group_key: anchor_index && Status.name(Enum.at(type.statuses, anchor_index)),
          group_anchor: index == anchor_index
        }
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

  @doc """
  The authored name a resting `position()` is displayed under
  (dsl-syntax.md §15.12, ORC-155): a status kind's own `name:` — its
  first-declared occurrence in `type_name`'s array, defaulting to the
  kind itself — or a gate's own declared name, which was always its
  whole identity. `nil` only for `nil` (no resting position at all).

  Read for display alone; nothing branches on it, and `status_kind`/
  `status_gate` are unaffected in shape or meaning by this (`Catapult
  .Delivery.Store.tickets_for_project/1`). Best-effort where a kind
  recurs under different authored names in the same type's array: this
  reads the *first* occurrence, since disambiguating *which* occurrence
  a resting ticket is actually at needs runtime position-tracking to
  carry the identical namespace awareness this ticket gives the
  loader's own reference resolution — ORC-116-adjacent future work, not
  this one's.
  """
  @spec name(Workflow.t(), String.t(), position() | nil) :: String.t() | nil
  def name(%Workflow{}, _type_name, nil), do: nil
  def name(%Workflow{}, _type_name, {:gate, gate_name}), do: gate_name

  def name(%Workflow{types: types}, type_name, {:kind, kind}) do
    with {:ok, type} <- Map.fetch(types, type_name),
         %Status{} = entry <- Enum.find(type.statuses, &(&1.status == Atom.to_string(kind))) do
      Status.name(entry)
    else
      _not_found -> Atom.to_string(kind)
    end
  end

  defp take_through_boundary(indexed_positions) do
    {before, at_and_after} =
      Enum.split_while(indexed_positions, fn {position, _index} ->
        position != {:kind, @reachable_boundary}
      end)

    case at_and_after do
      [] -> before
      [boundary | _rest] -> before ++ [boundary]
    end
  end
end
