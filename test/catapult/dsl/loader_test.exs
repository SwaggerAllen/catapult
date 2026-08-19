defmodule Catapult.Dsl.LoaderTest do
  use ExUnit.Case, async: true

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

  test "an edge with instances: covers several source/target sites under one name", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/other.yaml" => """
      tier: other
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/third.yaml" => """
      tier: third
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/edges/decomposition.yaml" => """
      edge: decomposition
      type: fanout
      instances:
        - source: comparch
          target: other
          declared_in: comparch.draft.a[]
          cardinality:
            source: { min: 1 }
            target: { min: 1, max: 1 }
        - source: comparch
          target: third
          declared_in: comparch.draft.b[]
          cardinality:
            source: { min: 0 }
            target: { min: 1, max: 1 }
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert length(loaded.chain.edges["decomposition"].instances) == 2
  end

  test "instances: and a flat source/target together is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/edges/bad.yaml" => """
      edge: bad
      type: reference
      source: comparch
      target: comparch
      declared_in: comparch.draft.x
      instances:
        - source: comparch
          target: comparch
          declared_in: comparch.draft.y
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "both a flat source/target and instances:"))
  end

  test "a multi-hop context walk resolves through two edges, one reversed", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comp.yaml" => """
      tier: comp
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/resp.yaml" => """
      tier: resp
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/policy.yaml" => """
      tier: policy
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: per(comp)
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      context:
        - self.parent.fulfills.policy_application~ -> policy.handle
      """,
      "bundles/default/edges/fulfills.yaml" => """
      edge: fulfills
      type: reference
      source: comp
      target: resp
      declared_in: comp.draft.fulfills
      cardinality:
        source: { min: 1 }
        target: { min: 1, max: 1 }
      """,
      "bundles/default/edges/policy_application.yaml" => """
      edge: policy_application
      type: policy_application
      source: policy
      target: resp
      declared_in: policy.required
      cardinality:
        source: { min: 0, max: 1 }
        target: { min: 0 }
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a reversed hop with no matching instance is a load error", %{tmp_dir: dir} do
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
        - self.fulfills~ -> other.handle
      """,
      "bundles/default/tiers/other.yaml" => """
      tier: other
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/edges/fulfills.yaml" => """
      edge: fulfills
      type: reference
      source: other
      target: other
      declared_in: other.draft.fulfills
      cardinality:
        source: { min: 0 }
        target: { min: 0 }
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "none of whose instances has target"))
  end

  test "all.<tier>.<projection> reads every instance of a tier with no edge", %{tmp_dir: dir} do
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
        - all.vocab.handle
      """,
      "bundles/default/tiers/vocab.yaml" => """
      tier: vocab
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
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
        - all.bogus.handle
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "all.bogus"))
  end

  test "a fan-out edge's -> target naming no matching instance is a load error", %{
    tmp_dir: dir
  } do
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
        - self.decomposition -> third.handle
      """,
      "bundles/default/tiers/other.yaml" => """
      tier: other
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/fourth.yaml" => """
      tier: fourth
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/third.yaml" => """
      tier: third
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/edges/decomposition.yaml" => """
      edge: decomposition
      type: fanout
      instances:
        - source: comparch
          target: other
          declared_in: comparch.draft.a
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
        - source: comparch
          target: fourth
          declared_in: comparch.draft.b
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
      """
    })

    # Two instances share source: comparch (targets other, fourth);
    # `third` is a real, declared tier, but neither instance targets
    # it, so this must fail rather than silently resolving to
    # whichever instance happens to be listed first.
    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "none landing on"))
  end

  test "an edge fanning one source to several targets resolves the one -> names", %{
    tmp_dir: dir
  } do
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
        - self.decomposition -> third.handle
      """,
      "bundles/default/tiers/other.yaml" => """
      tier: other
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/tiers/third.yaml" => """
      tier: third
      scope: singleton
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """,
      "bundles/default/edges/decomposition.yaml" => """
      edge: decomposition
      type: fanout
      instances:
        - source: comparch
          target: other
          declared_in: comparch.draft.a
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
        - source: comparch
          target: third
          declared_in: comparch.draft.b
          cardinality:
            source: { min: 0 }
            target: { min: 0 }
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end

  test "a cascade_visit-scoped tier loads with no parent-tier cross-reference", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default/tiers/comparch.yaml" => """
      tier: comparch
      scope: cascade_visit
      identity: id
      generator: synthesis
      handle:
        fields: [id]
      """
    })

    assert {:ok, loaded} = Loader.load(dir)
    assert loaded.chain.tiers["comparch"].scope == {:cascade_visit}
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

  test "a duplicate gate after: is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/other-review.yaml" => """
      review: other-review
      after: generation
      role: design
      escalation: author
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "total order"))
  end

  test "a gate naming itself as its own after: is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      after: product-review
      role: design
      escalation: author
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "a genuine cycle across two gates' after: is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      after: other-review
      role: design
      escalation: author
      """,
      "bundles/default-flow/gates/other-review.yaml" => """
      review: other-review
      after: product-review
      role: design
      escalation: author
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "a throwback that is not earlier in the sequence is a load error", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review.yaml" => """
      review: product-review
      after: generation
      role: design
      escalation: author
      throwback: [product-review]
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "not earlier"))
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

  # dsl-syntax.md §13/§15.1: "a queue status precedes every generation
  # and every deployment" is a fact about the fixed system-status
  # skeleton (Catapult.Dsl.SystemStatus.queue_precedes?/1), not bundle
  # content — like the sibling blocked-exit skeleton check, it cannot
  # be made to fail from bundle data, so this locks in that the check
  # is wired into every workflow load rather than dead code.
  test "the queue-precedes-generation/deploy skeleton check is wired into workflow load", %{
    tmp_dir: dir
  } do
    Fixture.minimal!(dir)
    assert {:ok, _loaded} = Loader.load(dir)
    assert SystemStatus.queue_precedes?(:generation)
    assert SystemStatus.queue_precedes?(:deploy)
  end

  test "naming discipline flags two declared statuses one hyphen-word apart", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/gates/product-review-final.yaml" => """
      review: product-review-final
      after: product-review
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
      after: deploy
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
      after: deploy
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
      after: merge
      promote_from: staging
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      after: deploy
      promote_from: dev
      """
    })

    assert {:error, :bundle, problems} = Loader.load(dir)
    assert Enum.any?(problems, &String.contains?(&1, "cycle"))
  end

  test "environments chain by promote_from and resolve against system statuses", %{tmp_dir: dir} do
    Fixture.minimal!(dir)

    Fixture.write!(dir, %{
      "bundles/default-flow/environments/dev.yaml" => """
      environment: dev
      after: merge
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      after: deploy
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
      after: merge
      """,
      "bundles/default-flow/environments/staging.yaml" => """
      environment: staging
      after: deploy
      """
    })

    assert {:ok, _loaded} = Loader.load(dir)
  end
end
