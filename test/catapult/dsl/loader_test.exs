defmodule Catapult.Dsl.LoaderTest do
  use ExUnit.Case, async: true

  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.Fixture
  alias Catapult.Dsl.Loader
  alias Catapult.Dsl.SystemStatus

  @moduletag :tmp_dir

  test "loads a minimal, valid chain + workflow bundle pair", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    assert {:ok, loaded} = Loader.load(dir)
    assert %{"comparch" => _tier} = loaded.chain.tiers
    assert %{"product-review" => _gate} = loaded.workflow.gates
  end

  test "Chain.predicates carries predicates.yaml forward for the engine's runtime evaluator",
       %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/predicates.yaml" => """
      is_domain: kind == domain
      """,
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      scope_filter: is_domain
      identity: id
      fields:
        name: draft.name
      handle:
        fields: [id, name]
        fragments: [techspec]
      draft:
        root_tag: comparch
        grammar: schemas/comparch.xsd
      generator: llm
      prompt: prompts/comparch.md.liquid
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert {:ok, predicate} = Chain.resolve_predicate(loaded.chain, "is_domain")
    assert predicate == Map.fetch!(loaded.chain.predicates, "is_domain")

    # An inline expression not registered in predicates.yaml parses
    # fresh rather than failing for want of a name.
    assert {:ok, _predicate} = Chain.resolve_predicate(loaded.chain, "has_edge(fulfills)")
  end

  test "reports catapult.yaml missing", %{tmp_dir: dir} do
    assert {:error, :catapult_yaml, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "catapult.yaml"))
  end

  test "reports catapult.yaml missing chain:", %{tmp_dir: dir} do
    Fixture.write!(dir, %{"catapult.yaml" => "workflow: default-flow\n"})
    assert {:error, :catapult_yaml, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "missing required field \"chain\""))
  end

  test "the runtime dialect refuses a workflow: entry in catapult.yaml", %{tmp_dir: dir} do
    Fixture.minimal!(dir)
    assert {:error, :catapult_yaml, problems} = Loader.load(dir, dialect: "runtime")
    assert Enum.any?(problems, &String.contains?(&1, "runtime dialect"))
  end

  test "the runtime dialect loads the chain axis alone", %{tmp_dir: dir} do
    Fixture.minimal!(dir)
    Fixture.write!(dir, %{"catapult.yaml" => "chain: default\n"})

    assert {:ok, loaded} = Loader.load(dir, dialect: "runtime")
    assert loaded.workflow == nil
  end

  test "an unknown top-level tier field is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      handle:
        fields: [id]
      gate: some-gate
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "unknown field \"gate\""))
  end

  test "scope naming an undeclared tier is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/subcomparch.yaml" => """
      tier: subcomparch
      scope: per(nonexistent)
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "per(nonexistent)"))
  end

  test "a delivery.phase outside the fixed system statuses is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      delivery:
        phase: Architecting
        agent_step: design
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "delivery.phase"))
  end

  test "a valid delivery block resolves against the fixed vocabulary", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      delivery:
        phase: generation
        agent_step: design
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "an edge cycle across tiers fails type-level acyclicity", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/a.yaml" => """
      tier: a
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/b.yaml" => """
      tier: b
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/edges/a_to_b.yaml" => """
      edge: a_to_b
      type: reference
      source: a
      target: b
      declared_in: a.draft.b_ref
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """,
      "bundles/default/edges/b_to_a.yaml" => """
      edge: b_to_a
      type: reference
      source: b
      target: a
      declared_in: b.draft.a_ref
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "type-level cycle"))
  end

  test "a self-referencing dependency edge is legal at the type level", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/edges/dependency.yaml" => """
      edge: dependency
      type: dependency
      source: comparch
      target: comparch
      declared_in: comparch.draft.dependencies
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      graph_constraint: [acyclic]
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a navigation edge cannot be walked in a readiness context", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.nav -> comparch.handle
      """,
      "bundles/default/edges/nav.yaml" => """
      edge: nav
      type: reference
      source: comparch
      target: comparch
      declared_in: comparch.draft.nav
      navigation: true
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "navigation: true"))
  end

  test "extends: layers a base bundle and lets a same-path file replace it", %{tmp_dir: dir} do
    Fixture.write!(dir, %{
      "catapult.yaml" => "chain: project\n",
      "bundles/base/bundle.yaml" => """
      name: base
      version: "1.0.0"
      kind: chain
      tiers: [tiers/*.yaml]
      fragments: [techspec]
      """,
      "bundles/base/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/base/tiers/other.yaml" => """
      tier: other
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/project/bundle.yaml" => """
      name: project
      version: "1.0.0"
      kind: chain
      extends: base
      tiers: [tiers/*.yaml]
      fragments: [techspec, pubapi]
      """,
      # Same relative path as base's comparch.yaml: replaces it.
      "bundles/project/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: alias
      generator: synthesis
      handle:
        fields: [id]
      """
    })

    assert {:ok, loaded} = Loader.load(dir, dialect: "runtime")
    assert Map.keys(loaded.chain.tiers) |> Enum.sort() == ["comparch", "other"]
    assert loaded.chain.tiers["comparch"].identity == "alias"
    assert "pubapi" in loaded.chain.fragments
  end

  test "extends: never crosses axes", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/bundle.yaml" => """
      name: default
      version: "1.0.0"
      kind: chain
      extends: default-flow
      tiers: [tiers/*.yaml]
      fragments: [techspec]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "across axes"))
  end

  ## §15.3 — the array is the only ordering mechanism. `after:` is
  ## retired, so the checks it needed (one total order over the bundle,
  ## no cycle in predecessor references) are gone with it; what
  ## replaces them is the declaration graph over `flow:` (§15.6) and a
  ## throwback resolving inside the citing type's own array (§15.4).

  test "the same two gates may run in opposite order in two types", %{tmp_dir: dir} do
    # Impossible to express under `after:`, which required one order
    # for the whole bundle — the change §15.3 is explicitly about.
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/other-review.yaml" => """
      review: other-review
      role: design
      escalation: author
      """,
      "bundles/default-flow/types/feature.yaml" =>
        ticket_type!("feature", ["product-review", "other-review"]),
      "bundles/default-flow/types/defect.yaml" =>
        ticket_type!("defect", ["other-review", "product-review"])
    })

    assert {:ok, loaded} = Loader.load(dir)

    assert Enum.map(loaded.workflow.types["feature"].statuses, & &1.review) ==
             [nil, nil, "product-review", "other-review", nil, nil, nil, nil]

    assert Enum.map(loaded.workflow.types["defect"].statuses, & &1.review) ==
             [nil, nil, "other-review", "product-review", nil, nil, nil, nil]
  end

  test "a workflow bundle carrying after: on a gate is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      after: generation
      role: design
      escalation: author
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "unknown field \"after\""))
  end

  ## §15.6 — the declaration graph over `flow:` must be acyclic, with a
  ## type naming itself the degenerate one-node case.

  test "a type whose flow: names itself is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: project
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "names itself"))
  end

  test "a two-node cycle through a skeleton-less type is a load error", %{tmp_dir: dir} do
    # The hole §15.6's fifth pass found: restricting the graph's nodes
    # to container-skeleton types excludes every edge *into* a
    # skeleton-less one, which is exactly the edge this cycle runs on.
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
      """,
      "bundles/default-flow/types/milestone.yaml" => """
      type: milestone
      skeleton: container
      statuses:
        - status: setup
          flow: feature
        - status: prep
          flow: feature
        - status: main
          flow: project
        - status: retro
          flow: feature
        - status: cleanup
          flow: feature
        - status: terminal
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "a container-skeleton type nests another container for free", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: epic
      """,
      "bundles/default-flow/types/epic.yaml" => container_type!("epic", "milestone"),
      "bundles/default-flow/types/milestone.yaml" => container_type!("milestone", "feature")
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.workflow.types["epic"].skeleton == "container"
    assert loaded.workflow.entry == "project"
  end

  ## §15.4, §15.8 — a throwback resolves inside the citing type's own
  ## array, which is where position lives now.

  test "a throwback that is not earlier in the citing type's array is a load error", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      throwback: [checks]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "not earlier in this type's own statuses"))
  end

  test "a throwback naming an earlier entry in the citing type's array loads", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      throwback: [generation]
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.workflow.gates["product-review"].throwback == ["generation"]
  end

  ## §2, §15.6 — `entry:` names the root a fresh project starts from.

  test "entry: is required on a workflow manifest", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      gates: [gates/*.yaml]
      types: [types/*.yaml]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "missing required field \"entry\""))
  end

  test "entry: naming a ticket-skeleton type is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      gates: [gates/*.yaml]
      types: [types/*.yaml]
      entry: feature
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "no queue-shaped anchor"))
  end

  test "entry: must name a type nothing else's flow: targets", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
      """,
      "bundles/default-flow/types/milestone.yaml" => container_type!("milestone", "feature"),
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      gates: [gates/*.yaml]
      types: [types/*.yaml]
      entry: milestone
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "is not a root in the declaration graph"))
  end

  ## §15.1 — the two fixed skeletons.

  test "a container-skeleton type must hold the five anchors, in order, then terminal", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
      """,
      "bundles/default-flow/types/milestone.yaml" => """
      type: milestone
      skeleton: container
      statuses:
        - status: prep
          flow: feature
        - status: setup
          flow: feature
        - status: main
          flow: feature
        - status: retro
          flow: feature
        - status: cleanup
          flow: feature
        - status: terminal
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "in that order"))
  end

  test "a ticket-skeleton type must open with pending and close with terminal", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: generation
        - status: pending
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "must open with pending"))
  end

  test "a queue-shaped entry's flow: must name a declared type", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: nonexistent
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "which is not a declared type"))
  end

  test "terminal carries no flow:, even in a container-skeleton array", %{tmp_dir: dir} do
    # §15.7's blanket sentence would read `terminal` as queue-shaped;
    # §15.2's own worked example declares it bare and §15.6 settles it
    # — "a fixed terminal kind, not a further queue name."
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
      """,
      "bundles/default-flow/types/milestone.yaml" => container_type!("milestone", "feature")
    })

    assert {:ok, loaded} = Loader.load(dir)

    terminal = List.last(loaded.workflow.types["milestone"].statuses)
    assert terminal.status == "terminal"
    assert terminal.flow == nil
  end

  ## §15.7 — `blocks:` names siblings only.

  test "a blocks: entry naming a queue in another declaration is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
          blocks: [prep]
      """,
      "bundles/default-flow/types/milestone.yaml" => container_type!("milestone", "feature")
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(&1, "not a queue-shaped anchor declared in the same type")
           )
  end

  test "main blocking retro is a legal sibling relation", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/project.yaml" => """
      type: project
      statuses:
        - status: build-out
          flow: milestone
      """,
      "bundles/default-flow/types/milestone.yaml" => """
      type: milestone
      skeleton: container
      statuses:
        - status: setup
          flow: feature
          singleton: true
        - status: prep
          flow: feature
        - status: main
          flow: feature
          blocks: [retro]
        - status: retro
          flow: feature
          singleton: true
        - status: cleanup
          flow: feature
        - status: terminal
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    statuses = loaded.workflow.types["milestone"].statuses

    assert Enum.find(statuses, &(&1.status == "main")).blocks == ["retro"]
    assert Enum.find(statuses, &(&1.status == "setup")).singleton
    assert Enum.find(statuses, &(&1.status == "retro")).singleton
    refute Enum.find(statuses, &(&1.status == "main")).singleton
  end

  test "opt-in role-holder check flags a gate whose role has no holders", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    assert {:error, :bundle, problems} = Loader.load(dir, role_holders: %{"design" => []})
    assert Enum.any?(problems, &String.contains?(&1, "no holders"))
  end

  test "role-holder check is skipped when no resolver is supplied", %{tmp_dir: dir} do
    Fixture.minimal!(dir)
    assert {:ok, _loaded} = Loader.load(dir)
  end

  # dsl-syntax.md §13/§15.1: "a `pending` precedes every generation and
  # every deployment" is a fact about the fixed system-status skeleton
  # (Catapult.Dsl.SystemStatus.pending_precedes?/1), not bundle
  # content — like the sibling blocked-exit skeleton check, it cannot
  # be made to fail from bundle data, so this locks in that the check
  # is wired into every workflow load rather than dead code. Renamed
  # from `queue` at ORC-104, when a container's own named queue
  # position made the old word ambiguous (§15.1).
  test "the pending-precedes-generation/deploy skeleton check is wired into workflow load", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)
    assert {:ok, _loaded} = Loader.load(dir)
    assert SystemStatus.pending_precedes?(:generation)
    assert SystemStatus.pending_precedes?(:deploy)
  end

  test "naming discipline flags two declared statuses one hyphen-word apart", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review-final.yaml" => """
      review: product-review-final
      role: design
      escalation: author
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "hyphen-separated word apart"))
  end

  test "a workflow manifest carrying a chain-only key is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      gates: [gates/*.yaml]
      environments: [environments/*.yaml]
      tiers: [tiers/*.yaml]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "unknown field \"tiers\""))
  end

  test "an environment's promote_from must name a declared environment", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      promote_from: nonexistent
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(&1, "\"nonexistent\" names an environment that is not declared")
           )
  end

  test "an environment naming itself as its own promote_from is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      promote_from: staging
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "a genuine cycle across two environments' promote_from is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/dev.yaml" => """
      environment: dev
      promote_from: staging
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      promote_from: dev
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "environments chain by promote_from", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/dev.yaml" => """
      environment: dev
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      promote_from: dev
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.workflow.environments["staging"].promote_from == "dev"
  end

  test "the opt-in mirror-mapping check flags an unmapped gate", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    assert {:error, :bundle, problems} = Loader.load(dir, mirror_mapping: %{})
    assert Enum.any?(problems, &String.contains?(&1, "no counterpart in the outbound tracker"))
  end

  test "mirror-mapping check is skipped when no resolver is supplied", %{tmp_dir: dir} do
    Fixture.minimal!(dir)
    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "naming discipline does not flag unrelated single-word names", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/dev.yaml" => """
      environment: dev
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  ## dsl-syntax.md §4.1 — instances:

  test "instances: consolidates several source/target sites under one edge name", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/resp.yaml" => tier!("resp"),
      "bundles/default/tiers/vocab.yaml" => tier!("vocab"),
      "bundles/default/edges/decomposition.yaml" => """
      edge: decomposition
      type: fanout
      instances:
        - source: comparch
          target: resp
          declared_in: comparch.draft.resp[]
          cardinality:
            source: { min: 0 }
            target: { min: 1, max: 1 }
        - source: comparch
          target: vocab
          declared_in: comparch.draft.vocab[]
          cardinality:
            source: { min: 0 }
            target: { min: 1, max: 1 }
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "instances: and the flat single-site shape are mutually exclusive", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/edges/dependency.yaml" => """
      edge: dependency
      type: dependency
      source: comparch
      target: comparch
      declared_in: comparch.draft.dependencies
      instances:
        - source: comparch
          target: comparch
          declared_in: comparch.draft.dependencies
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "never both"))
  end

  test "an edge declaring neither an inline instance nor instances: is a load error", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/edges/dependency.yaml" => """
      edge: dependency
      type: dependency
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "neither an inline instance"))
  end

  test "a multi-instance edge's last hop disambiguates by the walk's own declared target", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/resp.yaml" => tier!("resp"),
      "bundles/default/tiers/vocab.yaml" => tier!("vocab"),
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.decomposition -> vocab.handle
      """,
      "bundles/default/edges/decomposition.yaml" => """
      edge: decomposition
      type: fanout
      instances:
        - source: comparch
          target: resp
          declared_in: comparch.draft.resp[]
          cardinality:
            source: { min: 0 }
            target: { min: 1, max: 1 }
        - source: comparch
          target: vocab
          declared_in: comparch.draft.vocab[]
          cardinality:
            source: { min: 0 }
            target: { min: 1, max: 1 }
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  ## dsl-syntax.md §7.1 — hop chains and reversal

  test "a reversed hop matches the edge's target instead of its source", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/resp.yaml" => tier!("resp"),
      "bundles/default/tiers/policy.yaml" => tier!("policy"),
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.fulfills.policy_application~ -> policy.handle
      """,
      "bundles/default/edges/fulfills.yaml" => """
      edge: fulfills
      type: reference
      source: comparch
      target: resp
      declared_in: comparch.draft.resp_ref
      cardinality:
        source: { min: 1 }
        target: { min: 1, max: 1 }
      """,
      "bundles/default/edges/policy_application.yaml" => """
      edge: policy_application
      type: policy_application
      instances:
        - source: policy
          target: comparch
          declared_in: policy.structural
          cardinality:
            source: { min: 0, max: 1 }
            target: { min: 0 }
        - source: policy
          target: resp
          declared_in: policy.required
          cardinality:
            source: { min: 0, max: 1 }
            target: { min: 0 }
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a hop naming an edge with no instance on the required side is a load error", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/resp.yaml" => tier!("resp"),
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.fulfills~ -> resp.handle
      """,
      "bundles/default/edges/fulfills.yaml" => """
      edge: fulfills
      type: reference
      source: comparch
      target: resp
      declared_in: comparch.draft.resp_ref
      cardinality:
        source: { min: 1 }
        target: { min: 1, max: 1 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "does not include"))
  end

  ## dsl-syntax.md §7.2 — all.<tier>

  test "all.<tier> reads every declared instance with no walker at all", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/vocab.yaml" => tier!("vocab"),
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - all.vocab.handle
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "all.<tier> naming an undeclared tier is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - all.nonexistent.handle
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "\"nonexistent\", which is not declared"))
  end

  ## dsl-syntax.md §3.1 — cascade_visit

  test "cascade_visit is a legal scope with no parent tier to check", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/plan.yaml" => """
      tier: plan
      scope: cascade_visit
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.chain.tiers["plan"].scope == {:cascade_visit}
  end

  ## dsl-syntax.md §3.3, §13 — review tiers

  test "a valid review tier loads, sharing the reviewed tier's context", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.handle
      delivery:
        phase: generation
        agent_step: design
      """,
      "bundles/default/tiers/comparch_review.yaml" => """
      tier: comparch_review
      reviews: comparch
      generator: llm
      prompt: prompts/review/comparch.md.liquid
      grammar: schemas/review.xsd
      context:
        - self.handle
      delivery:
        phase: critique
        agent_step: critique
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.chain.tiers["comparch_review"].reviews == "comparch"
  end

  test "reviews: naming an undeclared tier is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch_review.yaml" => """
      tier: comparch_review
      reviews: nonexistent
      generator: llm
      prompt: prompts/review/comparch.md.liquid
      grammar: schemas/review.xsd
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(&1, "reviews \"nonexistent\" names a tier that is not declared")
           )
  end

  test "a review tier's context must match the reviewed tier's own context", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.handle
      """,
      "bundles/default/tiers/comparch_review.yaml" => """
      tier: comparch_review
      reviews: comparch
      generator: llm
      prompt: prompts/review/comparch.md.liquid
      grammar: schemas/review.xsd
      context: []
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(
               &1,
               "context does not match reviewed tier \"comparch\"'s own context"
             )
           )
  end

  test "a review tier declaring scope: is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch_review.yaml" => """
      tier: comparch_review
      reviews: comparch
      scope: singleton
      generator: llm
      prompt: prompts/review/comparch.md.liquid
      grammar: schemas/review.xsd
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(&1, "declares \"scope\", which a review tier")
           )
  end

  ## depth: (§13, §15.2, §15.4, §15.5) — the scalar-or-pair grammar,
  ## shared by a gate, an environment and critique.yaml

  test "a gate's depth: accepts the [first, rest] pair", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      depth: [2, 0]
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.workflow.gates["product-review"].depth == {2, 0}
  end

  test "an environment's depth: accepts the [first, rest] pair", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      depth: [1, 0]
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.workflow.environments["staging"].depth == {1, 0}
  end

  test "a depth: list of other than exactly two entries is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      depth: [1, 2, 3]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(
               &1,
               "expected a non-negative integer or a list of exactly two non-negative integers"
             )
           )
  end

  test "a negative depth: is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      role: design
      escalation: author
      depth: -1
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(
               &1,
               "expected a non-negative integer or a list of exactly two non-negative integers"
             )
           )
  end

  ## critique (§15.5) — the auto-review knob, now an inline array entry
  ## rather than a singular `critique.yaml`. Participation is per type
  ## and presence is participation: there is no `enabled:` field, and a
  ## type declaring no critique entry runs no critique tier.

  test "a type declaring no critique entry has none", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    assert {:ok, loaded} = Loader.load(dir)
    statuses = loaded.workflow.types["feature"].statuses

    refute Enum.any?(statuses, &(&1.status == "critique"))
  end

  test "a critique entry turns the slot on, at the depth it declares", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: pending
        - status: generation
        - status: critique
          depth: [2, 0]
        - review: product-review
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    critique = Enum.find(loaded.workflow.types["feature"].statuses, &(&1.status == "critique"))

    assert critique.depth == {2, 0}
  end

  test "a critique entry's depth defaults to 0 when omitted", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: pending
        - status: generation
        - status: critique
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    critique = Enum.find(loaded.workflow.types["feature"].statuses, &(&1.status == "critique"))

    assert critique.depth == 0
  end

  test "a critique entry not immediately after a generation is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: pending
        - status: generation
        - review: product-review
        - status: critique
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)

    assert Enum.any?(
             problems,
             &String.contains?(&1, "must sit immediately after a generation entry")
           )
  end

  test "two generation entries may each carry their own critique depth", %{tmp_dir: dir} do
    # §15.5: "citing it more than once in a type's array (once per
    # generation entry it should pair with) is the ordinary way to give
    # two generation phases different depths."
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/types/feature.yaml" => """
      type: feature
      skeleton: ticket
      statuses:
        - status: pending
        - status: generation
        - status: critique
          depth: 1
        - review: product-review
        - status: generation
        - status: critique
          depth: 2
        - status: checks
        - status: merge
        - status: deploy
        - status: terminal
      """
    })

    assert {:ok, loaded} = Loader.load(dir)

    depths =
      loaded.workflow.types["feature"].statuses
      |> Enum.filter(&(&1.status == "critique"))
      |> Enum.map(& &1.depth)

    assert depths == [1, 2]
  end

  ## §11, §13 — a workflow bundle is forked, never layered.

  test "a workflow bundle declaring extends: is a load error", %{tmp_dir: dir} do
    # v5 §7.18's own workflow-axis base layer, reversed at ORC-105:
    # `extends:` narrows to the chain axis, because fork-tailor-merge
    # is how bundles are actually distributed (§3.1) and git has a
    # merge story hex does not.
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/bundle.yaml" => """
      name: default-flow
      version: "1.0.0"
      kind: workflow
      extends: base-flow
      gates: [gates/*.yaml]
      types: [types/*.yaml]
      entry: project
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "unknown field \"extends\""))
  end

  defp ticket_type!(name, gates) do
    entries =
      ["- status: pending", "- status: generation"] ++
        Enum.map(gates, &"- review: #{&1}") ++
        ["- status: checks", "- status: merge", "- status: deploy", "- status: terminal"]

    "type: #{name}\nskeleton: ticket\nstatuses:\n" <>
      Enum.map_join(entries, "\n", &("  " <> &1)) <> "\n"
  end

  defp container_type!(name, flow) do
    """
    type: #{name}
    skeleton: container
    statuses:
      - status: setup
        flow: #{flow}
      - status: prep
        flow: #{flow}
      - status: main
        flow: #{flow}
      - status: retro
        flow: #{flow}
      - status: cleanup
        flow: #{flow}
      - status: terminal
    """
  end

  defp tier!(name) do
    """
    tier: #{name}
    scope: singleton
    identity: id
    generator: synthesis
    handle:
      fields: [id]
    """
  end
end
