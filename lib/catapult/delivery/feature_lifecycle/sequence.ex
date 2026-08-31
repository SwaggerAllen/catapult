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

  **An inline dispatch point has no `types/<name>.yaml` to read this
  from at all** (`systems/delivery.md`'s ORC-176 design pass):
  `Catapult.Delivery.ContainerLifecycle.open_inline/3` opens `setup`/
  `retro` with `flow_name` set to the entry's own literal name, never a
  declared type. When `type_name` fails to resolve above, this module
  asks the identical question `ContainerLifecycle.inline_dispatch_point?/1`
  already answers before opening one — agent-balled and not
  review-shaped (`SystemStatus.agent_balled?/1`,
  `SystemStatus.review_shaped?/1`) — and, if so, returns a fixed
  two-entry sequence instead of an empty one: the kind's own `pending`,
  then the kind itself, and nothing after, since neither flow runs its
  own `checks`/`reconcile`/`merge`/`deploy` (ORC-155). Anything else is
  still the authoring bug `Catapult.Delivery.FeatureLifecycle
  .warn_unplaceable/3` logs.

  **`annotated_position()`'s own `anchor` field carries the identical
  canonical identity ORC-116 gave the container axis, at ORC-171**
  (`systems/delivery.md`'s own entry): `nil` when a position's own bare
  kind or gate does not recur elsewhere in `type_name`'s array (the
  ordinary case — no shipped bundle recurs one today), else the
  recurring group's own anchor name, the identical ambiguity rule
  `Catapult.Dsl.Type.namespaced_positions/1`'s own `canonical` field
  applies. `identified_positions/2` is `positions/2` paired with it;
  `Catapult.Delivery.FeatureLifecycle.Projection`'s own `resting/3`
  reads that instead of the bare list, so a resting ticket standing at
  a kind that recurs is recorded as the occurrence it actually is
  rather than whichever comes first. `position()` itself stays exactly
  `{:kind, atom()} | {:gate, String.t()}` — unqualified — since
  `CatapultWeb.Live.Positions` (`system:dashboard`) already reads it
  bare and takes an anchor as a separate argument; widening the type
  itself would force that module open for no reason this ticket needs.
  """

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  @typedoc "One stop in the effective sequence: a fixed system-status kind, or a declared gate by its own name."
  @type position :: {:kind, atom()} | {:gate, String.t()}

  @typedoc "A position's own qualifying anchor (§15.12) — `nil` when its bare kind or gate is unambiguous within the citing type, the recurring group's own anchor name otherwise (ORC-171)."
  @type anchor :: String.t() | nil

  @typedoc """
  One `positions/2` entry, paired with the sub-array it belongs to
  (dsl-syntax.md §15.10, ORC-116). `group_key` is shared by every
  entry a declared sub-array spans — the group's own anchor's bare
  name — and `nil` for an entry no sub-array cites. `group_anchor`
  marks the group's own non-review-shaped agent step — not always
  where `Catapult.Dsl.Workflow.throwback_default/3` derives a decline
  back to, since a generation-shaped anchor's own derivation lands on
  its leading `pending` instead (§15.10's fourth-pass correction).
  `anchor` is the moduledoc's own canonical-identity field (ORC-171).
  """
  @type annotated_position :: %{
          position: position(),
          group_key: String.t() | nil,
          group_anchor: boolean(),
          anchor: anchor()
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

  Returns `[]` if `type_name` neither resolves in `workflow` nor names
  an inline dispatch point's own fixed sequence (see the moduledoc's
  ORC-176 entry) — logged and skipped by the caller,
  `Catapult.Delivery.FeatureLifecycle`, exactly as an unloadable bundle
  already is.
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
        namespaced_by_index =
          type |> Type.namespaced_positions() |> Map.new(&{&1.index, &1})

        type.statuses
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} -> {to_position(entry), index} end)
        |> Enum.reject(fn {position, _index} -> is_nil(position) end)
        |> take_through_boundary()
        |> Enum.map(fn {position, index} ->
          annotate(type, position, index, Map.fetch!(namespaced_by_index, index))
        end)

      :error ->
        inline_dispatch_positions(type_name)
    end
  end

  @doc """
  `positions/2`, each entry paired with its own qualifying anchor
  (the moduledoc's own ORC-171 entry) — what `Catapult.Delivery
  .FeatureLifecycle.Projection`'s `resting/3` reads instead of
  `positions/2`'s bare list.
  """
  @spec identified_positions(Workflow.t(), String.t()) :: [{position(), anchor()}]
  def identified_positions(%Workflow{} = workflow, type_name) do
    workflow |> annotated_positions(type_name) |> Enum.map(&{&1.position, &1.anchor})
  end

  # `type_name` is an inline dispatch point's own literal entry name
  # (`ContainerLifecycle.open_inline/3`), never a declared type — the
  # moduledoc's ORC-176 entry. Ungrouped: there is no declared array
  # for `Type.group_at/2` to read a sub-array off, and each of the two
  # synthesized entries carries the identical `anchor` field every
  # other constructor of `annotated_position()` supplies — `nil`,
  # unambiguous, since the two are distinct process-manager instances
  # never compared inside one `Projection` (`systems/delivery.md`'s own
  # ORC-171 entry).
  defp inline_dispatch_positions(type_name) do
    if SystemStatus.agent_balled?(type_name) and not SystemStatus.review_shaped?(type_name) do
      [
        %{position: {:kind, :pending}, group_key: nil, group_anchor: false, anchor: nil},
        %{
          position: {:kind, String.to_existing_atom(type_name)},
          group_key: nil,
          group_anchor: false,
          anchor: nil
        }
      ]
    else
      []
    end
  end

  defp annotate(type, position, index, namespaced) do
    anchor = if namespaced.canonical == namespaced.bare, do: nil, else: namespaced.namespace

    case Type.group_at(type, index) do
      nil ->
        %{position: position, group_key: nil, group_anchor: false, anchor: anchor}

      range ->
        anchor_index = Type.anchor_index(type, range)

        %{
          position: position,
          group_key: anchor_index && Status.name(Enum.at(type.statuses, anchor_index)),
          group_anchor: index == anchor_index,
          anchor: anchor
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
  validates it against at load time (ORC-34), bare or namespace-
  qualified `<anchor>.<name>` (§15.12) either way — to its `position()`
  shape paired with its own qualifying anchor (ORC-171), the same
  `position()` shape `to_position/1` produces from a `%Status{}` entry.
  A gate name is never also a declared status kind (the two live in
  disjoint vocabularies — `@ticket_status_names`'s closed set vs. a
  bundle-authored gate name), so membership in `workflow.gates` alone
  decides which shape a bare string resolves to; a gate's own name is
  never ambiguous (§13's gate/status disjointness check), so its own
  anchor is always `nil`.
  """
  @spec resolve_position(Workflow.t(), String.t(), String.t()) :: {position(), anchor()}
  def resolve_position(%Workflow{gates: gates} = workflow, type_name, name) do
    if Map.has_key?(gates, name) do
      {{:gate, name}, nil}
    else
      {bare, anchor} = resolve_kind_reference(workflow, type_name, name)
      {{:kind, String.to_existing_atom(bare)}, anchor}
    end
  end

  # `Type.namespaced_positions/1`'s own `qualified`/`bare`/`canonical`
  # fields (§15.12) resolve `name` the identical way `Catapult.Dsl
  # .Workflow`'s own (private) `resolve_reference/2` does for the
  # loader — a qualified `<anchor>.<name>` matches `qualified`
  # directly, a bare name matches `bare` only when exactly one entry
  # carries it (never whichever comes first). Load time already refused
  # an ambiguous bare reference (`gate_throwback_problems/2`), so `name`
  # reaching here unresolved is not expected; the fallback strips a
  # stray anchor rather than crash `String.to_existing_atom/1` on a
  # qualified string.
  defp resolve_kind_reference(%Workflow{types: types}, type_name, name) do
    with {:ok, type} <- Map.fetch(types, type_name),
         %{} = position <- find_namespaced(type, name) do
      anchor = if position.canonical == position.bare, do: nil, else: position.namespace
      {position.bare, anchor}
    else
      _not_found -> {name |> String.split(".", parts: 2) |> List.last(), nil}
    end
  end

  defp find_namespaced(%Type{} = type, ref) do
    positions = Type.namespaced_positions(type)

    case String.split(ref, ".", parts: 2) do
      [_anchor, _local] ->
        Enum.find(positions, &(&1.qualified == ref))

      [_bare] ->
        case Enum.filter(positions, &(&1.bare == ref)) do
          [position] -> position
          _none_or_ambiguous -> nil
        end
    end
  end

  @doc """
  The authored name a resting `position()` is displayed under
  (dsl-syntax.md §15.12, ORC-155): a status kind's own `name:` — the
  occurrence `anchor` (ORC-171) picks out, defaulting to the kind
  itself — or a gate's own declared name, which was always its whole
  identity. `nil` only for `nil` (no resting position at all).

  Read for display alone; nothing branches on it, and `status_kind`/
  `status_gate` are unaffected in shape or meaning by this (`Catapult
  .Delivery.Store.tickets_for_project/1`). `anchor` is what closes the
  gap this function's own moduledoc note used to name: `nil` still
  reads as "unambiguous" for a type that never recurs the kind, the
  ordinary case, but for one that does and `anchor` does not resolve to
  a real occurrence (`Catapult.Engine.Events.FlowResumed`'s own
  anchor-less `to_kind`/`to_gate`, `Catapult.Delivery.FeatureLifecycle
  .Projection`'s `resume/2`), this falls back to the bare kind rather
  than guessing an occurrence — transparently unresolved beats silently
  wrong.
  """
  @spec name(Workflow.t(), String.t(), position() | nil, anchor()) :: String.t() | nil
  def name(%Workflow{}, _type_name, nil, _anchor), do: nil
  def name(%Workflow{}, _type_name, {:gate, gate_name}, _anchor), do: gate_name

  def name(%Workflow{types: types}, type_name, {:kind, kind}, anchor) do
    with {:ok, type} <- Map.fetch(types, type_name),
         %Status{} = entry <- find_kind_entry(type, kind, anchor) do
      Status.name(entry)
    else
      _not_found -> Atom.to_string(kind)
    end
  end

  defp find_kind_entry(%Type{} = type, kind, anchor) do
    kind_str = Atom.to_string(kind)

    type
    |> Type.namespaced_positions()
    |> Enum.find_value(fn position ->
      entry_anchor = if position.canonical == position.bare, do: nil, else: position.namespace

      if position.entry.status == kind_str and entry_anchor == anchor, do: position.entry
    end)
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
