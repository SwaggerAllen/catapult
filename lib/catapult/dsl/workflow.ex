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
  .Manifest`'s own moduledoc) — it is forked from the platform's
  default gates/environments/types instead of layered — so, unlike
  `Catapult.Dsl.Chain`, this loader reads one directory directly and
  never resolves an `Catapult.Dsl.Extends` chain.

  **Backward movement resolves here, and through one predicate**
  (§15.10). A decline's target is legal iff it is earlier in the citing
  type's own effective sequence — the identical test §7.19 gives a
  Blocked-return, and the identical test this loader has always run
  over a *declared* `throwback:`. So `gate_throwback_problems/2` and
  the runtime pick (`throwback_targets/3`, `throwback_legal?/4`) share
  `earlier_names/2` rather than agreeing by coincidence, and
  `throwback_default/3` supplies the landing point: the gate's own
  declared target, else the citing sub-array's own non-critique agent
  step. None of it is stored — a stored default would be a second home
  for a fact the citing type's array already carries, and a workflow
  cutover could not re-resolve it (§15.1).

  Two of §13's checks need data this loader is never handed in Phase 3
  — a gate's role holders live in the identity component (Phase 7,
  v5 §7.16), and the mirror mapping lives with the outbound tracker
  add-on (Phase 4+, v5 §7.17) — so both are **opt-in**: passed via
  `role_holders`/`mirror_mapping` in `opts`, skipped (not failed) when
  absent.
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
  @ticket_status_names ~w(pending generation design architecture critique checks merge deploy terminal)

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
        critique_adjacency_problems(type_map) ++
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
        gate.throwback not in earlier_names(type, index) do
      "type #{inspect(type_name)}'s #{inspect(status.review)} " <>
        "(#{Type.declared_path(type, index)}) throwback names #{inspect(gate.throwback)}, " <>
        "which is not earlier in this type's own statuses: array (§13, §15.4, §15.8)"
    end
  end

  ## The one predicate (§15.10). Everything backward-moving — the load
  ## check above, the runtime pick below — reads legality off this.

  defp earlier_names(%Type{statuses: statuses}, index) do
    statuses |> Enum.take(index) |> Enum.map(&Status.name/1)
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
  Where a decline at `gate_name` lands by default for a ticket of type
  `type_name` (§15.10): the gate's own declared `throwback:` when it
  names one, otherwise the derived default — the citing sub-array's own
  non-critique agent step.

  Never the array position immediately before the gate. That reading
  fails the shape §15.10 argues from, `[milestone-signoff, retro,
  proposals-read]`: a gate sitting *after* its group's agent step would
  fall back to the entry before it and re-ask a human a question they
  already answered, instead of re-running the agent that produced the
  thing being declined.

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
        type.statuses
        |> Enum.slice(range)
        |> Enum.find_index(&Status.non_critique_agent_step?/1)
        |> case do
          nil ->
            nil

          offset when range.first + offset < index ->
            Status.name(Enum.at(type.statuses, range.first + offset))

          _not_earlier ->
            nil
        end
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
    for kind <- [:generation, :design, :architecture], not SystemStatus.can_block?(kind) do
      "platform defect: the fixed system-status skeleton has no path from #{kind} to blocked"
    end
  end

  defp pending_precedes_problems do
    for kind <- [:generation, :design, :architecture, :deploy],
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

      Enum.count(names, &(&1 == "pending")) > 1 ->
        ["type #{inspect(name)}'s statuses: declares pending more than once (§15.1)"]

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
        label == {:status, "critique"} and (i == 0 or not generation_shaped_label?(labels, i - 1))
      end)
      |> Enum.map(fn {_label, i} ->
        "type #{inspect(type_name)}'s #{Type.declared_path(type, i)} is critique, which must " <>
          "sit immediately after a generation-shaped entry (§13, §15.5)"
      end)
    end
    |> List.flatten()
  end

  defp generation_shaped_label?(labels, index) do
    case Enum.at(labels, index) do
      {:status, name} -> SystemStatus.generation_shaped?(name)
      _review_or_environment -> false
    end
  end

  defp entry_label(%Status{status: s}) when not is_nil(s), do: {:status, s}
  defp entry_label(%Status{review: r}) when not is_nil(r), do: {:review, r}
  defp entry_label(%Status{environment: e}) when not is_nil(e), do: {:environment, e}

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
      matches = Enum.filter(type.statuses, &(Status.name(&1) == target))

      cond do
        target == status.status ->
          "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names itself (§13, §15.7)"

        matches == [] ->
          "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, " <>
            "which does not resolve to any entry in this type's own statuses: array (§13, §15.7, §15.10)"

        length(matches) > 1 ->
          "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, " <>
            "which resolves to #{length(matches)} entries in this type's own statuses: array — " <>
            "not unique (§13, §15.10)"

        true ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
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
