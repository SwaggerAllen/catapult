defmodule Catapult.Generation.IntegrationTest do
  @moduledoc """
  The whole chain, offline (conventions §9): a ready scope dispatches
  through `Catapult.Delivery.HostPort.Fake`, which drives a canned
  body through the exact same commit path a real inbound result-report
  would — grammar validation, extraction, `CommitDraft` dispatch — with
  no network anywhere. Exercises the real `bundles/default` bundle,
  the same one the reference deployment runs.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Projections.RunFailures
  alias Catapult.Engine.Store
  alias Catapult.Generation.ContextAssembly

  @vocab_body """
  <vocab-entry>
    <definition>Authentication mechanism for the service.</definition>
  </vocab-entry>
  """

  setup do
    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
  end

  test "a ready vocab scope dispatches through the fake port and commits" do
    project_id = "gen-e2e-#{System.unique_integer([:positive])}"

    Store.upsert_node(%{
      id: "fe1",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :approved,
      fields: %{}
    })

    Store.mint_node(%{
      id: "vocab:auth",
      project_id: project_id,
      tier: "vocab",
      scope_key: %{"id" => "auth"},
      parent_node_id: "fe1",
      status: :absent
    })

    {:ok, loaded} = Dsl.load(".")
    assert [node] = ReadyScopes.ready(loaded.chain, project_id, "vocab")

    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :success, body: @vocab_body, credential_used: "claude_code_oauth_token"}
    end)

    assert {:ok, request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
    assert request.root_tag == "vocab-entry"
    assert request.credential_name == "claude_code_oauth_token"

    assert {:ok, %{run_key: run_key}} = FakeHostPort.dispatch_run(request)

    committed = Store.get_node(project_id, "vocab:auth")
    assert committed.status == :drafted
    assert is_binary(committed.body_sha)

    run = DeliveryStore.get_dispatch_run(run_key)
    assert run.status == :completed

    assert Delivery.get_draft_body(project_id, "vocab:auth") == @vocab_body
  end

  test "a grammar-invalid body is rejected without committing" do
    project_id = "gen-e2e-invalid-#{System.unique_integer([:positive])}"

    Store.upsert_node(%{
      id: "fe1",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :approved,
      fields: %{}
    })

    Store.mint_node(%{
      id: "vocab:billing",
      project_id: project_id,
      tier: "vocab",
      scope_key: %{"id" => "billing"},
      parent_node_id: "fe1",
      status: :absent
    })

    {:ok, loaded} = Dsl.load(".")
    assert [node] = ReadyScopes.ready(loaded.chain, project_id, "vocab")

    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :success, body: "<vocab-entry><not-a-field/></vocab-entry>", credential_used: "x"}
    end)

    assert {:ok, request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
    assert {:ok, %{run_key: _run_key}} = FakeHostPort.dispatch_run(request)

    refute Store.get_node(project_id, "vocab:billing").status == :drafted
  end

  test "a limit-class failure is recorded and derivable via RunFailures" do
    project_id = "gen-e2e-limit-#{System.unique_integer([:positive])}"

    Store.upsert_node(%{
      id: "fe1",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :approved,
      fields: %{}
    })

    Store.mint_node(%{
      id: "vocab:rate",
      project_id: project_id,
      tier: "vocab",
      scope_key: %{"id" => "rate"},
      parent_node_id: "fe1",
      status: :absent
    })

    {:ok, loaded} = Dsl.load(".")
    assert [node] = ReadyScopes.ready(loaded.chain, project_id, "vocab")

    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :limit_class_failure, reason: "usage_limit", credential_used: "x"}
    end)

    assert {:ok, request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
    assert {:ok, %{run_key: _}} = FakeHostPort.dispatch_run(request)

    assert RunFailures.count_since_commit(project_id, "vocab:rate") ==
             1
  end
end
