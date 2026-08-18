defmodule Catapult.Audit.BoundaryAppsTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.BoundaryApps

  # A dependency universe standing in for compiled `.app` files: what
  # each application reaches, and whether Boundary could restrain a call
  # into it. `:web` reaches two Erlang-only applications the way
  # plug_cowboy reaches cowboy and ranch; `:kit` is the path dep, and it
  # is the only route to `:leaf`, which is why the walk has to descend
  # into it.
  @tree %{
    kit: %{applications: [:leaf], elixir_modules?: true},
    leaf: %{applications: [], elixir_modules?: true},
    sql: %{applications: [:pool], elixir_modules?: true},
    pool: %{applications: [], elixir_modules?: true},
    web: %{applications: [:erl_server, :erl_wire], elixir_modules?: true},
    erl_server: %{applications: [:erl_wire], elixir_modules?: false},
    erl_wire: %{applications: [], elixir_modules?: false},
    boundary: %{applications: [], elixir_modules?: true},
    tooling: %{applications: [], elixir_modules?: true}
  }

  @deps [
    {:kit, path: "components/kit"},
    {:sql, "~> 3.0"},
    {:web, "~> 2.0"},
    {:boundary, "~> 0.10", runtime: false},
    {:tooling, "~> 1.0", only: [:dev, :test], runtime: false}
  ]

  # Everything the closure holds that Boundary can restrain: `:boundary`
  # itself, the two Erlang-only applications and the path dep are all
  # excluded by derivation.
  @restrainable [:sql, :pool, :web, :leaf]

  ## Which state the project is in

  describe "a project that declares no apps list" do
    test "is inert rather than failing, and says which inert it is" do
      verdict = BoundaryApps.audit(project(boundary: nil), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "inert"
      assert verdict.census =~ "module attribute this cannot see"
    end

    test "is inert on type: :strict, which needs no list" do
      verdict = BoundaryApps.audit(project(boundary: [default: [type: :strict]]), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "inert"
      assert verdict.census =~ "type: :strict"
    end

    test "is inert on a nil check:, which states nothing rather than nothing valid" do
      verdict = BoundaryApps.audit(project(boundary: [default: [check: nil]]), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "states no apps:"
    end

    test "is inert on a boundary: block that names no default:" do
      verdict = BoundaryApps.audit(project(boundary: [other: []]), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "inert"
    end

    test "is inert on a check: that states no apps:, and says that too" do
      verdict = BoundaryApps.audit(project(boundary: [default: [check: [in: false]]]), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "states no apps:"
    end

    test "reads strict ahead of a list, because strict makes the list moot" do
      declaration = [default: [type: :strict, check: [apps: []]]]
      verdict = BoundaryApps.audit(project(boundary: declaration), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "type: :strict"
    end
  end

  describe "a malformed declaration" do
    test "is reported rather than read as declining" do
      verdict = BoundaryApps.audit(project(boundary: :strict), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "boundary: is :strict, expected a keyword list"
      refute verdict.census =~ "inert"
    end

    test "reports a default: that is not a keyword list" do
      verdict = BoundaryApps.audit(project(boundary: [default: [:ecto]]), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "boundary: default: is [:ecto]"
    end

    test "reports apps: that is not a list" do
      verdict = BoundaryApps.audit(project(boundary: [default: [check: [apps: :sql]]]), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "apps: is :sql, expected a list"
    end

    # Boundary takes only `type` and `check` out of a project default and
    # drops the rest without a word, so a key it does not know is a
    # declaration the author believes in and the compiler never sees.
    test "reports a key Boundary drops in silence, and still checks the list" do
      declaration = [default: [check: [apps: @restrainable], typ: :strict]]
      verdict = BoundaryApps.audit(project(boundary: declaration), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "unknown key :typ"
      assert problem =~ "drops the rest silently"
      assert verdict.census =~ "4 of 4 restrainable named"
    end

    # `{:sql, :runtim}` is carried through untouched by Boundary, where
    # it matches no reference and restrains nothing — a typo that reads
    # as coverage.
    test "reports a key Boundary drops even where the state is inert anyway" do
      verdict = BoundaryApps.audit(project(boundary: [default: [typ: :strict]]), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "unknown key :typ"
      assert verdict.census =~ "inert"
    end

    test "reports an entry Boundary passes through and never matches" do
      declaration = [default: [check: [apps: [{:sql, :runtim} | @restrainable]]]]
      verdict = BoundaryApps.audit(project(boundary: declaration), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "carries {:sql, :runtim}"
      assert problem =~ "restrains nothing"
    end
  end

  ## The closure

  describe "the subject" do
    test "is complete when every restrainable application is named" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.problems == []
    end

    test "reports an application the list omits, as exempt rather than partial" do
      verdict = BoundaryApps.audit(project(apps: @restrainable -- [:pool]), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "pool is reachable from a :prod build"
      assert problem =~ "it is exempt"
    end

    # The path dep is the only route to `:leaf`, which is what stops this
    # check from sharing the license walk's closure: that one stops at a
    # path dep, and stopping here would leave a hole one level in.
    test "descends into a path dep, because its dependencies reach lib/ too" do
      verdict = BoundaryApps.audit(project(apps: @restrainable -- [:leaf]), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "leaf is reachable"
    end

    test "excludes a dev/test-only dependency, which no :prod build resolves" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.problems == []
      refute verdict.census =~ "tooling"
    end

    test "ignores an application outside the project's own dependencies" do
      tree = put_in(@tree.sql.applications, [:pool, :kernel])
      verdict = BoundaryApps.audit(project(apps: @restrainable), tree)

      assert verdict.problems == []
      assert verdict.census =~ "out of 8 reachable"
    end

    # Reachable and unreadable is the one state that would otherwise be
    # exempt without saying so.
    test "reports a reachable application whose spec cannot be read" do
      tree = put_in(@tree.pool[:loaded?], false)
      verdict = BoundaryApps.audit(project(apps: @restrainable), tree)

      assert [problem] = verdict.problems
      assert problem =~ "pool is reachable"
      assert problem =~ "application spec cannot be read"
    end
  end

  ## The three exclusions, none of them a name anybody writes

  describe "an exclusion" do
    test "covers :boundary, which the checker excludes before anything else" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "boundary itself"
    end

    test "covers an application contributing no Elixir modules" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "2 unrestrainable (erl_server, erl_wire)"
    end

    test "covers a path dep, because naming one reproduces the strict defect" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.problems == []
      assert verdict.census =~ "1 path dep (kit)"
    end

    # There is no waiver, so naming an excluded application is legal and
    # inert rather than an escape somebody can spend.
    test "is inert when named rather than an error, and still not required" do
      named = [:boundary, :erl_wire, :kit | @restrainable]

      assert BoundaryApps.audit(project(apps: named), @tree).problems == []
    end
  end

  ## Both modes, and coverage rather than equality

  describe "coverage" do
    test "means both modes — a runtime-only entry leaves compile calls unchecked" do
      apps = [{:sql, :runtime} | @restrainable -- [:sql]]
      verdict = BoundaryApps.audit(project(apps: apps), @tree)

      assert [problem] = verdict.problems
      assert problem =~ "sql is named for [:runtime] only"
      assert problem =~ "[:compile]"
    end

    test "is satisfied by the two modes named separately" do
      apps = [{:sql, :runtime}, {:sql, :compile} | @restrainable -- [:sql]]

      assert BoundaryApps.audit(project(apps: apps), @tree).problems == []
    end

    test "counts a half-named application as unnamed in the census" do
      apps = [{:sql, :runtime} | @restrainable -- [:sql]]
      verdict = BoundaryApps.audit(project(apps: apps), @tree)

      assert verdict.census =~ "3 of 4 restrainable named"
    end

    # A list is free to say more than the floor requires: a test-only
    # dependency named deliberately is the ordinary case.
    test "is never equality — a name outside the closure is not a problem" do
      verdict = BoundaryApps.audit(project(apps: [:tooling, :absent | @restrainable]), @tree)

      assert verdict.problems == []
    end
  end

  ## The census

  describe "the census" do
    test "names the exclusions rather than counting them" do
      verdict = BoundaryApps.audit(project(apps: @restrainable), @tree)

      assert verdict.census ==
               "4 of 4 restrainable named, out of 8 reachable; " <>
                 "2 unrestrainable (erl_server, erl_wire); 1 path dep (kit); boundary itself"
    end

    test "says nothing about an exclusion the closure does not hold" do
      deps = [{:sql, "~> 3.0"}]
      verdict = BoundaryApps.audit(project(deps: deps, apps: [:sql, :pool]), @tree)

      assert verdict.census == "2 of 2 restrainable named, out of 2 reachable"
    end
  end

  defp project(opts) do
    boundary =
      case Keyword.fetch(opts, :boundary) do
        {:ok, value} -> value
        :error -> [default: [check: [apps: Keyword.fetch!(opts, :apps)]]]
      end

    [deps: Keyword.get(opts, :deps, @deps), boundary: boundary]
  end
end
