defmodule Catapult.ApplicationTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Composer
  alias Catapult.Config

  test "the configured component roster validates" do
    components = Application.get_env(:catapult, :components)
    assert :ok = Composer.validate!(components)
  end

  test "foundation is in the roster" do
    assert Catapult.Foundation in Application.get_env(:catapult, :components)
  end

  test "boot loaded every declared value, cast, before anything started" do
    assert Config.loaded?()
    assert Config.fetch!(:foundation, :pool_size) == 10
    assert Config.fetch!(:foundation, :health_port) == 8080
    assert Config.fetch!(:foundation, :database_url)[:url] =~ "catapult_test"
  end

  test "the test build reads config through the fake, never the environment" do
    assert {Catapult.Config.Static, seed} = Application.get_env(:catapult, :config_source)
    assert is_map(seed)
  end
end
