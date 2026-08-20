defmodule Catapult.Engine.ChildrenTest do
  use ExUnit.Case, async: true

  # This is the assertion the deploy needed and the suite could not
  # make. `children/0` used to branch on the configured adapter and
  # list `Catapult.Engine.EventStore` alongside the Commanded
  # application under the persistent one — but the adapter's own
  # `child_spec/2` already returns that module as a child, under the
  # same registered name, so the second start answered
  # `{:error, {:already_started, _}}` and took the boot down.
  #
  # The test env runs `Commanded.EventStore.Adapters.InMemory`, whose
  # branch never listed it, so every test passed against a
  # supervision tree no deployment ever ran. Asserting on the child
  # list itself rather than on a booted tree is what makes this
  # answerable in the environment that has the wrong adapter.
  test "the event store is never a direct child; the Commanded adapter starts it" do
    children = Catapult.Engine.children()

    refute Catapult.Engine.EventStore in children,
           "the Commanded adapter's child_spec/2 already starts the event store"

    assert Catapult.Engine.Application in children
    assert Catapult.Engine.Projector in children
  end
end
