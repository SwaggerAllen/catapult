defmodule Catapult.Generation.ContextAssemblyTest do
  @moduledoc """
  `feedback`/`prior_review` (ORC-34), against the real `bundles/default`
  bundle the reference deployment runs — `vocab.md.liquid` renders the
  shared `partials/_architecture_framing` with `feedback: feedback`
  (ORC-193), and that partial's own `{% if feedback.size > 0 %}` guard
  is what proves the two are correctly left unset rather than rendered
  as an empty list/map. The guard tests `.size > 0` rather than bare
  truthiness precisely because Liquid treats an empty list as truthy
  (ORC-134, `systems/platform_content.md`'s entry) — so
  `ContextAssembly` leaving `feedback` unset on `[]` is what the tests
  below exercise, not what the guard alone depends on to stay closed.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
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

  # `ContextAssembly.build/4` can only produce two of these three
  # shapes — `feedback_variable/3` (see this module's own moduledoc)
  # never sets `feedback: []`, only omits the key or sets it populated
  # — so the `[]` shape can't be driven through the full event-sourced
  # path the tests above use. This renders the four `.size > 0` guards
  # directly through `Solid.parse/1` + `Solid.render/3` against the
  # real `bundles/default/prompts` tree, the same two calls
  # `ContextAssembly`'s own (private) `parse_template/1` and
  # `render/3` make, to exercise the `[]` shape at arm's length and
  # cover the shared partial and the three tiers that still carry
  # their own copy — `vocab` and `ref` lost theirs at ORC-193, once
  # the partial started reaching them correctly
  # (`systems/platform_content.md`'s ORC-134/ORC-193 entries).
  test "the four {% if feedback.size > 0 %} guards hold across all three feedback shapes" do
    prompts_root = Path.join(["bundles", "default", "prompts"])
    file_system = Solid.LocalFileSystem.new(prompts_root, "%s.md.liquid")

    guarded_templates = ~w(partials/_architecture_framing sysarch comparch subcomparch)

    shapes = [
      {"omitted", %{}},
      {"[]", %{"feedback" => []}},
      {"populated", %{"feedback" => [%{"body" => "tighten this definition"}]}}
    ]

    for name <- guarded_templates, {label, variables} <- shapes do
      {:ok, template} =
        prompts_root |> Path.join("#{name}.md.liquid") |> File.read!() |> Solid.parse()

      assert {:ok, iolist, []} =
               Solid.render(template, variables,
                 file_system: {Solid.LocalFileSystem, file_system}
               )

      rendered = IO.iodata_to_binary(iolist)

      case label do
        "populated" ->
          assert rendered =~ "Revising against feedback",
                 "#{name}.md.liquid should render its feedback section for #{label} feedback"

          if name == "partials/_architecture_framing" do
            assert rendered =~ "tighten this definition",
                   "the shared partial's {% for entry in feedback %} loop should render " <>
                     "each entry's body, not a bare {{ feedback }} interpolation"
          end

        _ ->
          refute rendered =~ "Revising against feedback",
                 "#{name}.md.liquid should not render its feedback section for #{label} feedback"
      end
    end
  end

  # `partials/_review_framing` is rendered by all eight
  # `review/<tier>.md.liquid` prompts and, until ORC-201, was rendered
  # bare — so `draft` never entered its scope and it said "the draft
  # below" above nothing. This drives the partial directly, the same
  # two calls the guard test above makes, because the assertion is
  # about what the partial does with the variables rather than about
  # which caller supplies them.
  test "_review_framing renders the draft and the prior review it is passed (ORC-201)" do
    prompts_root = Path.join(["bundles", "default", "prompts"])
    file_system = Solid.LocalFileSystem.new(prompts_root, "%s.md.liquid")

    variables = %{
      "draft" => "<vocab><definition>the draft body</definition></vocab>",
      "prior_review" => %{
        "score" => 42,
        "kind" => "ai",
        "body_sha" => "sha1",
        # String-keyed, matching what a jsonb round trip returns: the
        # write path builds these atom-keyed and the column is
        # `{:array, :map}`, so `%{id: "f1"}` reads back `%{"id" => "f1"}`.
        "findings" => [%{"id" => "f1", "message" => "the prior finding"}]
      }
    }

    {:ok, template} =
      prompts_root
      |> Path.join("partials/_review_framing.md.liquid")
      |> File.read!()
      |> Solid.parse()

    assert {:ok, iolist, []} =
             Solid.render(template, variables, file_system: {Solid.LocalFileSystem, file_system})

    rendered = IO.iodata_to_binary(iolist)

    assert rendered =~ "the draft body",
           "the partial says 'the draft below' and must actually render {{ draft }}"

    assert rendered =~ "42", "the prior review's score should reach the reviewer"

    assert rendered =~ "the prior finding",
           "the {% for entry in prior_review.findings %} loop should render each entry's " <>
             "message, not a bare {{ prior_review.findings }} interpolation"

    assert rendered =~ "f1", "each prior finding's own id should reach the reviewer"
  end

  test "_review_framing omits the prior-review section when there is none (ORC-201)" do
    prompts_root = Path.join(["bundles", "default", "prompts"])
    file_system = Solid.LocalFileSystem.new(prompts_root, "%s.md.liquid")

    {:ok, template} =
      prompts_root
      |> Path.join("partials/_review_framing.md.liquid")
      |> File.read!()
      |> Solid.parse()

    # `prior_review_variable/3` omits the key entirely rather than
    # setting it empty, and a map is not a list — so a bare truthiness
    # guard is right here, unlike `feedback`'s `.size > 0` (ORC-134).
    assert {:ok, iolist, []} =
             Solid.render(template, %{"draft" => "body"},
               file_system: {Solid.LocalFileSystem, file_system}
             )

    refute IO.iodata_to_binary(iolist) =~ "The prior review of this draft"
  end

  # `feature_expansion` is `bundles/default`'s one tier with an
  # `input.<role>` context entry (`context: - input.project_doc`) — the
  # direct-delivery-read path `ContextAssembly`'s own moduledoc
  # describes (ORC-107), never `ContextResolver`'s node-collection
  # fold, which resolves every `input.*` walk `{:ok, []}` regardless.
  defp seed_feature_expansion_node(project_id) do
    Store.upsert_node(%{
      id: "feature_expansion:root",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      status: :absent
    })
  end

  test "input.project_doc renders as a plain string once pinned (ORC-107)" do
    project_id = "context-assembly-#{System.unique_integer([:positive])}"
    seed_feature_expansion_node(project_id)

    Delivery.pin_input_documents(project_id, "sha1", %{
      "project_doc.md" => "Signpost is an internal link-shortening service."
    })

    {:ok, loaded} = Dsl.load(".")
    node = Store.get_node(project_id, "feature_expansion:root")

    assert {:ok, request} =
             ContextAssembly.build(loaded.chain, project_id, "feature_expansion", node)

    assert request.rendered_prompt =~ "Signpost is an internal link-shortening service."
  end

  test "a role with no pinned documents is left out of the prompt entirely" do
    project_id = "context-assembly-#{System.unique_integer([:positive])}"
    seed_feature_expansion_node(project_id)

    {:ok, loaded} = Dsl.load(".")
    node = Store.get_node(project_id, "feature_expansion:root")

    assert {:ok, request} =
             ContextAssembly.build(loaded.chain, project_id, "feature_expansion", node)

    refute request.rendered_prompt =~ "Signpost"
  end

  test "a prior review doesn't crash rendering end to end" do
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
