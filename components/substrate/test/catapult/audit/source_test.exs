defmodule Catapult.Audit.SourceTest do
  use ExUnit.Case, async: true

  alias Catapult.Audit.Source

  @tag_name "demo"

  setup do
    dir = Path.join(System.tmp_dir!(), "catapult-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  defp write(dir, name, source) do
    path = Path.join(dir, name)
    File.write!(path, source)
    path
  end

  # The rule under test throughout: every call to `banned/0`, wherever
  # the parser found one.
  defp finder(source) do
    Source.collect(source.ast, fn
      {:banned, meta, args} = node when is_list(args) -> [{Source.line(node) || meta, "banned"}]
      _node -> []
    end)
  end

  defp scan(dir), do: Source.scan(Path.join(dir, "*.ex"), @tag_name, &finder/1)

  test "a violation is reported as path:line: message", %{dir: dir} do
    path = write(dir, "a.ex", "defmodule A do\n  def f, do: banned()\nend\n")

    assert scan(dir) == ["#{path}:2: banned"]
  end

  test "a string that spells the violation is a string", %{dir: dir} do
    write(
      dir,
      "a.ex",
      ~s|defmodule A do\n  @moduledoc "never call banned()"\n  def f, do: :ok\nend\n|
    )

    assert scan(dir) == []
  end

  describe "catapult:allow" do
    test "excuses the line below it", %{dir: dir} do
      write(dir, "a.ex", "defmodule A do\n  # catapult:allow demo\n  def f, do: banned()\nend\n")

      assert scan(dir) == []
    end

    test "excuses its own line", %{dir: dir} do
      write(dir, "a.ex", "defmodule A do\n  def f, do: banned() # catapult:allow demo\nend\n")

      assert scan(dir) == []
    end

    test "spans those two lines and no others", %{dir: dir} do
      path =
        write(dir, "a.ex", """
        defmodule A do
          # catapult:allow demo
          def f, do: banned()
          def g, do: banned()
        end
        """)

      assert scan(dir) == ["#{path}:4: banned"]
    end

    test "written inside a string literal excuses nothing", %{dir: dir} do
      path =
        write(dir, "a.ex", """
        defmodule A do
          @moduledoc "the escape is spelled catapult:allow demo"
          def f, do: banned()
        end
        """)

      assert scan(dir) == ["#{path}:3: banned"]
    end

    test "a tag excusing no violation is itself reported", %{dir: dir} do
      path =
        write(dir, "a.ex", """
        defmodule A do
          # catapult:allow demo
          def f, do: :ok
        end
        """)

      assert scan(dir) == [
               "#{path}:2: catapult:allow demo excuses nothing on this line or the next (remove it)"
             ]
    end

    test "a tag naming another check is not this check's to prune", %{dir: dir} do
      write(
        dir,
        "a.ex",
        "defmodule A do\n  # catapult:allow something_else\n  def f, do: :ok\nend\n"
      )

      assert scan(dir) == []
    end
  end

  test "a file that does not parse is a problem, not a skip", %{dir: dir} do
    path = write(dir, "a.ex", "defmodule A do\n  def f, do: (\nend\n")

    assert [problem] = scan(dir)
    assert problem =~ "#{path}:"
    assert problem =~ "does not parse"
  end

  test "files are scanned in a stable order", %{dir: dir} do
    write(dir, "b.ex", "defmodule B do\n  def f, do: banned()\nend\n")
    write(dir, "a.ex", "defmodule A do\n  def f, do: banned()\nend\n")

    assert [first, second] = scan(dir)
    assert first =~ "a.ex"
    assert second =~ "b.ex"
  end

  describe "alias?/2" do
    test "one module, three spellings" do
      for source <- ["DateTime", "Elixir.DateTime", ~s(:"Elixir.DateTime")] do
        {:ok, ast} = Code.string_to_quoted(source)
        assert Source.alias?(ast, :DateTime)
      end

      {:ok, other} = Code.string_to_quoted("NaiveDateTime")
      refute Source.alias?(other, :DateTime)
    end
  end
end
