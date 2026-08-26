defmodule Catapult.Audit.DeclarationsTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.Declarations
  alias Catapult.Component.Composer
  alias Catapult.Config

  # The component under test is compiled from a file *inside* the scope,
  # because that is the predicate every dead direction hangs on: a
  # declaration is dead only in the tree that declares it, and
  # `module_info(:compile)` is what says which tree that is. A component
  # defined in this file would be out of every scope below — which is
  # `Shipped`, at the bottom.
  @engine """
    use Catapult.Component, slug: :engine

    def processes do
      [
        {:engine_plain, :local},
        {:engine_bounded, :singleton, max_heap_size: 200_000},
        {:engine_watched, :local, message_queue_alarm_len: 10_000}
      ]
    end

    def errors do
      [
        {:engine_grammar_invalid, "the grammar does not parse", remedy: "check it"},
        {:engine_not_found, "no bundle with that id", remedy: "check the id"},
        {:engine_forgotten, "nothing ever builds this", remedy: "delete it"}
      ]
    end

    def config do
      [
        {:bundle_root, "ENGINE_BUNDLE_ROOT", []},
        {:timeout, "ENGINE_TIMEOUT", cast: :integer, default: "30"},
        {:forgotten, "ENGINE_FORGOTTEN", default: "x"}
      ]
    end
  """

  # A component that arrived from a package: it declares the same three
  # facts and is compiled from this test file, which no scope below
  # expands to.
  defmodule Shipped do
    use Catapult.Component, slug: :shipped

    def processes, do: [{:shipped_bounded, :singleton, max_heap_size: 100_000}]
    def errors, do: [{:shipped_gone, "nothing builds this", remedy: "delete it"}]
    def config, do: [{:token, "SHIPPED_TOKEN", []}]
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "catapult-decl-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    engine = compile!(dir, @engine)

    {:ok,
     dir: dir,
     scope: Path.join(dir, "*.ex"),
     inventory: Composer.inventory([engine]),
     declarations: Config.declarations([engine])}
  end

  defp compile!(dir, body) do
    name = Module.concat([__MODULE__, "Engine#{System.unique_integer([:positive])}"])
    path = Path.join(dir, "engine.ex")
    File.write!(path, "defmodule #{inspect(name)} do\n#{body}end\n")
    [{module, _binary}] = Code.compile_file(path)
    module
  end

  defp write(dir, source), do: File.write!(Path.join(dir, "a.ex"), source)

  defp guardrails(ctx),
    do: Declarations.guardrails(ctx.inventory.processes, [:max_heap_size], ctx.scope)

  defp operator_values(ctx),
    do: Declarations.operator_values(ctx.declarations, ctx.manifest, ctx.scope)

  defp manifest!(ctx, body), do: File.write!(ctx.manifest, body)

  describe "declared ↔ applied" do
    test "an applied guardrail is not a problem", ctx do
      write(ctx.dir, """
      defmodule A do
        def init(arg) do
          Catapult.Guardrails.apply!(Engine, :engine_bounded)
          {:ok, arg}
        end
      end
      """)

      assert guardrails(ctx) == []
    end

    test "a declared guardrail nobody applies is", ctx do
      write(ctx.dir, "defmodule A do\n  def init(arg), do: {:ok, arg}\nend\n")

      assert [problem] = guardrails(ctx)
      assert problem =~ "declares VM guardrails for process :engine_bounded"
      assert problem =~ "no Catapult.Guardrails.apply!/2 call applies them"
    end

    test "a sampled threshold asks for no application at all", ctx do
      write(ctx.dir, "defmodule A do\n  def init(arg), do: {:ok, arg}\nend\n")

      # `:engine_watched` declares only the mailbox threshold, which the
      # VM cannot enforce and `Catapult.Guardrails` therefore never
      # applies — so demanding a call would demand a no-op.
      refute Enum.any?(guardrails(ctx), &(&1 =~ ":engine_watched"))
      refute Enum.any?(guardrails(ctx), &(&1 =~ ":engine_plain"))
    end
  end

  describe "declared ↔ constructed" do
    test "both spellings of a construction count", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: Engine.Error.new(:engine_grammar_invalid, bundle: "acme")
        def b, do: %Engine.Error{kind: :engine_not_found, meaning: "m", remedy: "r"}
      end
      """)

      assert [problem] = Declarations.error_kinds(ctx.inventory.errors, ctx.scope)
      assert problem =~ "declares error kind :engine_forgotten and nothing constructs it"
    end

    test "an empty registry parses nothing and reports nothing", ctx do
      assert Declarations.error_kinds([], ctx.scope) == []
    end
  end

  describe "declared ↔ read" do
    test "a read joins its declaration on the slug and the key", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: Catapult.Config.fetch!(:engine, :bundle_root)
        def b, do: Config.fetch!(:engine, :timeout)
      end
      """)

      assert [problem] = Declarations.config(ctx.declarations, ctx.scope)
      assert problem =~ "declares config key :forgotten (ENGINE_FORGOTTEN)"
      assert problem =~ "nothing reads it with Catapult.Config.fetch!/2"
    end

    test "a key nobody declares is reported at its call site", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: Catapult.Config.fetch!(:engine, :bundle_root)
        def b, do: Catapult.Config.fetch!(:engine, :timeout)
        def c, do: Catapult.Config.fetch!(:engine, :forgotten)
        def d, do: Catapult.Config.fetch!(:engine, :never_declared)
      end
      """)

      assert [problem] = Declarations.config(ctx.declarations, ctx.scope)
      assert problem =~ "a.ex:5: config :engine.never_declared is read and no component declares"
    end

    test "a computed key is a problem of its own, and suppresses that slug", ctx do
      write(ctx.dir, """
      defmodule A do
        def a(key), do: Catapult.Config.fetch!(:engine, key)
      end
      """)

      # One line per cause: the three declarations it might have been
      # reading are not also reported dead, because that report's advice
      # is to delete a value the boot requires.
      assert [problem] = Declarations.config(ctx.declarations, ctx.scope)
      assert problem =~ "a.ex:2: Catapult.Config.fetch!/2 reads :engine under a computed key"
      assert problem =~ "spell the key"
    end

    test "a computed slug suppresses the direction", ctx do
      write(ctx.dir, """
      defmodule A do
        def a(slug), do: Catapult.Config.fetch!(slug, :bundle_root)
      end
      """)

      assert [problem] = Declarations.config(ctx.declarations, ctx.scope)
      assert problem =~ "a.ex:2: Catapult.Config.fetch!/2 is called with a computed slug"
    end

    test "a renamed alias hides the read, and the dead direction says so", ctx do
      write(ctx.dir, """
      defmodule A do
        alias Catapult.Config, as: Cfg
        def a, do: Cfg.fetch!(:engine, :bundle_root)
      end
      """)

      # The family's standing limit (`Catapult.Audit.Source.alias?/2`),
      # and the one place it is benign: hiding a read hides no violation,
      # it makes the declaration that read serves report as dead.
      problems = Declarations.config(ctx.declarations, ctx.scope)
      assert length(problems) == 3
      assert Enum.any?(problems, &(&1 =~ "declares config key :bundle_root (ENGINE_BUNDLE_ROOT)"))
    end

    test "the piped spelling is the same read", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: :engine |> Catapult.Config.fetch!(:bundle_root)
        def b, do: Catapult.Config.fetch!(:engine, :timeout)
        def c, do: Catapult.Config.fetch!(:engine, :forgotten)
      end
      """)

      assert Declarations.config(ctx.declarations, ctx.scope) == []
    end

    test "nothing declared and nothing read is nothing reported", ctx do
      write(ctx.dir, "defmodule A do\n  def a, do: :ok\nend\n")

      assert Declarations.config([], ctx.scope) == []
    end
  end

  # The sixth check's own component, because the predicate has three
  # clauses and `@engine` exercises one of them. Compiled into the same
  # scope, so every value below is in-tree and the only thing under test
  # is the manifest.
  @operator """
    use Catapult.Component, slug: :engine

    def config do
      [
        {:invented, "ENGINE_INVENTED", []},
        {:defaulted, "ENGINE_DEFAULTED", default: "x"},
        {:imposed, "DATABASE_URL", external: true},
        {:opted_out, "ENGINE_OPTED_OUT", required: false}
      ]
    end
  """

  describe "declared ↔ recorded" do
    setup ctx do
      component = compile!(ctx.dir, @operator)

      {:ok,
       declarations: Config.declarations([component]),
       manifest: Path.join(ctx.dir, "SETUP.md")}
    end

    test "only the invented, required, non-external value is a subject", ctx do
      manifest!(ctx, "```catapult:required-env\n```\n")

      assert [problem] = operator_values(ctx)
      assert problem =~ "ENGINE_INVENTED"
      # The three clauses of the predicate, each as a name that must not
      # appear. `required: false` is the one ORC-136's own predicate
      # missed, and the one a later reader is likeliest to drop.
      refute problem =~ "ENGINE_DEFAULTED"
      refute problem =~ "DATABASE_URL"
      refute problem =~ "ENGINE_OPTED_OUT"
    end

    test "a recorded value is silent", ctx do
      manifest!(ctx, "```catapult:required-env\nENGINE_INVENTED\n```\n")

      assert operator_values(ctx) == []
    end

    test "no manifest at all is the finding, and it names the subjects", ctx do
      refute File.exists?(ctx.manifest)

      assert [problem] = operator_values(ctx)
      assert problem =~ "records no required variables"
      assert problem =~ "catapult:required-env"
      assert problem =~ "ENGINE_INVENTED"
    end

    test "a manifest with no fenced block is the same finding", ctx do
      manifest!(ctx, "# Setup\n\nSet ENGINE_INVENTED before deploying.\n")

      assert [problem] = operator_values(ctx)
      assert problem =~ "records no required variables"
    end

    # The direction that keeps the file worth reading: a line an operator
    # would act on, for a declaration that no longer exists.
    test "a recorded name nothing declares is reported too", ctx do
      manifest!(ctx, "```catapult:required-env\nENGINE_INVENTED\nENGINE_RETIRED\n```\n")

      assert [problem] = operator_values(ctx)
      assert problem =~ "ENGINE_RETIRED"
      assert problem =~ "no component in scope"
    end

    test "both directions report together", ctx do
      manifest!(ctx, "```catapult:required-env\nENGINE_RETIRED\n```\n")

      assert [missing, stale] = operator_values(ctx)
      assert missing =~ "ENGINE_INVENTED"
      assert missing =~ "no manifest entry records it"
      assert stale =~ "ENGINE_RETIRED"
    end

    test "comments and blank lines in the block are not names", ctx do
      manifest!(ctx, """
      ```catapult:required-env
      # the plane's own credential
      ENGINE_INVENTED  # set on the instance, encrypted

      ```
      """)

      assert operator_values(ctx) == []
    end

    test "the block ends at its fence", ctx do
      manifest!(ctx, """
      ```catapult:required-env
      ENGINE_INVENTED
      ```

      ENGINE_RETIRED is prose, not a name.
      """)

      assert operator_values(ctx) == []
    end

    # A generated project that has invented no required variable needs no
    # manifest and must never be told to write one — this module ships
    # into every one of them.
    test "no subjects means no manifest is demanded", ctx do
      refute File.exists?(ctx.manifest)

      assert Declarations.operator_values([], ctx.manifest, ctx.scope) == []
    end
  end

  describe "a declaration is only dead in the tree that declares it" do
    setup ctx do
      write(ctx.dir, "defmodule A do\n  def a, do: :ok\nend\n")

      {:ok,
       inventory: Composer.inventory([Shipped]), declarations: Config.declarations([Shipped])}
    end

    test "a shipped component's guardrails are not this tree's to delete", ctx do
      assert Declarations.guardrails(ctx.inventory.processes, [:max_heap_size], ctx.scope) == []
    end

    test "nor are its error kinds", ctx do
      assert Declarations.error_kinds(ctx.inventory.errors, ctx.scope) == []
    end

    test "nor are its config values", ctx do
      assert Declarations.config(ctx.declarations, ctx.scope) == []
    end

    # SHIPPED_TOKEN has no default and no external: true, so it is
    # invented-and-required by the predicate — and it is not this tree's
    # operator's to set. The manifest of the project being audited cannot
    # be asked to carry a packaged component's variables.
    test "nor does its required value belong in this tree's manifest", ctx do
      manifest = Path.join(ctx.dir, "SETUP.md")

      assert Declarations.operator_values(ctx.declarations, manifest, ctx.scope) == []
    end

    test "but a read in this tree still joins against them", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: Catapult.Config.fetch!(:shipped, :token)
        def b, do: Catapult.Config.fetch!(:shipped, :absent)
      end
      """)

      assert [problem] = Declarations.config(ctx.declarations, ctx.scope)
      assert problem =~ "a.ex:3: config :shipped.absent is read and no component declares it"
    end
  end
end
