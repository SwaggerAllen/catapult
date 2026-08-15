defmodule Catapult.ErrorTest do
  use ExUnit.Case, async: true

  defmodule Engine do
    use Catapult.Component, slug: :engine

    def errors do
      [
        {:engine_grammar_invalid, "the bundle's grammar does not parse",
         remedy: "run mix catapult.dsl.check", runbook: "ops/grammar"},
        {:engine_not_found, "no bundle with that id", remedy: "check the id"}
      ]
    end
  end

  defmodule Engine.Error do
    @moduledoc false
    use Catapult.Error, component: Catapult.ErrorTest.Engine
  end

  test "the struct speaks for its component's declaration" do
    assert Engine.Error.component() == Engine
    assert Engine.Error.kinds() == [:engine_grammar_invalid, :engine_not_found]
  end

  test "meaning and remedy come from the registry, never from the call site" do
    error = Engine.Error.new(:engine_grammar_invalid, bundle: "acme")

    assert %Engine.Error{
             kind: :engine_grammar_invalid,
             meaning: "the bundle's grammar does not parse",
             remedy: "run mix catapult.dsl.check",
             runbook: "ops/grammar",
             admin: nil,
             details: [bundle: "acme"]
           } = error
  end

  test "conventions §8's spelling is what a caller matches on" do
    assert {:error, %Engine.Error{kind: :engine_not_found}} =
             {:error, Engine.Error.new(:engine_not_found)}
  end

  test "an undeclared kind has nowhere to be constructed from" do
    error = assert_raise ArgumentError, fn -> Engine.Error.new(:engine_invented) end

    assert error.message =~ ":engine_invented is not a kind"
    assert error.message =~ "declared: [:engine_grammar_invalid, :engine_not_found]"
  end

  test "the struct enforces the one field a failure cannot be without" do
    assert_raise ArgumentError, fn -> struct!(Engine.Error, meaning: "no kind") end
  end

  test "the registry is read at construction, never at compile time" do
    # The property this buys: `Engine` may construct `%Engine.Error{}` in
    # its own body without the two modules waiting on each other, which
    # is a compile cycle and a hard gate (conventions §2).
    assert Catapult.Error.kinds(Engine) == Engine.Error.kinds()
    assert Catapult.Error.fields() == [:kind, :meaning, :remedy, :runbook, :admin, :details]
  end
end
