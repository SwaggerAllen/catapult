defmodule Catapult.Foundation.Policies.ErlangHttpTest do
  use ExUnit.Case, async: true

  alias Catapult.Foundation.Policies.ErlangHttp

  setup do
    dir =
      Path.join(System.tmp_dir!(), "catapult-erlang-http-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir, scope: Path.join(dir, "*.ex")}
  end

  defp write(dir, source), do: File.write!(Path.join(dir, "a.ex"), source)

  test "catches a remote call into any banned Erlang HTTP client", ctx do
    write(ctx.dir, """
    defmodule A do
      def a, do: :httpc.request(:post, {"http://x", [], [], []}, [], [])
      def b, do: :inets.start()
      def c, do: :hackney.post("http://x")
      def d, do: :gun.post(conn, "/x", [])
      def e, do: :ibrowse.send_req("http://x", [], :post)
    end
    """)

    problems = ErlangHttp.run(ctx.scope)

    assert length(problems) == 5
    assert Enum.any?(problems, &(&1 =~ ":2: call into :httpc"))
    assert Enum.any?(problems, &(&1 =~ ":3: call into :inets"))
  end

  test "catches apply/3 on a literal module atom", ctx do
    write(ctx.dir, """
    defmodule A do
      def a, do: apply(:httpc, :request, [:post, {"http://x", [], [], []}, [], []])
    end
    """)

    assert [problem] = ErlangHttp.run(ctx.scope)
    assert problem =~ ":2: call into :httpc"
  end

  test "an Elixir client behind the same call shape is not a violation", ctx do
    write(ctx.dir, """
    defmodule A do
      def a, do: Req.get!("http://x")
      def b, do: apply(Req, :get!, ["http://x"])
    end
    """)

    assert ErlangHttp.run(ctx.scope) == []
  end

  test "prose may name the modules it forbids", ctx do
    write(ctx.dir, """
    defmodule A do
      @moduledoc "never call :httpc.request/4 from plane code"
      @ban ":httpc"
      def a, do: @ban
    end
    """)

    assert ErlangHttp.run(ctx.scope) == []
  end

  test "the sanctioned exception is a comment away", ctx do
    write(ctx.dir, """
    defmodule A do
      # catapult:allow erlang_http — this module IS the adapter.
      def a, do: :httpc.request(:get, {"http://x", []}, [], [])
    end
    """)

    assert ErlangHttp.run(ctx.scope) == []
  end

  test "the package's own tree has nothing to catch" do
    assert ErlangHttp.run("lib/**/*.ex") == []
  end
end
