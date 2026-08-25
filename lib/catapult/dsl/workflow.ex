defmodule Catapult.Dsl.Workflow do
  @moduledoc """
  Loads and validates one `kind: workflow` bundle end to end
  (dsl-syntax.md §15): declared gates and environments (§15.4), and
  the unified work-item declaration `types/<name>.yaml` (§15.2) whose
  `statuses:` array positions everything — the skeleton's own fixed
  anchors, gate/environment citations, `flow:`/`blocks:`/`singleton:`
  queue metadata — by array index alone. There is no `after:` anywhere
  in this grammar (§15.3): position moved from a named-predecessor
  field on the gate/environment declaration itself to the citing
  type's own array, so the identical gate may run at different
  relative positions across two types without either being wrong.

  A workflow bundle carries no `extends:` (§11, §13; `Catapult.Dsl
  .Manifest`'s own moduledoc) — it is forked from the platform's
  default gates/environments/types instead of layered — so, unlike
  `Catapult.Dsl.Chain`, this loader reads one directory directly and
  never resolves an `Catapult.Dsl.Extends` chain.

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

  @container_anchors ~w(setup prep main retro cleanup terminal)
  @ticket_status_names ~w(pending generation critique checks merge deploy terminal)
  @ticket_required_order ~w(generation checks merge deploy)

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

  ## Gate throwback (§13, §15.4, §15.8): each target must resolve to a
  ## status or another cited gate *earlier in the citing type's own
  ## array* — position lives there now, never on the gate itself.

  defp gate_throwback_problems(types, gates) do
    for {type_name, type} <- types,
        {status, index} <- Enum.with_index(type.statuses),
        not is_nil(status.review),
        gate = Map.get(gates, status.review),
        not is_nil(gate),
        target <- gate.throwback do
      earlier = type.statuses |> Enum.take(index) |> Enum.map(&entry_name/1)

      if target in earlier do
        nil
      else
        "type #{inspect(type_name)}'s #{inspect(status.review)} (statuses[#{index}]) throwback " <>
          "names #{inspect(target)}, which is not earlier in this type's own statuses: array " <>
          "(§13, §15.4, §15.8)"
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  defp entry_name(%Status{status: s}) when not is_nil(s), do: s
  defp entry_name(%Status{review: r}) when not is_nil(r), do: r
  defp entry_name(%Status{environment: e}) when not is_nil(e), do: e

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
    if SystemStatus.can_block?(:generation) do
      []
    else
      ["platform defect: the fixed system-status skeleton has no path from generation to blocked"]
    end
  end

  defp pending_precedes_problems do
    for kind <- [:generation, :deploy], not SystemStatus.pending_precedes?(kind) do
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

  defp container_shape_problems(name, type) do
    names = anchor_names(type)

    if names == @container_anchors do
      []
    else
      [
        "type #{inspect(name)}'s statuses: must hold exactly #{inspect(@container_anchors)} " <>
          "in that order (§15.1, §13); got #{inspect(names)}"
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

  defp ticket_relative_order_problems(name, names) do
    present = Enum.filter(@ticket_required_order, &(&1 in names))

    if present != @ticket_required_order do
      missing = @ticket_required_order -- present

      [
        "type #{inspect(name)}'s statuses: is missing #{inspect(missing)} (§15.1 requires " <>
          "generation, checks, merge, deploy at least once each)"
      ]
    else
      indices = for req <- @ticket_required_order, do: Enum.find_index(names, &(&1 == req))

      if indices == Enum.sort(indices) do
        []
      else
        [
          "type #{inspect(name)}'s statuses: holds generation/checks/merge/deploy out of their " <>
            "required relative order (§15.1); got #{inspect(names)}"
        ]
      end
    end
  end

  ## Critique adjacency (§13, §15.5): must sit immediately after a
  ## generation entry in the same type's array — no skeleton check
  ## needed, since a container/skeleton-less type never has a
  ## generation anchor to sit after in the first place.

  defp critique_adjacency_problems(types) do
    for {type_name, type} <- types do
      labels = Enum.map(type.statuses, &entry_label/1)

      labels
      |> Enum.with_index()
      |> Enum.filter(fn {label, i} ->
        label == {:status, "critique"} and
          (i == 0 or Enum.at(labels, i - 1) != {:status, "generation"})
      end)
      |> Enum.map(fn {_label, i} ->
        "type #{inspect(type_name)}'s statuses[#{i}] is critique, which must sit immediately after a generation entry (§13, §15.5)"
      end)
    end
    |> List.flatten()
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

  ## `blocks:` scoping (§13, §15.6-§15.7): a queue may only block
  ## another queue-shaped anchor declared in its own type's array.

  defp blocks_problems(types) do
    for {type_name, type} <- types,
        status <- type.statuses,
        Status.queue_shaped?(status),
        target <- status.blocks do
      own_queue_names =
        type.statuses |> Enum.filter(&Status.queue_shaped?/1) |> Enum.map(& &1.status)

      cond do
        target == status.status ->
          "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names itself (§13, §15.7)"

        target not in own_queue_names ->
          "type #{inspect(type_name)}'s #{inspect(status.status)} blocks: names #{inspect(target)}, " <>
            "which is not a queue-shaped anchor declared in the same type (§13, §15.6-§15.7)"

        true ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  ## Declaration graph (§13, §15.6): nodes are every type with a
  ## queue-shaped anchor (container-skeleton or skeleton-less alike),
  ## edges are `flow:` references between them; must be acyclic.

  defp declaration_graph_nodes(types) do
    for {name, type} <- types, type.skeleton in [nil, "container"], do: name
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

      {:ok, %Type{skeleton: "ticket"}} ->
        [
          "entry #{inspect(entry_name)} names a ticket-skeleton type, which has no queue-shaped " <>
            "anchor to start a project from"
        ]

      {:ok, %Type{}} ->
        if entry_name in declaration_graph_roots(types) do
          []
        else
          [
            "entry #{inspect(entry_name)} is not a root in the declaration graph — some other " <>
              "type's flow: already targets it"
          ]
        end
    end
  end
end
