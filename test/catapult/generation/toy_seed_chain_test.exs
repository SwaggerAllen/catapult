defmodule Catapult.Generation.ToySeedChainTest do
  @moduledoc """
  Phase 3's exit criterion, made executable (ORC-10): the toy seed
  (`test/catapult/generation/fixtures/toy_seed/`, `Catapult.ToySeed`)
  drives every Initial-scope tier in `bundles/default` — every LLM
  generation tier and its review, every synthesis/join tier, `ref` —
  through the real commit path (grammar validation via `core_dsl`,
  extraction, the engine's event-sourced reducer), offline against
  `Catapult.Delivery.HostPort.Fake` (conventions §9: no network,
  deterministic, the default suite forever after). At least one
  instance of every edge type this bundle declares lands in the graph.

  **What "real" means here, and where it stops — read before editing.**
  `docs/non-goals.md`'s ORC-10 entry proved `input.<role>` resolves
  `{:error, :unsupported}` for every role, which `Catapult.Engine
  .Projections.ReadyScopes.ready?/2` treats as *not ready* (not the
  vacuous-pass dsl-syntax.md §7.2 promises) — so `feature_expansion`,
  the chain's one tier with an `input.*` context entry, can never be
  *selected* by the scheduler today. This test still drives it through
  the real generation/commit/validation path — `ContextAssembly.build/4`
  called directly against a hand-built candidate node, exactly the
  shape `ReadyScopes` would have handed the dispatch worker if
  readiness worked — because the mechanism being proven is dispatch and
  validation, not the scheduler's own selection query (already covered
  elsewhere; the gap is `ReadyScopes`'s, not this test's to paper over).

  Three more implementation gaps, each verified by hand against
  `Catapult.Generation.Extraction` before being worked around rather
  than assumed:

    * **Fanout mint identity.** `Extraction.mints/4`'s own moduledoc
      documents that a minted instance's identity resolves via an
      `id`/`alias` attribute fallback verified only for `sysarch`'s
      `<component alias="...">` — `resp` (from `<responsibility>`, no
      id/alias), `vocab` (from `<term>`, no id/alias) and `policy`
      (from `<policy>`, no id/alias) mint with a `nil` scope-key value
      instead. `comp` and `subcomp` mint for real here (both instance
      shapes carry `alias`); `resp`/`vocab`/`policy` are minted by this
      test directly via `Store.mint_node/1` + `Store.insert_edge/1` —
      the exact fanout edge a working extraction would have written —
      mirroring `Catapult.Generation.IntegrationTest`'s own precedent
      for `vocab` (ORC-9).
    * **Third-tier-authored edges.** `fulfills` (authored inside
      `sysarch`'s own draft, declaring `comp` as its edge source) and
      `dependency`/`policy_application` (`Extraction`'s own moduledoc
      names these two by example) all fail the same
      `instance.source == tier_name` filter — none is extracted from
      *any* draft today. Seeded directly, same shape as above.
    * **`ref`'s scope-key.** `ref` is `scope: singleton`, so a real
      dispatch commits it with `scope_key: %{}` — but `reference`-type
      edge resolution hardcodes a `%{"id" => value}` lookup
      (`Catapult.Generation.CommitPath.resolve_target/3`), which a
      singleton's `%{}` never matches. `ref` still drafts and validates
      for real; the one `reference` edge instance is seeded the same
      way as the mints above.

  None of these four are fixed here — `docs/non-goals.md`'s ORC-10
  entry and this ticket's own `Touches:` line both keep this ticket to
  `test/`, fixtures and `docs/`, and `Extraction`/`CommitPath` are
  ORC-9's already-reviewed work. Each is a real, load-bearing gap
  either way — recorded here, not quietly routed around, and named in
  this ticket's hand-back.

  `plan_target` (the sixth declared edge type) is not exercised: every
  instance is `cascade_visit`-scoped, and flow instances are
  `systems/engine.md`'s own Initial-vs-target "Target" line — there is
  no flow machinery yet for a toy seed to drive.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed

  ## -- canned draft/review bodies ------------------------------------

  @feature_expansion_body File.read!(
                            Path.join(__DIR__, "fixtures/toy_seed/feature_expansion.xml")
                          )
  @requirements_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/requirements.xml"))
  @sysarch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/sysarch.xml"))
  @comparch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/comparch.xml"))
  @subcomparch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/subcomparch.xml"))
  @impl_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/impl.xml"))
  @vocab_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/vocab.xml"))
  @ref_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/ref.xml"))
  @approve_review_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/review_approve.xml"))

  setup do
    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
  end

  test "the toy seed generates and validates through every tier, offline against the fake" do
    project_id = "toy-seed-#{System.unique_integer([:positive])}"
    {:ok, loaded} = Dsl.load(".")
    chain = loaded.chain

    # The fixture's repo-reset half exercises the same path a live run
    # would (systems/delivery.md's ORC-10 entry) — the fake's
    # `reset_repo/2` reaches no network, but the call is real.
    assert :ok = FakeHostPort.reset_repo(project_id, ToySeed.reset_files())

    # -- feature_expansion: bypasses ReadyScopes' own selection (see
    #    moduledoc), not the commit/validation mechanism itself. -------
    fe_candidate = %Node{
      id: "virtual:feature_expansion:#{inspect(%{})}",
      project_id: project_id,
      tier: "feature_expansion",
      scope_key: %{},
      parent_node_id: nil,
      status: :absent
    }

    fe = commit!(chain, project_id, "feature_expansion", fe_candidate, @feature_expansion_body)
    review!(chain, project_id, "feature_expansion_review", fe, @approve_review_body)
    approve_real!(project_id, fe.id, fe.current_draft_id)

    # -- requirements: organically ready (self.parent = feature_expansion, approved) --
    req = ready_one!(chain, project_id, "requirements")
    req = commit!(chain, project_id, "requirements", req, @requirements_body)
    review!(chain, project_id, "requirements_review", req, @approve_review_body)
    approve_real!(project_id, req.id, req.current_draft_id)

    # -- resp: requirements' own mint (decomposition), seeded — see moduledoc.
    #    `requirements.xml`'s own two `<responsibility>` blocks also drive
    #    the *organic* (broken) mint through the same commit, since
    #    `Extraction` cannot tell a `<responsibility>` apart from any
    #    other body content without an `id`/`alias` to key on — real,
    #    inert, and approved along with the two seeded here rather than
    #    left to dangle unapproved and block `sysarch`'s own forward
    #    `decomposition` walk (`Enum.all?` over every resolved target). --
    resp_redirect = seed_mint!(project_id, "resp", "redirect_resolution", req.id, "decomposition")
    resp_link = seed_mint!(project_id, "resp", "link_creation", req.id, "decomposition")

    for node <- Store.list_nodes(project_id, "resp"), do: Store.approve_node(project_id, node.id)

    # -- sysarch: organically ready (self.parent = requirements, approved;
    #    self.parent.decomposition -> resp.handle, both resps approved) --
    sysarch = ready_one!(chain, project_id, "sysarch")
    sysarch = commit!(chain, project_id, "sysarch", sysarch, @sysarch_body)
    review!(chain, project_id, "sysarch_review", sysarch, @approve_review_body)
    approve_real!(project_id, sysarch.id, sysarch.current_draft_id)

    # -- comp: sysarch's own mint, real extraction (both components
    #    carry `alias`, the one identity shape the fallback covers) --
    redirector = fetch_node!(project_id, "comp", %{"id" => "redirector"})
    link_admin = fetch_node!(project_id, "comp", %{"id" => "link_admin"})
    approve_real!(project_id, redirector.id, Ecto.UUID.generate())
    # link_admin stays unapproved on purpose — one branch is carried all
    # the way to `impl`, the other exists only to give `dependency` and
    # `fulfills` a second real node to point at (richness, not depth).

    seed_edge!(project_id, "fulfills", :reference, redirector.id, resp_redirect.id)
    seed_edge!(project_id, "fulfills", :reference, link_admin.id, resp_link.id)
    seed_edge!(project_id, "dependency", :dependency, link_admin.id, redirector.id)

    policy =
      seed_mint!(project_id, "policy", "immutable_short_codes", sysarch.id, "decomposition")

    seed_edge!(project_id, "policy_application", :policy_application, policy.id, resp_redirect.id)
    Store.approve_node(project_id, policy.id)

    # -- ref: context is empty, so ReadyScopes selects it unconditionally --
    ref = ready_one!(chain, project_id, "ref")
    ref = commit!(chain, project_id, "ref", ref, @ref_body)
    approve_real!(project_id, ref.id, ref.current_draft_id)

    # -- vocab: feature_expansion's own mint, seeded — see moduledoc --
    seed_mint!(project_id, "vocab", "short_code", fe.id, "decomposition")
    vocab = ready_one!(chain, project_id, "vocab")
    vocab = commit!(chain, project_id, "vocab", vocab, @vocab_body)
    review!(chain, project_id, "vocab_review", vocab, @approve_review_body)
    approve_real!(project_id, vocab.id, vocab.current_draft_id)

    # -- comparch: per(comp), only `redirector` approved -> exactly one ready scope --
    comparch = ready_one!(chain, project_id, "comparch")
    comparch = commit!(chain, project_id, "comparch", comparch, @comparch_body)
    review!(chain, project_id, "comparch_review", comparch, @approve_review_body)
    approve_real!(project_id, comparch.id, comparch.current_draft_id)

    # `reference`: comparch's own draft named `target="ref"`, but ref's
    # singleton scope-key defeats the real lookup (see moduledoc) —
    # seeded directly, standing in for what a matching lookup would
    # have written from that exact draft content.
    seed_edge!(project_id, "reference", :reference, comparch.id, ref.id)

    # -- subcomp: comparch's own mint, real extraction (`alias` again) --
    lookup_engine = fetch_node!(project_id, "subcomp", %{"id" => "lookup_engine"})
    cache_layer = fetch_node!(project_id, "subcomp", %{"id" => "cache_layer"})
    approve_real!(project_id, lookup_engine.id, Ecto.UUID.generate())
    # cache_layer stays unapproved — same reasoning as link_admin above.

    seed_edge!(project_id, "dependency", :dependency, cache_layer.id, lookup_engine.id)

    # -- subcomparch: per(subcomp), only `lookup_engine` approved --
    subcomparch = ready_one!(chain, project_id, "subcomparch")
    subcomparch = commit!(chain, project_id, "subcomparch", subcomparch, @subcomparch_body)
    review!(chain, project_id, "subcomparch_review", subcomparch, @approve_review_body)
    approve_real!(project_id, subcomparch.id, subcomparch.current_draft_id)

    # -- impl: per(subcomp), same one ready scope --
    impl = ready_one!(chain, project_id, "impl")
    impl = commit!(chain, project_id, "impl", impl, @impl_body)
    review!(chain, project_id, "impl_review", impl, @approve_review_body)
    approve_real!(project_id, impl.id, impl.current_draft_id)

    # -- every tier committed for real drafted (then approved) --
    for node <- [fe, req, sysarch, comparch, subcomparch, impl, vocab, ref] do
      committed = Store.get_node(project_id, node.id)
      assert committed.status == :approved
      assert is_binary(committed.body_sha)
    end

    for node <- [
          redirector,
          link_admin,
          lookup_engine,
          cache_layer,
          resp_redirect,
          resp_link,
          policy
        ] do
      assert Store.get_node(project_id, node.id)
    end

    # -- every declared edge type (bar `plan_target` — see moduledoc)
    #    has at least one instance in the graph --
    edge_names = for edge <- Map.values(chain.edges), do: edge.name
    assert "decomposition" in edge_names
    assert "dependency" in edge_names
    assert "fulfills" in edge_names
    assert "policy_application" in edge_names
    assert "reference" in edge_names

    assert Store.edges_from(project_id, sysarch.id, "decomposition") != []
    assert Store.edges_from(project_id, link_admin.id, "dependency") != []
    assert Store.edges_from(project_id, redirector.id, "fulfills") != []
    assert Store.edges_from(project_id, policy.id, "policy_application") != []
    assert Store.edges_from(project_id, comparch.id, "reference") != []
  end

  ## -- helpers --------------------------------------------------------

  # The one ready scope this call expects — every tier this test drives
  # organically has exactly one candidate ready at the point it's
  # called (asserted, not assumed: a second candidate here means the
  # toy seed's own state grew a branch this test didn't account for).
  defp ready_one!(chain, project_id, tier_name) do
    assert [node] = ReadyScopes.ready(chain, project_id, tier_name)
    node
  end

  # Dispatches `node` through the fake with `body` as the canned
  # result, and returns the freshly committed row — the real
  # commit/validation path (`Catapult.Generation.CommitPath`), offline.
  defp commit!(chain, project_id, tier_name, node, body) do
    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :success, body: body, credential_used: "claude_code_oauth_token"}
    end)

    assert {:ok, request} = ContextAssembly.build(chain, project_id, tier_name, node)
    assert {:ok, %{run_key: _}} = FakeHostPort.dispatch_run(request)

    committed = Store.get_node(project_id, request.node_id)
    assert committed.status == :drafted, "#{tier_name} did not commit: #{inspect(committed)}"
    committed
  end

  # Same shape as `commit!/5`, for a review tier: `node` is the
  # *reviewed* tier's own committed node (ReadyScopes.ready_review/3's
  # own contract), never the review tier's.
  defp review!(chain, project_id, review_tier_name, node, body) do
    Application.put_env(:catapult, :fake_dispatch_result, fn _request ->
      %{status: :success, body: body, credential_used: "claude_code_oauth_token"}
    end)

    assert {:ok, request} = ContextAssembly.build(chain, project_id, review_tier_name, node)
    assert {:ok, %{run_key: _}} = FakeHostPort.dispatch_run(request)
    :ok
  end

  # Real `ApproveDraft` dispatch — the same command a human/dashboard
  # approval takes (`Catapult.Engine.Commands.ApproveDraft`; nothing in
  # this codebase approves a node automatically yet, generation or
  # synthesis tier alike — `systems/engine.md`'s "creation is not
  # dispatchability" bullet describes minting, not this gap, which this
  # ticket found and works around rather than closes). `draft_id` is
  # real for a drafted node (its own `current_draft_id`) and synthetic
  # for a synthesis-tier node that never had one — `ApproveDraft`'s own
  # aggregate handling validates neither (see the command's moduledoc).
  defp approve_real!(project_id, node_id, draft_id) do
    cmd = %ApproveDraft{project_id: project_id, node_id: node_id, draft_id: draft_id}
    assert :ok = Router.dispatch(cmd, consistency: :strong)
  end

  # Stands in for a fanout mint `Catapult.Generation.Extraction` cannot
  # extract today (see moduledoc) — the exact node + edge shape
  # `Catapult.Engine.Reducer.apply_mint/2` would have written from a
  # working extraction.
  defp seed_mint!(project_id, tier, id_value, parent_node_id, edge_name) do
    node =
      Store.mint_node(%{
        id: "#{tier}:#{id_value}",
        project_id: project_id,
        tier: tier,
        scope_key: %{"id" => id_value},
        parent_node_id: parent_node_id,
        status: :absent
      })

    seed_edge!(project_id, edge_name, :fanout, parent_node_id, node.id)
    node
  end

  # Stands in for a declared (non-fanout) edge instance
  # `Catapult.Generation.Extraction` cannot extract today (see
  # moduledoc) — the exact row `Catapult.Engine.Reducer
  # .apply_declared_edge/2` would have written from a working
  # extraction.
  defp seed_edge!(project_id, edge_name, type, source_id, target_id) do
    Store.insert_edge(%{
      id: "#{edge_name}|#{source_id}|#{target_id}",
      project_id: project_id,
      edge_name: edge_name,
      type: type,
      source_node_id: source_id,
      target_node_id: target_id
    })
  end

  defp fetch_node!(project_id, tier, scope_key) do
    node = Store.get_node_by_scope(project_id, tier, scope_key)
    assert node, "expected a real #{tier} node at #{inspect(scope_key)}"
    node
  end
end
