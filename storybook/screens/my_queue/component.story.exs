defmodule Catapult.Storybook.Screens.MyQueueStory do
  @moduledoc """
  Variations for `screens/my-queue.md`. Each variation id is the state name — `screens/
  my-queue.md` and this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.MyQueue

  def function, do: &MyQueue.my_queue/1

  defp cross_project_rows do
    [
      %{
        id: "ORC-75",
        project_id: "proj_catapult",
        project_name: "Catapult",
        title: "UI v1: the working surface, and the authoring loop's floor",
        status: "Design review",
        kind: :sign_off,
        href: "#"
      },
      %{
        id: "ACME-12",
        project_id: "proj_acme",
        project_name: "Acme Storefront",
        title: "Checkout: add saved-address autofill",
        status: "Blocked",
        kind: :unblock,
        href: "#"
      },
      %{
        id: "ACME-9",
        project_id: "proj_acme",
        project_name: "Acme Storefront",
        title: "Nightly advisory bump: postgrex",
        status: "Todo",
        kind: :triage,
        href: "#"
      }
    ]
  end

  def variations do
    [
      %Variation{
        id: :assigned_default,
        description:
          "The default view: tickets assigned to you, across every project you touch — sign-off, " <>
            "unblock and triage rows side by side, each naming its project.",
        attributes: %{tab: :assigned, rows: cross_project_rows()}
      },
      %Variation{
        id: :my_roles,
        description:
          "The 'could I unblock something' view: statuses a held role owns, whether or not " <>
            "anyone is assigned yet.",
        attributes: %{
          tab: :my_roles,
          rows: cross_project_rows() |> Enum.take(2)
        }
      },
      %Variation{
        id: :empty_assigned,
        description:
          "A real state, not a loading spinner: nothing assigned means the machine has the ball. " <>
            "Links to explain-why.",
        attributes: %{tab: :assigned, rows: []}
      },
      %Variation{
        id: :single_project_still_labeled,
        description:
          "Even with every row from one project, the project column stays — the read is never " <>
            "scoped to one, so nothing here should look like it is.",
        attributes: %{
          tab: :assigned,
          rows: cross_project_rows() |> Enum.filter(&(&1.project_id == "proj_acme"))
        }
      }
    ]
  end
end
