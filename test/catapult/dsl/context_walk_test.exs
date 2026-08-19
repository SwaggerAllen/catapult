defmodule Catapult.Dsl.ContextWalkTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.ContextWalk

  describe "self forms" do
    test "self alone" do
      assert {:ok, %ContextWalk{source: :self, parent: false, hops: [], projection: nil}} =
               ContextWalk.parse("self")
    end

    test "self.parent" do
      assert {:ok, %ContextWalk{source: :self, parent: true, projection: nil}} =
               ContextWalk.parse("self.parent")
    end

    test "self.parent.handle reads a projection with no edge walk" do
      assert {:ok, %ContextWalk{source: :self, parent: true, hops: [], projection: :handle}} =
               ContextWalk.parse("self.parent.handle")
    end

    test "self.parent.handle.fragments[pubapi]" do
      assert {:ok, %ContextWalk{projection: {:fragments, "pubapi"}}} =
               ContextWalk.parse("self.parent.handle.fragments[pubapi]")
    end

    test "self.synthesis" do
      assert {:ok, %ContextWalk{source: :self, parent: false, projection: :synthesis}} =
               ContextWalk.parse("self.synthesis")
    end

    test "self.parent.fulfills -> resp.handle walks an edge to a typed target" do
      assert {:ok,
              %ContextWalk{
                source: :self,
                parent: true,
                hops: [%{edge: "fulfills", reverse: false}],
                target_tier: "resp",
                projection: :handle
              }} =
               ContextWalk.parse("self.parent.fulfills -> resp.handle")
    end

    test "self.parent.dependency -> target.handle.fragments[pubapi]" do
      assert {:ok,
              %ContextWalk{
                hops: [%{edge: "dependency", reverse: false}],
                target_tier: "target",
                projection: {:fragments, "pubapi"}
              }} =
               ContextWalk.parse("self.parent.dependency -> target.handle.fragments[pubapi]")
    end

    test "an edge name with no -> is an error" do
      assert {:error, reason} = ContextWalk.parse("self.parent.fulfills")
      assert reason =~ "handle.fragments"
    end

    test "-> with no edge name before it is an error" do
      assert {:error, reason} = ContextWalk.parse("self -> resp.handle")
      assert reason =~ "no edge name"
    end

    test "more than one -> is an error" do
      assert {:error, reason} = ContextWalk.parse("self.a -> b.handle -> c.handle")
      assert reason =~ "more than one ->"
    end

    test "a chain of two forward hops reaches a second edge" do
      assert {:ok,
              %ContextWalk{
                hops: [
                  %{edge: "fulfills", reverse: false},
                  %{edge: "policy_application", reverse: false}
                ],
                target_tier: "policy",
                projection: :handle
              }} =
               ContextWalk.parse("self.parent.fulfills.policy_application -> policy.handle")
    end

    test "a `~`-suffixed hop is reversed" do
      assert {:ok, %ContextWalk{hops: [%{edge: "policy_application", reverse: true}]}} =
               ContextWalk.parse("self.parent.policy_application~ -> policy.handle")
    end

    test "a chain mixing a forward and a reversed hop" do
      assert {:ok,
              %ContextWalk{
                hops: [
                  %{edge: "fulfills", reverse: false},
                  %{edge: "policy_application", reverse: true}
                ]
              }} =
               ContextWalk.parse("self.parent.fulfills.policy_application~ -> policy.handle")
    end

    test "a reversed hop with no edge name is an error" do
      assert {:error, reason} = ContextWalk.parse("self.parent.~ -> policy.handle")
      assert reason =~ "no edge name"
    end
  end

  describe "input forms" do
    test "input.<role>" do
      assert {:ok, %ContextWalk{source: :input, role: "project_doc", wildcard: false}} =
               ContextWalk.parse("input.project_doc")
    end

    test "input.*" do
      assert {:ok, %ContextWalk{source: :input, wildcard: true}} = ContextWalk.parse("input.*")
    end

    test "input.* with a -> target is an error" do
      assert {:error, reason} = ContextWalk.parse("input.* -> resp.handle")
      assert reason =~ "no -> target"
    end
  end

  describe "ticket forms" do
    test "ticket.findings" do
      assert {:ok, %ContextWalk{source: :ticket, ticket_source: "findings"}} =
               ContextWalk.parse("ticket.findings")
    end
  end

  describe "all forms" do
    test "all.<tier>.handle reads every instance of a tier with no edge" do
      assert {:ok, %ContextWalk{source: :all, pool_tier: "vocab", projection: :handle}} =
               ContextWalk.parse("all.vocab.handle")
    end

    test "all.<tier>.handle.fragments[<kind>]" do
      assert {:ok,
              %ContextWalk{source: :all, pool_tier: "comp", projection: {:fragments, "techspec"}}} =
               ContextWalk.parse("all.comp.handle.fragments[techspec]")
    end

    test "all.* with a -> target is an error" do
      assert {:error, reason} = ContextWalk.parse("all.vocab -> vocab.handle")
      assert reason =~ "no -> target"
    end

    test "all.<tier> with no projection is an error" do
      assert {:error, reason} = ContextWalk.parse("all.vocab")
      assert reason =~ "all.<tier>.<projection>"
    end
  end

  test "an unknown source is an error" do
    assert {:error, reason} = ContextWalk.parse("bogus.thing")
    assert reason =~ "expected self, input, ticket or all"
  end
end
