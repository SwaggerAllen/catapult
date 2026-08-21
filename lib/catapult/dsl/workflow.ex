defmodule Catapult.Dsl.Workflow do
  @moduledoc """
  Loads and validates one `kind: workflow` bundle end to end
  (dsl-syntax.md §15): declared gates and environments, positioned by
  named predecessor (§15.3) rather than index, over the platform-fixed
  system-status skeleton (`Catapult.Dsl.SystemStatus`).

  Two of §13's checks need data this loader is never handed in Phase 3
  — a gate's role holders live in the identity component (Phase 7,
  v5 §7.16), and the mirror mapping lives with the outbound tracker
  add-on (Phase 4+, v5 §7.17) — so both are **opt-in**: passed via
  `role_holders`/`mirror_mapping` in `opts`, skipped (not failed) when
  absent. That is the same shape dsl-syntax.md §13 already gives the
  mirror-mapping check ("when the outbound tracker add-on is
  configured"); nothing in this codebase can source either today, so
  a bundle with no data supplied loads on the checks it can actually
  perform rather than failing on a resolver that does not exist yet.
  """

  alias Catapult.Dsl.Critique
  alias Catapult.Dsl.Environment
  alias Catapult.Dsl.Extends
  alias Catapult.Dsl.Gate
  alias Catapult.Dsl.Graph, as: DslGraph
  alias Catapult.Dsl.Manifest
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Yaml

  @enforce_keys [:name]
  defstruct [:name, :critique, gates: %{}, environments: %{}]

  @type t :: %__MODULE__{
          name: String.t(),
          gates: %{String.t() => Gate.t()},
          environments: %{String.t() => Environment.t()},
          critique: Critique.t() | nil
        }

  @doc "Loads and validates the workflow bundle named `name` under `bundles_root`."
  @spec load(String.t(), String.t(), keyword()) :: {:ok, t()} | {:error, [String.t()]}
  def load(bundles_root, name, opts \\ []) do
    manifest_path = Path.join([bundles_root, name, "bundle.yaml"])

    with {:ok, raw} <- Yaml.read(manifest_path),
         {:ok, manifest} <- Manifest.parse(manifest_path, raw),
         {:ok, manifest} <- require_kind(manifest, "workflow"),
         {:ok, layers} <- Extends.chain(bundles_root, Path.join(bundles_root, name), manifest) do
      build(name, layers, opts)
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

  defp build(name, layers, opts) do
    gate_files = Extends.resolve_files(layers, :gate_globs)
    env_files = Extends.resolve_files(layers, :environment_globs)

    {gates, gate_problems} = parse_all(gate_files, Gate)
    {environments, env_problems} = parse_all(env_files, Environment)
    {critique, critique_problems} = parse_critique(layers)

    gate_map = index(gates)
    env_map = index(environments)

    problems =
      gate_problems ++
        env_problems ++
        critique_problems ++
        duplicate_names(gates, "gate") ++
        duplicate_names(environments, "environment") ++
        gate_after_problems(gate_map) ++
        gate_ordering_problems(gate_map) ++
        gate_throwback_problems(gate_map) ++
        environment_after_problems(env_map) ++
        environment_promotion_problems(env_map) ++
        naming_discipline_problems(gate_map, env_map) ++
        role_holder_problems(gate_map, Keyword.get(opts, :role_holders)) ++
        mirror_mapping_problems(gate_map, Keyword.get(opts, :mirror_mapping)) ++
        generation_blocked_exit_problems() ++
        queue_precedes_problems()

    if problems == [] do
      {:ok, %__MODULE__{name: name, gates: gate_map, environments: env_map, critique: critique}}
    else
      {:error, Enum.uniq(problems)}
    end
  end

  # `critique.yaml` is a fixed, singular path, never a glob (§15.5): the
  # same specific-first, same-path-replace resolution
  # `Catapult.Generation.ContextAssembly` and `Catapult.Dsl.Grammar`
  # already use for other bundle-relative content, applied to a
  # declaration file instead of a prompt or a schema.
  defp parse_critique(layers) do
    case Extends.resolve_content_path(layers, "critique.yaml") do
      nil -> {nil, []}
      path -> parse_critique_file(path)
    end
  end

  defp parse_critique_file(path) do
    with {:ok, raw} <- Yaml.read(path),
         {:ok, critique} <- Critique.parse(path, raw) do
      {critique, []}
    else
      {:error, reason} when is_binary(reason) -> {nil, [reason]}
      {:error, problems} when is_list(problems) -> {nil, problems}
    end
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

  ## after: resolution (§15.2, §15.3)

  defp status_names, do: Enum.map(SystemStatus.kinds(), &to_string/1)

  defp gate_after_problems(gates) do
    for {name, gate} <- gates,
        gate.after not in status_names(),
        not Map.has_key?(gates, gate.after) do
      "gate #{inspect(name)}'s after #{inspect(gate.after)} is not a system status " <>
        "(#{inspect(status_names())}) or another gate in the loaded union"
    end
  end

  # §15.3: position is total — two reviews declaring the same `after:` is
  # a load error, as is a cycle in `after:` references.
  defp gate_ordering_problems(gates) do
    duplicate_after_problems(gates) ++ after_cycle_problems(gates)
  end

  defp duplicate_after_problems(gates) do
    gates
    |> Map.values()
    |> Enum.frequencies_by(& &1.after)
    |> Enum.filter(fn {_after, count} -> count > 1 end)
    |> Enum.map(fn {after_, _count} ->
      names = for {name, gate} <- gates, gate.after == after_, do: name

      "two or more gates declare after: #{inspect(after_)}, which must be a total order (§15.3): #{inspect(Enum.sort(names))}"
    end)
  end

  # `DslGraph.acyclic?/find_cycle` drop self-loops before building the
  # graph (that module's moduledoc: correct for the edge-instance graph,
  # where a same-tier dependency edge is a legitimate self-loop). A gate
  # naming itself as its own predecessor has no such legitimate meaning
  # — it is the degenerate one-node case of §15.3's "order must be
  # total" — so it is checked directly rather than through the shared
  # cycle check, which would silently drop it.
  defp after_cycle_problems(gates) do
    edges = for {name, gate} <- gates, do: {name, gate.after}

    self_problems =
      for {name, gate} <- gates, gate.after == name do
        "gates' after: references cycle: #{inspect([name, name])}"
      end

    graph_problems =
      if DslGraph.acyclic?(edges) do
        []
      else
        ["gates' after: references cycle: #{inspect(DslGraph.find_cycle(edges))}"]
      end

    self_problems ++ graph_problems
  end

  defp gate_throwback_problems(gates) do
    for {name, gate} <- gates, target <- gate.throwback do
      cond do
        target in status_names() ->
          nil

        not Map.has_key?(gates, target) ->
          "gate #{inspect(name)}'s throwback names #{inspect(target)}, which is not a system status or a declared gate"

        not ancestor?(gates, name, target) ->
          "gate #{inspect(name)}'s throwback names #{inspect(target)}, which is not earlier than it in the effective sequence (§15.3, §7.19)"

        true ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end

  # "Earlier" over the declared set: reachable by walking `after:`
  # predecessors from `from`, which is exactly the total-order prefix
  # §7.19 defines once gate_ordering_problems/1 has ruled out a cycle.
  defp ancestor?(gates, from, target) do
    edges = for {name, gate} <- gates, do: {name, gate.after}
    DslGraph.reachable?(edges, from, target) and from != target
  end

  ## environments (§15.4)

  defp environment_after_problems(environments) do
    for {name, env} <- environments, env.after not in status_names() do
      "environment #{inspect(name)}'s after #{inspect(env.after)} is not a system status (#{inspect(status_names())})"
    end
  end

  # Same reasoning as `after_cycle_problems/1`: a same-name
  # `promote_from:` is the one-node cycle case, and `DslGraph`'s shared
  # cycle check drops self-loops by design, so it is checked directly.
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

  ## §7.6's naming discipline over the declared set, now a real check
  ## rather than "cheap against a fixed list": no two declared names
  ## differ by exactly one *inserted or removed* hyphen-separated word
  ## (e.g. `product-review` vs `product-review-final`) — the shape a
  ## copy-pasted, half-renamed declaration actually takes.
  ##
  ## Deliberately narrower than "one word substituted": two same-length
  ## word lists differing in one position (`dev` vs `staging`, both one
  ## word) would flag *any* two unrelated single-word names, which is a
  ## false positive a load-time gate cannot afford — this check only
  ## fires on a genuine subsequence relationship between the two names.

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

  # dsl-syntax.md §13: "Blocked is a single system status; return routing
  # is a rule over the ticket's effective sequence, not declared data, so
  # there is nothing per-workflow to validate beyond this" — the check is
  # a fact about the fixed skeleton, exercised at load time so a defect
  # in that skeleton (not in any one bundle) is what it would catch.
  defp generation_blocked_exit_problems do
    if SystemStatus.can_block?(:generation) do
      []
    else
      ["platform defect: the fixed system-status skeleton has no path from generation to blocked"]
    end
  end

  # dsl-syntax.md §13/§15.1: "a queue status precedes every generation
  # and every deployment" — same shape as generation_blocked_exit_problems/0
  # above: a fact about the fixed skeleton (Catapult.Dsl.SystemStatus),
  # exercised at load time so a defect in that skeleton, not in any one
  # bundle, is what it would catch.
  defp queue_precedes_problems do
    for kind <- [:generation, :deploy], not SystemStatus.queue_precedes?(kind) do
      "platform defect: the fixed system-status skeleton has no queue precedent for #{kind}"
    end
  end
end
