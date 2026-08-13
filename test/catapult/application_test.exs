defmodule Catapult.ApplicationTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Composer

  test "the configured component roster validates" do
    components = Application.get_env(:catapult, :components)
    assert :ok = Composer.validate!(components)
  end

  test "foundation is in the roster" do
    assert Catapult.Foundation in Application.get_env(:catapult, :components)
  end
end
