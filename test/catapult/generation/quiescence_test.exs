defmodule Catapult.Generation.QuiescenceTest do
  @moduledoc """
  Direct, non-`:live` coverage for `Catapult.Generation.Quiescence`
  (`test/support/quiescence.ex`) — the decision core of the live
  suite's quiescence poll (`Catapult.Generation.ToySeedChainLiveTest`,
  `systems/generation.md`'s ORC-225 entry). Synthetic run-list inputs,
  no network, no `Process.sleep`: this is the coverage this ticket's
  rework asked for, since nothing in the offline suite previously
  exercised this arithmetic and the live suite's own run had never
  once reached it.
  """

  use ExUnit.Case, async: true

  alias Catapult.Generation.Quiescence

  describe "next_quiet_since/5" do
    test "an empty run set is never quiet, however it compares to prev_ids" do
      ids = MapSet.new()

      assert Quiescence.next_quiet_since([], ids, ids, 100, 200) == nil
      assert Quiescence.next_quiet_since([], ids, nil, nil, 200) == nil
    end

    test "opens the window at `now` the first poll the set is stable and terminal" do
      run = %{"run_key" => "r1", "status" => "completed"}
      ids = MapSet.new(["r1"])

      assert Quiescence.next_quiet_since([run], ids, ids, nil, 500) == 500
    end

    test "holds the window open at its original timestamp on a later stable poll" do
      run = %{"run_key" => "r1", "status" => "completed"}
      ids = MapSet.new(["r1"])

      assert Quiescence.next_quiet_since([run], ids, ids, 500, 800) == 500
    end

    test "a run-id set that stabilizes then grows resets the window" do
      run1 = %{"run_key" => "r1", "status" => "completed"}
      ids1 = MapSet.new(["r1"])
      quiet_since = Quiescence.next_quiet_since([run1], ids1, ids1, nil, 500)
      assert quiet_since == 500

      run2 = %{"run_key" => "r2", "status" => "dispatched"}
      ids2 = MapSet.new(["r1", "r2"])

      # The new poll's id set (ids2) doesn't match the previous poll's
      # (ids1) — a new run appearing closes the window.
      assert Quiescence.next_quiet_since([run1, run2], ids2, ids1, quiet_since, 700) == nil
    end

    test "a run flipping non-terminal after appearing stable closes the window" do
      run_terminal = %{"run_key" => "r1", "status" => "completed"}
      ids = MapSet.new(["r1"])
      quiet_since = Quiescence.next_quiet_since([run_terminal], ids, ids, nil, 500)
      assert quiet_since == 500

      run_reopened = %{"run_key" => "r1", "status" => "dispatched"}

      assert Quiescence.next_quiet_since([run_reopened], ids, ids, quiet_since, 700) == nil
    end
  end

  describe "outcome/4" do
    test "continues polling with no quiet window yet, time remaining" do
      assert Quiescence.outcome(nil, 100, 1_000, 50) == :continue
    end

    test "continues polling before the quiet window has stood open long enough" do
      assert Quiescence.outcome(100, 120, 1_000, 50) == :continue
    end

    test "reports quiescent once the quiet window has stood open long enough" do
      assert Quiescence.outcome(100, 160, 1_000, 50) == :quiescent
    end

    test "times out once the deadline passes with no quiet window open" do
      assert Quiescence.outcome(nil, 1_000, 1_000, 50) == :timeout
    end

    test "quiescence is checked before the deadline, and wins even at or past it" do
      assert Quiescence.outcome(900, 1_000, 1_000, 50) == :quiescent
    end
  end
end
