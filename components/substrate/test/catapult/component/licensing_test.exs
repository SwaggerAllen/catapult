defmodule Catapult.Component.LicensingTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Licensing

  defmodule GitComponent do
    use Catapult.Component, slug: :git_component
    def licensing, do: [distribution: :distributed, license: "MIT"]
  end

  defmodule OtherGitComponent do
    use Catapult.Component, slug: :other_git_component
    def licensing, do: [distribution: :distributed, license: "MIT"]
  end

  defmodule DisagreeingGitComponent do
    use Catapult.Component, slug: :disagreeing_git_component
    def licensing, do: [distribution: :distributed, license: "Apache-2.0"]
  end

  defmodule NotAComponent do
  end

  ## `components_of/1`

  describe "components_of/1" do
    test "an application with no .app file to load answers []" do
      assert Licensing.components_of(:no_such_git_dependency_app) == []
    end

    test "an application whose modules carry no component marker answers []" do
      app = register(:plain_git_dep, [NotAComponent])

      assert Licensing.components_of(app) == []
    end

    test "an application's own component modules are found off its module list" do
      app = register(:one_component_git_dep, [GitComponent, NotAComponent])

      assert Licensing.components_of(app) == [GitComponent]
    end

    test "every component module the application ships is returned, agreeing or not" do
      app = register(:two_component_git_dep, [GitComponent, OtherGitComponent])

      assert Enum.sort(Licensing.components_of(app)) ==
               Enum.sort([GitComponent, OtherGitComponent])
    end

    test "an already-loaded application is read rather than rejected" do
      app = register(:already_loaded_git_dep, [GitComponent])

      assert Licensing.components_of(app) == [GitComponent]
    end
  end

  defp register(app, modules) do
    :ok = :application.load({:application, app, [vsn: ~c"1.0.0", modules: modules]})
    app
  end
end
