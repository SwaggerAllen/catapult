defmodule Catapult.Generation.ContextAssemblyTest do
  @moduledoc """
  `feedback`/`prior_review` (ORC-34), against the real `bundles/default`
  bundle the reference deployment runs — `vocab.md.liquid`'s own `{% if
  feedback %}` guard is what proves the two are correctly left unset
  rather than rendered as an empty list/map (this module's own
  moduledoc: an always-present `feedback` would make that guard fire on
  every render, Liquid's empty-list-is-truthy gotcha).
  """

  use Catapult.DataCase, async: false

  alias Catapult.Dsl
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.OpenFlow
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Commands.WriteReview
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Generation.ContextAssembly
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    Sandbox.mode(Catapult.Repo, {:shared, self()})
    on_exit(fn -> Sandbox.mode(Catapult.Repo, :manual) end)
    :ok
  end

  defp seed_vocab_node(project_id, body_sha) do
    Store.upsert_node(%{
      id: "fe1",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :approved,
      fields: %{}
    })

    Router.dispatch(
      %CommitDraft{
        project_id: project_id,
        node_id: "vocab:auth",
        tier: "vocab",
        scope_key: %{"id" => "auth"},
        parent_node_id: "fe1",
        draft_id: "d-#{System.unique_integer([:positive])}",
        body_sha: body_sha,
        committed_at: ~U[2026-01-01 00:00:00Z],
        fields: %{"name" => "auth", "term_scope" => "project", "feature_name" => nil}
      },
      consistency: :strong
    )
  end

  test "no comment has landed: the prompt's own feedback guard doesn't fire" do
    project_id = "context-assembly-#{System.unique_integer([:positive])}"
    assert :ok = seed_vocab_node(project_id, "sha1")

    {:ok, loaded} = Dsl.load(".")
    node = Store.get_node(project_id, "vocab:auth")

    assert {:ok, request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
    refute request.rendered_prompt =~ "Revising against feedback"
  end

  test "a declined gate's comment renders into the prompt's own feedback section" do
    project_id = "context-assembly-#{System.unique_integer([:positive])}"
    assert :ok = seed_vocab_node(project_id, "sha1")

    comment = %PostComment{
      project_id: project_id,
      node_id: "vocab:auth",
      body_sha: "sha1",
      author_id: "human-1",
      body: "tighten this definition",
      posted_at: ~U[2026-01-02 00:00:00Z]
    }

    assert :ok = Router.dispatch(comment, consistency: :strong)

    # `Catapult.Delivery.FeatureLifecycle` starts a fresh instance for
    # this `flow_id` on the decline below regardless (Commanded's own
    # `{:continue, id}` semantics); one that never applied `FlowOpened`
    # would persist a row with no `project_id`, which the store's
    # composite primary key rejects. Opened for real here so that
    # doesn't happen.
    open = %OpenFlow{
      project_id: project_id,
      flow_id: "f1",
      flow_name: "feature",
      entry_node_id: "vocab:auth"
    }

    assert :ok = Router.dispatch(open, consistency: :strong)

    decline = %DeclineGate{
      project_id: project_id,
      flow_id: "f1",
      gate: "ux-review",
      throwback_to: "pending",
      since_sequence: nil,
      node_id: "vocab:auth",
      body_sha: "sha1"
    }

    assert :ok = Router.dispatch(decline, consistency: :strong)

    {:ok, loaded} = Dsl.load(".")
    node = Store.get_node(project_id, "vocab:auth")

    assert {:ok, request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
    assert request.rendered_prompt =~ "Revising against feedback"
  end

  test "a prior review doesn't crash rendering, even though no shipped prompt shows it yet" do
    project_id = "context-assembly-#{System.unique_integer([:positive])}"
    assert :ok = seed_vocab_node(project_id, "sha1")

    node = Store.get_node(project_id, "vocab:auth")

    review = %WriteReview{
      project_id: project_id,
      draft_id: node.current_draft_id,
      review_id: "review-1",
      score: 90,
      body_sha: "sha1",
      findings: [],
      kind: :human
    }

    assert :ok = Router.dispatch(review, consistency: :strong)
    assert %{score: 90} = Store.reviews_for_node(project_id, "vocab:auth")

    {:ok, loaded} = Dsl.load(".")
    assert {:ok, _request} = ContextAssembly.build(loaded.chain, project_id, "vocab", node)
  end
end
