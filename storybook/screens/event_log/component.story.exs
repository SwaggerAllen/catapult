defmodule Catapult.Storybook.Screens.EventLogStory do
  @moduledoc """
  Variations for `screens/event-log.md`. Each variation id is the state name —
  `screens/event-log.md` and this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.EventLog

  def function, do: &EventLog.event_log/1

  @project_id "proj_9f2a"

  defp events do
    [
      %{
        id: "evt_1",
        type: "container_minted",
        recorded_version: 1,
        current_version: 1,
        occurred_at: "2026-08-19 09:02:11Z",
        actor_id: "author",
        container_id: "ORC-35",
        node_id: nil,
        summary: "Container minted for ORC-35",
        payload: %{project_id: @project_id, container_id: "ORC-35", type_name: "feature"}
      },
      %{
        id: "evt_2",
        type: "draft_committed",
        recorded_version: 1,
        current_version: 1,
        occurred_at: "2026-08-19 09:05:44Z",
        actor_id: nil,
        container_id: "ORC-35",
        node_id: "comparch:dashboard",
        summary: "comparch draft committed",
        payload: %{node_id: "comparch:dashboard", tier: "comparch", body_sha: "a1b2c3d"}
      },
      %{
        id: "evt_3",
        type: "review_written",
        recorded_version: 1,
        current_version: 2,
        occurred_at: "2026-08-19 09:06:02Z",
        actor_id: nil,
        container_id: "ORC-35",
        node_id: "comparch:dashboard",
        summary: "Review written, score 73",
        payload: %{
          project_id: @project_id,
          draft_id: "draft_44",
          review_id: "rev_12",
          score: 73,
          kind: :ai,
          findings: []
        }
      },
      %{
        id: "evt_4",
        type: "run_failed",
        recorded_version: 1,
        current_version: 1,
        occurred_at: "2026-08-19 09:12:30Z",
        actor_id: nil,
        container_id: "ORC-35",
        node_id: "impl:dashboard",
        summary: "Dispatch run failed (limit class)",
        payload: %{node_id: "impl:dashboard", tier: "impl", reason: "context_budget_exceeded"}
      },
      %{
        id: "evt_5",
        type: "flag_set_flipped",
        recorded_version: 1,
        current_version: 1,
        occurred_at: "2026-08-19 09:20:15Z",
        actor_id: "author",
        container_id: "ORC-35",
        node_id: nil,
        summary: "Flags flipped: [\"dashboard_v0\"]",
        payload: %{container_id: "ORC-35", request_id: "req_7", flags: ["dashboard_v0"]}
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :streaming,
        description:
          "The default view: one project's whole log, newest activity visible, nothing selected.",
        attributes: %{
          project_id: @project_id,
          events: events(),
          filters: %{container_id: nil, actor_id: nil, node_query: nil},
          selected: nil
        }
      },
      %Variation{
        id: :event_selected_upcasted,
        description:
          "A v1 review_written event opened: the detail pane discloses that it is stored at " <>
            "version 1 and shown upcast to version 2, and says so before showing the payload.",
        attributes: %{
          project_id: @project_id,
          events: events(),
          filters: %{container_id: nil, actor_id: nil, node_query: nil},
          selected: Enum.at(events(), 2)
        }
      },
      %Variation{
        id: :event_selected_current,
        description:
          "A current-shape event opened: recorded and shown versions match, so the detail pane " <>
            "carries one quiet version badge and no upcast disclosure.",
        attributes: %{
          project_id: @project_id,
          events: events(),
          filters: %{container_id: nil, actor_id: nil, node_query: nil},
          selected: Enum.at(events(), 3)
        }
      },
      %Variation{
        id: :filtered_by_ticket,
        description:
          "The 'ticket' filter from docs/ui-spec.md, bound to container_id — every row shares one ticket.",
        attributes: %{
          project_id: @project_id,
          events: events(),
          filters: %{container_id: "ORC-35", actor_id: nil, node_query: nil},
          selected: nil
        }
      },
      %Variation{
        id: :filtered_by_actor,
        description:
          "The 'actor' filter, bound to actor_id — narrowed to what a human (not the executor) did.",
        attributes: %{
          project_id: @project_id,
          events: events() |> Enum.filter(&(&1.actor_id == "author")),
          filters: %{container_id: nil, actor_id: "author", node_query: nil},
          selected: nil
        }
      },
      %Variation{
        id: :node_scoped_from_explain_why,
        description:
          "Arrived via explain-why's node link: a banner names where the filter came from, " <>
            "list narrowed to events touching that one node.",
        attributes: %{
          project_id: @project_id,
          events: events() |> Enum.filter(&(&1.node_id == "impl:dashboard")),
          filters: %{container_id: nil, actor_id: nil, node_query: "impl:dashboard"},
          selected: nil
        }
      },
      %Variation{
        id: :empty_stream,
        description:
          "A project with no events yet — a real state, not a loading spinner or an error.",
        attributes: %{
          project_id: "proj_new",
          events: [],
          filters: %{container_id: nil, actor_id: nil, node_query: nil},
          selected: nil
        }
      }
    ]
  end
end
