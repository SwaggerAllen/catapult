defmodule Catapult.Generation.CommitPathGraphConstraintTest do
  @moduledoc """
  `chain.md` #30 at the commit path (`systems/generation.md` #13): an
  edge's `graph_constraint` rejects a body whose own declared instances
  violate it, before the commit lands, with the typed error
  `report_result/2` answers 422 for.

  The toy seed's `sysarch` declares one `dependency`, `link_admin →
  redirector`; each case here adds one `<dep>` to that same body. The
  unmodified body commits in `ToySeedChainTest`, which is the case that
  shows the check does not reject an acyclic graph.

  This check had no caller before: `GraphConstraints` evaluated the
  same constraints in a projection nothing invoked, and its own tests
  built edge instances by hand, so the suite stayed green while no
  constraint was ever checked. These tests go through the real loader
  and the real extraction instead.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Dsl
  alias Catapult.Generation.CommitPath

  @sysarch File.read!(Path.join(__DIR__, "fixtures/toy_seed/sysarch.xml"))
  @declared ~s(    <dep from="link_admin" to="redirector"/>\n)

  setup do
    {:ok, %{chain: chain}} = Dsl.load(".")
    assert chain.edges["dependency"].graph_constraint == ["acyclic", "no_self_loop"]
    :ok
  end

  test "a body whose own dependencies close a cycle is rejected as acyclic" do
    body = with_dep(~s(    <dep from="redirector" to="link_admin"/>\n))

    assert {:error, {:graph_constraint_violated, %{edge: "dependency", constraint: "acyclic"}}} =
             commit(body)
  end

  test "a body declaring a dependency on itself is rejected as no_self_loop" do
    body = with_dep(~s(    <dep from="redirector" to="redirector"/>\n))

    assert {:error,
            {:graph_constraint_violated, %{edge: "dependency", constraint: "no_self_loop"}}} =
             commit(body)
  end

  defp with_dep(extra) do
    assert String.contains?(@sysarch, @declared), "the fixture no longer declares #{@declared}"
    String.replace(@sysarch, @declared, @declared <> extra)
  end

  defp commit(body) do
    project_id = "graph-constraint-#{System.unique_integer([:positive])}"

    CommitPath.handle_result(%{
      status: :success,
      body: body,
      credential_used: "stub",
      project_id: project_id,
      node_id: "sysarch:requirements:feature_expansion",
      tier: "sysarch",
      scope_key: %{"per" => "requirements:feature_expansion"},
      run_key: Ecto.UUID.generate()
    })
  end
end
