defmodule Catapult.Dsl.Workflow do
  @moduledoc """
  Loads and validates one `kind: workflow` bundle end to end
  (dsl-syntax.md §15): declared gates and environments (§15.4), and
  the unified work-item declaration `types/<name>.yaml` (§15.2) whose
  `statuses:` array positions everything — the skeleton's own required
  backbone, gate/environment citations, `flow:`/`blocks:` population-
  anchor metadata — by array index alone. There is no `after:` anywhere
  in this grammar (§15.3): position moved from a named-predecessor
  field on the gate/environment declaration itself to the citing
  type's own array, so the identical gate may run at different
  relative positions across two types without either being wrong.

  A workflow bundle carries no `extends:` (§11, §13; `Catapult.Dsl
  .Manifest`'s own moduledoc), the same as a chain bundle now that
  `extends:` has retired from the DSL entirely (ORC-153) — it is
  forked from the platform's default gates/environments/types, and
  this loader has always read its one directory directly.

  **Backward movement resolves here, and through one predicate**
  (§15.10). A decline's target is legal iff it is earlier in the citing
  type's own effective sequence — the identical test §7.19 gives a
  Blocked-return, and the identical test this loader has always run
  over a *declared* `throwback:`. So `gate_throwback_problems/2` and
  the runtime pick (`throwback_targets/3`, `throwback_legal?/4`) share
  `earlier_names/2` rather than agreeing by coincidence, and
  `throwback_default/3` supplies the landing point: the gate's own
  declared target, else the citing sub-array's own earliest entry.
  None of it is stored — a stored default would be a second
  home for a fact the citing type's array already carries, and a
  workflow cutover could not re-resolve it (§15.1).

  **A `merge` entry must be preceded, earlier in the same array, by a
  `reconcile` entry — stated positionally rather than per skeleton, at
  ORC-151's design review** (§15.1, §15.11): nothing merges, of any
  skeleton, without first having been read against its own argument
  (`docs/v5-design-decisions.md` §7.5). `merge_reconcile_problems/1`
  checks this over every declared array, `container`-skeleton ones
  included — closing the gap the ticket-skeleton-only framing left open
  (`types/milestone.yaml`'s own `setup`/`retro` sequences used to merge
  twice with nothing read first).

  Two of §13's checks need data this loader is never handed in Phase 3
  — a gate's role holders live in the identity component (Phase 7,
  v5 §7.16), and the mirror mapping lives with the outbound tracker
  add-on (Phase 4+, v5 §7.17) — so both are **opt-in**: passed via
  `role_holders`/`mirror_mapping` in `opts`, skipped (not failed) when
  absent.

  **A position's identity is `<anchor>.<name>` inside a sub-array, bare
  at the top level (§15.12, ORC-155).** `Catapult.Dsl.Type
  .namespaced_positions/1` builds every entry's bare name and its
  namespace-qualified form once per type — moved there at ORC-116 so
  `Catapult.Delivery.ContainerLifecycle.Sequence` can share the
  identical computation for the container axis, rather than this
  module being the only place it exists; `resolve_reference/2` is what
  `gate_throwback_problems/2` and `blocks_problems/1` both call to
  resolve a declared `throwback:`/`blocks:` string against that set —
  bare when the bare name is unique in the type, refused as ambiguous
  when it recurs across more than one namespace, and this is the one
  place that decision is made. `earlier_names/2` (§15.10's own
  backward-movement predicate) folds the identical ambiguity rule into
  the strings it returns, so a recurring bare name never silently
  prefers whichever occurrence comes first there either.
  """

  alias Catapult.Dsl.Environment
  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Dsl.Manifest
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Yaml

  @enforce_keys [:name, :entry]
  defstruct [:name, :entry, gates: %{}, environments: %{}, types: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          entry: String.t(),
          gates: %{String.t() => Gate.t()},
          environments: %{String.t() => Environment.t()},
          types: %{String.t() => Type.t()}
        }

  @container_required_order ~w(setup prep main retro cleanup)
  # The full fixed vocabulary (§15.1), not the ticket-skeleton's required
  # backbone: a ticket-skeleton array may additionally hold any other
  # anchor (e.g. a population anchor like `retro`/`setup`), so membership
  # here is checked against every kind, not the subset `ticket_relative_
  # order_problems/2` requires.
  @ticket_status_names Enum.map(SystemStatus.kinds(), &Atom.to_string/1)

  @doc "Loads and validates the workflow bundle named `name` under `bundles_root`."
  @spec load(String.t(), String.t(), keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def load(bundles_root, name, opts \\ []) do
    dir = Path.join(bundles_root, name)
    manifest_path = Path.join(dir, "bundle.yaml")

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw),
         {:ok, manifest} <- require_kind(manifest, "workflow") do
      build(dir, manifest, opts)
    end
  end

  defp require_kind(%{kind: kind} = manifest, kind), do: {:ok, manifest}

  defp require_kind(manifest, expected) do
    {:error,
     [
       "#{manifest.file} is a #{manifest.kind} bundle, expected #{expected} " <>
         "(catapult.yaml named it on the #{expected} axis)"
     ]}
  end

  defp build(dir, manifest, opts) do
    gate_files = resolve_globs(dir, manifest.gate_globs)
    env_files = resolve_globs(dir, manifest.environment_globs)
    type_files = resolve_globs(dir, manifest.type_globs)

    {gates, gate_problems} = parse_all(gate_files, Gate)
    {environments, env_problems} = parse_all(env_files, Environment)
    {types, type_problems} = parse_all(type_files, Type)

    gate_map = index(gates)
    env_map = index(environments)
    type_map = index(types)

    problems =
      gate_problems ++
        env_problems ++
        type_problems ++
        duplicate_names(gates, "gate") ++
        duplicate_names(environments, "environment") ++
        duplicate_names(types, "type") ++
        gate_throwback_problems(type_map, gate_map) ++
        environment_promotion_problems(env_map) ++
        naming_discipline_problems(gate_map, env_map) ++
        role_holder_problems(gate_map, Keyword.get(opts, :role_holders)) ++
        mirror_mapping_problems(gate_map, Keyword.get(opts, :mirror_mapping)) ++
        generation_blocked_exit_problems() ++
        pending_precedes_problems() ++
        skeleton_shape_problems(type_map) ++
        merge_reconcile_problems(type_map) ++
        pending_precedes_generation_problems(type_map) ++
        critique_adjacency_problems(type_map) ++
        name_uniqueness_problems(type_map) ++
        gate_status_disjointness_problems(type_map, gate_map) ++
        flow_reference_problems(type_map) ++
        review_reference_problems(type_map, gate_map) ++
        environment_reference_problems(type_map, env_map) ++
        blocks_problems(type_map) ++
        declaration_graph_problems(type_map) ++
        entry_problems(manifest.entry, type_map)

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: manifest.name,
         entry: manifest.entry,
         gates: gate_map,
         environments: env_map,
         types: type_map
       }}
    else
      {:error, Enum.uniq(problems)}
    end
  end

  defp resolve_globs(dir, globs) do
    globs |> Enum.flat_map(&Yaml.glob(dir, &1)) |> Enum.uniq() |> Enum.sort()
  end

  defp parse_all(files, module) do
    results =
      for path <- files do
        case Yaml.read(path) do
          {:ok, raw} -> module.parse(path, raw)
          {:error, reason} -> {:error, [reason]}
        end
      end

    problems =
      Enum.flat_map(results, fn
        {:ok, _} -> []
        {:error, p} -> p
      end)

    parsed = for {:ok, entry} <- results, do: entry
    {parsed, problems}
  end

  defp index(entries), do: Map.new(entries, &{&1.name, &1})

  defp duplicate_names(entries, label) do
    entries
    |> Enum.frequencies_by(& &1.name)
    |> Enum.filter(fn {_name, count} -> count > 1 end)
    |> Enum.map(fn {name, _count} -> "two or more #{label} declarations name #{inspect(name)}" end)
  end

  ## Gate throwback (§13, §15.4, §15.8, §15.10): a declared target must
  ## resolve to a status or another cited gate *earlier in the citing
  ## type's own array* — position lives there now, never on the gate
  ## itself. A gate declaring nothing has nothing to check here; its
  ## landing point is derived at throwback time instead
  ## (`throwback_default/3`).

  defp gate_throwback_problems(types, gates) do
    for {type_name, type} <- types,
        {status, index} <- Enum.with_index(type.statuses),
        not is_nil(status.review),
        gate = Map.get(gates, status.review),
        not is_nil(gate),
        not is_nil(gate.throwback),
        problem = gate_throwback_problem(type_name, type, index, status, gate) do
      problem
    end
    |> Enum.reject(&is_nil/1)
  end

  # A declared `throwback:` is resolved the identical way a `blocks:`
  # reference is (§15.12): a bare recurring across more than one
  # namespace is its own, specific load error, distinct from "does not
  # resolve at all" — both collapse to "not earlier" once resolved,
  # since a resolved-but-later position is exactly as illegal as one
  # that never resolved.
  defp gate_throwback_problem(type_name, type, index, status, gate) do
    case resolve_reference(type, gate.throwback) do
      {:ambiguous, namespaces} ->
        "type #{inspect(type_name)}'s #{inspect(status.review)} " <>
          "(#{Type.declared_path(type, index)}) throwback names #{inspect(gate.throwback)}, " <>
          "which resolves inside more than one namespace #{inspect(namespaces)} — qualify it " <>
          "<anchor>.<name> (§13, §15.12)"

      {:ok, %{index: target_index}} when target_index < index ->
        nil

      _not_earlier_or_not_found ->
        "type #{inspect(type_name)}'s #{inspect(status.review)} " <>
          "(#{Type.declared_path(type, index)}) throwback names #{inspect(gate.throwback)}, " <>
          "which is not earlier in this type's own statuses: array (§13, §15.4, §15.8)"
    end
  end

  ## The one predicate (§15.10). Everything backward-moving — the load
  ## check above, the runtime pick below — reads legality off this.
  ## `canonical` (§15.12) is `earlier_names/2`'s bare name unless that
  ## bare name recurs elsewhere in the same type, in which case only
  ## the qualified form is offered — the identical "stays bare when
  ## unambiguous" rule `resolve_reference/2` enforces on the way in,
  ## applied here on the way out so a decline's own legal-target list
  ## never offers a string that would refuse to resolve if written back.

  defp earlier_names(%Type{} = type, index) do
    type |> earlier_positions(index) |> Enum.map(& &1.canonical)
  end

  # `Type.namespaced_positions/1` is the one place §15.12's bare/
  # qualified/ambiguity computation happens — `Catapult.Delivery
  # .ContainerLifecycle.Sequence` reads it too, for the container axis
  # (ORC-116) — so this module only filters and reshapes what it
  # returns, never re-derives it.
  defp earlier_positions(%Type{} = type, index) do
    type
    |> Type.namespaced_positions()
    |> Enum.filter(&(&1.index < index))
  end

  # Resolves a `blocks:`/`throwback:` reference (or any other citation
  # into a `statuses:` array) against `type`'s own namespaced positions
  # (§15.12): `{:ok, position}` for an unambiguous match — bare or
  # `<anchor>.<name>` — `{:ambiguous, namespaces}` when a bare
  # reference matches more than one namespace, `:error` when it
  # matches nothing at all. One level of qualification only: `ref` is
  # split on its first `.`, never re-split further.
  defp resolve_reference(%Type{} = type, ref) do
    positions = Type.namespaced_positions(type)

    case String.split(ref, ".", parts: 2) do
      [_anchor, _local] ->
        case Enum.find(positions, &(&1.qualified == ref)) do
          nil -> :error
          position -> {:ok, position}
        end

      [_bare] ->
        case Enum.filter(positions, &(&1.bare == ref)) do
          [] -> :error
          [position] -> {:ok, position}
          many -> {:ambiguous, Enum.map(many, & &1.namespace)}
        end
    end
  end

  # Where in `type_name`'s array `gate_name` is cited, as `{type,
  # index}`. The *first* citation, which is also the only one the rest
  # of the system can express: a position is `{:gate, name}` with no
  # index (`Catapult.Delivery.FeatureLifecycle.Sequence
  # .resolve_position/2`, and the projection's own `status_gate`
  # column), so a type citing one gate twice already has no way to say
  # which citation a ticket is resting at.
  defp citation(%__MODULE__{types: types}, type_name, gate_name) do
    with {:ok, type} <- Map.fetch(types, type_name),
         index when not is_nil(index) <-
           Enum.find_index(type.statuses, &(&1.review == gate_name)) do
      {type, index}
    else
      _not_cited -> nil
    end
  end

  @doc """
  Every legal landing point for a decline at `gate_name` on a ticket of
  type `type_name`: each entry earlier than that gate in the citing
  type's own effective sequence, in array order (§15.10).

  This is the whole of legality — there is no per-gate allow-list, and
  a gate's `throwback:` bounds nothing. `[]` when `type_name` does not
  resolve or does not cite `gate_name`, which is a caller that has
  paired a gate with the wrong type rather than a gate no decline can
  leave.
  """
  @spec throwback_targets(t(), String.t(), String.t()) :: [String.t()]
  def throwback_targets(%__MODULE__{} = workflow, type_name, gate_name)
      when is_binary(type_name) and is_binary(gate_name) do
    case citation(workflow, type_name, gate_name) do
      {type, index} -> earlier_names(type, index)
      nil -> []
    end
  end

  @doc """
  Whether `target` is a legal decline target for `gate_name` on a
  ticket of type `type_name` (§15.10).

  This is the check `Catapult.Engine.Commands.DeclineGate`'s own
  moduledoc assigns to the command edge — bundle content is the
  command edge's to validate, never the aggregate's — and the same one
  `Catapult.Delivery.ContainerLifecycle.Sequence.earlier?/4` already
  answers for a container's own array.
  """
  @spec throwback_legal?(t(), String.t(), String.t(), String.t()) :: boolean()
  def throwback_legal?(%__MODULE__{} = workflow, type_name, gate_name, target)
      when is_binary(target) do
    target in throwback_targets(workflow, type_name, gate_name)
  end

  @doc """
  `throwback_targets/3`, each target marked whether landing there
  leaves the gate's own sub-array (§15.10, ORC-116) — the annotation
  `screens/document-review.md`'s own secondary "choose a different
  target" disclosure renders beside a target outside the gate's own
  group, the identical distinction `screens/ticket.md`'s Blocked-return
  control draws over the identical legality test.

  `leaves_group` is `false` throughout when the gate itself sits in no
  sub-array — there is no group to leave. When it does, a target still
  inside that group reads `false`; every other target, including one
  in no group at all, reads `true`.
  """
  @spec throwback_target_details(t(), String.t(), String.t()) :: [
          %{target: String.t(), leaves_group: boolean()}
        ]
  def throwback_target_details(%__MODULE__{} = workflow, type_name, gate_name)
      when is_binary(type_name) and is_binary(gate_name) do
    case citation(workflow, type_name, gate_name) do
      {type, index} ->
        gate_group = Type.group_at(type, index)

        type
        |> earlier_positions(index)
        |> Enum.map(fn pos ->
          %{target: pos.canonical, leaves_group: leaves_group?(type, gate_group, pos.index)}
        end)

      nil ->
        []
    end
  end

  defp leaves_group?(_type, nil, _target_index), do: false

  defp leaves_group?(type, gate_group, target_index),
    do: Type.group_at(type, target_index) != gate_group

  @doc """
  Where a decline at `gate_name` lands by default for a ticket of type
  `type_name` (§15.10): the gate's own declared `throwback:` when it
  names one, otherwise the derived default — the citing sub-array's own
  earliest entry.

  Never the array position immediately before the gate. That reading
  fails the shape §15.10 argues from, `[milestone-signoff, retro,
  proposals-read]`: a gate sitting *after* its group's agent step would
  fall back to the entry before it and re-ask a human a question they
  already answered, instead of re-running the agent that produced the
  thing being declined.

  Nor is it always the group's own non-review-shaped agent step: when
  the group's own first entry is a `pending`, dedicated to that anchor
  (§13's pending-precedes check guarantees this for every
  generation-shaped anchor, and a bundle may add one by convention even
  where nothing requires it, as `types/milestone.yaml`'s `setup` group
  does), the earliest entry is that `pending` rather than the anchor —
  a decline then queues the repair through the same dispatch wait any
  other `pending` entry goes through, instead of landing straight on
  the agent step and skipping it (§15.10's fourth-pass correction). An
  anchor with no leading `pending` of its own — `retro`'s group, in the
  shipped bundle — still derives to itself.

  `nil` when the gate declares no target and cites no sub-array. That
  is a gate with no one-click default rather than a gate that cannot be
  declined — `throwback_targets/3` is unaffected, and every entry it
  lists stays legal.

  Also `nil` for a gate sitting *before* its own group's agent step,
  where the derivation would otherwise name a target later than the
  gate and so illegal by the rule above. §15.10 does not reach this
  case: it reasons about the agent step as "the earliest entry the
  group has," which the shape it argues from
  (`[milestone-signoff, retro, proposals-read]`) does not satisfy for
  its own first gate — and does not have to, since `milestone-signoff`
  declares `throwback: main` and never derives. Deriving nothing is the
  narrow reading; offering a one-click default the same module would
  reject as illegal is not a defensible alternative, and inventing a
  second derivation rule for the case is the accretion
  `docs/v5-design-decisions.md` §4.5 warns off. Flagged in ORC-141's
  hand-back as a gap for the record to settle.
  """
  @spec throwback_default(t(), String.t(), String.t()) :: String.t() | nil
  def throwback_default(%__MODULE__{} = workflow, type_name, gate_name)
      when is_binary(type_name) and is_binary(gate_name) do
    case citation(workflow, type_name, gate_name) do
      {type, index} ->
        case Map.get(workflow.gates, gate_name) do
          %Gate{throwback: declared} when is_binary(declared) -> declared
          _derived -> derived_throwback(type, index)
        end

      nil ->
        nil
    end
  end

  defp derived_throwback(type, index) do
    case Type.group_at(type, index) do
      nil ->
        nil

      range ->
        case Type.anchor_index(type, range) do
          anchor_index when not is_nil(anchor_index) and anchor_index < index ->
            target_index = fallback_index(type, range, anchor_index)

            type
            |> Type.namespaced_positions()
            |> Enum.find(&(&1.index == target_index))
            |> Map.fetch!(:canonical)

          _nil_or_not_earlier ->
            nil
        end
    end
  end

  # §15.10's fourth-pass correction: the sub-array's own "earliest
  # entry" is its leading `pending` when it has one, not the anchor
  # itself — §13's pending-precedes check guarantees a `pending` at
  # `range.first` for every generation-shaped anchor, and
  # `bundles/default-flow/types/milestone.yaml`'s own `setup` group
  # carries one by convention though nothing requires it there. Either
  # way landing on it queues the repair through the same dispatch wait
  # any other `pending` entry does, rather than skipping straight to
  # the agent step. An anchor with no leading `pending` — `retro`'s own
  # group, which no check requires one for — keeps deriving to itself.
  defp fallback_index(type, range, anchor_index) do
    if match?(%Status{status: "pending"}, Enum.at(type.statuses, range.first)) do
      range.first
    else
      anchor_index
    end
  end

  ## environments (§15.4)

  defp environment_promotion_problems(environments) do
    missing =
      for {name, env} <- environments,
          env.promote_from,
          not Map.has_key?(environments, env.promote_from) do
        "environment #{inspect(name)}'s promote_from #{inspect(env.promote_from)} names an environment that is not declared"
      end

    self_problems =
      for {name, env} <- environments, env.promote_from == name do
        "environments' promote_from: references cycle: #{inspect([name, name])}"
      end

    edges = for {name, env} <- environments, env.promote_from, do: {name, env.promote_from}

    cycle_problems =
      if DslGraph.acyclic?(edges) do
        []
      else
        ["environments' promote_from: references cycle: #{inspect(DslGraph.find_cycle(edges))}"]
      end

    missing ++ self_problems ++ cycle_problems
  end

  ## §7.6's naming discipline over the declared set: no two declared
  ## names differ by exactly one *inserted or removed* hyphen-separated
  ## word (e.g. `product-review` vs `product-review-final`).

  defp naming_discipline_problems(gates, environments) do
    names = Map.keys(gates) ++ Map.keys(environments)

    for {a, i} <- Enum.with_index(names),
        {b, j} <- Enum.with_index(names),
        i < j,
        one_word_apart?(a, b) do
      "#{inspect(a)} and #{inspect(b)} are one hyphen-separated word apart (§7.6's naming discipline) — pick names that read as clearly distinct"
    end
  end

  defp one_word_apart?(a, b) do
    wa = String.split(a, "-")
    wb = String.split(b, "-")

    case {length(wa), length(wb)} do
      {la, lb} when abs(la - lb) == 1 -> insertion_apart?(wa, wb)
      _same_or_far -> false
    end
  end

  defp insertion_apart?(shorter, longer) when length(shorter) > length(longer) do
    insertion_apart?(longer, shorter)
  end

  defp insertion_apart?(shorter, longer) do
    Enum.any?(0..(length(longer) - 1), &(List.delete_at(longer, &1) == shorter))
  end

  ## Opt-in checks (see moduledoc)

  defp role_holder_problems(_gates, nil), do: []

  defp role_holder_problems(gates, holders) do
    for {name, gate} <- gates, gate.role, Map.get(holders, gate.role, []) == [] do
      "gate #{inspect(name)}'s role #{inspect(gate.role)} has no holders — a gate with nobody to route to is indistinguishable from a slow reviewer (v5 §7.16)"
    end
  end

  defp mirror_mapping_problems(_gates, nil), do: []

  defp mirror_mapping_problems(gates, mapping) do
    for {name, _gate} <- gates, not Map.has_key?(mapping, name) do
      "gate #{inspect(name)} has no counterpart in the outbound tracker's mirror mapping (v5 §7.17) — an unmapped state has halted a sweep for hours"
    end
  end

  # dsl-syntax.md §13: a fact about the fixed skeleton, exercised at
  # load time so a defect in that skeleton (not in any one bundle) is
  # what it would catch.
  defp generation_blocked_exit_problems do
    for kind <- [:generation, :design, :architecture, :implementation],
        not SystemStatus.can_block?(kind) do
      "platform defect: the fixed system-status skeleton has no path from #{kind} to blocked"
    end
  end

  defp pending_precedes_problems do
    for kind <- [:generation, :design, :architecture, :implementation, :deploy],
        not SystemStatus.pending_precedes?(kind) do
      "platform defect: the fixed system-status skeleton has no pending precedent for #{kind}"
    end
  end

  ## Skeleton shape (§15.1, §13): a container-skeleton type's array
  ## holds exactly the five fixed anchors, in order, then terminal; a
  ## ticket-skeleton type's array opens with pending, closes with
  ## terminal, and holds generation/checks/merge/deploy at least once
  ## each in that relative order.

  defp skeleton_shape_problems(types) do
    types
    |> Enum.flat_map(fn {name, type} ->
      case type.skeleton do
        "container" -> container_shape_problems(name, type)
        "ticket" -> ticket_shape_problems(name, type)
        nil -> []
      end
    end)
  end

  defp anchor_names(type) do
    for %Status{status: s} <- type.statuses, not is_nil(s), do: s
  end

  # A skeleton fixes a required backbone, never an exclusive membership
  # (§15.1, a seventh-pass reversal, ORC-148): `setup`, `prep`, `main`,
  # `retro`, `cleanup` must each appear at least once, in that relative
  # order, and `terminal` exactly once, last — what a container-skeleton
  # type's array may *additionally* hold (a bare generation, a second
  # population anchor, gates, environments) is unbounded by this check,
  # symmetrically with the ticket-skeleton read below.
  defp container_shape_problems(name, type) do
    names = anchor_names(type)
    present = Enum.filter(@container_required_order, &(&1 in names))

    cond do
      present != @container_required_order ->
        missing = @container_required_order -- present

        [
          "type #{inspect(name)}'s statuses: is missing #{inspect(missing)} (§15.1 requires " <>
            "setup, prep, main, retro, cleanup at least once each, in that relative order)"
        ]

      names == [] or List.last(names) != "terminal" ->
        [
          "type #{inspect(name)}'s statuses: must close with terminal (§15.1); got " <>
            "#{inspect(List.last(names))}"
        ]

      Enum.count(names, &(&1 == "terminal")) > 1 ->
        ["type #{inspect(name)}'s statuses: declares terminal more than once (§15.1)"]

      true ->
        container_relative_order_problems(name, names)
    end
  end

  defp container_relative_order_problems(name, names) do
    indices = for req <- @container_required_order, do: Enum.find_index(names, &(&1 == req))

    if indices == Enum.sort(indices) do
      []
    else
      [
        "type #{inspect(name)}'s statuses: holds setup/prep/main/retro/cleanup out of their " <>
          "required relative order (§15.1); got #{inspect(names)}"
      ]
    end
  end

  defp ticket_shape_problems(name, type) do
    names = anchor_names(type)
    invalid = Enum.uniq(names) -- @ticket_status_names

    cond do
      invalid != [] ->
        [
          "type #{inspect(name)}'s statuses: names #{inspect(invalid)}, not part of the ticket " <>
            "skeleton's fixed anchor set #{inspect(@ticket_status_names)} (§15.1)"
        ]

      names == [] or List.first(names) != "pending" ->
        [
          "type #{inspect(name)}'s statuses: must open with pending (§15.1); got " <>
            "#{inspect(List.first(names))}"
        ]

      List.last(names) != "terminal" ->
        [
          "type #{inspect(name)}'s statuses: must close with terminal (§15.1); got " <>
            "#{inspect(List.last(names))}"
        ]

      Enum.count(names, &(&1 == "terminal")) > 1 ->
        ["type #{inspect(name)}'s statuses: declares terminal more than once (§15.1)"]

      true ->
        ticket_relative_order_problems(name, names)
    end
  end

  # "At least one generation-shaped entry (generation, design or
  # architecture, in any combination), checks, merge and deploy at
  # least once each, in that relative order" (§15.1) — a generation-
  # shaped kind and merge may recur; the order check below reasons over
  # each required token's *first* occurrence, the same simplification
  # the pre-ORC-148 check already made for `merge`'s own recurrence.
  defp ticket_relative_order_problems(name, names) do
    has_generation_shaped? = Enum.any?(names, &SystemStatus.generation_shaped?/1)
    missing_fixed = for req <- ~w(checks merge deploy), req not in names, do: req

    if not has_generation_shaped? or missing_fixed != [] do
      missing = if has_generation_shaped?, do: [], else: ["a generation-shaped entry"]

      [
        "type #{inspect(name)}'s statuses: is missing #{inspect(missing ++ missing_fixed)} " <>
          "(§15.1 requires at least one generation-shaped entry — generation, design or " <>
          "architecture — plus checks, merge and deploy at least once each)"
      ]
    else
      generation_index = Enum.find_index(names, &SystemStatus.generation_shaped?/1)
      fixed_indices = for req <- ~w(checks merge deploy), do: Enum.find_index(names, &(&1 == req))
      indices = [generation_index | fixed_indices]

      if indices == Enum.sort(indices) do
        []
      else
        [
          "type #{inspect(name)}'s statuses: holds a generation-shaped entry/checks/merge/" <>
            "deploy out of their required relative order (§15.1); got #{inspect(names)}"
        ]
      end
    end
  end

  ## `reconcile` before `merge` (§13, §15.11, ORC-151): a fact about the
  ## array's own contents, checked identically whichever skeleton, if
  ## any, the citing type declares — `merge`'s own ball is `plane`
  ## (§15.1), so nothing merges without first having been read against
  ## its own argument (`docs/v5-design-decisions.md` §7.5). Stated
  ## positionally rather than folded into the ticket-skeleton backbone
  ## list above: `reconcile` is required wherever `merge` is, not merely
  ## once per ticket-skeleton array, and it reaches `container`-skeleton
  ## arrays too.

  defp merge_reconcile_problems(types) do
    for {type_name, type} <- types do
      names = anchor_names(type)

      names
      |> Enum.with_index()
      |> Enum.filter(fn {name, i} ->
        name == "merge" and "reconcile" not in Enum.take(names, i)
      end)
      |> Enum.map(fn {_name, i} ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, anchor_index(type, i))} is " <>
          "merge, with no earlier reconcile entry in this type's own statuses: array (§13, §15.11)"
      end)
    end
    |> List.flatten()
  end

  # `merge_reconcile_problems/1` walks anchor (`status:`) names alone, so
  # its own index into that filtered list is not the effective-sequence
  # index `Type.declared_path/2` expects — this re-finds the entry's
  # real position, the same re-indexing `anchor_names/1`'s other callers
  # would need if they rendered a path.
  defp anchor_index(%Type{statuses: statuses}, anchor_occurrence) do
    statuses
    |> Enum.with_index()
    |> Enum.filter(fn {%Status{status: s}, _i} -> not is_nil(s) end)
    |> Enum.at(anchor_occurrence)
    |> elem(1)
  end

  ## `pending` before every generation-shaped entry (§13, §15.1): the
  ## first entry of that entry's own sub-array, when it sits in one
  ## (§15.10); any earlier top-level `pending` otherwise — but never one
  ## already spent on another generation-shaped entry. A single leading
  ## `pending` used to license every later generation-shaped entry in
  ## the same array; a design-review tightening retired that reading
  ## (ORC-151) once `fanout` stopped giving a second such entry
  ## somewhere else to sit meanwhile, so this walks the array in
  ## declared order and tracks how many un-spent top-level `pending`s
  ## have been seen — a grouped `pending` is never added to that pool,
  ## since it is already dedicated to its own sub-array's entry.

  defp pending_precedes_generation_problems(types) do
    for {type_name, type} <- types do
      type.statuses
      |> Enum.with_index()
      |> Enum.reduce({[], 0}, fn {status, index}, {problems, available} ->
        pending_precedes_generation_step(type_name, type, status, index, problems, available)
      end)
      |> elem(0)
    end
    |> List.flatten()
  end

  defp pending_precedes_generation_step(
         _type_name,
         type,
         %Status{status: "pending"},
         index,
         problems,
         available
       ) do
    if is_nil(Type.group_at(type, index)) do
      {problems, available + 1}
    else
      {problems, available}
    end
  end

  defp pending_precedes_generation_step(
         type_name,
         type,
         %Status{status: name},
         index,
         problems,
         available
       )
       when is_binary(name) do
    if SystemStatus.generation_shaped?(name) do
      generation_pending_problem(type_name, type, index, problems, available)
    else
      {problems, available}
    end
  end

  defp pending_precedes_generation_step(_type_name, _type, %Status{}, _index, problems, available) do
    {problems, available}
  end

  defp generation_pending_problem(type_name, type, index, problems, available) do
    case Type.group_at(type, index) do
      nil ->
        if available > 0 do
          {problems, available - 1}
        else
          problem =
            "type #{inspect(type_name)}'s #{Type.declared_path(type, index)} is " <>
              "generation-shaped, with no earlier pending entry left un-spent by another " <>
              "generation-shaped entry in this type's own statuses: array (§13, §15.1) — one " <>
              "pending per generation-shaped entry, never shared"

          {[problem | problems], available}
        end

      range ->
        if match?(%Status{status: "pending"}, Enum.at(type.statuses, range.first)) do
          {problems, available}
        else
          problem =
            "type #{inspect(type_name)}'s #{Type.declared_path(type, index)} is " <>
              "generation-shaped and grouped in a sub-array whose first entry is not pending " <>
              "(§13, §15.1, §15.10)"

          {[problem | problems], available}
        end
    end
  end

  ## Critique adjacency (§13, §15.5): must sit immediately after a
  ## generation-shaped entry (generation, design or architecture) in
  ## the same type's array — no skeleton check needed, since whether a
  ## given array has one to pair with is a fact about that array's own
  ## contents, never about which skeleton the citing type declares
  ## (ORC-148: a container-skeleton or skeleton-less type may hold a
  ## bare generation-shaped entry now too, §15.2).

  defp critique_adjacency_problems(types) do
    for {type_name, type} <- types do
      labels = Enum.map(type.statuses, &entry_label/1)

      labels
      |> Enum.with_index()
      |> Enum.filter(fn {label, i} ->
        label == {:status, "critique"} and not critique_adjacent?(labels, i)
      end)
      |> Enum.map(fn {_label, i} ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, i)} is critique, which must " <>
          "sit immediately after a generation-shaped entry, or that entry's own checks (§13, §15.5)"
      end)
    end
    |> List.flatten()
  end

  # A `critique` is adjacent when it directly follows a generation-shaped
  # entry, or directly follows that entry's own `checks` — never before
  # it (a fifth-design-review addition, ORC-151): `checks` runs first,
  # so neither an agent's critique nor a human gate reads a draft CI has
  # not yet validated.
  defp critique_adjacent?(labels, i) do
    i > 0 and
      (generation_shaped_label?(labels, i - 1) or
         (checks_label?(labels, i - 1) and i > 1 and generation_shaped_label?(labels, i - 2)))
  end

  defp generation_shaped_label?(labels, index) do
    case Enum.at(labels, index) do
      {:status, name} -> SystemStatus.generation_shaped?(name)
      _review_or_environment -> false
    end
  end

  defp checks_label?(labels, index), do: Enum.at(labels, index) == {:status, "checks"}

  defp entry_label(%Status{status: s}) when not is_nil(s), do: {:status, s}
  defp entry_label(%Status{review: r}) when not is_nil(r), do: {:review, r}
  defp entry_label(%Status{environment: e}) when not is_nil(e), do: {:environment, e}

  ## Name uniqueness within a namespace (§13, §15.12, ORC-155): the
  ## top-level array is one namespace, and each sub-array is its own —
  ## the sub-array's own anchor counts as a member of its own
  ## namespace, exactly as much as anything else inside it. A default
  ## that would collide (two undeclared `checks` entries in one
  ## sub-array, both defaulting to the name `checks`) is exactly as
  ## much a load error as a declared collision naming the same string
  ## twice on purpose.

  defp name_uniqueness_problems(types) do
    for {type_name, type} <- types do
      top_level_name_problems(type_name, type) ++ group_name_problems(type_name, type)
    end
    |> List.flatten()
  end

  defp top_level_name_problems(type_name, type) do
    type
    |> Type.namespaced_positions()
    |> Enum.filter(&(&1.namespace == :top_level))
    |> duplicate_bare_name_problems(fn bare ->
      "type #{inspect(type_name)}'s top-level statuses: array names #{inspect(bare)} more " <>
        "than once (§13, §15.12 requires unique names within a namespace)"
    end)
  end

  defp group_name_problems(type_name, type) do
    for range <- type.groups do
      range
      |> Enum.map(&{&1, Status.name(Enum.at(type.statuses, &1))})
      |> duplicate_bare_name_pairs()
      |> Enum.map(fn bare ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, range.first)} sub-array names " <>
          "#{inspect(bare)} more than once (§13, §15.10, §15.12 requires unique names within a " <>
          "namespace)"
      end)
    end
    |> List.flatten()
  end

  defp duplicate_bare_name_problems(positions, message) do
    positions
    |> Enum.map(& &1.bare)
    |> duplicate_bare_names()
    |> Enum.map(message)
  end

  defp duplicate_bare_name_pairs(pairs) do
    pairs |> Enum.map(fn {_index, bare} -> bare end) |> duplicate_bare_names()
  end

  defp duplicate_bare_names(bares) do
    bares
    |> Enum.frequencies()
    |> Enum.filter(fn {_bare, count} -> count > 1 end)
    |> Enum.map(fn {bare, _count} -> bare end)
  end

  ## Gate/status name disjointness (§13, §15.12, ORC-155):
  ## `Catapult.Delivery.FeatureLifecycle.Sequence.resolve_position/2`
  ## decides gate-vs-status by membership in the workflow's own
  ## declared gate set alone, safe only as long as a gate's own name
  ## never collides with any addressable status name — bare or
  ## namespace-qualified — in the loaded union. Without this check a
  ## collision resolves to `{:gate, name}` unconditionally and an
  ## unrecognized name raises inside `String.to_existing_atom`, both on
  ## the throwback path and both invisible until a decline fires.

  defp gate_status_disjointness_problems(types, gates) do
    for {type_name, type} <- types,
        position <- Type.namespaced_positions(type),
        not is_nil(position.entry.status),
        {gate_name, gate} <- gates,
        gate_name in Enum.uniq([position.bare, position.qualified]) do
      gate_status_collision_problem(type_name, type, position, gate_name, gate)
    end
  end

  defp gate_status_collision_problem(
         type_name,
         type,
         %{bare: bare, qualified: bare} = position,
         gate_name,
         gate
       ) do
    "gate #{inspect(gate_name)} (#{gate.file}) collides with type #{inspect(type_name)}'s " <>
      "status name #{inspect(bare)} (#{Type.declared_path(type, position.index)}) — a declared " <>
      "gate's own name must stay disjoint from every addressable status name (§13, §15.12)"
  end

  defp gate_status_collision_problem(type_name, type, position, gate_name, gate) do
    "gate #{inspect(gate_name)} (#{gate.file}) collides with type #{inspect(type_name)}'s " <>
      "status name #{inspect(position.bare)} in the #{inspect(position.namespace)} namespace " <>
      "(#{inspect(position.qualified)}, #{Type.declared_path(type, position.index)}) — a " <>
      "declared gate's own name must stay disjoint from every addressable status name (§13, §15.12)"
  end

  ## `flow:`/`review:`/`environment:` cross-references (§13)

  defp flow_reference_problems(types) do
    for {type_name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        not Map.has_key?(types, status.flow) do
      "type #{inspect(type_name)}'s #{inspect(status.status)} flow: names #{inspect(status.flow)}, which is not a declared type"
    end
  end

  defp review_reference_problems(types, gates) do
    for {type_name, type} <- types,
        status <- type.statuses,
        not is_nil(status.review),
        not Map.has_key?(gates, status.review) do
      "type #{inspect(type_name)} cites review: #{inspect(status.review)}, which is not a declared gate"
    end
  end

  defp environment_reference_problems(types, environments) do
    for {type_name, type} <- types,
        status <- type.statuses,
        not is_nil(status.environment),
        not Map.has_key?(environments, status.environment) do
      "type #{inspect(type_name)} cites environment: #{inspect(status.environment)}, which is not a declared environment"
    end
  end

  ## `blocks:` scoping (§13, §15.7, §15.10, ORC-148 design review): a
  ## `blocks:` entry names an entry that is unique within the citing
  ## type's own array — a bare top-level entry, or one that belongs to
  ## a sub-array, in which case the reference is to the whole sub-array
  ## (resolved by containment, since a sub-array is referenced through
  ## an entry it contains, never by a name of its own). Uniqueness is a
  ## property of the reference, not the declaration it lands on: zero
  ## matches or two-or-more is the load error.

  defp blocks_problems(types) do
    for {type_name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        target <- status.blocks do
      blocks_problem(type_name, type, status, target)
    end
    |> Enum.reject(&is_nil/1)
  end

  defp blocks_problem(type_name, _type, status, target) when target == status.status do
    "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names itself (§13, §15.7)"
  end

  defp blocks_problem(type_name, type, status, target) do
    case resolve_reference(type, target) do
      {:ok, _position} ->
        nil

      {:ambiguous, namespaces} ->
        "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, " <>
          "which resolves inside more than one namespace #{inspect(namespaces)} — qualify it " <>
          "<anchor>.<name> (§13, §15.7, §15.12)"

      :error ->
        "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, " <>
          "which does not resolve to any entry in this type's own statuses: array (§13, §15.7, §15.10)"
    end
  end

  ## Declaration graph (§13, §15.6): nodes are every type with a
  ## population anchor of its own (a fact about that type's own
  ## declared entries, never about which skeleton, if any, it declares
  ## — ORC-148), edges are `flow:` references between them; must be
  ## acyclic.

  defp declaration_graph_nodes(types) do
    for {name, type} <- types, Enum.any?(type.statuses, &Status.queue_shaped?/1), do: name
  end

  defp declaration_graph_edges(types) do
    nodes = declaration_graph_nodes(types)

    for {name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        status.flow in nodes,
        do: {name, status.flow}
  end

  defp declaration_graph_problems(types) do
    edges = declaration_graph_edges(types)

    self_problems =
      for {from, to} <- edges, from == to do
        "type #{inspect(from)}'s flow: names itself — a container/skeleton-less type may not nest its own kind (§15.6)"
      end

    cycle_problems =
      if DslGraph.acyclic?(edges) do
        []
      else
        [
          "the declaration graph (types' flow: references) has a cycle: #{inspect(DslGraph.find_cycle(edges))} (§13, §15.6)"
        ]
      end

    self_problems ++ cycle_problems
  end

  defp declaration_graph_roots(types) do
    nodes = declaration_graph_nodes(types)
    targeted = for {_from, to} <- declaration_graph_edges(types), do: to
    nodes -- Enum.uniq(targeted)
  end

  ## `entry:` (§2, §13, §15.2, §15.6): names the type a fresh project
  ## dispatches from — resolves, carries a queue-shaped anchor, and is
  ## a root in the declaration graph.

  defp entry_problems(entry_name, types) do
    case Map.fetch(types, entry_name) do
      :error ->
        ["entry #{inspect(entry_name)} does not resolve to a declared type"]

      {:ok, %Type{}} ->
        cond do
          entry_name not in declaration_graph_nodes(types) ->
            [
              "entry #{inspect(entry_name)} names a type with no population anchor of its own " <>
                "(§13, §15.2, §15.6) — it has nothing to start a project from"
            ]

          entry_name not in declaration_graph_roots(types) ->
            [
              "entry #{inspect(entry_name)} is not a root in the declaration graph — some other " <>
                "type's flow: already targets it"
            ]

          true ->
            []
        end
    end
  end
end
