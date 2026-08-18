defmodule Catapult.Dsl.SystemStatusTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.SystemStatus

  test "the eleven fixed kinds, dsl-syntax.md §15.1's order" do
    assert SystemStatus.kinds() == [
             :backlog,
             :queue,
             :generation,
             :fanout,
             :checks,
             :merge,
             :deploy,
             :validating,
             :blocked,
             :stubbed,
             :terminal
           ]
  end

  test "a queue precedes every generation and every deploy" do
    assert SystemStatus.queue_precedes?(:generation)
    assert SystemStatus.queue_precedes?(:deploy)
    refute SystemStatus.queue_precedes?(:checks)
  end

  test "every non-terminal, non-blocked status can be kicked to blocked" do
    for kind <- SystemStatus.kinds(), kind not in [:terminal, :blocked] do
      assert SystemStatus.can_block?(kind), "#{kind} should have a blocked exit"
    end

    refute SystemStatus.can_block?(:terminal)
    refute SystemStatus.can_block?(:blocked)
  end

  test "the five fixed agent steps" do
    assert SystemStatus.agent_steps() == [:design, :dev, :reconcile, :validate, :boundary]
  end
end
