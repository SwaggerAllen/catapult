defmodule Catapult.Component.ComposerTest do
  use ExUnit.Case, async: true

  alias Catapult.Component.Composer

  defmodule CompA do
    use Catapult.Component, slug: :a
    def pubsub_topics, do: [:shared_topic, :a_only]
    def oban_queues, do: [:a_work]
    def processes, do: [{:a_server, :singleton}]
  end

  defmodule CompB do
    use Catapult.Component, slug: :b
    def pubsub_topics, do: [:shared_topic]
    def processes, do: [{:a_server, :local}]
  end

  defmodule CompBSlugDup do
    use Catapult.Component, slug: :a
  end

  defmodule NotAComponent do
    def slug, do: :nope
  end

  test "clean set validates" do
    assert :ok = Composer.validate!([CompA])
  end

  test "collisions are reported all at once, per registry" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([CompA, CompB]) end
    assert err.message =~ "pubsub topic :shared_topic"
    assert err.message =~ "process name :a_server"
  end

  test "duplicate slugs and missing behaviour are problems" do
    err =
      assert_raise Composer.CollisionError, fn ->
        Composer.validate!([CompA, CompBSlugDup, NotAComponent])
      end

    assert err.message =~ "slug :a claimed by"
    assert err.message =~ "does not `use Catapult.Component`"
  end

  test "readiness maps slugs" do
    assert Composer.readiness([CompA, CompB]) == %{a: true, b: true}
  end
end
