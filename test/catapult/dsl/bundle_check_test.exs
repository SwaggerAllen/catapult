defmodule Mix.Tasks.Catapult.Bundle.CheckTest do
  @moduledoc """
  `bundle.md` #14's acceptance test, exercised against the actual
  shipped bundle — this task's whole job is to load `bundles/default`
  and `bundles/default-flow` off the real repo root, so unlike every
  other test in `test/catapult/dsl/`, this one deliberately does not
  build a fixture.
  """

  use ExUnit.Case, async: true

  alias Mix.Tasks.Catapult.Bundle.Check

  test "the shipped default pair loads and stays within bundle.md #14's bound" do
    assert :ok = Check.run([])
  end
end
