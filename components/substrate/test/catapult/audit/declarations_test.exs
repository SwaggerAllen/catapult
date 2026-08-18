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
