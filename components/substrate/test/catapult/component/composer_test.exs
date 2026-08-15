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

  defmodule ConfigA do
    use Catapult.Component, slug: :cfg_a
    def config, do: [{:url, "DATABASE_URL", external: true}, {:size, "CFG_A_SIZE", []}]
  end

  defmodule ConfigB do
    use Catapult.Component, slug: :cfg_b
    def config, do: [{:url, "DATABASE_URL", external: true}]
  end

  defmodule ConfigSloppy do
    use Catapult.Component, slug: :sloppy

    def config do
      [
        {:off_spine, "POOL_SIZE", []},
        {:unknown, "SLOPPY_UNKNOWN", [secrit: true]},
        {:bad_default, "SLOPPY_BAD_DEFAULT", [cast: :integer, default: 10]},
        {:both, "SLOPPY_BOTH", [default: "x", required: false]},
        {:bad_cast, "SLOPPY_BAD_CAST", [cast: :atom]},
        {:lowercase, "sloppy_lowercase", []},
        {:dup, "SLOPPY_DUP", []},
        {:dup, "SLOPPY_DUP_TWO", []},
        :not_a_declaration
      ]
    end
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

  test "an env var claimed twice is a collision like a queue or a topic" do
    assert :ok = Composer.validate!([ConfigA])

    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([ConfigA, ConfigB]) end
    assert err.message =~ ~s(env var "DATABASE_URL" claimed by)
  end

  test "declaration structure is reported at build time, all at once" do
    err = assert_raise Composer.CollisionError, fn -> Composer.validate!([ConfigSloppy]) end

    # A name off the slug spine, without the flag that says something
    # outside this codebase imposed it.
    assert err.message =~ "POOL_SIZE is off the slug spine (expected SLOPPY_*"
    assert err.message =~ "unknown config opt :secrit"
    assert err.message =~ "non-string default 10"
    assert err.message =~ "declares both a default and required: false"
    assert err.message =~ "unusable cast :atom"
    assert err.message =~ ~s("sloppy_lowercase" is not a SCREAMING_SNAKE env var name)
    assert err.message =~ "declares config key :dup more than once"
    assert err.message =~ "malformed config declaration :not_a_declaration"
  end

  test "readiness maps slugs" do
    assert Composer.readiness([CompA, CompB]) == %{a: true, b: true}
  end
end
