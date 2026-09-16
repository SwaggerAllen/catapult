defmodule Catapult.Dsl.SystemStatusTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.SystemStatus

  test "the nineteen fixed kinds, workflow.md #10's order (ORC-151: implementation and " <>
         "reconcile join, fanout retires)" do
    assert SystemStatus.kinds() == [
             :backlog,
             :pending,
             :generation,
             :design,
             :architecture,
             :implementation,
             :critique,
             :checks,
             :reconcile,
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

  test "merge is plane-balled, not agent-balled (ORC-151: the reconcile/merge split)" do
    assert SystemStatus.ball(:merge) == :plane
    assert SystemStatus.ball(:reconcile) == :agent
    refute SystemStatus.agent_balled?("merge")
    assert SystemStatus.agent_balled?("reconcile")
  end

  test "a pending precedes every generation-shaped kind and every deploy" do
    assert SystemStatus.pending_precedes?(:generation)
    assert SystemStatus.pending_precedes?(:design)
    assert SystemStatus.pending_precedes?(:architecture)
    assert SystemStatus.pending_precedes?(:implementation)
    assert SystemStatus.pending_precedes?(:deploy)
    refute SystemStatus.pending_precedes?(:checks)
  end

  test "generation, design, architecture and implementation are the generation-shaped kinds" do
    assert SystemStatus.generation_shaped?("generation")
    assert SystemStatus.generation_shaped?("design")
    assert SystemStatus.generation_shaped?("architecture")
    assert SystemStatus.generation_shaped?("implementation")
    refute SystemStatus.generation_shaped?("critique")
    refute SystemStatus.generation_shaped?("merge")
  end

  test "critique and reconcile are the review-shaped kinds" do
    assert SystemStatus.review_shaped?("critique")
    assert SystemStatus.review_shaped?("reconcile")
    refute SystemStatus.review_shaped?("generation")
    refute SystemStatus.review_shaped?("merge")
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
