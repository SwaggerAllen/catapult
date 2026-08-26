defmodule CatapultWeb.BoardLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.Board.board/1` (`screens/
  board.md`): swim lanes for one project, in the effective sequence
  `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` returns for
  the selected ticket type — the lane order *is* the sequence, never a
  separate workflow view.

  **"Lanes abbreviate to the ones you have standing in" degenerates to
  "every lane" in Phase 4** (`screens/board.md`, `systems/dashboard.md`'s
  ORC-114 entry): no role-holder projection exists yet, so the
  abbreviated view and the full one coincide and `show_all_lanes` is
  rendered but not yet wired to anything that would narrow it.

  Fan-out is already collapsed, but not by a rendering choice this
  module makes: `Catapult.Engine.Store.Flow` carries no parent-flow
  reference in Phase 4 (fan-out below the top-level ticket is a node/
  tier concept today, not a second flow instance), so `children` is
  always `[]` — recorded in this ticket's hand-back as a real gap
  rather than a v1 narrowing, since nothing here is choosing to hide
  data that exists.

  Cards never dispatch `ApproveGate`/`DeclineGate` (`screens/board.md`'s
  own ORC-114 correction): a gate lane's card links to `document-review`
  instead.
  """
  use CatapultWeb, :live_view

  alias Catapult.Config
  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias CatapultWeb.Live.EventFacts
  alias CatapultWeb.Live.Positions

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    {:ok, assign(socket, project_id: project_id)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    project_id = socket.assigns.project_id
    filters = %{type: presence(params["type"]), label: nil}
    show_all_lanes = params["all"] == "true"
    tickets = DeliveryStore.tickets_for_project(project_id)

    {lanes, cards} =
      case Dsl.load(Config.fetch!(:engine, :bundles_root)) do
        {:ok, %{workflow: workflow}} when not is_nil(workflow) ->
          type_name = filters.type || default_type(tickets, workflow)
          lanes = Sequence.positions(workflow, type_name) |> Enum.map(&lane/1)

          cards =
            tickets
            |> Enum.filter(&(&1.flow_name == type_name))
            |> Enum.map(&card(&1, project_id, workflow))

          {lanes, cards}

        _no_workflow_bundle ->
          {[], []}
      end

    {:noreply,
     assign(socket,
       project_name: project_id,
       lanes: lanes,
       cards: cards,
       filters: filters,
       show_all_lanes: show_all_lanes
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Catapult.Storybook.Screens.Board.board
      project_name={@project_name}
      lanes={@lanes}
      cards={@cards}
      filters={@filters}
      show_all_lanes={@show_all_lanes}
    />
    """
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp lane(position) do
    %{
      key: Positions.key(position),
      label: Positions.label(position),
      kind: Positions.kind(position)
    }
  end

  defp default_type(tickets, workflow) do
    case tickets
         |> Enum.frequencies_by(& &1.flow_name)
         |> Enum.max_by(&elem(&1, 1), fn -> nil end) do
      {name, _count} -> name
      nil -> first_ticket_type(workflow)
    end
  end

  # `Map.keys/1`'s own order is unspecified, so "the first ticket type"
  # needs a real tiebreak to be deterministic across runs — name order,
  # since there is no other declared ranking between two ticket types
  # (`Catapult.Dsl.Workflow` itself draws none).
  defp first_ticket_type(%{types: types}) do
    types
    |> Enum.filter(fn {_name, type} -> type.skeleton == "ticket" end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
    |> List.first()
  end

  defp card(ticket, project_id, workflow) do
    position = Positions.from_columns(ticket.status_kind, ticket.status_gate)
    origin = Positions.from_columns(ticket.blocked_origin_kind, ticket.blocked_origin_gate)
    lane_position = if position == {:kind, :blocked}, do: origin, else: position

    %{
      id: ticket.ticket_ref || ticket.id,
      title: Phoenix.Naming.humanize(ticket.flow_name || ""),
      type: ticket.flow_name,
      lane_key: lane_position && Positions.key(lane_position),
      children: [],
      blocked: blocked(ticket, project_id, origin),
      gate: gate(position, project_id, ticket, workflow)
    }
  end

  defp blocked(%{status_kind: "blocked"}, project_id, origin) do
    %{
      flavor: EventFacts.blocked_flavor(project_id),
      origin_label: origin && Positions.label(origin)
    }
  end

  defp blocked(_ticket, _project_id, _origin), do: nil

  defp gate({:gate, _name} = position, project_id, ticket, workflow) do
    %{
      role: Positions.role(position, workflow),
      href: "/projects/#{project_id}/tickets/#{ticket.id}/review"
    }
  end

  defp gate(_position, _project_id, _ticket, _workflow), do: nil
end
