defmodule Catapult.Storybook.Screens.ExplainWhyStory do
  @moduledoc """
  Variations for `screens/explain-why.md`. Each variation id is the state name —
  `screens/explain-why.md` and this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.ExplainWhy

  def function, do: &ExplainWhy.explain_why/1

  @project_id "proj_9f2a"

  def variations do
    [
      %Variation{
        id: :blocked_on_context,
        description:
          "One unsatisfied walk, its target still absent — the ordinary blocked shape.",
        attributes: %{
          project_id: @project_id,
          node_id: "comparch:dashboard",
          tier: "comparch",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [
            %{
              walk: "self.parent.dependency -> comp.handle.fragments[pubapi]",
              satisfied: false,
              targets: [%{node_id: "comp:dashboard", tier: "comp", status: :absent}]
            }
          ],
          review_tier?: false
        }
      },
      %Variation{
        id: :multiple_targets_partial,
        description:
          "A multi-target walk, partially satisfied — two of three dependency comps approved, " <>
            "one still drafted, rendered per-target rather than collapsed to pass/fail.",
        attributes: %{
          project_id: @project_id,
          node_id: "impl:dashboard",
          tier: "impl",
          scope_key: %{"per" => "subcomp:dashboard"},
          passes_scope_filter: true,
          blocking: [
            %{
              walk: "self.parent.dependency -> subcomp.handle.fragments[pubapi]",
              satisfied: false,
              targets: [
                %{node_id: "subcomp:auth", tier: "subcomp", status: :approved},
                %{node_id: "subcomp:billing", tier: "subcomp", status: :approved},
                %{node_id: "subcomp:reporting", tier: "subcomp", status: :drafted}
              ]
            }
          ],
          review_tier?: false
        }
      },
      %Variation{
        id: :unsupported_walk,
        description:
          "Illustrative only — no tier in bundles/default can produce this today. A " <>
            "ticket.<source> walk resolves :unsupported until an extension registers a context " <>
            "source (chain.ex's Registry.context_source?/2 check rejects the walk at load " <>
            "otherwise, so no bundle content can reach this row yet); shown mixed with an " <>
            "ordinary blocker for the visual treatment Phase 7 will need. input.<role> walks " <>
            "never reach this state (ORC-107) — a role resolves satisfied with no targets and " <>
            "never appears in blocking at all.",
        attributes: %{
          project_id: @project_id,
          node_id: "hypothetical_extension_tier:dashboard",
          tier: "hypothetical_extension_tier",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [
            %{walk: "ticket.findings", satisfied: false, targets: [], reason: :unsupported},
            %{
              walk: "self.parent.handle",
              satisfied: false,
              targets: [%{node_id: "sysarch:root", tier: "sysarch", status: :drafted}]
            }
          ],
          review_tier?: false
        }
      },
      %Variation{
        id: :excluded_by_scope_filter,
        description:
          "passes_scope_filter is false — this node was never a candidate, whatever its context looks like.",
        attributes: %{
          project_id: @project_id,
          node_id: "subcomparch:legacy_billing",
          tier: "subcomparch",
          scope_key: %{"per" => "subcomp:legacy_billing"},
          passes_scope_filter: false,
          blocking: [],
          review_tier?: false
        }
      },
      %Variation{
        id: :fully_satisfied,
        description:
          "Every context walk resolved and approved — nothing in scope is blocking this node.",
        attributes: %{
          project_id: @project_id,
          node_id: "comparch:dashboard",
          tier: "comparch",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [],
          review_tier?: false
        }
      },
      %Variation{
        id: :stale_content,
        description:
          "Fully satisfied and stale at once — nothing is blocking this node, and its committed " <>
            "content predates a ref it depends on that was edited and re-approved since. The two " <>
            "facts render independently: the ordinary blocking sections stay empty while the " <>
            "content-status badge and detail block name what moved.",
        attributes: %{
          project_id: @project_id,
          node_id: "impl:dashboard",
          tier: "impl",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [],
          review_tier?: false,
          stale: true,
          stale_because: [
            %{
              walk: "self.parent.dependency -> ref.handle",
              targets: [%{node_id: "ref:runbook", tier: "ref", status: :approved}]
            }
          ]
        }
      },
      %Variation{
        id: :stale_unknown,
        description:
          "Illustrative only, same reachability caveat as unsupported_walk above — a node whose " <>
            "tier declares a ticket.<source> walk can't have its staleness computed for that walk, " <>
            "which reads as \"unknown,\" never as the green \"current\" state.",
        attributes: %{
          project_id: @project_id,
          node_id: "hypothetical_extension_tier:dashboard",
          tier: "hypothetical_extension_tier",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [
            %{walk: "ticket.findings", satisfied: false, targets: [], reason: :unsupported}
          ],
          review_tier?: false,
          stale: :unknown,
          stale_because: []
        }
      },
      %Variation{
        id: :review_tier_caveat,
        description:
          "A review tier: blocking is structurally always empty (no context: of its own), so the " <>
            "screen says explicitly that this is not the same fact as 'ready for review'.",
        attributes: %{
          project_id: @project_id,
          node_id: "comparch_review:dashboard",
          tier: "comparch_review",
          scope_key: %{},
          passes_scope_filter: true,
          blocking: [],
          review_tier?: true
        }
      }
    ]
  end
end
