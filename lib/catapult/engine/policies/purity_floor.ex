defmodule Catapult.Engine.Policies.PurityFloor do
  @moduledoc """
  The ES store family's purity floor, at call-graph grade (v5 §2.4,
  `systems/engine.md`): no clock, randomness or generated-id call may
  be reachable — directly, or through a local helper — from a
  function defined in the scoped files. This is the reason the family
  names a "call-graph audit check" rather than the single-hop AST ban
  `Catapult.Audit.Checks.WallClock` already runs everywhere: a reducer
  branch that calls a local `helper/0` which itself calls
  `DateTime.utc_now/0` is exactly as non-replayable as calling it
  directly, and a single-hop check would report it clean.

  ## What "call graph" means here, precisely

  Every function defined in the scoped files is a node. An edge is a
  literal call this codebase's own AST can see without guessing:
  `Module.fun(...)` where `Module` is a compile-time alias or atom, or
  a bare `fun(...)` call resolved to the same module (Elixir has no
  other kind of local call). A call through a variable, an anonymous
  function, `apply/3`, or any other computed target is **not**
  followed — chasing it would be the dataflow inference this repo has
  refused everywhere else it was tempting (`systems/substrate.md`'s
  "What a check may infer" — the computed-config-key and secret-taint
  cases). It is also not
  needed: a reducer/aggregate/upcaster branch that hides its clock
  read behind a computed dispatch is a shape nobody here writes, and a
  check that guessed at it would be reporting a belief rather than a
  fact.

  ## The sinks

  `DateTime`/`NaiveDateTime`/`Date`/`Time`'s wall-clock readers,
  `System`'s clock and unique-integer functions, their `:os`/
  `:erlang` equivalents, `:rand` (any function — the whole module is
  an entropy source), `:crypto.strong_rand_bytes/1`,
  `Ecto.UUID.generate/0` and `.bingenerate/0`, and a bare
  `make_ref/0`. Reading already-recorded metadata off an event
  (`metadata.stream_version`, a command's own `committed_at`) is not a
  call to any of these and passes clean — the floor is about
  *producing* a non-replayable value, not about touching data that
  carries one.

  ## Escape

  `# catapult:allow purity_floor`, on the offending line or the
  comment line directly above it (`Catapult.Audit.Source`). No
  sanctioned use exists in this tree today.
  """

  @behaviour Catapult.Audit.Check

  alias Catapult.Audit.Source

  @tag "purity_floor"

  # `~w(...)a` produces bare atoms (`:DateTime`), not the
  # `:"Elixir.DateTime"` atoms an `__aliases__` node resolves to via
  # `Module.concat/1` — these have to be written as real module
  # references (or `Module.concat([:DateTime])` explicitly) or the
  # sink table simply never matches anything.
  @sink_functions %{
    DateTime => [:utc_now],
    NaiveDateTime => [:utc_now],
    Date => [:utc_today],
    Time => [:utc_now],
    System => [:system_time, :os_time, :monotonic_time, :unique_integer],
    Ecto.UUID => [:generate, :bingenerate]
  }
  @erlang_sinks %{
    os: [:system_time, :timestamp],
    erlang: [:system_time, :monotonic_time, :make_ref, :unique_integer],
    crypto: [:strong_rand_bytes]
  }

  @doc "The bare name a `catapult:allow` comment gives this check."
  @spec tag() :: String.t()
  def tag, do: @tag

  @impl Catapult.Audit.Check
  def run(scope) do
    sources =
      scope
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(&Source.read/1)

    {ok_sources, errors} = Enum.split_with(sources, &match?({:ok, _}, &1))
    read_problems = for {:error, problem} <- errors, do: problem
    parsed = for {:ok, source} <- ok_sources, do: source

    graph = build_graph(parsed)
    impure = impure_functions(graph)

    read_problems ++ Enum.flat_map(parsed, &report(&1, graph, impure))
  end

  ## Graph construction: {module, fun, arity} => {line, [callee]}

  defp build_graph(sources) do
    Enum.reduce(sources, %{}, fn source, acc ->
      Map.merge(acc, functions_in(source.ast))
    end)
  end

  # A multi-clause function (`Reducer.apply/2`'s whole shape — one
  # clause per event type) visits this branch once per clause; clauses
  # merge into one `{module, fun, arity}` entry so the reachability
  # walk sees the union of every clause's callees (a caller of this
  # function needs to know whether calling it *at all* can reach a
  # sink) — but each clause's own call sites stay listed too, with
  # their own lines, so `report/3` can point at the exact call inside
  # the exact clause that reaches one, matching where a
  # `catapult:allow` comment would naturally sit.
  defp functions_in(ast) do
    {_ast, {_module, functions}} =
      Macro.prewalk(ast, {nil, %{}}, fn
        {:defmodule, _meta, [{:__aliases__, _, parts} | _rest]} = node, {_current, functions} ->
          {node, {Module.concat(parts), functions}}

        {kind, meta, [{fun, _fmeta, fargs} | rest]} = node, {module, functions}
        when kind in [:def, :defp] and is_atom(fun) and module != nil ->
          arity = if is_list(fargs), do: length(fargs), else: 0
          line = Keyword.get(meta, :line, 0)
          key = {module, fun, arity}
          # Only `rest` (the body) is scanned for calls — the head
          # (`{fun, _fmeta, fargs}`) is structurally identical to a
          # call node, so walking it too would misread a function
          # defining itself as a call to itself.
          call_sites = collect_calls(rest)
          callee_set = call_sites |> Enum.map(&elem(&1, 0)) |> MapSet.new()

          functions =
            Map.update(
              functions,
              key,
              %{callees: callee_set, clauses: [{line, call_sites}]},
              fn %{callees: existing_callees, clauses: clauses} ->
                %{
                  callees: MapSet.union(existing_callees, callee_set),
                  clauses: [{line, call_sites} | clauses]
                }
              end
            )

          {node, {module, functions}}

        node, acc ->
          {node, acc}
      end)

    functions
  end

  # Every call this function's own body makes, one hop — resolved to
  # `{{module_or_nil, fun, arity}, call_line}`; `nil` means "same
  # module as the caller", resolved by the reachability walk below.
  defp collect_calls(node) do
    Source.collect(node, fn
      {{:., _dot, [{:__aliases__, _, parts}, fun]}, meta, args}
      when is_atom(fun) and is_list(args) ->
        [{{Module.concat(parts), fun, length(args)}, Keyword.get(meta, :line, 0)}]

      {{:., _dot, [erl_mod, fun]}, meta, args}
      when is_atom(erl_mod) and is_atom(fun) and is_list(args) ->
        [{{erl_mod, fun, length(args)}, Keyword.get(meta, :line, 0)}]

      {fun, meta, args} when is_atom(fun) and is_list(args) ->
        if not special_form?(fun) and Keyword.has_key?(meta, :line) do
          [{{nil, fun, length(args)}, Keyword.get(meta, :line, 0)}]
        else
          []
        end

      _node ->
        []
    end)
    |> Enum.uniq()
  end

  # A conservative denylist rather than an allowlist: the walk already
  # only fires on `{atom, meta_with_line, list}` shapes, so this only
  # needs to exclude Elixir's own control-flow keywords, which share
  # that shape but are never "a call" in the sense this check means.
  @special_forms ~w(def defp defmodule do end fn case cond if unless
                     for with quote try rescue catch after else
                     alias require import use __block__ __aliases__)a
  defp special_form?(fun), do: fun in @special_forms

  ## Reachability: which {module, fun, arity} nodes can reach a sink

  defp impure_functions(graph) do
    Map.new(graph, fn {key, _} -> {key, reaches_sink?(key, graph, MapSet.new())} end)
  end

  defp reaches_sink?(_key, _graph, visited) when map_size(visited) > 200, do: false

  defp reaches_sink?({module, fun, arity}, graph, visited) do
    key = {module, fun, arity}

    if MapSet.member?(visited, key) do
      false
    else
      visited = MapSet.put(visited, key)

      case Map.fetch(graph, key) do
        :error ->
          false

        {:ok, %{callees: callees}} ->
          Enum.any?(callees, &callee_reaches_sink?(&1, module, graph, visited))
      end
    end
  end

  defp callee_reaches_sink?({nil, fun, arity}, caller_module, graph, visited) do
    sink?(nil, fun) or reaches_sink?({caller_module, fun, arity}, graph, visited)
  end

  defp callee_reaches_sink?({callee_module, fun, arity}, _caller_module, graph, visited) do
    sink?(callee_module, fun) or reaches_sink?({callee_module, fun, arity}, graph, visited)
  end

  defp sink?(:rand, _fun), do: true
  defp sink?(nil, :make_ref), do: true

  defp sink?(mod, fun) when is_map_key(@erlang_sinks, mod), do: fun in @erlang_sinks[mod]

  defp sink?(mod, fun) when is_atom(mod) do
    fun in Map.get(@sink_functions, mod, [])
  end

  defp sink?(_mod, _fun), do: false

  ## Report

  defp report(source, graph, impure) do
    module_of_source =
      for {{module, _fun, _arity}, _entry} <- graph,
          function_defined_in?(module, source),
          uniq: true,
          do: module

    findings =
      for module <- module_of_source,
          {{^module, fun, arity}, true} <- impure,
          %{clauses: clauses} = Map.fetch!(graph, {module, fun, arity}),
          {_def_line, call_sites} <- clauses,
          {callee, call_line} <- call_sites,
          callee_reaches_sink?(callee, module, graph, MapSet.new()) do
        {call_line,
         "#{inspect(module)}.#{fun}/#{arity} reaches a clock, randomness or id-generation call " <>
           "(directly or through a local helper) — inject the value at the command edge instead " <>
           "(v5 §2.4's purity floor)"}
      end

    Source.scan(source.path, @tag, fn _source -> findings end)
  end

  defp function_defined_in?(module, source) do
    source.path
    |> Path.basename(".ex")
    |> Macro.camelize()
    |> then(&(Module.split(module) |> List.last() == &1))
  end
end
