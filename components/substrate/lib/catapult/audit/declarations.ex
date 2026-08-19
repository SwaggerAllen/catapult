defmodule Catapult.Audit.Declarations do
  @moduledoc """
  The checks that hold a registry against a tree, rather than a tree
  against a rule (systems/substrate.md's enforcement roster).

  A `Catapult.Audit.Check` sees a scope and nothing else, which is what
  keeps a registered check from reaching across mix projects. These need
  the composed inventory as well, so they are the audit task's own
  rather than entries in `policies/0` — and they live here rather than
  inside the task because a check nobody can call is a check nobody
  tests.

  All three are the same shape, and it is the third, fourth and fifth
  instance of it:

    * **declared↔applied** — a `processes/0` entry declaring a VM
      guardrail with no `Catapult.Guardrails.apply!/2` applying it. The
      composer cannot thread `spawn_opt` (see `Catapult.Guardrails`), so
      the declaration and the application are two facts and this is where
      they meet.
    * **declared↔constructed** — an `errors/0` kind nothing builds. The
      other direction is the generated constructor's (`Catapult.Error`);
      this is the half no constructor can see, and dead vocabulary in a
      catalog operators read is worth a line.
    * **declared↔read** — a `config/0` value nothing reads through
      `Catapult.Config.fetch!/2`, and a `fetch!/2` call no declaration
      explains (ORC-48). `config/0` was the last registry with no
      declared↔used fact; ORC-4 deferred this half on a check registry
      that shipped two tickets later.

  A dead declaration never honours `catapult:allow`, deliberately: the
  escape excuses a *line* the parser found, and what these report is the
  absence of one. A declaration nobody uses is deleted, not excused. The
  config check's read direction does name a line and still declines the
  tag, for a reason of its own (`config/2`, docs/non-goals.md).

  ## A declaration is only dead in the tree that declares it

  Every dead direction takes as its subjects only the declarations of
  components whose own source is one of the files `scope` expanded to. A
  component shipped from a package declares in a module whose `lib/` is
  the package's, not the consumer's, so a consumer's audit sweeping its
  own tree would find no use of any of them — and the message these
  checks carry is *delete it*, which breaks the boot of every project
  that adopts the component. A check whose advice is destructive on a
  tree its author never read is what `Catapult.Audit.License`'s inert
  state was designed against.

  The predicate is neither a directory name nor a dependency list: the
  module's compile-time source (`module_info(:compile)`) either is one
  of those files or it is not. The scope glob is already this family's
  only definition of *code this project audits*, and the task compiles
  before it sweeps, so the recorded path is this run's. A module whose
  source cannot be read at all counts as out of scope, because the
  direction this may not fail in is the destructive one.

  The package's own CI is where its declarations meet its own `lib/`,
  which is exactly where this check already runs — once per mix project,
  and never across the dependency closure (systems/substrate.md).
  """

  alias Catapult.Audit.Source

  @doc """
  Guardrail declarations with no application under `scope`.

  `entries` are `processes/0` inventory entries; `enforceable` is the
  opts `Catapult.Guardrails` actually applies, so a threshold that is
  only sampled never asks for a call that would do nothing.
  """
  @spec guardrails([map()], [atom()], String.t()) :: [String.t()]
  def guardrails(entries, enforceable, scope) do
    entries
    |> Enum.filter(fn entry ->
      Enum.any?(entry.opts, fn {opt, _value} -> opt in enforceable end)
    end)
    |> unmatched(& &1.name, &guarded/1, scope, fn entry ->
      "#{inspect(entry.component)} declares VM guardrails for process #{inspect(entry.name)} " <>
        "and no Catapult.Guardrails.apply!/2 call applies them (conventions §5, v5 §2.5)"
    end)
  end

  @doc "Error kinds declared and never constructed under `scope`."
  @spec error_kinds([map()], String.t()) :: [String.t()]
  def error_kinds(entries, scope) do
    unmatched(entries, & &1.kind, &constructed/1, scope, fn entry ->
      "#{inspect(entry.component)} declares error kind #{inspect(entry.kind)} and nothing " <>
        "constructs it (dead vocabulary in the catalog; conventions §8)"
    end)
  end

  @doc """
  Both directions of the config declared↔read check, from one sweep.

  `declarations` is `Catapult.Config.declarations/1`: every value the
  project composes, in scope or not. The dead direction narrows that to
  the in-scope subjects the moduledoc describes; the read direction
  keeps the whole list and loses nothing by it, because a call in *this*
  tree is joinable with complete information wherever its declaration
  lives.

  The join key is the accessor's own two arguments, so this check is
  exact where declared↔applied is approximate: `fetch!(slug, key)` names
  a declaration completely and the store is already keyed by the pair.
  That is a property of the signature rather than of the check, and it
  is what lets this one afford to be strict about literals.

  A call it cannot join — a computed slug or key — is reported at its
  call site rather than guessed at, and while it stands the declarations
  it could have been reading are not also reported dead: a computed key
  suppresses that slug, a computed slug suppresses the direction. The
  alternative is worse than it looks, because the report being suppressed
  is the one that says *delete a value the boot requires*. Suppression
  costs no coverage — the run is already red on the call site — and what
  it buys is one line per cause. A file that did not parse suppresses on
  the same argument and reports nothing of its own: the file-scoped
  checks sweeping the same scope already own that line
  (`Catapult.Audit.Source`).

  It does not police *who* reads. ORC-4's sentence says "a component
  reading a key it did not declare"; this narrows it to *a key nobody
  declared*, because deciding that a call site belongs to a component
  needs a path→component map the audit may never hold, and because
  `fetch!/2` takes a slug precisely so a reader can name a value it does
  not own (docs/non-goals.md).

  The runtime raise stays where it is: `fetch!/2` still raises on an
  undeclared key, because this scope is `lib/**/*.ex` and a release
  task, a test and an `iex` session are all outside it.
  """
  @spec config([map()], String.t()) :: [String.t()]
  def config(declarations, scope) do
    paths = paths(scope)
    {calls, parsed?} = sweep(paths)
    declared = MapSet.new(declarations, &{&1.slug, &1.key})

    call_problems(calls, declared) ++ dead(declarations, calls, parsed?, paths)
  end

  ## Declared ↔ used, for the two registries with one name to match

  # The sweep runs only when something is declared, so the common case —
  # an empty registry, which is most of the roster today — parses nothing
  # at all. Neither does a registry whose every declaration arrived from
  # a package: there is no subject left to report.
  defp unmatched([], _key, _finder, _scope, _message), do: []

  defp unmatched(entries, key, finder, scope, message) do
    paths = paths(scope)
    sources = sources(paths)

    case Enum.filter(entries, &in_scope?(&1.component, sources)) do
      [] ->
        []

      subjects ->
        found =
          for path <- paths,
              {:ok, source} <- [Source.read(path)],
              name <- Source.collect(source.ast, finder),
              into: MapSet.new(),
              do: name

        for entry <- subjects, not MapSet.member?(found, key.(entry)), do: message.(entry)
    end
  end

  defp guarded({{:., _dot, [module, :apply!]}, _meta, [_component, name]}) when is_atom(name) do
    if Source.alias?(module, :Guardrails), do: [name], else: []
  end

  defp guarded(_node), do: []

  # Both spellings of a construction: the generated `new/2`, and the
  # struct literal conventions §8 shows at a boundary.
  defp constructed({{:., _dot, [_module, :new]}, _meta, [kind | _rest]}) when is_atom(kind) do
    [kind]
  end

  defp constructed({:%, _meta, [_module, {:%{}, _map, fields}]}) when is_list(fields) do
    case Keyword.get(fields, :kind) do
      kind when is_atom(kind) and not is_nil(kind) -> [kind]
      _other -> []
    end
  end

  defp constructed(_node), do: []

  ## Which declarations this project may call dead

  defp paths(scope), do: scope |> Path.wildcard() |> Enum.sort()

  defp sources(paths), do: MapSet.new(paths, &Path.expand/1)

  # A module compiled from a file the scope did not expand to belongs to
  # somebody else's tree, and so do its declarations.
  defp in_scope?(component, sources) do
    case compiled_from(component) do
      nil -> false
      source -> MapSet.member?(sources, source)
    end
  end

  defp compiled_from(module) do
    if is_atom(module) and Code.ensure_loaded?(module) do
      case module.module_info(:compile)[:source] do
        source when is_list(source) -> Path.expand(List.to_string(source))
        source when is_binary(source) -> Path.expand(source)
        _other -> nil
      end
    end
  end

  ## The config sweep: one pass, both directions

  defp sweep(paths) do
    {calls, parsed?} =
      Enum.reduce(paths, {[], true}, fn path, {calls, parsed?} ->
        case Source.read(path) do
          {:ok, source} -> {[reads(source) | calls], parsed?}
          {:error, _problem} -> {calls, false}
        end
      end)

    {calls |> Enum.reverse() |> Enum.concat(), parsed?}
  end

  defp reads(source) do
    for {line, slug, key} <- Source.collect(source.ast, &read/1),
        do: {source.path, line, slug, key}
  end

  # A read is a qualified `fetch!/2` on a module whose last segment is
  # `Config` — the limit `Source.alias?/2` imposes on every check in the
  # family. Here it is the benign case, and uniquely so: hiding a read
  # behind a renamed alias hides no violation, it makes the declaration
  # that read serves report as dead, so the other direction surfaces it.
  defp read({{:., _dot, [module, :fetch!]}, _meta, [slug, key]} = node) do
    if Source.alias?(module, :Config), do: [{Source.line(node), slug, key}], else: []
  end

  # The piped spelling is the same call and gets the same answer. It is
  # here rather than left as a second hole because the moduledoc's claim
  # is that the renamed alias is *the* one, and an arity-shaped miss
  # would make a live declaration report dead — the failure this whole
  # design is arranged around.
  defp read({:|>, _pipe, [slug, {{:., _dot, [module, :fetch!]}, _meta, [key]} = node]}) do
    if Source.alias?(module, :Config), do: [{Source.line(node), slug, key}], else: []
  end

  defp read(_node), do: []

  defp call_problems(calls, declared) do
    for {path, line, slug, key} <- calls,
        problem <- call_problem(slug, key, declared),
        do: "#{path}:#{line}: #{problem}"
  end

  defp call_problem(slug, key, declared) when is_atom(slug) and is_atom(key) do
    if MapSet.member?(declared, {slug, key}) do
      []
    else
      [
        "config #{inspect(slug)}.#{key} is read and no component declares it " <>
          "(Catapult.Config.fetch!/2 raises when this line runs; conventions §4, v5 §2.2)"
      ]
    end
  end

  defp call_problem(slug, _key, _declared) when is_atom(slug) do
    [
      "Catapult.Config.fetch!/2 reads #{inspect(slug)} under a computed key, which no " <>
        "declaration can be joined to (spell the key; docs/non-goals.md)"
    ]
  end

  defp call_problem(_slug, _key, _declared) do
    [
      "Catapult.Config.fetch!/2 is called with a computed slug, which no declaration can be " <>
        "joined to (spell the slug; docs/non-goals.md)"
    ]
  end

  ## The dead direction, and what the sweep makes unknowable

  defp dead([], _calls, _parsed?, _paths), do: []

  defp dead(declarations, calls, parsed?, paths) do
    case suppressed(calls, parsed?) do
      :all -> []
      slugs -> unread(declarations, slugs, joined(calls), sources(paths))
    end
  end

  defp suppressed(_calls, false), do: :all

  defp suppressed(calls, true) do
    Enum.reduce_while(calls, MapSet.new(), fn
      {_path, _line, slug, key}, slugs when is_atom(slug) and is_atom(key) -> {:cont, slugs}
      {_path, _line, slug, _key}, slugs when is_atom(slug) -> {:cont, MapSet.put(slugs, slug)}
      _call, _slugs -> {:halt, :all}
    end)
  end

  defp joined(calls) do
    for {_path, _line, slug, key} <- calls,
        is_atom(slug),
        is_atom(key),
        into: MapSet.new(),
        do: {slug, key}
  end

  defp unread(declarations, slugs, joined, sources) do
    for declaration <- declarations,
        not MapSet.member?(slugs, declaration.slug),
        not MapSet.member?(joined, {declaration.slug, declaration.key}),
        in_scope?(declaration.component, sources) do
      "#{inspect(declaration.component)} declares config key #{inspect(declaration.key)} " <>
        "(#{declaration.name}) and nothing reads it with Catapult.Config.fetch!/2 " <>
        "(dead configuration every deploy must still set; conventions §4, v5 §2.2)"
    end
  end
end
