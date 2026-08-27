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
    * **declared↔recorded** — a `config/0` value this codebase invented
      and requires, that the operator manifest does not name (ORC-136).
      The sixth instance, and the first whose other side is a document
      rather than a tree.

  ## Why the sixth exists at all, since the boot already catches it

  Nothing is broken about the boot report: `Catapult.Boot.load!/0` fails
  loudly and names the missing variable. What the sixth check moves is
  the *moment*. ORC-9 added `DELIVERY_GITHUB_TOKEN` with no default;
  `config/dev.exs` and `config/test.exs` each seed a value, so every gate
  in every environment that runs one passed, and the first environment
  reading the real environment was production. The declaration was a new
  obligation on whoever deploys, and the merge that created it said
  nothing to them.

  So the fact checked is a property of the declaration alone — no
  deployment knowledge, no comparison against a live instance, no taste:
  **a declaration with no `default:`, not marked `external: true`, and
  not opted out with `required: false` is a variable this codebase
  invented that nothing outside it will ever set.** Each clause earns
  its place:

    * `default:` **is requiredness.** `Catapult.Config` treats a value as
      required unless a default supplies one, so "no default" is the
      requiredness fact on its own. `secret:` is orthogonal — it governs
      redaction — and keying on it would miss a required URL or bucket
      name, which fails exactly the same way.
    * `external: true` **already marks the names imposed from outside**
      (`DATABASE_URL`). Those are required and nobody here sets them, so
      requiredness alone would fire on every one.
    * `required: false` **is the explicit opt-out**, and is legal with no
      default (`Catapult.Config`, `value_for/3`). A check that ignored it
      would demand a manifest line for a value the boot is content to
      leave `nil`.

  The manifest direction prunes itself the way the escape list does: a
  recorded name no declaration explains is reported too. A manifest that
  only ever grows is a manifest that stops being read, and the failure
  it is meant to prevent is somebody not reading it.

  A dead declaration never honours `catapult:allow`, deliberately: the
  escape excuses a *line* the parser found, and what these report is the
  absence of one. A declaration nobody uses is deleted, not excused. The
  config check's read direction does name a line and still declines the
  tag, for a reason of its own (`config/2`; systems/substrate.md,
  "What a check may infer").

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

  # The info string on the manifest's fenced block. A literal here and
  # in SETUP.md, deliberately: a check that accepted several spellings
  # would let a block drift out of the one the audit reads while still
  # looking to a reviewer like it was being read.
  @fence "catapult:required-env"

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
  not own (systems/substrate.md, "What a check may infer").

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

  @doc """
  Required variables this codebase invented that `manifest` does not record.

  `declarations` is `Catapult.Config.declarations/1`, narrowed here to
  the in-scope subjects the moduledoc describes — the manifest of the
  tree being audited cannot be asked to carry a packaged component's
  variables, and a report saying it should would be advice about a file
  its author never read.

  Both directions, for the reason the escape list has both: a
  declaration the manifest misses, and a manifest line no declaration
  explains. The second is not tidiness. The whole value of the file is
  that an operator can read it and believe it, and a stale line is a
  variable somebody sets for no reason and then keeps setting.

  ## The manifest is delimited, not prose

  `manifest` is a path; the recorded names are the lines of the first
  fenced block opened with `#{@fence}`, one name per line, `#` starting
  a comment. Fenced rather than a bare list because the alternative is
  parsing the surrounding document loosely, and a check that guesses at
  prose is a check whose author's guess is the specification — the
  antipattern this repo refuses wherever a check would have to guess.
  Fenced rather
  than an HTML comment because the block should be *visible*: it lands
  in a document somebody follows while standing up an instance, and a
  checklist they cannot see is a second place to forget.

  A missing file, or a file with no such block, is not silence. It is
  the finding, and it names every subject — but only when there is a
  subject, so a project that has invented no required variable needs no
  manifest and never hears about one. That matters more here than
  elsewhere: this module ships into every project the platform builds
  (`LICENSING.md`), most of which will never have a `SETUP.md`.
  """
  @spec operator_values([map()], String.t(), String.t()) :: [String.t()]
  def operator_values(declarations, manifest, scope) do
    # The predicate first, the scope glob only if it can matter: the
    # empty case is every generated project that has invented nothing,
    # and it should not pay for a wildcard to find that out.
    case Enum.filter(declarations, &invented_and_required?/1) do
      [] -> []
      candidates -> against_manifest(subjects(candidates, scope), manifest)
    end
  end

  defp subjects(candidates, scope) do
    sources = sources(paths(scope))

    Enum.filter(candidates, &in_scope?(&1.component, sources))
  end

  # The three clauses, in the moduledoc's order. `required: false` is the
  # one ORC-136's own predicate missed: it is legal with no default, and
  # demanding a manifest line for a value the boot leaves nil would make
  # the check wrong in the direction that costs an author an argument.
  defp invented_and_required?(%{opts: opts}) do
    not Keyword.has_key?(opts, :default) and
      Keyword.get(opts, :external, false) != true and
      Keyword.get(opts, :required, true) != false
  end

  defp against_manifest([], _manifest), do: []

  defp against_manifest(subjects, manifest) do
    case recorded(manifest) do
      :none -> [no_manifest(subjects, manifest)]
      recorded -> missing(subjects, recorded) ++ stale(subjects, recorded, manifest)
    end
  end

  defp no_manifest(subjects, manifest) do
    "#{manifest} records no required variables (expected a fenced ```#{@fence} block) " <>
      "and #{count(subjects)} declared with no default and no external: true: " <>
      "#{subject_names(subjects)} — every deploy must set them and nothing tells the " <>
      "operator so until the boot fails (ORC-136, v5 §2.2)"
  end

  defp missing(subjects, recorded) do
    for subject <- subjects, not MapSet.member?(recorded, subject.name) do
      "#{inspect(subject.component)} declares config key #{inspect(subject.key)} " <>
        "(#{subject.name}) with no default and no external: true, and no manifest entry " <>
        "records it — a deploy without it fails at boot, which is later than this merge " <>
        "(ORC-136, conventions §4)"
    end
  end

  defp stale(subjects, recorded, manifest) do
    declared = MapSet.new(subjects, & &1.name)

    for name <- Enum.sort(recorded), not MapSet.member?(declared, name) do
      "#{manifest} records #{name} as a required variable and no component in scope " <>
        "declares it that way — a line an operator would act on for nothing (ORC-136)"
    end
  end

  defp count([_one]), do: "1 value is"
  defp count(subjects), do: "#{length(subjects)} values are"

  defp subject_names(subjects),
    do: subjects |> Enum.map(& &1.name) |> Enum.sort() |> Enum.join(", ")

  # `:none` rather than an empty set for both "no file" and "no block":
  # they are the same finding, and distinguishing them would offer an
  # operator a difference they cannot act on differently.
  defp recorded(manifest) do
    case File.read(manifest) do
      {:ok, body} -> body |> String.split(["\r\n", "\n"]) |> block()
      {:error, _reason} -> :none
    end
  end

  defp block(lines) do
    case Enum.drop_while(lines, &(String.trim(&1) != "```" <> @fence)) do
      [] -> :none
      [_open | rest] -> rest |> Enum.take_while(&(String.trim(&1) != "```")) |> entries()
    end
  end

  defp entries(lines) do
    for line <- lines,
        entry = line |> String.split("#", parts: 2) |> hd() |> String.trim(),
        entry != "",
        into: MapSet.new(),
        do: entry
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
        "declaration can be joined to (spell the key)"
    ]
  end

  defp call_problem(_slug, _key, _declared) do
    [
      "Catapult.Config.fetch!/2 is called with a computed slug, which no declaration can be " <>
        "joined to (spell the slug)"
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
