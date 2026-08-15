defmodule Catapult.Audit.DeclarationsTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.Declarations
  alias Catapult.Component.Composer

  defmodule Engine do
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
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "catapult-decl-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    inventory = Composer.inventory([Engine])
    {:ok, dir: dir, scope: Path.join(dir, "*.ex"), inventory: inventory}
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
end
