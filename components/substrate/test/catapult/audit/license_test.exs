defmodule Catapult.Audit.LicenseTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.License

  @allow ~w(Apache-2.0 MIT ISC)

  defmodule Shipped do
    use Catapult.Component, slug: :shipped
    def licensing, do: [distribution: :distributed, license: "Apache-2.0"]
  end

  defmodule OurService do
    use Catapult.Component, slug: :ours
    def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]
  end

  defmodule ClosedService do
    use Catapult.Component, slug: :closed
    def licensing, do: [distribution: :service, license: "LicenseRef-Catapult-Hosted"]
  end

  defmodule Tooling do
    use Catapult.Component, slug: :tooling
    def licensing, do: [distribution: :internal, license: "Apache-2.0"]
  end

  defmodule Vague do
    use Catapult.Component, slug: :vague
    def licensing, do: [distribution: :internal, license: "Proprietary"]
  end

  defmodule Silent do
    use Catapult.Component, slug: :silent
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "catapult-license-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, deps: dir}
  end

  ## The project's own statement

  describe "a project that states no policy" do
    test "is inert rather than held to Catapult's list, and says so", ctx do
      verdict = License.audit(project(ctx, licensing: nil), [Shipped])

      assert verdict.problems == []
      assert verdict.census =~ "inert"
      assert verdict.census =~ "licensing: [allow:"
    end

    test "is inert with an undeclared component too — declining is not failing", ctx do
      assert License.audit(project(ctx, licensing: nil), [Silent]).problems == []
    end

    test "reports a typo in the key rather than reading it as declining", ctx do
      verdict = License.audit(project(ctx, licensing: [alow: @allow]), [Shipped])

      assert [problem] = verdict.problems
      assert problem =~ "unknown key :alow"
      assert verdict.census =~ "inert"
    end

    test "reports a malformed allow list, an overrides list and a non-keyword block", ctx do
      assert [problem] =
               License.audit(project(ctx, licensing: [allow: "Apache-2.0"]), []).problems

      assert problem =~ "expected a list of SPDX identifier strings"

      assert [problem] =
               License.audit(
                 project(ctx, licensing: [allow: @allow, overrides: [:plug]]),
                 []
               ).problems

      assert problem =~ ~s(expected [app: "SPDX-Id"])

      assert [problem] = License.audit(project(ctx, licensing: :yes), []).problems
      assert problem =~ "expected a keyword list"
    end
  end

  ## Which trees are checked, and for which reason

  describe "the class table" do
    test "a conveyed project package arms the check", ctx do
      verdict = License.audit(project(ctx, package: ["Apache-2.0"]), [])

      assert verdict.census =~ "armed by this project's package"
      assert verdict.census =~ "a recipient would inherit terms nobody offered them"
    end

    test "a :distributed component arms it, on the same reason", ctx do
      verdict = License.audit(project(ctx), [Shipped])

      assert verdict.census =~ "armed by"
      assert verdict.census =~ "a recipient would inherit terms nobody offered them"
    end

    test "conveying under an unlisted-by-name identifier arms it on its own reason", ctx do
      verdict =
        License.audit(project(ctx, package: ["LicenseRef-Catapult-Commercial"]), [])

      assert verdict.census =~ "we would be conveying a work under terms we have not met"
    end

    test "a public-licensed service is unchecked — we offer source on those terms", ctx do
      allow = @allow ++ ["AGPL-3.0-only"]
      verdict = License.audit(project(ctx, licensing: [allow: allow]), [OurService])

      assert verdict.problems == []
      assert verdict.census =~ "no subject arms a dependency check"
      assert verdict.census =~ "AGPL-3.0-only"
    end

    test "a proprietary service is checked, and its line says AGPL §13", ctx do
      verdict = License.audit(project(ctx), [ClosedService])

      assert verdict.census =~ "AGPL §13 would oblige an offer of source to our own users"
      refute verdict.census =~ "recipient"
    end

    test "an :internal component is unchecked whatever it carries", ctx do
      verdict = License.audit(project(ctx), [Tooling])

      assert verdict.problems == []
      assert verdict.census =~ "no subject arms a dependency check"
    end

    test "a project with a policy and no subject says exactly that", ctx do
      verdict = License.audit(project(ctx), [])

      assert verdict.problems == []
      assert verdict.census =~ "declares no licensing subject"
    end

    test "strictest wins: one shipped component checks the whole shared tree", ctx do
      allow = @allow ++ ["AGPL-3.0-only"]
      copyleft(ctx.deps)

      verdict =
        License.audit(
          project(ctx, licensing: [allow: allow], deps: [{:gpl_dep, "~> 1.0"}]),
          [OurService, Shipped]
        )

      assert [problem] = verdict.problems
      assert problem =~ "dependency gpl_dep"
      assert problem =~ "recipient would inherit"
    end
  end

  ## A subject is held to the standard it holds its dependencies to

  describe "the subject's own terms" do
    test "an identifier the project's list cannot place is reported", ctx do
      verdict = License.audit(project(ctx), [Vague])

      assert [problem] = verdict.problems
      assert problem =~ ~s(Catapult.Audit.LicenseTest.Vague declares "Proprietary")
      assert problem =~ "nor a LicenseRef-* identifier"
    end

    test "an unplaceable subject arms nothing — it is already the worse finding", ctx do
      copyleft(ctx.deps)

      verdict =
        License.audit(project(ctx, package: ["Proprietary"], deps: [{:gpl_dep, "~> 1.0"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ "neither on this project's licensing allow list"
    end

    test "shipping under terms the project would not accept from a dependency fails", ctx do
      verdict = License.audit(project(ctx, package: ["AGPL-3.0-only"]), [])

      assert [problem] = verdict.problems
      assert problem =~ "this project's package"
    end

    test "an undeclared component is reported, never defaulted to a class", ctx do
      verdict = License.audit(project(ctx), [Silent])

      assert [problem] = verdict.problems
      assert problem =~ "declares no licensing/0"
      assert problem =~ "distribution: :distributed | :service | :internal"
    end
  end

  ## Scope

  describe "the closure" do
    test "is the transitive non-optional requirements of the prod seed", ctx do
      package(ctx.deps, "plug", requires: [{:mix, "mime"}, {:mix, "plug_crypto"}])
      package(ctx.deps, "mime")
      package(ctx.deps, "plug_crypto")
      package(ctx.deps, "jason", requires: [{:mix_optional, "decimal"}])
      package(ctx.deps, "credo", licenses: ["GPL-3.0-only"])
      package(ctx.deps, "local", licenses: ["GPL-3.0-only"])

      deps = [
        {:plug, "~> 1.18"},
        {:jason, "~> 1.4"},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:local, path: "../local"}
      ]

      verdict = License.audit(project(ctx, package: ["Apache-2.0"], deps: deps), [])

      assert verdict.problems == []
      assert verdict.census =~ "4 dependencies checked"
    end

    test "reads the rebar encoding as well as the mix one", ctx do
      package(ctx.deps, "cowboy", licenses: ["ISC"], requires: [{:rebar, "cowlib"}])
      package(ctx.deps, "cowlib", licenses: ["GPL-3.0-only"])

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:cowboy, "~> 2.8"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ "dependency cowlib"
    end

    test "terminates on a cycle and counts each package once", ctx do
      package(ctx.deps, "a", requires: [{:mix, "b"}])
      package(ctx.deps, "b", requires: [{:mix, "a"}])

      verdict = License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:a, "~> 1.0"}]), [])

      assert verdict.problems == []
      assert verdict.census =~ "2 dependencies checked"
    end

    test "a dep whose only: includes :prod is in scope", ctx do
      package(ctx.deps, "runtime_only", licenses: ["GPL-3.0-only"])

      deps = [{:runtime_only, "~> 1.0", only: [:prod, :dev]}]
      verdict = License.audit(project(ctx, package: ["Apache-2.0"], deps: deps), [])

      assert [problem] = verdict.problems
      assert problem =~ "dependency runtime_only"
    end
  end

  ## The verdict on a dependency

  describe "resolving a dependency's license" do
    test "a copyleft dependency fails, naming the reason that armed the check", ctx do
      copyleft(ctx.deps)

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:gpl_dep, "~> 1.0"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ ~s(declares ["GPL-3.0-only"])
      assert problem =~ "contains none of them"
      assert problem =~ "checked because this project's package"
    end

    test "a dual-licensed dependency passes on any listed identifier", ctx do
      package(ctx.deps, "dual", licenses: ["GPL-2.0-only", "MIT"])

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:dual, "~> 1.0"}]), [])

      assert verdict.problems == []
    end

    test "a near-miss spelling is unrecognized, with no normalization table", ctx do
      package(ctx.deps, "nearly", licenses: ["Apache 2.0"])

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:nearly, "~> 1.0"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ ~s(declares ["Apache 2.0"])
    end

    test "a package with no metadata is reported, never passed over", ctx do
      File.mkdir_p!(Path.join(ctx.deps, "opaque"))

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:opaque, "~> 1.0"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ "its license cannot be read"
      assert problem =~ ~s(overrides: [opaque: "SPDX-Id"])
    end

    test "metadata declaring no license at all is the same finding", ctx do
      package(ctx.deps, "quiet", licenses: nil)

      verdict =
        License.audit(project(ctx, package: ["Apache-2.0"], deps: [{:quiet, "~> 1.0"}]), [])

      assert [problem] = verdict.problems
      assert problem =~ "its license cannot be read"
    end
  end

  describe "overrides" do
    test "supply the fact the metadata could not", ctx do
      package(ctx.deps, "nearly", licenses: ["Apache 2.0"])

      verdict =
        License.audit(
          project(ctx,
            package: ["Apache-2.0"],
            deps: [{:nearly, "~> 1.0"}],
            licensing: [allow: @allow, overrides: [nearly: "Apache-2.0"]]
          ),
          []
        )

      assert verdict.problems == []
    end

    test "supply no permission — an override recording copyleft fails like metadata", ctx do
      package(ctx.deps, "opaque", licenses: nil)

      verdict =
        License.audit(
          project(ctx,
            package: ["Apache-2.0"],
            deps: [{:opaque, "~> 1.0"}],
            licensing: [allow: @allow, overrides: [opaque: "GPL-3.0-only"]]
          ),
          []
        )

      assert [problem] = verdict.problems
      assert problem =~ ~s(declares ["GPL-3.0-only"])
    end

    test "one that resolves nothing is reported, like an escape nobody pruned", ctx do
      verdict =
        License.audit(
          project(ctx,
            package: ["Apache-2.0"],
            licensing: [allow: @allow, overrides: [gone: "MIT"]]
          ),
          []
        )

      assert [problem] = verdict.problems
      assert problem =~ "names a dependency that is not in the checked closure"
    end
  end

  ## The package's own tree, not a synthetic one

  test "this package's own closure is clean, and the check is armed to say so" do
    verdict = License.audit(Mix.Project.config(), [])

    assert verdict.problems == []

    assert verdict.census =~
             "armed by this project's package is :distributed under \"Apache-2.0\""

    assert verdict.census =~ "5 dependencies checked"
  end

  ## Helpers

  defp project(ctx, opts \\ []) do
    licensing = Keyword.get(opts, :licensing, allow: @allow)

    [
      app: :fake,
      deps_path: ctx.deps,
      deps: Keyword.get(opts, :deps, []),
      package: [licenses: Keyword.get(opts, :package, [])],
      licensing: licensing
    ]
  end

  defp copyleft(dir), do: package(dir, "gpl_dep", licenses: ["GPL-3.0-only"])

  defp package(dir, app, opts \\ []) do
    path = Path.join(dir, app)
    File.mkdir_p!(path)

    File.write!(Path.join(path, "hex_metadata.config"), """
    {<<"name">>,<<"#{app}">>}.
    {<<"version">>,<<"1.0.0">>}.
    #{licenses_term(Keyword.get(opts, :licenses, ["Apache-2.0"]))}
    {<<"requirements">>,[#{requirement_terms(Keyword.get(opts, :requires, []))}]}.
    """)
  end

  defp licenses_term(nil), do: ""

  defp licenses_term(licenses) do
    ~s({<<"licenses">>,[#{Enum.map_join(licenses, ",", &"<<\"#{&1}\">>")}]}.)
  end

  defp requirement_terms(requires), do: Enum.map_join(requires, ",", &requirement_term/1)

  defp requirement_term({:mix, name}), do: mix_requirement(name, "false")
  defp requirement_term({:mix_optional, name}), do: mix_requirement(name, "true")

  # The rebar-built spelling, which carries no "name" of its own.
  defp requirement_term({:rebar, name}) do
    ~s({<<"#{name}">>,[{<<"app">>,<<"#{name}">>},{<<"optional">>,false}]})
  end

  defp mix_requirement(name, optional) do
    ~s([{<<"name">>,<<"#{name}">>},{<<"app">>,<<"#{name}">>},{<<"optional">>,#{optional}}])
  end
end
