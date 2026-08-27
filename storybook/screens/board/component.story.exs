defmodule Catapult.Storybook.Screens.BoardStory do
  @moduledoc """
  Variations for `screens/board.md`. Each variation id is the state name — `screens/board.md` and
  this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.Board

  def function, do: &Board.board/1

  defp lanes do
    [
      %{key: "pending", label: "Pending", kind: :status, group_key: nil, group_anchor: false},
      %{
        key: "generation",
        label: "Generation",
        kind: :status,
        group_key: "review-loop",
        group_anchor: true
      },
      %{
        key: "product-review",
        label: "Product review",
        kind: :gate,
        group_key: "review-loop",
        group_anchor: false
      },
      %{
        key: "architecture-review",
        label: "Architecture review",
        kind: :gate,
        group_key: "review-loop",
        group_anchor: false
      },
      %{key: "checks", label: "Checks", kind: :status, group_key: nil, group_anchor: false}
    ]
  end

  def variations do
    [
      %Variation{
        id: :in_flight_project,
        description:
          "The daily view: several top-level tickets across the effective sequence, one fanned " <>
            "out into components rolled up on its own card, sitting in a gate lane grouped with " <>
            "Generation into one visible review-loop box — the two groupings (fan-out on the " <>
            "card, subflow around the lanes) compose without colliding.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "architecture-review",
              blocked: nil,
              gate: %{role: "architecture-review", href: "#"},
              children: [
                %{id: "ORC-75-1", lane_key: "generation", lane_label: "Generation"},
                %{id: "ORC-75-2", lane_key: "checks", lane_label: "Checks"}
              ]
            },
            %{
              id: "ORC-36",
              title: "Prove the authoring loop end to end",
              type: "feature",
              lane_key: "pending",
              blocked: nil,
              gate: nil,
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :blocked_grouped_under_origin,
        description:
          "A blocked card renders inside the lane it was standing at when it was kicked out — " <>
            "not in a lane of its own — with the flavor and origin named.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil},
          cards: [
            %{
              id: "ORC-40",
              title: "Point the README at SETUP for the reference instance",
              type: "feature",
              lane_key: "generation",
              blocked: %{flavor: "needs-setup", origin_label: "Generation"},
              gate: nil,
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :pending_gate_links_out,
        description:
          "A card sitting at a review gate: no Approve/Throw-back on the card itself — every " <>
            "Phase 4 gate reviews prose, so the card links into document-review (or ticket) " <>
            "rather than dispatching a command it cannot honestly compare-and-swap.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "product-review",
              blocked: nil,
              gate: %{role: "product-review", href: "#"},
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :filtered_and_abbreviated,
        description:
          "Filtered by type and label, lanes abbreviated to the ones the viewer has standing " <>
            "in — a reviewer's standing is the whole review-loop group here, so the group " <>
            "renders whole rather than fractured; most lanes are simply not shown, not " <>
            "shown-and-empty.",
        attributes: %{
          project_name: "Catapult",
          lanes: Enum.filter(lanes(), &(&1.group_key == "review-loop")),
          show_all_lanes: false,
          filters: %{type: "feature", label: "priority"},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "product-review",
              blocked: nil,
              gate: %{role: "product-review", href: "#"},
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :empty_lanes,
        description: "No tickets in flight — every lane renders its own empty placeholder.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil},
          cards: []
        }
      }
    ]
  end
end
