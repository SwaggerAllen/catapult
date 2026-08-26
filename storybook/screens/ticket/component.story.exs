defmodule Catapult.Storybook.Screens.TicketStory do
  @moduledoc """
  Variations for `screens/ticket.md`. Each variation id is the state name — `screens/ticket.md`
  and this file are the only two places the state list exists.
  """

  use PhoenixStorybook.Story, :component

  alias Catapult.Storybook.Screens.Ticket

  def function, do: &Ticket.ticket/1

  defp base_sequence do
    [
      %{key: "pending", label: "Pending", kind: :status, role: nil, state: :passed},
      %{key: "generation", label: "Generation", kind: :status, role: nil, state: :passed},
      %{
        key: "product-review",
        label: "Product review",
        kind: :gate,
        role: "product",
        state: :current
      },
      %{
        key: "architecture-review",
        label: "Architecture review",
        kind: :gate,
        role: "architecture",
        state: :upcoming
      },
      %{key: "checks", label: "Checks", kind: :status, role: nil, state: :upcoming}
    ]
  end

  def variations do
    [
      %Variation{
        id: :gate_awaiting_sign_off,
        description:
          "Resting at a review gate: the argument, the sequence rail, and a link to " <>
            "document-review — this screen never dispatches the gate command itself, since " <>
            "every Phase 4 gate reviews prose.",
        attributes: %{
          id: "ORC-75",
          title: "UI v1: the working surface, and the authoring loop's floor",
          argument:
            "Four screens, one ticket, because they share a projection surface and a command " <>
              "path — the authoring loop has no surface at all until they exist.",
          sequence: base_sequence(),
          gate_action: %{role: "product", href: "#"},
          blocked: nil,
          conflict: nil,
          children: [],
          prs: [%{number: 68, status: "open", href: "#"}],
          runs: [%{id: "run_9f2a", status: "succeeded", href: "#"}]
        }
      },
      %Variation{
        id: :no_gate_pending,
        description:
          "Resting at an ordinary status rather than a gate — no sign-off pending, so no gate " <>
            "card renders.",
        attributes: %{
          id: "ORC-75",
          title: "UI v1: the working surface, and the authoring loop's floor",
          argument: "Four screens, one ticket, because they share a projection surface.",
          sequence: [
            %{key: "pending", label: "Pending", kind: :status, role: nil, state: :passed},
            %{key: "generation", label: "Generation", kind: :status, role: nil, state: :current},
            %{
              key: "product-review",
              label: "Product review",
              kind: :gate,
              role: "product",
              state: :upcoming
            }
          ],
          gate_action: nil,
          blocked: nil,
          conflict: nil,
          children: [],
          prs: [],
          runs: []
        }
      },
      %Variation{
        id: :blocked_needs_setup,
        description:
          "Blocked, flavor needs-setup: the origin status and the return control, defaulting to " <>
            "origin with earlier positions offered behind it — never forward. Choosing one " <>
            "dispatches ResumeFlow.",
        attributes: %{
          id: "ORC-40",
          title: "Point the README at SETUP for the reference instance",
          argument: "SETUP.md §2 is the one home for the reference instance's live facts.",
          sequence: [
            %{key: "pending", label: "Pending", kind: :status, role: nil, state: :passed},
            %{key: "generation", label: "Generation", kind: :status, role: nil, state: :current},
            %{key: "checks", label: "Checks", kind: :status, role: nil, state: :upcoming}
          ],
          gate_action: nil,
          blocked: %{
            flavor: "needs-setup",
            origin_label: "Generation",
            return_options: [
              %{label: "Generation", target: "generation"},
              %{label: "Pending", target: "pending"}
            ]
          },
          conflict: nil,
          children: [],
          prs: [],
          runs: []
        }
      },
      %Variation{
        id: :rejected_resume,
        description:
          "A stale ResumeFlow was rejected by the compare-and-swap — someone else already " <>
            "resumed this ticket. The conflict names the position it moved to, not who moved " <>
            "it (neither ResumeFlow nor the gate commands' own compare carries an actor), " <>
            "rendered at the point of action rather than as a later revert.",
        attributes: %{
          id: "ORC-40",
          title: "Point the README at SETUP for the reference instance",
          argument: "SETUP.md §2 is the one home for the reference instance's live facts.",
          sequence: [
            %{key: "pending", label: "Pending", kind: :status, role: nil, state: :passed},
            %{key: "generation", label: "Generation", kind: :status, role: nil, state: :current},
            %{key: "checks", label: "Checks", kind: :status, role: nil, state: :upcoming}
          ],
          gate_action: nil,
          blocked: %{
            flavor: "needs-setup",
            origin_label: "Generation",
            return_options: [
              %{label: "Generation", target: "generation"},
              %{label: "Pending", target: "pending"}
            ]
          },
          conflict: %{to: "Pending"},
          children: [],
          prs: [],
          runs: []
        }
      },
      %Variation{
        id: :feature_with_children,
        description:
          "A feature ticket's flat child roll-up, each child showing its own position.",
        attributes: %{
          id: "ORC-75",
          title: "UI v1: the working surface, and the authoring loop's floor",
          argument: "Four screens, one ticket.",
          sequence: base_sequence(),
          gate_action: %{role: "product", href: "#"},
          blocked: nil,
          conflict: nil,
          children: [
            %{id: "ORC-75-1", title: "my-queue component", position_label: "Checks"},
            %{id: "ORC-75-2", title: "board component", position_label: "Generation"}
          ],
          prs: [],
          runs: []
        }
      }
    ]
  end
end
