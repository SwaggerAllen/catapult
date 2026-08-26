defmodule CatapultWeb.MyQueueLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.MyQueue.my_queue/1` (`screens/
  my-queue.md`): the one cross-project screen in this system
  (`systems/dashboard.md`'s ORC-75 narrowing of ORC-87) — one
  project-scoped `Catapult.Delivery.Store.tickets_for_project/1` read
  per project `Catapult.Engine.Store.list_project_ids/0` names, merged
  for display, never a query missing a project id.

  Both tabs read the identical set in Phase 4 (`screens/my-queue.md`'s
  "In Phase 4 both tabs show the identical set" — no assignee or
  role-holder projection exists yet); `tab` still switches the label,
  since the two questions are protocol-real and will diverge once
  identity ships one.

  This screen issues no commands (`screens/my-queue.md`): every row is
  a pointer into `document-review` (a `sign_off` row — every Phase 4
  gate reviews prose) or `ticket` (an `unblock` row), never a control
  rendered here.
  """
  use CatapultWeb, :live_view

  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Engine.Store, as: EngineStore
  alias CatapultWeb.Live.Positions

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "my_roles", do: :my_roles, else: :assigned
    {:noreply, assign(socket, tab: tab, rows: load_rows())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Catapult.Storybook.Screens.MyQueue.my_queue tab={@tab} rows={@rows} />
    """
  end

  defp load_rows do
    for project_id <- EngineStore.list_project_ids(),
        ticket <- DeliveryStore.tickets_for_project(project_id),
        row <- row_for(project_id, ticket) do
      row
    end
  end

  defp row_for(project_id, ticket) do
    position = Positions.from_columns(ticket.status_kind, ticket.status_gate)

    case kind_for(position) do
      nil ->
        []

      kind ->
        [
          %{
            id: ticket.ticket_ref || ticket.id,
            project_id: project_id,
            project_name: project_id,
            title: Phoenix.Naming.humanize(ticket.flow_name || ""),
            status: Positions.label(position),
            kind: kind,
            href: href_for(kind, project_id, ticket)
          }
        ]
    end
  end

  defp kind_for({:kind, :blocked}), do: :unblock
  defp kind_for({:gate, _name}), do: :sign_off
  defp kind_for(_position), do: nil

  defp href_for(:sign_off, project_id, ticket),
    do: "/projects/#{project_id}/tickets/#{ticket.id}/review"

  defp href_for(:unblock, project_id, ticket),
    do: "/projects/#{project_id}/tickets/#{ticket.id}"
end
