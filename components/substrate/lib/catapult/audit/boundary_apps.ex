defmodule Catapult.Audit.BoundaryApps do
  @moduledoc """
  The boundary-apps completeness check (ORC-50, `systems/substrate.md`):
  no application a `:prod` build can reach, and Boundary can restrain,
  is missing from the list that arms external-dependency checking.

  Boundary's `check: [apps: [...]]` buys compile-grade enforcement for
  the applications it names, and the naming is where it leaks. An
  application absent from the list is not partially checked, it is
  **silently exempt**: a clean `mix compile` over a dependency nobody
  constrained looks exactly like a clean `mix compile` over one that is
  constrained. The cost was priced as "a line in the same diff that
  added it", which assumes the omission gets noticed — and nothing
  noticed it. This is the same fail-open shape the platform has already
  refused twice on its own merits (a supply gate reporting clean from a
  clone it never made; a licensing check declining in silence), so it
  gets the same treatment: a check, and a census line on every green run
  saying what the tell would have said.

  ## The subject is what a `:prod` build can reach

  Computed, not listed. Seed from the project's own `deps` that survive
  into `:prod` — the same `only:` filter `Catapult.Audit.License`
  applies — then walk each application's compiled `.app` file
  (`applications` and `included_applications`), keeping only what
  `Mix.Project.deps_apps/0` also contains. That last filter is how OTP's
  own applications fall out without anybody writing a list of their
  names.

  The walk is env-independent by construction, and that is the reason
  for the mechanism rather than a bonus of it: a gate whose subject
  changes with `MIX_ENV` reports different coverage on different runs
  and cannot be reasoned about from its output.

  It does **not** share `Catapult.Audit.License`'s closure, and the
  divergence is the point. That walk answers *what a consumer would
  fetch*, out of publishers' `hex_metadata.config`, and it deliberately
  stops at a path dep because a path dep is another mix project audited
  in its own right. This one answers *what this build can reach*, out of
  compiled `.app` files, and it must descend into a path dep — a path
  dep's own dependencies are reachable from `lib/` and nothing else
  would name them. Sharing the walker would have imported that
  exclusion as a hole one level in, in the permissive direction.

  ## Three exclusions, none of them a waiver

  There is no ignore list, no `catapult:allow` reaching this check and
  no per-application waiver, for the reason the licensing check states:
  nobody imposes a dependency on us, so the fix for an unchecked
  application is naming it, and a waiver could only ever be spent
  restoring the fail-open the check exists to close. What is excluded is
  excluded by **derivation**, so there is nothing to forget and nothing
  to spend:

    * **`:boundary` itself.** `Boundary.Checker.check_external_dep?/3`
      opens by excluding it, so a list entry naming it is inert by
      construction.
    * **Applications contributing no `Elixir.*` modules** — cowboy,
      cowlib, ranch and telemetry, in this tree. `Boundary.Mix
      .app_modules/1` filters to `Elixir.*` and the checker resolves a
      callee's application through that map, so a call into one of them
      resolves to no application at all and no list entry can restrain
      it. Demanding those names would add lines that read as coverage
      and deliver none, which is this module's own complaint pointed
      backwards.
    * **Path deps**, read off `:path` in the dep options. Not a
      preference: naming a path dep in the apps list reproduces exactly
      the defect that made this project decline `type: :strict` —
      Boundary's cached view drops a path dep's boundaries on an
      incremental compile, and `check_external_dep?/3` treats "named in
      `check.apps`" and "`type: :strict`" as one condition, so
      everything downstream of it is identical.

  ## Both modes, and coverage rather than equality

  `Boundary.Definition` expands a bare atom to `{app, :runtime}` **and**
  `{app, :compile}`, so a list may legally carry one mode alone — and a
  `{app, :runtime}` entry leaves compile-time calls unchecked, which is
  the same fail-open one level smaller. Coverage means both modes; a
  half-covered application is reported.

  A name in the list the closure does not contain is not a problem. A
  test-only dependency named deliberately is the ordinary case, and a
  list is free to say more than the floor requires. The residue that
  leaves is that a typo'd or stale application name is inert rather than
  reported — named here rather than absorbed, and bounded by the fact
  that no name is load-bearing in the permissive direction.

  ## Armed by the declaration it audits, inert otherwise, and it says which

  Three states, each with its own census line, because the inert ones
  are the only ones that could be mistaken for a pass:

    * a project stating `check: [apps: [...]]` in its project-level
      `boundary` default has the list this check is about — **armed**;
    * a project stating `type: :strict` needs no list — **inert**;
    * a project stating neither may still declare per-boundary rules
      this check cannot see, because `use Boundary` options are module
      attributes rather than project config — **inert**.

  The armed line carries the exclusions by name rather than only a
  count, because the excluded applications *are* the residual gap and a
  number is not a tell.

  ## A built-in, and no dependency on Boundary

  A built-in of `mix catapult.audit` rather than a `policies/0` entry,
  on `Catapult.Audit.License`'s recorded criterion rather than by
  analogy with it: `Catapult.Audit.Check.run/1` takes a
  working-directory-relative glob, and a dependency graph is not a path
  scope. It reads a keyword list out of `Mix.Project.config()` and never
  calls Boundary, which is what keeps it shippable in a substrate that
  refuses dependencies on other people's behalf.

  The limit worth knowing before the first sub-boundary carves out:
  `Boundary.Definition.normalize!/3` merges a module's own `check:` over
  the project default with `Map.merge`, so a boundary declaring any
  `check:` key **replaces** the apps list rather than extending it. That
  has no subject in this tree yet, so no check is built for it.
  """

  @typedoc "An OTP application name."
  @type app :: atom()

  @typedoc """
  The dependency universe, keyed by application: what each one reaches,
  and whether Boundary could restrain a call into it. The key set is the
  filter — an application absent from it is outside the project's deps
  and is not walked into.
  """
  @type tree :: %{optional(app()) => entry()}

  @typedoc "One application's two facts. `:loaded?` defaults to true."
  @type entry :: %{
          required(:applications) => [app()],
          required(:elixir_modules?) => boolean(),
          optional(:loaded?) => boolean()
        }

  @typedoc "The problems to report, and the one line a green run prints."
  @type verdict :: %{problems: [String.t()], census: String.t()}

  # Boundary's own two modes. A bare atom in the list means both.
  @modes [:runtime, :compile]

  # `Boundary.Checker.check_external_dep?/3` excludes it before it looks
  # at anything else, so it can never be restrained and is never owed.
  @unrestrainable_by_construction :boundary

  # What `Boundary.Definition` takes from a project-level default. Every
  # other key is dropped in silence, which is the fail-open this module
  # is about, one level up.
  @default_keys [:type, :check]

  @doc """
  The whole check over one mix project.

  `project` is `Mix.Project.config()` — `:boundary` and `:deps` are the
  keys read, both of them the project's own declarations rather than
  facts about a layout. `tree` is the dependency universe; it defaults
  to the compiled `.app` files of `Mix.Project.deps_apps/0`, and is an
  argument so the check can be tested against a graph rather than
  against whatever happens to be on the code path.
  """
  @spec audit(keyword(), tree() | nil) :: verdict()
  def audit(project, tree \\ nil) do
    case declaration(project) do
      {:armed, covered, shape} -> armed(project, covered, shape, tree || tree())
      {:inert, census, problems} -> %{problems: problems, census: census}
      {:malformed, problems} -> %{problems: problems, census: malformed_census()}
    end
  end

  ## The project's own statement about this check

  # Which of the three states the project is in, and the shape problems
  # found on the way. A malformed declaration is reported rather than
  # read as declining, for the reason the licensing check states: the
  # inert branch is the one a typo would otherwise take in silence, and
  # a key Boundary drops is reported even where it changes no verdict.
  defp declaration(project) do
    with {:ok, boundary} <- keyword(project, :boundary, "boundary:"),
         {:ok, default} <- keyword(boundary, :default, "boundary: default:") do
      unknown = unknown_default_keys(default)

      cond do
        Keyword.get(default, :type) == :strict -> {:inert, strict_census(), unknown}
        not Keyword.has_key?(default, :check) -> {:inert, no_default_census(), unknown}
        true -> check_declaration(default, unknown)
      end
    else
      :absent -> {:inert, no_default_census(), []}
      {:malformed, problems} -> {:malformed, problems}
    end
  end

  defp check_declaration(default, unknown) do
    case keyword(default, :check, "boundary: default: check:") do
      {:ok, check} -> apps_declaration(check, unknown)
      :absent -> {:inert, no_apps_census(), unknown}
      {:malformed, problems} -> {:malformed, unknown ++ problems}
    end
  end

  defp apps_declaration(check, unknown) do
    case Keyword.fetch(check, :apps) do
      {:ok, apps} when is_list(apps) -> covered(apps, unknown)
      {:ok, other} -> {:malformed, unknown ++ [apps_shape(other)]}
      :error -> {:inert, no_apps_census(), unknown}
    end
  end

  # Boundary expands a bare atom to both modes; a `{app, mode}` entry
  # covers one. An entry that is neither is reported rather than
  # ignored: Boundary carries a `{app, :runtim}` typo through untouched,
  # where it matches no reference and restrains nothing.
  defp covered(apps, unknown) do
    {covered, malformed} =
      Enum.reduce(apps, {%{}, []}, fn
        app, {covered, bad} when is_atom(app) ->
          {Map.put(covered, app, MapSet.new(@modes)), bad}

        {app, mode}, {covered, bad} when is_atom(app) and mode in @modes ->
          {Map.update(covered, app, MapSet.new([mode]), &MapSet.put(&1, mode)), bad}

        entry, {covered, bad} ->
          {covered, [entry_shape(entry) | bad]}
      end)

    {:armed, covered, unknown ++ Enum.reverse(malformed)}
  end

  defp keyword(source, key, what) do
    case Keyword.get(source, key) do
      nil -> :absent
      value -> if Keyword.keyword?(value), do: {:ok, value}, else: shape(value, what)
    end
  end

  defp shape(value, what) do
    {:malformed, [problem("mix.exs #{what} is #{inspect(value)}, expected a keyword list")]}
  end

  # Boundary takes `type` and `check` out of a project-level default and
  # drops the rest without a word, so a key it does not know is a
  # declaration the author believes in and the compiler never sees.
  defp unknown_default_keys(default) do
    for {key, _value} <- default, key not in @default_keys do
      problem(
        "mix.exs boundary: default: carries unknown key #{inspect(key)} " <>
          "(Boundary reads only #{inspect(@default_keys)} there and drops the rest silently)"
      )
    end
  end

  defp apps_shape(other) do
    problem(
      "mix.exs boundary: default: check: apps: is #{inspect(other)}, expected a list of " <>
        "application names"
    )
  end

  defp entry_shape(entry) do
    problem(
      "mix.exs boundary: default: check: apps: carries #{inspect(entry)}, expected an " <>
        "application name or {app, :runtime | :compile} — Boundary passes an unrecognised " <>
        "entry through, where it restrains nothing"
    )
  end

  ## The closure, and the verdict on it

  defp armed(project, covered, shape, tree) do
    closure = closure(project, tree)
    paths = path_deps(project)

    unloaded = for app <- closure, not loaded?(tree, app), do: app
    boundary_itself = @unrestrainable_by_construction in closure

    {unrestrainable, restrainable} =
      closure
      |> Enum.reject(&(&1 == @unrestrainable_by_construction or &1 in paths))
      |> Enum.split_with(&(not elixir_modules?(tree, &1)))

    path_deps = Enum.filter(closure, &(&1 in paths))

    problems =
      shape ++
        Enum.map(unloaded, &unloaded_problem/1) ++
        Enum.flat_map(restrainable, &coverage_problems(&1, Map.get(covered, &1, MapSet.new())))

    %{
      problems: problems,
      census:
        census(
          named: Enum.count(restrainable, &fully_covered?(covered, &1)),
          restrainable: length(restrainable),
          reachable: length(closure),
          unrestrainable: unrestrainable,
          path_deps: path_deps,
          boundary_itself: boundary_itself
        )
    }
  end

  defp fully_covered?(covered, app) do
    covered |> Map.get(app, MapSet.new()) |> missing_modes() == []
  end

  defp coverage_problems(app, modes) do
    case {missing_modes(modes), MapSet.size(modes)} do
      {[], _size} -> []
      {_missing, 0} -> [unnamed_problem(app)]
      {missing, _size} -> [half_named_problem(app, modes, missing)]
    end
  end

  defp unnamed_problem(app) do
    problem(
      "#{app} is reachable from a :prod build and Boundary can restrain it, and the apps " <>
        "list does not name it — add it to mix.exs boundary: default: check: apps: (a bare " <>
        "atom covers both modes). An application the list omits is not partially checked, " <>
        "it is exempt"
    )
  end

  defp half_named_problem(app, modes, missing) do
    problem(
      "#{app} is named for #{inspect(MapSet.to_list(modes))} only, leaving " <>
        "#{inspect(missing)} calls unchecked — name it as a bare atom, which covers both modes"
    )
  end

  defp missing_modes(modes), do: Enum.reject(@modes, &MapSet.member?(modes, &1))

  # What a `:prod` build can reach: the project's own deps that survive
  # into `:prod`, then their compiled `.app` files' `applications` and
  # `included_applications`, kept to what the project actually depends
  # on. A path dep is seeded and descended into — its dependencies reach
  # `lib/` and nothing else in the project names them.
  defp closure(project, tree) do
    project
    |> seed()
    |> Enum.reduce(MapSet.new(), &visit(&1, tree, &2))
    |> Enum.sort()
  end

  defp visit(app, tree, seen) do
    if MapSet.member?(seen, app) or not Map.has_key?(tree, app) do
      seen
    else
      tree
      |> children(app)
      |> Enum.reduce(MapSet.put(seen, app), &visit(&1, tree, &2))
    end
  end

  defp children(tree, app), do: Map.fetch!(tree, app).applications

  defp elixir_modules?(tree, app), do: Map.fetch!(tree, app).elixir_modules?

  defp loaded?(tree, app), do: Map.get(Map.fetch!(tree, app), :loaded?, true)

  defp seed(project) do
    for dep <- Keyword.get(project, :deps, []),
        {app, opts} <- [dep_opts(dep)],
        prod?(opts),
        do: app
  end

  defp path_deps(project) do
    for dep <- Keyword.get(project, :deps, []),
        {app, opts} <- [dep_opts(dep)],
        Keyword.has_key?(opts, :path),
        do: app
  end

  defp dep_opts({app, opts}) when is_atom(app) and is_list(opts), do: {app, opts}
  defp dep_opts({app, _requirement}) when is_atom(app), do: {app, []}
  defp dep_opts({app, _requirement, opts}) when is_atom(app) and is_list(opts), do: {app, opts}
  defp dep_opts(app) when is_atom(app), do: {app, []}
  defp dep_opts(_other), do: nil

  defp prod?(opts) do
    case Keyword.get(opts, :only) do
      nil -> true
      only -> :prod in List.wrap(only)
    end
  end

  ## The dependency universe, read off compiled .app files

  defp tree do
    Map.new(Mix.Project.deps_apps(), fn app ->
      loaded? = load(app)

      {app,
       %{
         applications: spec(app, :applications) ++ spec(app, :included_applications),
         elixir_modules?: Enum.any?(spec(app, :modules), &elixir_module?/1),
         loaded?: loaded?
       }}
    end)
  end

  defp load(app) do
    case Application.load(app) do
      :ok -> true
      {:error, {:already_loaded, ^app}} -> true
      {:error, _reason} -> false
    end
  end

  defp spec(app, key), do: Application.spec(app, key) || []

  defp elixir_module?(module), do: String.starts_with?(Atom.to_string(module), "Elixir.")

  # Reachable and unreadable is the one state that would otherwise be
  # exempt without saying so: no `.app` file means no answer about what
  # it reaches or whether it carries Elixir modules, and defaulting
  # either way is a guess in the permissive direction.
  defp unloaded_problem(app) do
    problem(
      "#{app} is reachable from a :prod build and its application spec cannot be read, so " <>
        "neither what it reaches nor whether Boundary can restrain it is known (compile the " <>
        "project before auditing it)"
    )
  end

  ## The census

  defp strict_census do
    "inert — this project declares boundary: [default: [type: :strict]], which checks every " <>
      "external application and needs no apps list"
  end

  defp no_default_census do
    "inert — this project declares no boundary: [default: [check: [apps: [...]]]] in mix.exs, " <>
      "so there is no list to check (a per-boundary check: is a module attribute this cannot see)"
  end

  defp no_apps_census do
    "inert — this project's boundary: default: check: states no apps:, so external " <>
      "applications are unchecked and there is no list to complete"
  end

  defp malformed_census do
    "unread — this project's boundary declaration is malformed, so nothing was checked"
  end

  defp census(facts) do
    counts =
      "#{facts[:named]} of #{facts[:restrainable]} restrainable named, out of " <>
        "#{facts[:reachable]} reachable"

    Enum.join([counts | exclusions(facts)], "; ")
  end

  # The excluded applications *are* the residual gap, so they are named
  # rather than counted: a number tells a reader that something was left
  # out and not what, which is the tell this check exists to supply.
  defp exclusions(facts) do
    listed(facts[:unrestrainable], "unrestrainable") ++
      listed(facts[:path_deps], "path dep", "path deps") ++
      if(facts[:boundary_itself], do: ["boundary itself"], else: [])
  end

  defp listed(apps, singular, plural \\ nil)

  defp listed([], _singular, _plural), do: []

  defp listed(apps, singular, plural) do
    label = if length(apps) == 1, do: singular, else: plural || singular
    ["#{length(apps)} #{label} (#{Enum.map_join(Enum.sort(apps), ", ", &to_string/1)})"]
  end

  defp problem(message), do: "boundary apps: " <> message
end
