defmodule Catapult.Engine.Projections.PredicateEvaluatorTest do
  use Catapult.DataCase, async: true

  alias Catapult.Dsl.Predicate
  alias Catapult.Engine.Projections.PredicateEvaluator
  alias Catapult.Engine.Store

  # Every id this module writes is namespaced to it — see
  # ready_scopes_test.exs for why (shared `engine_nodes` table,
  # sandbox isolates visibility rather than row locks).
  @ns "predicate_evaluator"

  defp nid(nil), do: nil
  defp nid(id), do: @ns <> ":" <> id

  defp predicate!(raw) do
    {:ok, predicate} = Predicate.parse(raw)
    predicate
  end

  defp node!(id, tier, opts \\ []) do
    Store.upsert_node(%{
      id: nid(id),
      project_id: Keyword.get(opts, :project_id, "p1"),
      tier: tier,
      scope_key: Keyword.get(opts, :scope_key, %{}),
      parent_node_id: nid(Keyword.get(opts, :parent_node_id)),
      status: Keyword.get(opts, :status, :absent),
      fields: Keyword.get(opts, :fields, %{})
    })
  end

  defp edge!(name, type, source, target) do
    Store.insert_edge(%{
      id: name <> "|" <> source.id <> "|" <> target.id,
      project_id: source.project_id,
      edge_name: name,
      type: type,
      source_node_id: source.id,
      target_node_id: target.id
    })
  end

  describe "boolean field / comparison" do
    test "a bare field reads truthiness off the node's own fields" do
      truthy = node!("t", "comp", fields: %{"is_domain" => true}, scope_key: %{"n" => "t"})
      falsy = node!("f", "comp", fields: %{"is_domain" => false}, scope_key: %{"n" => "f"})
      absent = node!("a", "comp", scope_key: %{"n" => "a"})

      assert PredicateEvaluator.eval(predicate!("is_domain"), truthy)
      refute PredicateEvaluator.eval(predicate!("is_domain"), falsy)
      refute PredicateEvaluator.eval(predicate!("is_domain"), absent)
    end

    test "compares a field against a literal" do
      n = node!("n", "comp", fields: %{"kind" => "presentational"})

      assert PredicateEvaluator.eval(predicate!("kind == presentational"), n)
      refute PredicateEvaluator.eval(predicate!("kind == domain"), n)
    end

    test "AND / OR / NOT compose" do
      n = node!("n", "comp", fields: %{"a" => true, "b" => false})

      assert PredicateEvaluator.eval(predicate!("a AND NOT b"), n)
      refute PredicateEvaluator.eval(predicate!("a AND b"), n)
      assert PredicateEvaluator.eval(predicate!("a OR b"), n)
    end
  end

  describe "has_edge / count" do
    test "has_edge is true once an outgoing edge of that name exists" do
      comp = node!("comp1", "comp")
      resp = node!("resp1", "resp")

      refute PredicateEvaluator.eval(predicate!("has_edge(fulfills)"), comp)

      edge!("fulfills", :reference, comp, resp)

      assert PredicateEvaluator.eval(predicate!("has_edge(fulfills)"), comp)
    end

    test "count compares the number of outgoing edges of that name" do
      comp = node!("comp1", "comp")
      resp1 = node!("resp1", "resp", scope_key: %{"n" => "resp1"})
      resp2 = node!("resp2", "resp", scope_key: %{"n" => "resp2"})

      edge!("fulfills", :reference, comp, resp1)
      edge!("fulfills", :reference, comp, resp2)

      assert PredicateEvaluator.eval(predicate!("count(fulfills) == 2"), comp)
      refute PredicateEvaluator.eval(predicate!("count(fulfills) == 1"), comp)
      assert PredicateEvaluator.eval(predicate!("count(fulfills) > 1"), comp)
    end
  end

  describe "exists / all / any" do
    test "exists is true when some landed node satisfies the inner predicate" do
      comp = node!("comp1", "comp")
      resp_done = node!("resp1", "resp", fields: %{"done" => true}, scope_key: %{"n" => "resp1"})

      resp_pending =
        node!("resp2", "resp", fields: %{"done" => false}, scope_key: %{"n" => "resp2"})

      edge!("fulfills", :reference, comp, resp_done)
      edge!("fulfills", :reference, comp, resp_pending)

      assert PredicateEvaluator.eval(predicate!("exists(fulfills where done)"), comp)
      refute PredicateEvaluator.eval(predicate!("exists(fulfills where missing)"), comp)
    end

    test "all requires every landed node's field to be truthy, any requires just one" do
      comp = node!("comp1", "comp")

      resp1 =
        node!("resp1", "resp", fields: %{"approved" => true}, scope_key: %{"n" => "resp1"})

      resp2 =
        node!("resp2", "resp", fields: %{"approved" => false}, scope_key: %{"n" => "resp2"})

      edge!("fulfills", :reference, comp, resp1)
      edge!("fulfills", :reference, comp, resp2)

      refute PredicateEvaluator.eval(predicate!("all(fulfills -> approved)"), comp)
      assert PredicateEvaluator.eval(predicate!("any(fulfills -> approved)"), comp)
    end

    test "all is vacuously true over zero landed nodes" do
      comp = node!("comp1", "comp")
      assert PredicateEvaluator.eval(predicate!("all(fulfills -> approved)"), comp)
    end
  end

  describe "reaches" do
    test "true when a forward walk from a from_tier anchor reaches a to_tier node" do
      comp = node!("comp1", "comp")
      resp = node!("resp1", "resp")
      policy = node!("policy1", "policy")

      edge!("fulfills", :reference, comp, resp)
      edge!("policy_application", :policy_application, resp, policy)

      assert PredicateEvaluator.eval(predicate!("reaches(comp, policy)"), comp)
      refute PredicateEvaluator.eval(predicate!("reaches(comp, vocab)"), comp)
    end

    test "false when the anchor is not of the named from_tier" do
      resp = node!("resp1", "resp")
      refute PredicateEvaluator.eval(predicate!("reaches(comp, vocab)"), resp)
    end

    test "via restricts which edges the walk may follow" do
      comp = node!("comp1", "comp")
      resp = node!("resp1", "resp")
      policy = node!("policy1", "policy")

      edge!("fulfills", :reference, comp, resp)
      edge!("policy_application", :policy_application, resp, policy)

      # via restricts every hop of the walk, not just the first: reaching
      # policy from comp needs both edge names on offer.
      assert PredicateEvaluator.eval(
               predicate!("reaches(comp, policy, via=[fulfills, policy_application])"),
               comp
             )

      refute PredicateEvaluator.eval(predicate!("reaches(comp, policy, via=[fulfills])"), comp)

      refute PredicateEvaluator.eval(
               predicate!("reaches(comp, resp, via=[policy_application])"),
               comp
             )
    end
  end
end
