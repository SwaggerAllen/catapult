defmodule Catapult.Delivery.FlagSetTest do
  @moduledoc """
  The flag port (v5 §2.10, §7.8) and the outbox worker that drives it
  (§7.1's intent → idempotent effect → observed completion).
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FlagSet
  alias Catapult.Delivery.FlagSet.Deferred
  alias Catapult.Delivery.FlagSet.Fake

  describe "the configured implementation" do
    test "the suite runs against the fake (conventions §9)" do
      assert FlagSet.adapter() == Fake
    end

    test "the fake accumulates enabled flags, idempotently" do
      assert :ok = FlagSet.enable(["a", "b"])
      assert :ok = FlagSet.enable(["b", "c"])

      assert Fake.enabled() == ["a", "b", "c"]
    end

    test "the fake is per-process, so the suite stays async" do
      assert :ok = FlagSet.enable(["mine"])

      task = Task.async(fn -> Fake.enabled() end)

      assert Task.await(task) == []
      assert Fake.enabled() == ["mine"]
    end
  end

  describe "Deferred — the default, while conventions §13 defers flag consumption" do
    @tag :capture_log
    test "an empty set enables successfully" do
      # There is nothing to turn on, so the effect genuinely happened.
      # Failing here would hold every milestone open over a no-op — and
      # today every real aggregate is empty, since nothing in this tree
      # declares a feature_flags/0 entry.
      assert Deferred.enable([]) == :ok
    end

    @tag :capture_log
    test "a non-empty set fails rather than claiming an effect it did not have" do
      # v5 §7.1: the log never says "done" on the plane's own word. The
      # intent stays recorded and the container sits visibly at
      # :requested, which is the intent-without-effect case — visible,
      # and escalates.
      assert Deferred.enable(["some-flag"]) == {:error, :no_flag_backend}
    end
  end
end
