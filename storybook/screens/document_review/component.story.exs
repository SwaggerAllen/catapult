defmodule Catapult.Storybook.Screens.DocumentReviewStory do
  @moduledoc """
  Variations for `screens/document-review.md`. Each variation id is the state name — `screens/
  document-review.md` and this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.DocumentReview

  def function, do: &DocumentReview.document_review/1

  defp sentences do
    [
      %{index: 0, text: "The dashboard owns the work loop.", change: :unchanged},
      %{index: 1, text: "It also owns event-log inspection and explain-why.", change: :unchanged},
      %{
        index: 2,
        text: "Screens are designed through orchestration's native screen machinery.",
        change: :added
      },
      %{index: 3, text: "This is a debugging surface only.", change: :removed}
    ]
  end

  def variations do
    [
      %Variation{
        id: :first_pass_clean,
        description:
          "A first review pass, nothing commented yet: added and unchanged sentences, no prior " <>
            "body to diff against so nothing is marked removed.",
        attributes: %{
          node_id: "comparch:dashboard",
          tier: "comparch",
          body_sha: "a1b2c3d",
          sentences: Enum.reject(sentences(), &(&1.change == :removed)),
          comments: [],
          gate_exits: [%{label: "Generation", target: "generation"}],
          decline_error: nil
        }
      },
      %Variation{
        id: :regeneration_diff_with_comment,
        description:
          "A regeneration's diff: one sentence added, one removed, and a comment anchored to " <>
            "the sentence it's about — the anchor the harvester will bucket on.",
        attributes: %{
          node_id: "comparch:dashboard",
          tier: "comparch",
          body_sha: "e5f6a7b",
          sentences: sentences(),
          comments: [
            %{
              sentence_index: 3,
              author: "@author",
              body: "This is stale now — the reversal already happened, say so plainly."
            }
          ],
          gate_exits: [%{label: "Generation", target: "generation"}],
          decline_error: nil
        }
      },
      %Variation{
        id: :decline_rejected_no_comment,
        description:
          "A throw-back attempted with no comment: rejected at the point of action, per ORC-34 " <>
            "— never dispatched with blank feedback.",
        attributes: %{
          node_id: "comparch:dashboard",
          tier: "comparch",
          body_sha: "e5f6a7b",
          sentences: sentences(),
          comments: [],
          gate_exits: [%{label: "Generation", target: "generation"}],
          decline_error: "Name at least one comment before throwing this back."
        }
      },
      %Variation{
        id: :resolution_conflict,
        description:
          "An approve rejected by the compare-and-swap landed at ORC-114 — either this gate was " <>
            "already resolved by a racing writer, or the body regenerated underneath this " <>
            "screen's own view. Rendered synchronously, at the point of action, the same slot " <>
            "the no-comment rejection above uses.",
        attributes: %{
          node_id: "comparch:dashboard",
          tier: "comparch",
          body_sha: "f9e8d7c",
          sentences: sentences(),
          comments: [],
          gate_exits: [%{label: "Generation", target: "generation"}],
          decline_error:
            "This gate was already resolved, or the body changed underneath this view. " <>
              "Refresh to see the current state before trying again."
        }
      }
    ]
  end
end
