defmodule Catapult.Generation.IntegrationTest do
  @moduledoc """
  The whole chain, offline (conventions §9): a ready scope dispatches
  through `Catapult.Delivery.HostPort.Fake`, which drives a canned
  body through the exact same commit path a real inbound result-report
  would — grammar validation, extraction, `CommitDraft` dispatch — with
  no network anywhere. Exercises the real `bundles/default` bundle,
  the same one the reference deployment runs.

  The last test (ORC-36) extends this same shape through the
  gate-review commands — `PostComment`, `DeclineGate`, and a second
  dispatch reading the regenerated context back — to prove the
  authoring loop end to end: a decline's comment reaches only its own
  node's regeneration, not a sibling's (`systems/generation.md`'s
  ORC-36 entry).
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Projections.CommentFeedback
  alias Catapult.Engine.Projections.GateComments
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Projections.RunFailures
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node
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

  test "a decline's comment reaches only its own node's regenerated context, not a sibling's" do
    project_id = "gen-e2e-decline-#{System.unique_integer([:positive])}"

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

    Store.mint_node(%{
      id: "vocab:billing",
      project_id: project_id,
      tier: "vocab",
      scope_key: %{"id" => "billing"},
      parent_node_id: "fe1",
      status: :absent
    })

    {:ok, loaded} = Dsl.load(".")
    chain = loaded.chain

    ready = ReadyScopes.ready(chain, project_id, "vocab")
    assert length(ready) == 2
    assert %Node{} = auth_candidate = Enum.find(ready, &(&1.id == "vocab:auth"))
    assert %Node{} = billing_candidate = Enum.find(ready, &(&1.id == "vocab:billing"))

    {_req, auth} = dispatch!(chain, project_id, "vocab", auth_candidate, @vocab_body)
    {_req, billing} = dispatch!(chain, project_id, "vocab", billing_candidate, @vocab_body)

    # -- a human reviews the batch on the document-review screen: one
    #    line comment against `vocab:auth`'s committed body, then a
    #    decline on the gate that scope sits behind (v5 §7.17). --
    comment = %PostComment{
      project_id: project_id,
      node_id: "vocab:auth",
      body_sha: auth.body_sha,
      author_id: "human-1",
      body: "tighten this definition",
      posted_at: ~U[2026-01-02 00:00:00Z]
    }

    assert :ok = Router.dispatch(comment, consistency: :strong)

    assert :ok =
             Router.dispatch(
               %OpenFlow{
                 project_id: project_id,
                 flow_id: "f1",
                 flow_name: "feature",
                 entry_node_id: "vocab:auth"
               },
               consistency: :strong
             )

    decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: GateComments.last_resolution_sequence(project_id, "ux-review"),
      node_id: "vocab:auth",
      body_sha: auth.body_sha
    }

    assert :ok = Router.dispatch(decline, consistency: :strong)

    # -- clears each node's pending-draft slot for a second commit
    #    (`Catapult.Engine.Aggregate`'s `:engine_draft_conflict` guard)
    #    — orthogonal to the gate decision above: `vocab:billing` was
    #    never declined and still needs this before it can redraft. --
    for n <- [auth, billing] do
      assert :ok =
               Router.dispatch(
                 %ApproveDraft{
                   project_id: project_id,
                   node_id: n.id,
                   draft_id: n.current_draft_id
                 },
                 consistency: :strong
               )
    end

    auth_regen_candidate = Store.get_node(project_id, "vocab:auth")
    billing_regen_candidate = Store.get_node(project_id, "vocab:billing")

    {auth_request, auth_regen} =
      dispatch!(chain, project_id, "vocab", auth_regen_candidate, @vocab_body)

    {billing_request, billing_regen} =
      dispatch!(chain, project_id, "vocab", billing_regen_candidate, @vocab_body)

    # -- the assertion that matters (ORC-36): the comment reaches *its
    #    own node's* regenerated context, not merely "some" regen —
    #    a sibling minted off the same parent, never declined, must
    #    regenerate with no feedback at all (`vocab.md.liquid`'s own
    #    `{% if feedback.size > 0 %}` guard is what makes this visible
    #    in the rendered prompt, the same mechanism `ContextAssemblyTest`
    #    already proves for a single node). --
    assert auth_request.rendered_prompt =~ "Revising against feedback"
    refute billing_request.rendered_prompt =~ "Revising against feedback"

    assert [%{body: "tighten this definition"}] =
             CommentFeedback.since_last_resolution(project_id, "vocab:auth")

    assert CommentFeedback.since_last_resolution(project_id, "vocab:billing") == []

    # -- and the regeneration actually landed: both nodes drafted
    #    again for real, through the real commit path. --
    assert auth_regen.status == :drafted
    assert billing_regen.status == :drafted
  end

  ## -- helpers --------------------------------------------------------

  # Dispatches `node` through the fake with `body` as the canned
  # result and returns `{request, committed_node}` — the exact
  # `ContextAssembly.build/4` request that was sent, alongside the
  # freshly committed row, so a caller can inspect what context a
  # regeneration actually saw as well as what it produced.
  defp dispatch!(chain, project_id, tier_name, node, body) do
    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :success, body: body, credential_used: "claude_code_oauth_token"}
    end)

    assert {:ok, request} = ContextAssembly.build(chain, project_id, tier_name, node)
    assert {:ok, %{run_key: _}} = FakeHostPort.dispatch_run(request)

    {request, Store.get_node(project_id, request.node_id)}
  end
end
