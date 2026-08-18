defmodule Catapult.Dsl.ContextWalkTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.ContextWalk

  describe "self forms" do
    test "self alone" do
      assert {:ok, %ContextWalk{source: :self, parent: false, edge: nil, projection: nil}} =
               ContextWalk.parse("self")
    end

    test "self.parent" do
      assert {:ok, %ContextWalk{source: :self, parent: true, projection: nil}} =
               ContextWalk.parse("self.parent")
    end

    test "self.parent.handle reads a projection with no edge walk" do
      assert {:ok, %ContextWalk{source: :self, parent: true, edge: nil, projection: :handle}} =
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
                edge: "fulfills",
                target_tier: "resp",
                projection: :handle
              }} =
               ContextWalk.parse("self.parent.fulfills -> resp.handle")
    end

    test "self.parent.dependency -> target.handle.fragments[pubapi]" do
      assert {:ok,
              %ContextWalk{
                edge: "dependency",
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

  test "an unknown source is an error" do
    assert {:error, reason} = ContextWalk.parse("bogus.thing")
    assert reason =~ "expected self, input or ticket"
  end
end
