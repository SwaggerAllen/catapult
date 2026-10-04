defmodule Catapult.Delivery.FeatureLifecycle.SequenceTest do
  @moduledoc """
  Built against the real `bundles/default-flow` this repo ships with —
  "checked, not assumed" (`systems/delivery.md`'s own standard for this
  ticket) — rather than a synthetic fixture, so a change to the shipped
  types is caught here too.

  Rewritten at ORC-104: `after:` is retired (`workflow.md` #12), so
  there is no gate chain to walk and no orphan-anchor case to test.
  Position is the citing type's own array index, which is what the
  synthetic cases below now exercise instead.
  """

  use ExUnit.Case, async: true

  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Dsl
  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  describe "positions/2 against the shipped default-flow bundle" do
    setup do
      assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
      %{workflow: workflow}
    end

    # `types/feature.yaml`'s single-phase shape is retired: the shipped
    # bundle's `delta` type (an ordinary change ticket, `serves:
    # has_delta`) is the multi-phase shape `workflow.md` #12 describes —
    # a plan position ahead of each of the five generation phases
    # (features/experience/requirements/architecture/implementation),
    # each phase's own critique, and a gate on three of the five.
    test "the delta type's own array, in order, up to the reachable boundary", %{
      workflow: workflow
    } do
      assert Sequence.positions(workflow, "delta") == [
               {:kind, :generation},
               {:kind, :generation},
               {:kind, :critique},
               {:gate, "features-review"},
               {:kind, :generation},
               {:kind, :generation},
               {:kind, :critique},
               {:gate, "ux-review"},
               {:kind, :generation},
               {:kind, :generation},
               {:kind, :critique},
               {:kind, :generation},
               {:kind, :generation},
               {:kind, :critique},
               {:gate, "engineering-review"},
               {:kind, :generation},
               {:kind, :generation},
               {:kind, :critique},
               {:kind, :checks}
             ]
    end

    test "merge, deploy and terminal sit past this phase's reach", %{workflow: workflow} do
      positions = Sequence.positions(workflow, "delta")

      refute {:kind, :merge} in positions
      refute {:kind, :deploy} in positions
      refute {:kind, :terminal} in positions
    end

    test "an environment citation is not a resting position", %{workflow: workflow} do
      # `workflow.yaml`'s `delta` type cites `staging` before its
      # `deploy` entry (§15.5). It configures that deploy; nothing
      # rests at it.
      assert Enum.all?(Sequence.positions(workflow, "delta"), &match?({:kind, _}, &1)) or
               Enum.all?(
                 Sequence.positions(workflow, "delta"),
                 &(elem(&1, 0) in [:kind, :gate])
               )
    end

    test "a type name that does not resolve yields no positions", %{workflow: workflow} do
      assert Sequence.positions(workflow, "no-such-type") == []
    end
  end

  describe "positions/2 for an inline dispatch point (ORC-176)" do
    setup do
      assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
      %{workflow: workflow}
    end

    # `setup`/`retro` fold directly into `milestone`'s own array
    # (ORC-148) and never resolve as a `types/<name>.yaml` name — the
    # shipped bundle declares no such type.
    test "setup resolves to its own fixed pending/setup sequence", %{workflow: workflow} do
      assert Sequence.positions(workflow, "setup") == [{:kind, :pending}, {:kind, :setup}]
    end

    test "retro resolves to its own fixed pending/retro sequence", %{workflow: workflow} do
      assert Sequence.positions(workflow, "retro") == [{:kind, :pending}, {:kind, :retro}]
    end

    test "a review-shaped name is not treated as an inline dispatch point", %{workflow: workflow} do
      # `critique` is agent-balled but review-shaped — never one of
      # `ContainerLifecycle.open_inline/3`'s candidates — so an unresolved
      # `critique` type name is still the authoring bug `warn_unplaceable/3`
      # describes, not a fixed sequence.
      assert Sequence.positions(workflow, "critique") == []
    end

    test "a plane-balled name is not treated as an inline dispatch point", %{workflow: workflow} do
      # `merge`'s own `ball` is `plane` since ORC-151 — it fails
      # `SystemStatus.agent_balled?/1` before review-shapedness is asked.
      assert Sequence.positions(workflow, "merge") == []
    end
  end

  describe "positions/2 reads the citing type's own array" do
    test "a type declaring no critique entry has no critique position" do
      workflow = workflow_with(["pending", "generation", "checks"])

      assert Sequence.positions(workflow, "t") == [
               {:kind, :pending},
               {:kind, :generation},
               {:kind, :checks}
             ]
    end

    test "two types may run the same gates in opposite relative order" do
      # The change §15.3 is explicitly about: with position living on
      # the citing type's own array, neither declaration answers to the
      # other's.
      forward = %Type{
        name: "forward",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{review: "a"},
          %Status{review: "b"},
          %Status{status: "checks"}
        ]
      }

      backward = %Type{
        name: "backward",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{review: "b"},
          %Status{review: "a"},
          %Status{status: "checks"}
        ]
      }

      workflow = %Workflow{
        name: "test",
        entry: "forward",
        gates: %{},
        environments: %{},
        types: %{"forward" => forward, "backward" => backward}
      }

      assert Sequence.positions(workflow, "forward") == [
               {:kind, :pending},
               {:gate, "a"},
               {:gate, "b"},
               {:kind, :checks}
             ]

      assert Sequence.positions(workflow, "backward") == [
               {:kind, :pending},
               {:gate, "b"},
               {:gate, "a"},
               {:kind, :checks}
             ]
    end
  end

  describe "positions/2 boundary against a multi-phase type (workflow.md #12, ORC-182)" do
    test "the boundary is the last :checks ahead of merge, not the first" do
      # `types/feature.yaml`'s revised, multi-phase shape (§15.2's fourth
      # design review): three generation-shaped sub-arrays, each with its
      # own `checks`, and one trailing `merge`. Anchoring on the first
      # occurrence would silently drop everything from `architecture`
      # onward.
      type = %Type{
        name: "feature",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{status: "design"},
          %Status{status: "checks"},
          %Status{status: "critique"},
          %Status{review: "product-review"},
          %Status{status: "pending"},
          %Status{status: "architecture"},
          %Status{status: "checks"},
          %Status{status: "critique"},
          %Status{review: "architecture-review"},
          %Status{status: "reconcile"},
          %Status{review: "architecture-synthesis-review"},
          %Status{status: "pending"},
          %Status{status: "implementation"},
          %Status{status: "checks"},
          %Status{status: "critique"},
          %Status{status: "reconcile"},
          %Status{status: "merge"},
          %Status{status: "deploy"},
          %Status{status: "terminal"}
        ]
      }

      workflow = %Workflow{
        name: "test",
        entry: "feature",
        gates: %{},
        environments: %{},
        types: %{"feature" => type}
      }

      assert Sequence.positions(workflow, "feature") == [
               {:kind, :pending},
               {:kind, :design},
               {:kind, :checks},
               {:kind, :critique},
               {:gate, "product-review"},
               {:kind, :pending},
               {:kind, :architecture},
               {:kind, :checks},
               {:kind, :critique},
               {:gate, "architecture-review"},
               {:kind, :reconcile},
               {:gate, "architecture-synthesis-review"},
               {:kind, :pending},
               {:kind, :implementation},
               {:kind, :checks}
             ]
    end

    test "a single :checks (the shipped shape) still coincides as first and last" do
      workflow = workflow_with(["pending", "generation", "checks", "reconcile", "merge"])

      assert Sequence.positions(workflow, "t") == [
               {:kind, :pending},
               {:kind, :generation},
               {:kind, :checks}
             ]
    end
  end

  describe "annotated_positions/2 (workflow.md #6, ORC-116)" do
    setup do
      assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
      %{workflow: workflow}
    end

    test "delta's own generation phases each group their own critique and gates, anchored on their own generation entry",
         %{workflow: workflow} do
      annotated = Sequence.annotated_positions(workflow, "delta")

      assert Enum.map(annotated, & &1.position) == Sequence.positions(workflow, "delta")

      assert Enum.map(annotated, & &1.group_key) == [
               nil,
               "features",
               "features",
               "features",
               nil,
               "experience",
               "experience",
               "experience",
               nil,
               "requirements",
               "requirements",
               nil,
               "architecture",
               "architecture",
               "architecture",
               nil,
               "implementation",
               "implementation",
               nil
             ]

      assert Enum.map(annotated, & &1.group_anchor) == [
               false,
               true,
               false,
               false,
               false,
               true,
               false,
               false,
               false,
               true,
               false,
               false,
               true,
               false,
               false,
               false,
               true,
               false,
               false
             ]
    end

    test "a type with no sub-array groups nothing" do
      # `seed` no longer names a shipped type — a synthetic, group-less
      # type exercises the identical claim.
      workflow = workflow_with(["pending", "generation", "checks"])
      annotated = Sequence.annotated_positions(workflow, "t")

      assert Enum.all?(annotated, &(&1.group_key == nil and &1.group_anchor == false))
    end

    test "a type name that does not resolve yields no positions", %{workflow: workflow} do
      assert Sequence.annotated_positions(workflow, "no-such-type") == []
    end

    test "an inline dispatch point's fixed sequence is ungrouped (ORC-176)", %{
      workflow: workflow
    } do
      annotated = Sequence.annotated_positions(workflow, "setup")

      assert Enum.map(annotated, & &1.position) == Sequence.positions(workflow, "setup")
      assert Enum.all?(annotated, &(&1.group_key == nil and &1.group_anchor == false))
    end
  end

  describe "annotated_positions/2 over a sub-array that is not the sequence's own head" do
    test "an earlier entry outside the group carries no group_key at all" do
      # `[status, [status, review]]` — the shape §15.10 argues from
      # (`types/milestone.yaml`'s sign-off group), built small enough
      # to exercise "outside the group" without a container skeleton.
      type = %Type{
        name: "t",
        skeleton: "ticket",
        statuses: [
          %Status{status: "pending"},
          %Status{status: "generation"},
          %Status{review: "product-review"}
        ],
        groups: [1..2//1]
      }

      workflow = %Workflow{
        name: "test",
        entry: "t",
        gates: %{},
        environments: %{},
        types: %{"t" => type}
      }

      annotated = Sequence.annotated_positions(workflow, "t")

      assert [
               %{position: {:kind, :pending}, group_key: nil, group_anchor: false},
               %{position: {:kind, :generation}, group_key: "generation", group_anchor: true},
               %{
                 position: {:gate, "product-review"},
                 group_key: "generation",
                 group_anchor: false
               }
             ] = annotated
    end
  end

  describe "resolve_position/3 against the shipped default-flow bundle" do
    setup do
      assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
      %{workflow: workflow}
    end

    test "a gate name resolves to {:gate, name}, unqualified", %{workflow: workflow} do
      assert Sequence.resolve_position(workflow, "delta", "ux-review") ==
               {{:gate, "ux-review"}, nil}
    end

    test "a status name resolves to {:kind, atom}, unqualified — the ordinary case", %{
      workflow: workflow
    } do
      assert Sequence.resolve_position(workflow, "delta", "generation") ==
               {{:kind, :generation}, nil}
    end
  end

  describe "resolve_position/3 (workflow.md #7, ORC-171)" do
    # `pending` recurs across `setup`'s and a top-level entry's own —
    # see `name/4`'s own describe block below for why `generation` (not
    # `setup`/`retro`) is the anchor kind these fixtures reuse.
    defp ambiguous_workflow do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{status: "pending"},
        %Status{review: "review"},
        %Status{status: "checks"}
      ]

      type = %Type{
        name: "t",
        skeleton: "ticket",
        statuses: statuses,
        groups: [0..1//1]
      }

      %Workflow{name: "test", entry: "t", gates: %{}, environments: %{}, types: %{"t" => type}}
    end

    test "a qualified reference resolves to its own occurrence's anchor" do
      assert Sequence.resolve_position(ambiguous_workflow(), "t", "generation.pending") ==
               {{:kind, :pending}, "generation.pending"}
    end

    test "a bare reference resolves to the one occurrence it unambiguously names" do
      assert Sequence.resolve_position(ambiguous_workflow(), "t", "pending") ==
               {{:kind, :pending}, nil}
    end
  end

  describe "name/4 (workflow.md #7, ORC-155, ORC-171)" do
    setup do
      assert {:ok, %{workflow: %Workflow{} = workflow}} = Dsl.load(".")
      %{workflow: workflow}
    end

    test "a gate's own name is its whole identity", %{workflow: workflow} do
      assert Sequence.name(workflow, "delta", {:gate, "ux-review"}, nil) == "ux-review"
    end

    test "a status kind with no authored name: defaults to the kind", %{workflow: workflow} do
      assert Sequence.name(workflow, "delta", {:kind, :generation}, nil) == "generation"
    end

    test "nil has no name", %{workflow: workflow} do
      assert Sequence.name(workflow, "delta", nil, nil) == nil
    end

    test "a kind absent from the type's own array falls back to the kind itself", %{
      workflow: workflow
    } do
      assert Sequence.name(workflow, "delta", {:kind, :blocked}, nil) == "blocked"
    end
  end

  describe "name/4 disambiguates a recurring kind by its anchor (ORC-171)" do
    # `pending` recurs across `generation`'s own leading entry and a
    # top-level entry, neither carrying a `name:` override — the
    # ordinary, motivating shape (`setup`.`pending`/`retro`.`pending`,
    # no override on either): ambiguity is computed off `Status.name/1`
    # (`workflow.md` #7), so two entries only share one bare
    # identity when neither's own authored name pulls them apart, which
    # is exactly the case a `name:` override would break — not this
    # ticket's own gap, since a distinctly-named entry never needed
    # disambiguating in the first place (its own `qualified` value was
    # already unique).
    defp ambiguous_named_workflow do
      statuses = [
        %Status{status: "pending"},
        %Status{status: "generation"},
        %Status{status: "pending"},
        %Status{review: "review"},
        %Status{status: "checks"}
      ]

      type = %Type{
        name: "t",
        skeleton: "ticket",
        statuses: statuses,
        groups: [0..1//1]
      }

      %Workflow{name: "test", entry: "t", gates: %{}, environments: %{}, types: %{"t" => type}}
    end

    test "the group-qualified occurrence resolves without crashing on the ambiguity" do
      assert Sequence.name(ambiguous_named_workflow(), "t", {:kind, :pending}, "generation") ==
               "pending"
    end

    test "the top-level, unqualified occurrence resolves separately" do
      assert Sequence.name(ambiguous_named_workflow(), "t", {:kind, :pending}, nil) == "pending"
    end

    test "an anchor naming neither real occurrence falls back to the bare kind rather than guessing" do
      assert Sequence.name(ambiguous_named_workflow(), "t", {:kind, :pending}, "no-such-anchor") ==
               "pending"
    end
  end

  describe "a recurring kind carrying distinct name: overrides (ORC-198)" do
    # `setup.pending`/`retro.pending`, each with its own `name:`
    # override — the exact shape `canonical == bare` (ORC-171's own
    # test) never flags: each entry's own authored name is unique, so
    # the old anchor test gave both `anchor: nil`, indistinguishable
    # once paired with `to_position/1`'s identical `{:kind, :pending}`
    # for both. `kind_ambiguous` is keyed on `status:` alone and does
    # not miss it.
    defp kind_recurring_named_workflow do
      statuses = [
        %Status{status: "pending", name: "alpha"},
        %Status{status: "setup"},
        %Status{status: "pending", name: "beta"},
        %Status{status: "retro"}
      ]

      type = %Type{
        name: "t",
        skeleton: "ticket",
        statuses: statuses,
        groups: [0..1//1, 2..3//1]
      }

      %Workflow{name: "test", entry: "t", gates: %{}, environments: %{}, types: %{"t" => type}}
    end

    test "annotated_positions/2 carries each occurrence's own group anchor, not nil" do
      annotated = Sequence.annotated_positions(kind_recurring_named_workflow(), "t")

      assert Enum.map(annotated, & &1.position) == [
               {:kind, :pending},
               {:kind, :setup},
               {:kind, :pending},
               {:kind, :retro}
             ]

      assert Enum.map(annotated, & &1.anchor) == ["setup.alpha", nil, "retro.beta", nil]
    end

    test "resolve_position/3 resolves each occurrence's own bare name to its own anchor" do
      workflow = kind_recurring_named_workflow()

      assert Sequence.resolve_position(workflow, "t", "alpha") ==
               {{:kind, :pending}, "setup.alpha"}

      assert Sequence.resolve_position(workflow, "t", "beta") ==
               {{:kind, :pending}, "retro.beta"}
    end

    test "resolve_position/3 resolves each occurrence's own qualified name identically" do
      workflow = kind_recurring_named_workflow()

      assert Sequence.resolve_position(workflow, "t", "setup.alpha") ==
               {{:kind, :pending}, "setup.alpha"}

      assert Sequence.resolve_position(workflow, "t", "retro.beta") ==
               {{:kind, :pending}, "retro.beta"}
    end

    test "name/4 tells the two occurrences apart by anchor" do
      workflow = kind_recurring_named_workflow()

      assert Sequence.name(workflow, "t", {:kind, :pending}, "setup.alpha") == "alpha"
      assert Sequence.name(workflow, "t", {:kind, :pending}, "retro.beta") == "beta"
    end
  end

  describe "a recurring kind carrying distinct name: overrides inside ONE namespace (ORC-202)" do
    # The case `kind_recurring_named_workflow/0` above does not reach:
    # its two `pending` entries sit in *different* sub-arrays, so the
    # group anchor ("setup"/"retro") tells them apart on its own. Here
    # both are top-level, which `workflow.md` #7 permits — names
    # are unique within a namespace, kinds need not be ("three
    # `pending` entries" is its own example) — and the namespace is
    # therefore identical for both. Anything keyed on the namespace
    # alone reads one qualifier for two occurrences, and at the top
    # level that qualifier is the atom `:top_level` while `anchor()` is
    # declared `String.t() | nil`.
    defp same_namespace_named_workflow do
      statuses = [
        %Status{status: "pending", name: "alpha"},
        %Status{status: "pending", name: "beta"},
        %Status{status: "checks"}
      ]

      type = %Type{
        name: "t",
        skeleton: "ticket",
        statuses: statuses,
        groups: []
      }

      %Workflow{name: "test", entry: "t", gates: %{}, environments: %{}, types: %{"t" => type}}
    end

    test "each occurrence carries a distinct qualifier, and every one is a string" do
      annotated = Sequence.annotated_positions(same_namespace_named_workflow(), "t")

      assert Enum.map(annotated, & &1.position) == [
               {:kind, :pending},
               {:kind, :pending},
               {:kind, :checks}
             ]

      [alpha, beta, _checks] = annotated

      assert alpha.anchor == "alpha"
      assert beta.anchor == "beta"
      refute alpha.anchor == beta.anchor

      for %{anchor: anchor} <- annotated, not is_nil(anchor) do
        assert is_binary(anchor), "anchor() is String.t() | nil; got #{inspect(anchor)}"
      end
    end

    test "name/4 resolves each occurrence rather than whichever comes first" do
      workflow = same_namespace_named_workflow()

      assert Sequence.name(workflow, "t", {:kind, :pending}, "alpha") == "alpha"
      assert Sequence.name(workflow, "t", {:kind, :pending}, "beta") == "beta"
    end

    test "resolve_position/3 round-trips each name to the qualifier annotate/4 stored" do
      workflow = same_namespace_named_workflow()
      annotated = Sequence.annotated_positions(workflow, "t")
      [alpha, beta, _checks] = annotated

      assert Sequence.resolve_position(workflow, "t", "alpha") ==
               {{:kind, :pending}, alpha.anchor}

      assert Sequence.resolve_position(workflow, "t", "beta") == {{:kind, :pending}, beta.anchor}
    end
  end

  defp workflow_with(status_names) do
    type = %Type{
      name: "t",
      skeleton: "ticket",
      statuses: Enum.map(status_names, &%Status{status: &1})
    }

    %Workflow{
      name: "test",
      entry: "t",
      gates: %{},
      environments: %{},
      types: %{"t" => type}
    }
  end
end
