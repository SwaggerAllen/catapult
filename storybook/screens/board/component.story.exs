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
      %{key: "pending", label: "Pending", kind: :status},
      %{key: "generation", label: "Generation", kind: :status},
      %{key: "product-review", label: "Product review", kind: :gate},
      %{key: "architecture-review", label: "Architecture review", kind: :gate},
      %{key: "checks", label: "Checks", kind: :status}
    ]
  end

  def variations do
    [
      %Variation{
        id: :in_flight_project,
        description:
          "The daily view: several top-level tickets across the effective sequence, one fanned " <>
            "out into components rolled up on its own card.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil, assignee: nil},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "architecture-review",
              blocked: nil,
              conflict: nil,
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
              conflict: nil,
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
          filters: %{type: nil, label: nil, assignee: nil},
          cards: [
            %{
              id: "ORC-40",
              title: "Point the README at SETUP for the reference instance",
              type: "feature",
              lane_key: "generation",
              blocked: %{flavor: "needs-setup", origin_label: "Generation"},
              conflict: nil,
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :card_conflict_on_pass_forward,
        description:
          "A pass-forward rejected by the compare-and-swap: the card shows who already moved it " <>
            "and to where, in place, rather than silently failing.",
        attributes: %{
          project_name: "Catapult",
          lanes: lanes(),
          show_all_lanes: false,
          filters: %{type: nil, label: nil, assignee: nil},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "product-review",
              blocked: nil,
              conflict: %{by: "@author", to: "Architecture review"},
              children: []
            }
          ]
        }
      },
      %Variation{
        id: :filtered_and_abbreviated,
        description:
          "Filtered by type and assignee, lanes abbreviated to the ones the viewer has standing " <>
            "in — most lanes are simply not shown, not shown-and-empty.",
        attributes: %{
          project_name: "Catapult",
          lanes: Enum.filter(lanes(), &(&1.key in ["product-review", "checks"])),
          show_all_lanes: false,
          filters: %{type: "feature", label: nil, assignee: "@author"},
          cards: [
            %{
              id: "ORC-75",
              title: "UI v1: the working surface",
              type: "feature",
              lane_key: "product-review",
              blocked: nil,
              conflict: nil,
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
          filters: %{type: nil, label: nil, assignee: nil},
          cards: []
        }
      }
    ]
  end
end
