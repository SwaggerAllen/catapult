defmodule Catapult.Audit.ChecksTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.Checks.ProcessName
  alias Catapult.Audit.Checks.SecretInLog
  alias Catapult.Audit.Checks.WallClock

  setup do
    dir = Path.join(System.tmp_dir!(), "catapult-checks-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.ex")}
  end

  defp write(dir, source), do: File.write!(Path.join(dir, "a.ex"), source)

  describe "the wall-clock ban" do
    test "catches both built-in date/time modules, however spelled", ctx do
      write(ctx.dir, """
      defmodule A do
        def a, do: DateTime.utc_now()
        def b, do: NaiveDateTime.utc_now()
        def c, do: Elixir.DateTime.utc_now()
        def d, do: Catapult.Clock.System.utc_now()
      end
      """)

      problems = WallClock.run(ctx.scope)

      assert length(problems) == 3
      assert Enum.any?(problems, &(&1 =~ ":2: bare DateTime.utc_now"))
      assert Enum.any?(problems, &(&1 =~ ":3: bare NaiveDateTime.utc_now"))
      assert Enum.any?(problems, &(&1 =~ ":4: bare DateTime.utc_now"))
    end

    test "prose may now name the call it forbids", ctx do
      write(ctx.dir, """
      defmodule A do
        @moduledoc "never write DateTime.utc_now/0 in domain code"
        @ban "DateTime.utc_now"
        def a, do: @ban
      end
      """)

      assert WallClock.run(ctx.scope) == []
    end

    test "the sanctioned exception is a comment away", ctx do
      write(ctx.dir, """
      defmodule A do
        # catapult:allow utc_now — this module IS the clock.
        def utc_now, do: DateTime.utc_now()
      end
      """)

      assert WallClock.run(ctx.scope) == []
    end

    test "the package's own clock is the tree's one escape and it is live" do
      # Not a synthetic file: the real check over the real package, which
      # is what makes the tag in `Catapult.Clock` a fact rather than a
      # convention. An idle tag there would fail here too.
      assert WallClock.run("lib/**/*.ex") == []
    end
  end

  describe "the placement ban" do
    test "catches a process named after its own module", ctx do
      write(ctx.dir, """
      defmodule A do
        def start_link(arg) do
          GenServer.start_link(__MODULE__, arg, name: __MODULE__)
        end
      end
      """)

      assert [problem] = ProcessName.run(ctx.scope)
      assert problem =~ ":3: process registered under its own module name"
    end

    test "a registered name is not a violation", ctx do
      write(ctx.dir, """
      defmodule A do
        def start_link(arg) do
          GenServer.start_link(__MODULE__, arg, name: :engine_sweeper)
        end
      end
      """)

      assert ProcessName.run(ctx.scope) == []
    end

    test "the same two words in a docstring are not a violation", ctx do
      write(ctx.dir, ~s|defmodule A do\n  @moduledoc "never pass name: __MODULE__"\nend\n|)

      assert ProcessName.run(ctx.scope) == []
    end
  end

  describe "the secret-in-log residue" do
    test "catches an unwrap handed to the operational channel", ctx do
      write(ctx.dir, """
      defmodule A do
        require Logger

        def a(secret) do
          Logger.info("connecting to \#{Catapult.Config.Secret.unwrap(secret)}")
        end
      end
      """)

      assert [problem] = SecretInLog.run(ctx.scope)
      assert problem =~ ":5: unwrapped secret in a Logger call"
    end

    test "the wrapper itself is what a log may carry", ctx do
      write(ctx.dir, """
      defmodule A do
        require Logger

        def a(secret) do
          Logger.info("connecting with \#{secret}")
        end

        def b(secret), do: Catapult.Config.Secret.unwrap(secret)
      end
      """)

      assert SecretInLog.run(ctx.scope) == []
    end
  end
end
