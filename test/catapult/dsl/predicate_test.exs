defmodule Catapult.Dsl.PredicateTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Predicate

  describe "comparison" do
    test "field == bare-word enum literal" do
      assert {:ok, {:compare, :eq, {:path, ["kind"]}, {:path, ["presentational"]}}} =
               Predicate.parse("kind == presentational")
    end

    test "every comparator" do
      for {op, expected} <- [
            {"==", :eq},
            {"!=", :neq},
            {"<", :lt},
            {">", :gt},
            {"<=", :lte},
            {">=", :gte}
          ] do
        assert {:ok, {:compare, ^expected, _left, {:literal, 1}}} = Predicate.parse("n #{op} 1")
      end
    end

    test "a bare field is a boolean field reference" do
      assert {:ok, {:field, ["is_domain"]}} = Predicate.parse("is_domain")
    end

    test "a dotted path is a field reference" do
      assert {:ok, {:field, ["self", "kind"]}} = Predicate.parse("self.kind")
    end
  end

  describe "boolean" do
    test "AND / OR / NOT with precedence: NOT > AND > OR" do
      assert {:ok, {:or, {:and, {:not, {:field, ["a"]}}, {:field, ["b"]}}, {:field, ["c"]}}} =
               Predicate.parse("NOT a AND b OR c")
    end

    test "parentheses override precedence" do
      assert {:ok, {:and, {:field, ["a"]}, {:or, {:field, ["b"]}, {:field, ["c"]}}}} =
               Predicate.parse("a AND (b OR c)")
    end
  end

  describe "edge counting" do
    test "has_edge(edge_name)" do
      assert {:ok, {:has_edge, "dependency"}} = Predicate.parse("has_edge(dependency)")
    end

    test "count(edge_name) op N" do
      assert {:ok, {:count, "dependency", :gte, 2}} = Predicate.parse("count(dependency) >= 2")
    end
  end

  describe "existential and universal" do
    test "exists(path where predicate)" do
      assert {:ok, {:exists, ["children"], {:field, ["ready"]}}} =
               Predicate.parse("exists(children where ready)")
    end

    test "all(path -> field)" do
      assert {:ok, {:all, ["children"], "ready"}} = Predicate.parse("all(children -> ready)")
    end

    test "any(path -> field)" do
      assert {:ok, {:any, ["children"], "ready"}} = Predicate.parse("any(children -> ready)")
    end
  end

  describe "reachability" do
    test "reaches(a, b)" do
      assert {:ok, {:reaches, "a", "b", via: []}} = Predicate.parse("reaches(a, b)")
    end

    test "reaches(a, b, via=[edge1, edge2])" do
      assert {:ok, {:reaches, "a", "b", via: ["edge1", "edge2"]}} =
               Predicate.parse("reaches(a, b, via=[edge1, edge2])")
    end
  end

  describe "not Turing-complete" do
    test "arithmetic is not part of the grammar" do
      assert {:error, _reason} = Predicate.parse("1 + 1 == 2")
    end

    test "trailing input is rejected" do
      assert {:error, reason} = Predicate.parse("a AND b )")
      assert reason =~ "trailing input"
    end

    test "unrecognized syntax is rejected" do
      assert {:error, _reason} = Predicate.parse("a === b")
    end
  end
end
