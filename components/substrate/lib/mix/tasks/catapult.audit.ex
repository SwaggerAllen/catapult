defmodule Mix.Tasks.Catapult.Audit do
  @shortdoc "Runs the structural audit (conventions §2.14 of the v5 decisions)"
  @moduledoc """
  The audit, all-problems-at-once. Four kinds of check, and the kinds are
  the interesting part:

    * **Registry structure**, via the composer: collisions, malformed
      entries and the cross-registry facts, across the whole v5 §2.2
      roster.
    * **The platform's own bans**, at AST grade —
      `Catapult.Audit.Checks.WallClock`, `.ProcessName`, `.SecretInLog`.
      Every project inherits them by running this task at all; they need
      no declaration.
    * **Registered checks**, from every component's `policies/0`. A
      component ships its enforcement into every project that adopts it,
      each against the working-directory-relative scope it registered —
      which is what keeps a registered check from reaching across mix
      projects.
    * **Facts spanning a registry and a tree**: a declared VM guardrail
      never applied, a declared error kind never constructed, a declared
      config value never read (and a `Catapult.Config.fetch!/2` call no
      declaration explains), and a Phoenix-bearing project with no
      sobelow gate.
    * **The boundary apps list** (`Catapult.Audit.BoundaryApps`): every
      application a `:prod` build can reach and Boundary can restrain,
      against the list that arms `check: [apps: [...]]`. Armed by that
      declaration and inert without it — a project on `type: :strict`
      needs no list, and both inert states say so on stdout.
    * **The license inventory** (`Catapult.Audit.License`): every
      dependency a consumer of this project would fetch, against the
      list of SPDX identifiers the project states in its own `mix.exs`.
      Armed by declaration — the project's `package:` and its
      components' `licensing/0` — never by reading the tree for a
      `components/*` directory this task ships too widely to know about.

  ## AST grade, and what it bought (ORC-21)

  These bans were greps, and a grep for a banned call matches the ban's
  own name in a docstring — which is why this text used to *state* them
  rather than spell them. It can spell them now: a call is a call and a
  string is a string. The escape moved with the grade.
  `catapult:allow <check>` is matched against a comment the parser found,
  on the offending line or the comment line directly above it, so a tag
  written inside a string literal excuses nothing — and a tag that
  excuses nothing is itself reported, because an escape list nobody
  prunes is how the next reader learns the ban is negotiable
  (`Catapult.Audit.Source`).

  ## The audit never runs another gate

  It reports a *missing* one. A task that shelled out to sobelow would
  swallow that tool's exit code and its output formatting and become a
  meta-runner, while `qualityGates` and `ci.yml` are already the place
  where a gate is one line somebody can read. So the finding is the gap —
  this project has a web layer and no sobelow gate — and arming it is the
  ordinary author edit every other gate takes. The predicate is
  `:phoenix` in the dependency tree, never a directory name: a generated
  project puts its web layer wherever its own spine says, and this task
  ships into all of them.

  The compile-connected ratchet is the same rule from the other side:
  `mix xref graph --label compile-connected --fail-above N` is stock and
  already exits 1, so the number lives in `qualityGates` — author-owned,
  which is what makes "raising it is a reviewed change" literal rather
  than aspirational (docs/conventions.md §2).

  ## A green run prints a census

  One count per registry, because most of the roster consumes nothing yet
  and an unconsumed registry's failure mode is rot rather than collision
  (systems/substrate.md).

  The licensing and boundary-apps lines ride the same argument for a
  different reason: both checks have an *inert* state — a project that
  states no `allow:` list has declined the license check, and a project
  that names no `check: [apps: ...]` has no list to complete — and a
  gate whose failure mode is a clean report is the thing ORC-37 was
  filed about. So the state each one reached is on stdout of every green
  run, armed or not. The boundary-apps line goes further and names the
  applications it could *not* cover, because those are the residual gap
  and a count is not a tell (ORC-50).

  The globs are rooted at the working directory and stay that way: this
  task ships into every generated project, so the layout of any one tree
  is not a fact it may hold (systems/substrate.md). Auditing a repo with
  more than one mix project means running it once per project — at the
  root of this one, `mix catapult.audit.all` does exactly that.

  The host app declares its components in config:
      config :catapult, :components, [Catapult.Foundation, ...]
  """

  use Mix.Task

  alias Catapult.Audit.BoundaryApps
  alias Catapult.Audit.Declarations
  alias Catapult.Audit.License
  alias Catapult.Component.Composer
  alias Catapult.Component.Registries
  alias Catapult.Config

  @platform_checks [
    Catapult.Audit.Checks.WallClock,
    Catapult.Audit.Checks.ProcessName,
    Catapult.Audit.Checks.SecretInLog
  ]

  @scope "lib/**/*.ex"

  # Where an operator standing up an instance is already reading. A
  # project that has invented no required variable never needs the
  # file to exist, so naming it here costs a generated project
  # nothing until it declares its first one.
  @manifest "SETUP.md"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("compile")
    project = Mix.Project.config()
    app = project[:app]
    Application.load(app)
    components = Application.get_env(app, :components, [])
    licensing = License.audit(project, components)
    boundary_apps = BoundaryApps.audit(project)

    problems =
      registry_problems(components) ++
        Enum.flat_map(@platform_checks, &check(&1, @scope)) ++
        policy_problems(components) ++
        declaration_problems(components) ++
        sobelow_problems() ++
        licensing.problems ++
        boundary_apps.problems

    case problems do
      [] ->
        Mix.shell().info("catapult.audit: clean (#{length(components)} component(s))")
        census(components)
        Mix.shell().info("  licensing: #{licensing.census}")
        Mix.shell().info("  boundary apps: #{boundary_apps.census}")

      _ ->
        Mix.raise("catapult.audit failed:\n  " <> Enum.join(problems, "\n  "))
    end
  end

  # The census is what makes an unconsumed registry visible. Most of the
  # roster aggregates into nothing today and that is deliberate
  # (systems/substrate.md), so the failure mode is not collision but rot
  # — twelve registries nobody looks at between now and Phase 3. One
  # line per registry on every green run is the cheapest thing that
  # makes an empty registry a fact somebody sees, and it keeps the
  # inventory surface from being the one unconsumed registry itself.
  defp census(components) do
    inventory = Composer.inventory(components)

    for key <- Registries.keys() do
      Mix.shell().info("  #{key}: #{length(Map.fetch!(inventory, key))}")
    end

    :ok
  end

  defp registry_problems([]), do: []

  defp registry_problems(components) do
    Composer.validate!(components)
    []
  rescue
    e in Composer.CollisionError -> [Exception.message(e)]
  end

  ## Registered checks

  defp policy_problems([]), do: []

  defp policy_problems(components) do
    for entry <- Composer.inventory(components).policies,
        problem <- check(entry.check, entry.scope) do
      problem
    end
  end

  # A check that raised would take the rest of the report down with it,
  # which is the one thing the all-problems-at-once style cannot afford —
  # so a broken check becomes a problem like any other rather than an
  # aborted audit.
  defp check(module, scope) do
    case module.run(scope) do
      problems when is_list(problems) -> problems
      other -> ["#{inspect(module)}.run/1 returned #{inspect(other)}, expected a list"]
    end
  rescue
    error ->
      [
        "#{inspect(module)}.run/1 raised #{inspect(error.__struct__)}: #{Exception.message(error)}"
      ]
  end

  ## Declared ↔ the tree

  # `Catapult.Audit.Declarations` holds all four, because a check nobody
  # can call is a check nobody tests; the task's job is to hand them the
  # composed inventory a registered check deliberately never sees.
  #
  # There is no empty-components short circuit, and config is why: a
  # project composing nothing declares nothing, but a `fetch!/2` call in
  # its tree is then a read nothing can explain, which is exactly the
  # line worth printing. The two registry checks skip their own sweep
  # when their entries are empty, which is where that saving belongs.
  #
  # declared↔recorded is the one whose other side is not the tree, so the
  # manifest path is the task's to name rather than the check's. Relative
  # to the working directory, like `@scope` and for the same reason: the
  # audit's globs are rooted there deliberately, because this task ships
  # into every generated project (`systems/substrate.md`).
  defp declaration_problems(components) do
    inventory = Composer.inventory(components)
    declarations = Config.declarations(components)

    Declarations.guardrails(inventory.processes, Catapult.Guardrails.enforceable(), @scope) ++
      Declarations.error_kinds(inventory.errors, @scope) ++
      Declarations.config(declarations, @scope) ++
      Declarations.operator_values(declarations, @manifest, @scope)
  end

  ## Gates this task reports and never runs

  defp sobelow_problems do
    apps = Mix.Project.deps_apps()

    if :phoenix in apps and :sobelow not in apps do
      [
        "this project's dependency tree contains :phoenix and no :sobelow — " <>
          "arm the gate (add sobelow to deps, a qualityGates line and a ci.yml step); v5 §2.14"
      ]
    else
      []
    end
  end
end
