defmodule Catapult.Audit.License do
  @moduledoc """
  The license-inventory check (ORC-16, `LICENSING.md`): no dependency in
  a checked tree declares terms nobody accepted.

  A built-in of `mix catapult.audit` rather than a `Catapult.Audit.Check`
  — that callback takes a working-directory-relative glob, and a
  dependency tree is not a path scope, so forcing it through would mean
  passing a scope value meaning "ignore this argument". `policies/0` is
  how a *component* ships a check into projects that adopt it; this one
  is the task's own, present in every project and armed or silent by
  declaration.

  ## Two declarations arm it, and neither is a path

  Dependencies are a *mix project's* fact — one lockfile, one `deps/`,
  one working directory. Distribution class is a *component's* fact.
  Neither substitutes for the other, so both are read:

    * `package: [licenses: [...]]` in `mix.exs` — what this **project**
      conveys. A project with a package block is fetched by somebody,
      and being fetched is what conveyance is. It is also the one
      declaration nothing that ships can forget: `mix hex.build` refuses
      a package with no `licenses`.
    * `licensing/0` on a **component** — `distribution:` and `license:`
      (`Catapult.Component.Licensing`).

  What neither of them is, is a path. A task that walked `components/*`
  would know where one repository keeps its components while shipping
  into customer trees where that glob means nothing (docs/non-goals.md).

  ## Arming and standard are two facts

  The declarations decide *whether* a tree is checked; the project's own
  `allow:` list decides *against what*:

      licensing: [
        allow: ~w(Apache-2.0 MIT BSD-2-Clause BSD-3-Clause ISC),
        overrides: [cowboy_telemetry: "Apache-2.0"]
      ]

  The list is not compiled in here. This module ships into every
  generated project, so a constant would be Catapult's legal position
  imposed on codebases nobody here has read — and a project that needs
  `MPL-2.0` is stating a policy, not evading a gate. A project that
  states no list is **inert**, never held to Catapult's five by default:
  a default would make every project's audit print a policy verdict
  nobody asserted, which is the check-that-checked-nothing this whole
  ticket exists to remove from the ladder. The census line says so on
  stdout of every green run, because the inert state is the only one
  that could be mistaken for a pass.

  The criterion behind the default value that `bundles/platform-elixir`
  writes into a generated project stays ours and is worth restating: not
  "permissive" but *imposes no terms on the linking application*, which
  is what `LICENSING.md` actually requires.

  ## Which trees are checked, and for which reason

  | The subject's own terms | How it reaches people | Dependencies |
  | --- | --- | --- |
  | on the project's list | conveyed | **checked** — a recipient would inherit terms nobody offered them |
  | `LicenseRef-*` | conveyed | **checked** — we would be conveying a work under terms we have not met |
  | on the project's list | `:service` | unchecked — we offer source on those terms |
  | `LicenseRef-*` | `:service` | **checked** — AGPL §13 would oblige an offer of source to our own users |
  | any | `:internal` | unchecked — nothing is conveyed and nobody is served |

  A project's policy is the **strictest** among every subject it
  composes, because the dependency tree is shared: nothing offline can
  attribute `plug` to one component rather than another, and any
  attribution that tried would be a guess running in the permissive
  direction. The *reason* is not shared, and the report prints it — a
  proprietary `:service` component failing on a GPL dependency must not
  read as a shipped-layer failure, because nobody receives that
  component.

  An identifier is `LicenseRef-*` (SPDX's own spelling of "no listed
  license applies") or it is on the project's list, and there is no
  third bucket: **an identifier in neither is a reported problem**,
  `:internal` included. There is deliberately no classification of an
  identifier as copyleft, because the residue of a project-stated list
  is not copyleft — it is whatever that project did not write down, and
  reading it as copyleft would leave the tree unchecked, an inference in
  the one direction this check may not fail in.

  ## Scope is what a consumer would fetch

  The transitive closure over non-optional `requirements` in each
  dependency's `hex_metadata.config`, seeded by the project's own deps
  that survive into `:prod`. Dev/test-only deps reach no generated
  project, and excluding them is what makes "no exceptions" affordable.

  `mix.lock` is not the source: it carries names and checksums and no
  license at all, while the metadata file carries the license, the
  version and the requirement graph, and sits beside the code whose
  terms are in question. Offline throughout — `:file.consult/1` over
  files `deps.get --check-locked` has already placed, so conventions
  §9's no-network rule reaches the audit without an exception.

  Two format facts, both measured, because the naive read of either is a
  wrong answer that looks right: `requirements` has two encodings — a
  flat proplist carrying `name` from mix-built packages, and a
  `{name, proplist}` tuple from rebar-built ones such as cowboy — and an
  entry may be `optional`, which makes it the consumer's dependency
  rather than ours, as `jason` declares `decimal`.

  A **path dep** is not in the closure and is not a skip: it is another
  mix project in the same tree, with its own `package:`, its own
  subjects and its own `mix catapult.audit` run (`mix
  catapult.audit.all` is what runs them all). Asking it for hex metadata
  it will never have would report a problem that is not one. Everything
  else in scope owes metadata or an override.

  ## An override supplies a fact; nothing supplies a permission

  A dependency whose license the metadata cannot answer is resolved by
  `overrides:` naming what a human read out of that package's own
  LICENSE — and it is then checked like any other, so an override
  recording `GPL-3.0-only` fails the audit exactly as the metadata would
  have. There is no ignore list, no `catapult:allow` reaching this
  check, and no per-dependency waiver: `allow:` says *these terms are
  acceptable in this tree* and every dependency is measured against it,
  where a waiver would say *this dependency is measured against
  nothing*. The fix for a copyleft dependency is not taking it.

  Licenses match as exact SPDX identifiers, with no normalization table
  and no reading of LICENSE text: a table's failures run silent and in
  the permissive direction, and the next near-miss after `Apache 2.0` is
  a string like `GPL-2.0-with-classpath-exception`, whose distance from
  `GPL-2.0-only` is the entire question. A dependency declaring several
  identifiers is dual-licensed and passes if *any* of them is on the
  list, which is what dual licensing means rather than an inference
  about it — the recipient chooses.

  ## What it honestly claims

  That no dependency in a checked tree *declares* terms nobody accepted.
  Hex metadata is the publisher's own assertion, and the counsel pass
  `LICENSING.md` schedules is what verification means. What this buys is
  noticing, at merge time, cheaply, forever.
  """

  alias Catapult.Component.Licensing

  @license_ref "LicenseRef-"
  @known_keys [:allow, :overrides]

  @typedoc "The problems to report, and the one line a green run prints."
  @type verdict :: %{problems: [String.t()], census: String.t()}

  @doc """
  The whole check over one mix project.

  `project` is `Mix.Project.config()` — `:deps`, `:deps_path`,
  `:package` and `:licensing` are the keys read, all of them the
  project's own answers rather than facts about a layout. `components`
  is the composed component list.
  """
  @spec audit(keyword(), [module()]) :: verdict()
  def audit(project, components) do
    shape = shape_problems(project)

    case allow_list(project) do
      nil -> %{problems: shape, census: inert_census()}
      allow -> stated(project, components, allow, overrides(project), shape)
    end
  end

  ## The project's own statement about this check

  # Reported whether or not the check is armed, and this is the seam a
  # reader should worry at: deleting `allow:` disarms the gate, in a
  # diff, in the file `package:` lives in, with every run afterwards
  # saying on stdout that nothing was checked. A *typo* in it must not
  # read as the same declining, which is what these lines buy.
  defp shape_problems(project) do
    case Keyword.get(project, :licensing) do
      nil -> []
      stated when is_list(stated) -> key_problems(stated)
      other -> [problem("mix.exs licensing: is #{inspect(other)}, expected a keyword list")]
    end
  end

  defp key_problems(stated) do
    if Keyword.keyword?(stated) do
      unknown_keys(stated) ++ allow_problems(stated) ++ override_problems(stated)
    else
      [problem("mix.exs licensing: is #{inspect(stated)}, expected a keyword list")]
    end
  end

  defp unknown_keys(stated) do
    for {key, _value} <- stated, key not in @known_keys do
      problem(
        "mix.exs licensing: carries unknown key #{inspect(key)} " <>
          "(known: #{inspect(@known_keys)})"
      )
    end
  end

  defp allow_problems(stated) do
    case Keyword.fetch(stated, :allow) do
      {:ok, value} -> unless_identifiers(value)
      :error -> []
    end
  end

  defp unless_identifiers(value) do
    if is_list(value) and Enum.all?(value, &is_binary/1) do
      []
    else
      [
        problem(
          "mix.exs licensing: allow: is #{inspect(value)}, " <>
            "expected a list of SPDX identifier strings"
        )
      ]
    end
  end

  defp override_problems(stated) do
    case Keyword.fetch(stated, :overrides) do
      {:ok, value} -> unless_override_list(value)
      :error -> []
    end
  end

  defp unless_override_list(value) do
    if Keyword.keyword?(value) and Enum.all?(value, fn {_app, id} -> is_binary(id) end) do
      []
    else
      [
        problem(
          "mix.exs licensing: overrides: is #{inspect(value)}, " <>
            "expected [app: \"SPDX-Id\"]"
        )
      ]
    end
  end

  defp allow_list(project) do
    with stated when is_list(stated) <- Keyword.get(project, :licensing, []),
         true <- Keyword.keyword?(stated),
         {:ok, allow} when is_list(allow) <- Keyword.fetch(stated, :allow),
         true <- Enum.all?(allow, &is_binary/1) do
      allow
    else
      _ -> nil
    end
  end

  defp overrides(project) do
    with stated when is_list(stated) <- Keyword.get(project, :licensing, []),
         true <- Keyword.keyword?(stated),
         {:ok, overrides} <- Keyword.fetch(stated, :overrides),
         true <- Keyword.keyword?(overrides) do
      Map.new(overrides, fn {app, id} -> {Atom.to_string(app), id} end)
    else
      _ -> %{}
    end
  end

  ## Subjects, and which of them arms the check

  defp stated(project, components, allow, overrides, shape) do
    subjects = subjects(project, components)

    subject_problems =
      shape ++ undeclared_problems(components) ++ unplaceable_problems(subjects, allow)

    case Enum.flat_map(subjects, &arming(&1, allow)) do
      [] ->
        %{problems: subject_problems, census: unchecked_census(subjects, allow)}

      arming ->
        dependencies(project, allow, overrides, arming, subject_problems)
    end
  end

  # The project's package is one subject per identifier it names, which
  # makes the self-check and the arming total with no special case for a
  # dual-licensed package. A component's `license:` is a single string
  # the composer has already typed.
  defp subjects(project, components) do
    package =
      for id <- package_licenses(project),
          do: %{what: "this project's package", distribution: :distributed, license: id}

    declared =
      for component <- components,
          {:ok, distribution, license} <- [Licensing.declared(component)],
          do: %{what: inspect(component), distribution: distribution, license: license}

    package ++ declared
  end

  defp package_licenses(project) do
    with package when is_list(package) <- Keyword.get(project, :package, []),
         true <- Keyword.keyword?(package),
         {:ok, licenses} when is_list(licenses) <- Keyword.fetch(package, :licenses) do
      Enum.filter(licenses, &is_binary/1)
    else
      _ -> []
    end
  end

  # A default class is refused one level up (`Catapult.Component.Licensing`);
  # this is where the absence surfaces, alongside every other structural
  # one.
  defp undeclared_problems(components) do
    for component <- components, Licensing.declared(component) == :none do
      problem(
        "#{inspect(component)} declares no licensing/0, so this project's policy " <>
          "cannot place it (expected [distribution: :distributed | :service | " <>
          ":internal, license: \"SPDX-Id\"])"
      )
    end
  end

  # The bucket rule applied to a subject's own terms, `:internal`
  # included — it decides nothing about dependencies there and is still a
  # declaration the project's own policy cannot place, which is what
  # stops `license: "Proprietary"` from reading as an open-source
  # identifier and taking the unchecked branch.
  defp unplaceable_problems(subjects, allow) do
    for subject <- subjects, bucket(subject.license, allow) == :unplaceable do
      problem(
        "#{subject.what} declares #{inspect(subject.license)}, which is neither on " <>
          "this project's licensing allow list #{inspect(allow)} nor a " <>
          "#{@license_ref}* identifier"
      )
    end
  end

  defp bucket(license, allow) do
    cond do
      license in allow -> :listed
      String.starts_with?(license, @license_ref) -> :ref
      true -> :unplaceable
    end
  end

  # A subject is held to the standard it holds its dependencies to, which
  # is why the unplaceable row arms nothing: it is already reported, one
  # level worse than a copyleft dependency, and a verdict on its
  # dependencies would be a verdict from a list that cannot place the
  # thing shipping.
  defp arming(subject, allow) do
    case {subject.distribution, bucket(subject.license, allow)} do
      {:internal, _bucket} ->
        []

      {:service, :listed} ->
        []

      {_distribution, :unplaceable} ->
        []

      {:service, :ref} ->
        [because(subject, "AGPL §13 would oblige an offer of source to our own users")]

      {:distributed, :listed} ->
        [because(subject, "a recipient would inherit terms nobody offered them")]

      {:distributed, :ref} ->
        [because(subject, "we would be conveying a work under terms we have not met")]
    end
  end

  defp because(subject, reason) do
    "#{subject.what} is #{inspect(subject.distribution)} under " <>
      "#{inspect(subject.license)} (#{reason})"
  end

  ## The closure, and the verdict on it

  defp dependencies(project, allow, overrides, arming, subject_problems) do
    {order, metadata} = closure(project)
    checked = "checked because " <> Enum.join(arming, "; ")

    problems =
      subject_problems ++
        Enum.flat_map(order, &dependency_problems(&1, metadata, allow, overrides, checked)) ++
        unused_override_problems(overrides, order)

    %{problems: problems, census: armed_census(order, allow, arming)}
  end

  defp closure(project) do
    deps_path = Keyword.get(project, :deps_path) || "deps"
    {order, metadata} = Enum.reduce(seed(project), {[], %{}}, &visit(&1, deps_path, &2))
    {Enum.sort(order), metadata}
  end

  # What a consumer would fetch: the project's own deps, minus the ones
  # no `:prod` build resolves and minus path deps, which are mix projects
  # audited in their own right rather than packages with metadata.
  defp seed(project) do
    for dep <- Keyword.get(project, :deps, []),
        {app, opts} <- [dep_opts(dep)],
        not Keyword.has_key?(opts, :path),
        prod?(opts),
        do: Atom.to_string(app)
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

  defp visit(app, deps_path, {order, metadata}) do
    if Map.has_key?(metadata, app) do
      {order, metadata}
    else
      meta = read_metadata(deps_path, app)
      acc = {[app | order], Map.put(metadata, app, meta)}
      Enum.reduce(requirements(meta), acc, &visit(&1, deps_path, &2))
    end
  end

  defp read_metadata(deps_path, app) do
    path = Path.join([deps_path, app, "hex_metadata.config"])

    case :file.consult(String.to_charlist(path)) do
      {:ok, terms} -> {:ok, Map.new(terms)}
      {:error, _reason} -> :missing
    end
  end

  defp requirements(:missing), do: []

  defp requirements({:ok, meta}) do
    meta |> Map.get("requirements", []) |> Enum.flat_map(&requirement/1)
  end

  # The rebar-built encoding: `{name, proplist}`, as cowboy declares
  # cowlib and ranch.
  defp requirement({name, props}) when is_binary(name) and is_list(props),
    do: required(name, props)

  # The mix-built encoding: a flat proplist carrying its own `name`.
  defp requirement(props) when is_list(props), do: required(prop(props, "name"), props)

  defp requirement(_other), do: []

  # `optional` makes an entry the consumer's dependency rather than ours
  # — `jason` declares `decimal` that way, and a naive walk would put a
  # package nobody fetches into the closure.
  defp required(name, props) do
    app = prop(props, "app") || name

    if prop(props, "optional") == true or not is_binary(app), do: [], else: [app]
  end

  defp prop(props, key) do
    case List.keyfind(props, key, 0) do
      {^key, value} -> value
      _other -> nil
    end
  end

  defp dependency_problems(app, metadata, allow, overrides, checked) do
    case license_of(app, Map.get(metadata, app, :missing), overrides) do
      {:ok, ids} -> placed(app, ids, allow, checked)
      :unresolved -> [unresolved(app, checked)]
    end
  end

  defp license_of(app, meta, overrides) do
    case Map.fetch(overrides, app) do
      {:ok, id} -> {:ok, [id]}
      :error -> declared_licenses(meta)
    end
  end

  defp declared_licenses(:missing), do: :unresolved

  defp declared_licenses({:ok, meta}) do
    case Map.get(meta, "licenses") do
      [_first | _rest] = ids -> {:ok, Enum.filter(ids, &is_binary/1)}
      _other -> :unresolved
    end
  end

  defp placed(app, ids, allow, checked) do
    if Enum.any?(ids, &(&1 in allow)) do
      []
    else
      [
        problem(
          "dependency #{app} declares #{inspect(ids)}, and this project's licensing " <>
            "allow list #{inspect(allow)} contains none of them — #{checked}"
        )
      ]
    end
  end

  defp unresolved(app, checked) do
    problem(
      "dependency #{app} is in the checked closure and its license cannot be read " <>
        "(no hex_metadata.config, or none declaring one) — read its LICENSE and " <>
        "record it as licensing: [overrides: [#{app}: \"SPDX-Id\"]] in mix.exs; " <>
        "#{checked}"
    )
  end

  # The same argument `catapult:allow` takes in `Catapult.Audit.Source`:
  # an entry that resolves nothing is how the next reader learns the
  # overrides list is where a dependency goes to stop being checked. It
  # is a fact about a package, and a package that left the tree took the
  # fact with it.
  defp unused_override_problems(overrides, order) do
    in_scope = MapSet.new(order)

    for {app, id} <- Enum.sort(overrides), not MapSet.member?(in_scope, app) do
      problem(
        "licensing override #{app}: #{inspect(id)} names a dependency that is not in " <>
          "the checked closure (delete it; a stale override is read as a live one)"
      )
    end
  end

  ## The census

  defp inert_census do
    "inert — this project states no licensing policy, so nothing was checked " <>
      "(state one in mix.exs: licensing: [allow: [\"Apache-2.0\", ...]])"
  end

  defp unchecked_census([], allow) do
    "unchecked against #{count(allow, "identifier")} — this project declares no licensing " <>
      "subject (no package: licenses, no component licensing/0)"
  end

  defp unchecked_census(subjects, allow) do
    summary =
      Enum.map_join(subjects, "; ", fn subject ->
        "#{subject.what} #{inspect(subject.distribution)} #{inspect(subject.license)}"
      end)

    "unchecked against #{count(allow, "identifier")} — no subject arms a dependency " <>
      "check (#{summary})"
  end

  defp armed_census(order, allow, arming) do
    "#{count(order, "dependency", "dependencies")} checked against " <>
      "#{count(allow, "identifier")}, armed by #{Enum.join(arming, "; ")}"
  end

  defp count(list, singular, plural \\ nil) do
    case length(list) do
      1 -> "1 #{singular}"
      n -> "#{n} #{plural || singular <> "s"}"
    end
  end

  defp problem(message), do: "licensing: " <> message
end
