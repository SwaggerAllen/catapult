defmodule Catapult.Dsl.SystemStatusTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.SystemStatus

  test "the seventeen fixed kinds, dsl-syntax.md §15.1's order" do
    assert SystemStatus.kinds() == [
             :backlog,
             :pending,
             :generation,
             :critique,
             :fanout,
             :checks,
             :merge,
             :deploy,
             :validating,
             :blocked,
             :stubbed,
             :setup,
             :prep,
             :main,
             :retro,
             :cleanup,
             :terminal
           ]
  end

  test "a pending precedes every generation and every deploy" do
    assert SystemStatus.pending_precedes?(:generation)
    assert SystemStatus.pending_precedes?(:deploy)
    refute SystemStatus.pending_precedes?(:checks)
  end

  test "every non-terminal, non-blocked status can be kicked to blocked" do
    for kind <- SystemStatus.kinds(), kind not in [:terminal, :blocked] do
      assert SystemStatus.can_block?(kind), "#{kind} should have a blocked exit"
    end

    refute SystemStatus.can_block?(:terminal)
    refute SystemStatus.can_block?(:blocked)
  end

  test "the five fixed agent steps — :boundary retired (ORC-104)" do
    assert SystemStatus.agent_steps() == [
             :design,
             :dev,
             :critique,
             :reconcile,
             :validate
           ]

    refute SystemStatus.agent_step?(:boundary)
  end
end
