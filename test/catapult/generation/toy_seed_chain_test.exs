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
  `systems/generation.md`'s old ORC-10 entry proved `input.<role>`
  resolved `{:error, :unsupported}` for every role, which
  `Catapult.Engine.Projections.ReadyScopes.ready?/2` treated as *not
  ready* rather than the vacuous pass `chain.md` #22 warns of — so
  `feature_expansion`, the chain's one tier with an `input.project_doc`
  context entry, could never be *selected* by the scheduler. ORC-107
  closed that gap: `Catapult.Engine.Projections.ContextResolver`
  resolves every `input.<role>`/`input.*` walk `{:ok, []}` now, always
  (`systems/engine.md`'s ORC-107 entry), so `feature_expansion` is
  organically ready the moment it exists — this test drives it through
  `ready_one!/3` exactly like every other tier below, no hand-built
  virtual candidate needed anymore. Intake itself is exercised for
  real too, ahead of that first `ready_one!/3` call: the fake forge is
  seeded with the same fixture content a real `reset_repo/2` would
  have written to the bound repo, and `Catapult.Delivery.intake_raft/2`
  pins it from there — the one assertion below that reaches
  `Catapult.Generation.ContextAssembly`'s direct-delivery-read step
  (`systems/generation.md`'s ORC-107 entry) checks the rendered
  `feature_expansion` prompt carries `project_doc`'s own pinned text.

  **ORC-236 closes the two extraction gaps this file used to route
  around by hand-seeding.** `fulfills` (authored inside `sysarch`'s own
  draft, declaring `comp` as its edge source), `dependency` (comp<->comp
  and subcomp<->subcomp, both declared a level above the tier they
  connect) and `policy_application` (a mint-time marker, not a second
  draft) all extract for real now, via `Catapult.Dsl.EdgeLocator`'s
  five-locator resolution (`chain.md` #27) — this test no longer
  seeds any of the three; it asserts they land from the toy seed's own
  fixture content instead (`sysarch.xml`'s own `<dep>`/`<resp>`/
  `<required>` elements, `comparch.xml`'s own `<structural/>` policy and
  `<reference target="ref"/>`). `ref` itself is `scope: reference`/
  `generator: reference` now (`docs/v5-design-decisions.md` §4.5,
  ORC-236): purely tool-authored, no draft, no dispatch — this test
  creates it the same way any write path outside the chain would,
  directly via `Store.mint_node/1`, before `comparch` commits and cites
  it for real.

  **One gap remains, unfixed by ORC-236 and out of its stated scope**
  (`Extraction`'s own moduledoc): a minted instance's identity resolves
  via an `id`/`alias` attribute fallback verified only for `sysarch`'s
  `<component alias="...">` — `resp` (from `<responsibility>`, no
  id/alias), `vocab` (from `<term>`, no id/alias), `policy` (from
  `<policy>`, no id/alias) and `screen` (from `<screen>`, no id/alias
  either) mint with a `nil` identity value instead. `comp` and
  `subcomp` mint for real here (both instance shapes carry `alias`);
  `resp`/`vocab`/`policy`/`screen`/`journey` are minted by this test
  directly via `Store.mint_node/1` + `Store.insert_edge/1` — the exact
  fanout edge a working extraction would have written — mirroring
  `Catapult.Generation.IntegrationTest`'s own precedent for `vocab`
  (ORC-9). A same-tier `dependency`/`reference` locator whose sibling's
  identity is one of these broken ones resolves `nil` rather than a
  dangling id pointed at a node the real mint will never produce
  (`Catapult.Generation.Extraction.resolve_sibling/6`) — checked here
  by the toy seed's own `screens.xml` fixture, which declares a real
  `<navigation>` block between two identity-broken screens: the edge is
  silently dropped, not a crash, and asserted absent below.

  **A fifth gap, unlike the two above, is what this pass fixes
  (ORC-117).** A join-target tier (no `draft:` — `comp`/`subcomp`/
  `resp`/`policy`) has no commit path of its own, so nothing could
  ever move it off whatever status it minted at; minted at `:absent`
  (the old default), `Catapult.Engine.Projections.ReadyScopes
  .walk_ready?/2`'s `status == :approved` could never turn true for
  it, and the chain stalled at the first join target forever. This
  test used to fabricate the missing approval three ways — `resp` by a
  bare `Store.approve_node/2` loop, `comp`/`subcomp` by dispatching
  `ApproveDraft` against an `Ecto.UUID.generate()` draft id that named
  no real draft. `Extraction.mints/6` and `Catapult.Engine.Reducer
  .apply_mint/2` now mint a join target straight to `:approved`
  (`systems/engine.md`'s ORC-117 entry), so none of the three is
  needed: `comp` and `subcomp` arrive approved through the same real
  extraction path as before, and `seed_mint!`'s `status:` argument
  (below) mirrors that same rule for the joins this test still seeds
  by hand.

  **What mint-time approval changes about "one ready scope."** Before
  this fix, only an explicitly-approved comp/subcomp let its `per(X)`
  child (`comparch`/`subcomparch`/`impl_backend`) become ready, which is what
  let this test single out one sibling of `redirector`/`link_admin`
  (and `lookup_engine`/`cache_layer`) to carry forward while the other
  sat unapproved as `dependency`/`fulfills` richness. A join target
  minting straight to `:approved` erases that asymmetry: both siblings
  of every pair are ready at once, for real, the moment their parent
  commits. This test still drives only one branch to `impl_backend` — a
  scheduler picking one of several ready scopes is an ordinary dispatch
  decision, not a fabrication — via `ready_matching!/4` rather than
  `ready_one!/3`, which would now fail on the second, equally-real
  candidate.

  `plan_target` (the sixth declared edge type) is not exercised: every
  instance is `cascade_visit`-scoped, and flow instances are
  `systems/engine.md`'s own Initial-vs-target "Target" line — there is
  no flow machinery yet for a toy seed to drive.
  """

  use Catapult.DataCase, async: false

  alias Catapult.Delivery
  alias Catapult.Delivery.HostPort.Fake, as: FakeHostPort
  alias Catapult.Delivery.HostPort.Fake.Forge
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ApproveDraft
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Generation.ContextAssembly
  alias Catapult.ToySeed

  ## -- canned draft/review bodies ------------------------------------

  @project_doc_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/project_doc.md"))
  @feature_expansion_body File.read!(
                            Path.join(__DIR__, "fixtures/toy_seed/feature_expansion.xml")
                          )
  @journeys_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/journeys.xml"))
  @screens_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/screens.xml"))
  @requirements_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/requirements.xml"))
  @sysarch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/sysarch.xml"))
  @comparch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/comparch.xml"))
  @subcomparch_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/subcomparch.xml"))
  @impl_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/impl.xml"))
  @vocab_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/vocab.xml"))
  @approve_review_body File.read!(Path.join(__DIR__, "fixtures/toy_seed/review_approve.xml"))

  setup do
    on_exit(fn -> Application.delete_env(:catapult, :fake_dispatch_result) end)
  end

  test "the toy seed generates and validates through every tier, offline against the fake" do
    project_id = "toy-seed-#{System.unique_integer([:positive])}"
    {:ok, loaded} = Dsl.load(".")
    chain = loaded.chain

    {:ok, _pid} = start_supervised({Forge, name: Forge})

    # The fixture's repo-reset half exercises the same path a live run
    # would (systems/delivery.md's ORC-10 entry) — the fake's
    # `reset_repo/2` reaches no network, but the call is real.
    assert {:ok, _ref} = FakeHostPort.reset_repo(project_id, ToySeed.reset_files())

    # -- intake: seed the forge with the same fixture content a real
    #    `reset_repo/2` would have written to the bound repo (the
    #    fake's own `reset_repo/2` is a no-op — see `HostPort.Fake`'s
    #    moduledoc), then pin it for real through the production
    #    intake path (ORC-107, systems/delivery.md). --
    Forge.seed_branch(Forge, "main", ToySeed.reset_files())
    assert :ok = Delivery.intake_raft(project_id, "main")

    # -- feature_expansion: organically ready now that `input.project_doc`
    #    resolves `{:ok, []}` (ORC-107 — see moduledoc). --------------
    fe_candidate = ready_one!(chain, project_id, "feature_expansion")

    assert {:ok, fe_request} =
             ContextAssembly.build(chain, project_id, "feature_expansion", fe_candidate)

    assert fe_request.rendered_prompt =~ @project_doc_body

    fe = commit!(chain, project_id, "feature_expansion", fe_candidate, @feature_expansion_body)
    review!(chain, project_id, "feature_expansion_review", fe, @approve_review_body)
    approve_real!(project_id, fe.id, fe.current_draft_id)

    # -- journeys: organically ready (self.parent = feature_expansion,
    #    approved) — dispatched ahead of requirements now that
    #    `all.journey.handle` gates on it for real (ORC-235,
    #    systems/engine.md: an `all.<tier>` walk is no longer vacuously
    #    satisfied by an as-yet-undrafted tier). --
    journeys = ready_one!(chain, project_id, "journeys")
    journeys = commit!(chain, project_id, "journeys", journeys, @journeys_body)
    review!(chain, project_id, "journeys_review", journeys, @approve_review_body)
    approve_real!(project_id, journeys.id, journeys.current_draft_id)

    # -- journey: journeys' own mint, seeded — see moduledoc (`<journey>`
    #    carries no id/alias, the same fanout-mint-identity gap
    #    resp/vocab/policy already carry). Seeded `:approved`, the
    #    ORC-117 join-target mint rule. --
    seed_mint!(
      project_id,
      "journey",
      "create_and_monitor",
      journeys.id,
      "decomposition",
      :approved
    )

    # -- screens: organically ready once `all.journey.handle` is
    #    drained (journeys approved, its one journey settled — ORC-235).
    #    Before this fix this tier was organically ready alongside
    #    journeys itself, off the identical vacuous-`all.<tier>` bug. --
    screens = ready_one!(chain, project_id, "screens")
    screens = commit!(chain, project_id, "screens", screens, @screens_body)
    review!(chain, project_id, "screens_review", screens, @approve_review_body)
    approve_real!(project_id, screens.id, screens.current_draft_id)

    # -- screen: screens' own mint, seeded — same identity gap as journey. --
    seed_mint!(project_id, "screen", "link_list", screens.id, "decomposition", :approved)
    seed_mint!(project_id, "screen", "link_create", screens.id, "decomposition", :approved)

    # -- requirements: organically ready once `all.journey.handle` AND
    #    `all.screen.handle` are both drained (ORC-235 — before this
    #    fix, requirements was organically ready right after
    #    feature_expansion alone, the vacuous-`all.<tier>` bug this
    #    ticket fixes). --
    req = ready_one!(chain, project_id, "requirements")
    req = commit!(chain, project_id, "requirements", req, @requirements_body)
    review!(chain, project_id, "requirements_review", req, @approve_review_body)
    approve_real!(project_id, req.id, req.current_draft_id)

    # -- resp: requirements' own mint (decomposition), seeded — see moduledoc.
    #    `requirements.xml`'s own two `<responsibility>` blocks also drive
    #    the *organic* (broken) mint through the same commit, since
    #    `Extraction` cannot tell a `<responsibility>` apart from any
    #    other body content without an `id`/`alias` to key on — real and
    #    inert either way. Seeded at `:approved`, mirroring the status a
    #    working extraction now mints a join target at (ORC-117) rather
    #    than reaching for a separate approval step. --
    resp_redirect =
      seed_mint!(project_id, "resp", "redirect_resolution", req.id, "decomposition", :approved)

    resp_link =
      seed_mint!(project_id, "resp", "link_creation", req.id, "decomposition", :approved)

    # -- sysarch: organically ready (self.parent = requirements, approved;
    #    self.parent.decomposition -> resp.handle, both resps approved) --
    sysarch = ready_one!(chain, project_id, "sysarch")
    sysarch = commit!(chain, project_id, "sysarch", sysarch, @sysarch_body)
    review!(chain, project_id, "sysarch_review", sysarch, @approve_review_body)
    approve_real!(project_id, sysarch.id, sysarch.current_draft_id)

    # -- comp: sysarch's own mint, real extraction (both components
    #    carry `alias`, the one identity shape the fallback covers) —
    #    both arrive already `:approved` (ORC-117: a join target mints
    #    straight there, ready is not asymmetric between siblings). This
    #    test still carries only `redirector` all the way to `impl_backend`;
    #    `link_admin` is real and equally ready, and is used only to
    #    give `dependency`/`fulfills` a second real node to point at
    #    (richness, not depth) — see `ready_matching!/4` below. --
    # `fulfills` (comp -> resp, declared inside sysarch's own draft) and
    # `dependency` (comp <-> comp, declared a level above the tier it
    # connects) both extract for real now, off the exact `sysarch.xml`
    # content seed_edge! used to stand in for: `redirector`'s own
    # `<resp id="redirect_resolution"/>`, `link_admin`'s own
    # `<resp id="link_creation"/>`, and `<dep from="link_admin"
    # to="redirector"/>` (`Catapult.Dsl.EdgeLocator`, `chain.md`
    # #27) — asserted below rather than fabricated.
    redirector = fetch_node!(project_id, "comp", %{"id" => "redirector"})
    link_admin = fetch_node!(project_id, "comp", %{"id" => "link_admin"})

    # -- policy: sysarch's own mint (decomposition), seeded — `policy`'s
    #    identity extraction is the same documented gap as resp/vocab
    #    (see moduledoc): the sysarch draft's own `<policy>` element
    #    mints organically too, but with a broken (`nil`) identity, so
    #    this test still seeds a properly-identified stand-in and its
    #    `policy_application` edge rather than assert against the
    #    organic, unaddressable one. --
    policy =
      seed_mint!(
        project_id,
        "policy",
        "immutable_short_codes",
        sysarch.id,
        "decomposition",
        :approved
      )

    seed_edge!(project_id, "policy_application", :policy_application, policy.id, resp_redirect.id)

    # -- ref: `scope: reference`/`generator: reference` (ORC-236) — no
    #    draft, no dispatch, created directly the way any write path
    #    outside the chain would (`docs/v5-design-decisions.md` §4.5) —
    #    `id: "ref"` matches `comparch.xml`'s own `<reference
    #    target="ref"/>` so the real `reference` edge extraction below
    #    resolves it, rather than seeding that edge by hand. Settled
    #    unconditionally the moment it exists (`ReadyScopes.settled?/3`'s
    #    `generator: "reference"` clause), so nothing here approves it. --
    ref =
      Store.mint_node(%{
        id: "ref:ref",
        project_id: project_id,
        tier: "ref",
        scope_key: %{"id" => "ref"},
        status: :approved,
        fields: %{
          "title" => "No blocking calls in the redirect path",
          "body" =>
            "The redirect path must never issue a blocking call — see sysarch's own policy of the same name."
        }
      })

    # -- vocab: feature_expansion's own mint, seeded — see moduledoc --
    seed_mint!(project_id, "vocab", "short_code", fe.id, "decomposition")
    vocab = ready_one!(chain, project_id, "vocab")
    vocab = commit!(chain, project_id, "vocab", vocab, @vocab_body)
    review!(chain, project_id, "vocab_review", vocab, @approve_review_body)
    approve_real!(project_id, vocab.id, vocab.current_draft_id)

    # -- comparch: per(comp) — both `redirector` and `link_admin` are
    #    ready (both approved at mint), so pick the `redirector` scope
    #    deliberately rather than asserting there is only one (see
    #    moduledoc's "one ready scope" note). --
    comparch = ready_matching!(chain, project_id, "comparch", redirector.id)
    comparch = commit!(chain, project_id, "comparch", comparch, @comparch_body)
    review!(chain, project_id, "comparch_review", comparch, @approve_review_body)
    approve_real!(project_id, comparch.id, comparch.current_draft_id)

    # -- subcomp: comparch's own mint, real extraction (`alias` again) —
    #    both arrive already `:approved`, same reasoning as `comp` above.
    #    `cache_layer` gets the same "richness, not depth" treatment as
    #    `link_admin`. `subcomp <-> subcomp` dependency (`cache_layer`
    #    depends on `lookup_engine`) and `reference` (comparch's own
    #    `target="ref"`) both extract for real too, off `comparch.xml`'s
    #    own `<sub-dependencies>`/`<references>` content. --
    lookup_engine = fetch_node!(project_id, "subcomp", %{"id" => "lookup_engine"})
    cache_layer = fetch_node!(project_id, "subcomp", %{"id" => "cache_layer"})

    # -- subcomparch: per(subcomp) — both subcomps are ready; pick
    #    `lookup_engine`'s scope deliberately, same reasoning as comparch. --
    subcomparch = ready_matching!(chain, project_id, "subcomparch", lookup_engine.id)
    subcomparch = commit!(chain, project_id, "subcomparch", subcomparch, @subcomparch_body)
    review!(chain, project_id, "subcomparch_review", subcomparch, @approve_review_body)
    approve_real!(project_id, subcomparch.id, subcomparch.current_draft_id)

    # -- impl_backend: per(subcomp), same two-ready-scopes shape as subcomparch --
    impl = ready_matching!(chain, project_id, "impl_backend", lookup_engine.id)
    impl = commit!(chain, project_id, "impl_backend", impl, @impl_body)
    review!(chain, project_id, "impl_backend_review", impl, @approve_review_body)
    approve_real!(project_id, impl.id, impl.current_draft_id)

    # -- every generation-tier node committed for real drafted (then approved) --
    for node <- [fe, req, sysarch, comparch, subcomparch, impl, vocab] do
      committed = Store.get_node(project_id, node.id)
      assert committed.status == :approved
      assert is_binary(committed.body_sha)
    end

    # -- ref: never drafted (scope: reference has no draft: at all,
    #    ORC-236), settled unconditionally, its write-path payload
    #    intact. --
    committed_ref = Store.get_node(project_id, ref.id)
    assert committed_ref.status == :approved
    assert is_nil(committed_ref.body_sha)
    assert committed_ref.fields["title"] == "No blocking calls in the redirect path"

    # -- every join-target node arrives `:approved` at mint, with no
    #    approval step of its own (ORC-117 — this loop is the guard: it
    #    fails the way it used to before the fix, back when these nodes
    #    minted `:absent` and nothing could ever move them off it). --
    for node <- [
          redirector,
          link_admin,
          lookup_engine,
          cache_layer,
          resp_redirect,
          resp_link,
          policy
        ] do
      committed = Store.get_node(project_id, node.id)
      assert committed, "expected #{node.id} to exist"
      assert committed.status == :approved
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

  # For a `per(X)` tier where a join-target `X` mints straight to
  # `:approved` (ORC-117), every sibling scoped off it is ready at
  # once — `comparch`/`subcomparch`/`impl_backend` below each have two ready
  # candidates once both siblings exist. This picks the one scoped to
  # `parent_id` deliberately (a scheduler choosing which of several
  # real ready scopes to dispatch next), rather than asserting away
  # the second, equally-real one the way `ready_one!/3` would.
  defp ready_matching!(chain, project_id, tier_name, parent_id) do
    ready = ReadyScopes.ready(chain, project_id, tier_name)

    assert node = Enum.find(ready, &(&1.scope_key["per"] == parent_id)),
           "expected a ready #{tier_name} scope for parent #{parent_id}, got #{inspect(ready)}"

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
  # approval takes (`Catapult.Engine.Commands.ApproveDraft`). Every
  # caller here is a generation-tier node with a real `current_draft_id`
  # — a synthesis/join-target node needs no approval of its own since
  # ORC-117 (it mints `:approved` directly, see `seed_mint!/6` and
  # `Catapult.Generation.Extraction.mints/4`).
  defp approve_real!(project_id, node_id, draft_id) do
    cmd = %ApproveDraft{project_id: project_id, node_id: node_id, draft_id: draft_id}
    assert :ok = Router.dispatch(cmd, consistency: :strong)
  end

  # Stands in for a fanout mint `Catapult.Generation.Extraction` cannot
  # extract today (see moduledoc) — the exact node + edge shape
  # `Catapult.Engine.Reducer.apply_mint/2` would have written from a
  # working extraction, `status:` included: `:approved` for a
  # join-target tier (`resp`/`policy` here — ORC-117), `:absent` for a
  # tier with its own `draft:` (`vocab`), matching
  # `Catapult.Generation.Extraction.mints/4`'s own rule rather than
  # picking a value independently of it.
  defp seed_mint!(project_id, tier, id_value, parent_node_id, edge_name, status \\ :absent) do
    node =
      Store.mint_node(%{
        id: "#{tier}:#{id_value}",
        project_id: project_id,
        tier: tier,
        scope_key: %{"id" => id_value},
        parent_node_id: parent_node_id,
        status: status
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
