defmodule Catapult.Config.EnvTest do
  @moduledoc """
  The shipped source. This is the one test in the suite that touches the
  real environment, and it has to be: an adapter over `System.get_env/0`
  that is only ever exercised through the fake is an adapter nobody
  runs. Everything *else* reads config through
  `Catapult.Config.Static` — which is the rule this test is the
  exception to, not a hole in it (conventions §9).
  """
  # Not async: the process environment is global.
  use ExUnit.Case, async: false

  alias Catapult.Config.Env

  @declared "CATAPULT_CONFIG_ENV_TEST_DECLARED"
  @undeclared "CATAPULT_CONFIG_ENV_TEST_UNDECLARED"

  setup do
    System.put_env(@declared, "present")
    System.put_env(@undeclared, "also present")
    on_exit(fn -> Enum.each([@declared, @undeclared], &System.delete_env/1) end)
  end

  test "answers for declared names only" do
    assert Env.load([@declared], []) == {:ok, %{@declared => "present"}}
  end

  test "a name with no value is simply absent — not an error" do
    # The environment always answers, so this source cannot fail; a name
    # it has nothing for is the layer's problem to report, against the
    # declaration that wanted it.
    assert {:ok, found} = Env.load([@declared, "CATAPULT_CONFIG_ENV_TEST_UNSET"], [])
    assert found == %{@declared => "present"}
  end
end
