defmodule Catapult.Engine.Policies.PurityFloorTest do
  use ExUnit.Case, async: true

  alias Catapult.Engine.Policies.PurityFloor

  setup do
    dir = Path.join(System.tmp_dir!(), "purity_floor_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp write(dir, filename, content) do
    path = Path.join(dir, filename)
    File.write!(path, content)
    path
  end

  test "clean code that calls only an injected clock reports nothing", %{dir: dir} do
    write(dir, "clean.ex", """
    defmodule Purity.Clean do
      def stamp(clock), do: clock.now()
    end
    """)

    assert PurityFloor.run(Path.join(dir, "*.ex")) == []
  end

  test "a direct call to DateTime.utc_now/0 is reported at its own line", %{dir: dir} do
    write(dir, "direct.ex", """
    defmodule Purity.Direct do
      def stamp do
        DateTime.utc_now()
      end
    end
    """)

    assert [problem] = PurityFloor.run(Path.join(dir, "*.ex"))
    assert problem =~ "direct.ex:3:"
    assert problem =~ "Purity.Direct.stamp/0"
  end

  test "a transitive call through a local helper is reported", %{dir: dir} do
    write(dir, "transitive.ex", """
    defmodule Purity.Transitive do
      def apply_event(event) do
        stamp(event)
      end

      defp stamp(event) do
        Map.put(event, :at, DateTime.utc_now())
      end
    end
    """)

    problems = PurityFloor.run(Path.join(dir, "*.ex"))
    assert Enum.any?(problems, &(&1 =~ "Purity.Transitive.apply_event/1"))
    assert Enum.any?(problems, &(&1 =~ "Purity.Transitive.stamp/1"))
  end

  test "randomness, id generation, and bare make_ref are all sinks", %{dir: dir} do
    write(dir, "sinks.ex", """
    defmodule Purity.Sinks do
      def a, do: :rand.uniform(10)
      def b, do: Ecto.UUID.generate()
      def c, do: make_ref()
      def d, do: :erlang.unique_integer()
    end
    """)

    problems = PurityFloor.run(Path.join(dir, "*.ex"))
    assert length(problems) == 4
    assert Enum.any?(problems, &(&1 =~ "Purity.Sinks.a/0"))
    assert Enum.any?(problems, &(&1 =~ "Purity.Sinks.b/0"))
    assert Enum.any?(problems, &(&1 =~ "Purity.Sinks.c/0"))
    assert Enum.any?(problems, &(&1 =~ "Purity.Sinks.d/0"))
  end

  test "one impure clause makes the whole multi-clause function impure, at its own clause line",
       %{
         dir: dir
       } do
    write(dir, "multi_clause.ex", """
    defmodule Purity.MultiClause do
      def apply(:a), do: :ok
      def apply(:b), do: DateTime.utc_now()
    end
    """)

    assert [problem] = PurityFloor.run(Path.join(dir, "*.ex"))
    assert problem =~ "multi_clause.ex:3:"
    assert problem =~ "Purity.MultiClause.apply/1"
  end

  test "# catapult:allow purity_floor excuses the tagged line", %{dir: dir} do
    write(dir, "escaped.ex", """
    defmodule Purity.Escaped do
      def stamp do
        # catapult:allow purity_floor
        DateTime.utc_now()
      end
    end
    """)

    assert PurityFloor.run(Path.join(dir, "*.ex")) == []
  end

  test "an idle escape (no violation on its line) is itself reported", %{dir: dir} do
    write(dir, "idle.ex", """
    defmodule Purity.Idle do
      # catapult:allow purity_floor
      def stamp(clock), do: clock.now()
    end
    """)

    assert [problem] = PurityFloor.run(Path.join(dir, "*.ex"))
    assert problem =~ "excuses nothing"
  end

  test "a call to an out-of-scope module is not chased, and passes clean", %{dir: dir} do
    write(dir, "boundary.ex", """
    defmodule Purity.Boundary do
      def apply_event(event), do: Catapult.Engine.Store.upsert_node(event)
    end
    """)

    assert PurityFloor.run(Path.join(dir, "*.ex")) == []
  end
end
