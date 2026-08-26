defmodule CatapultWeb.TicketLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.Ticket.ticket/1` (`screens/
  ticket.md`): the argument, position in the effective sequence
  (`Catapult.Delivery.FeatureLifecycle.Sequence.positions/2`, the same
  read `board`'s lanes come from), the blocked-return control under
  optimistic concurrency, child roll-up, linked PRs and runs.

  **The gate action is a pointer, never a control this screen
  dispatches** (`screens/ticket.md`): every Phase 4 gate reviews prose,
  so the card links to `document-review` rather than rendering a second
  `ApproveGate`/`DeclineGate` pair. The blocked-return control is this
  screen's one real write — `Catapult.Engine.Commands.ResumeFlow` under
  the identical compare-and-swap `document-review`'s gate actions use,
  rendered as a conflict at the point of action rather than an
  after-the-fact revert.

  **Child roll-up is always empty in Phase 4.** `Catapult.Engine.Store
  .Flow` carries no parent-flow reference — fan-out below a top-level
  ticket is a node/tier concept today, not a second flow instance — so
  there is no data source for it yet, named in this ticket's hand-back
  rather than silently rendered as "no children."
  """
  use CatapultWeb, :live_view

  alias Catapult.Config
  alias Catapult.Delivery.FeatureLifecycle
  alias Catapult.Delivery.FeatureLifecycle.Sequence
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ResumeFlow
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store, as: EngineStore
  alias CatapultWeb.Live.Actor
  alias CatapultWeb.Live.EventFacts
  alias CatapultWeb.Live.Positions

  @impl true
  def mount(%{"project_id" => project_id, "flow_id" => flow_id}, _session, socket) do
    {:ok, assign(socket, project_id: project_id, flow_id: flow_id, conflict: nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("resume", %{"target" => target}, socket) do
    cmd = %ResumeFlow{
      project_id: socket.assigns.project_id,
      flow_id: socket.assigns.flow_id,
      to: Positions.decode_key(target),
      actor_id: Actor.id()
    }

    case Router.dispatch(cmd, consistency: :strong) do
      :ok ->
        {:noreply, socket |> load() |> assign(conflict: nil)}

      {:error, {:engine_flow_not_blocked, _}} ->
        reloaded = load(socket)
        {:noreply, assign(reloaded, conflict: %{to: current_label(reloaded)})}
    end
  end

  @impl true
  def render(%{found?: false} = assigns) do
    ~H"""
    <div class="p-6">
      No ticket <span class="font-mono">{@flow_id}</span> in project <span class="font-mono">{@project_id}</span>.
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Catapult.Storybook.Screens.Ticket.ticket
      id={@id}
      title={@title}
      argument={@argument}
      sequence={@sequence}
      gate_action={@gate_action}
      blocked={@blocked}
      conflict={@conflict}
      children={@children}
      prs={@prs}
      runs={@runs}
    />
    """
  end

  defp load(socket) do
    project_id = socket.assigns.project_id
    flow_id = socket.assigns.flow_id
    flow = EngineStore.get_flow(project_id, flow_id)
    lifecycle = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    workflow_load = Dsl.load(Config.fetch!(:engine, :bundles_root))

    case {flow, lifecycle, workflow_load} do
      {%{} = flow, %{} = lifecycle, {:ok, %{workflow: %{} = workflow}}} ->
        assign_ticket(socket, flow, lifecycle, workflow)

      _not_found_or_unloadable ->
        assign(socket, found?: false)
    end
  end

  defp assign_ticket(socket, flow, lifecycle, workflow) do
    project_id = socket.assigns.project_id
    node = flow.entry_node_id && EngineStore.get_node(project_id, flow.entry_node_id)
    positions = Sequence.positions(workflow, flow.flow_name)
    resting = FeatureLifecycle.status(lifecycle)
    marker = if resting == {:kind, :blocked}, do: origin(lifecycle), else: resting

    assign(socket,
      found?: true,
      id: flow.ticket_ref || flow.id,
      title: Phoenix.Naming.humanize(flow.flow_name || ""),
      argument: (node && node.fields && node.fields["argument"]) || "",
      sequence: sequence_rail(positions, marker, workflow),
      gate_action: gate_action(resting, workflow, project_id, flow.id),
      blocked: blocked(resting, lifecycle, positions, project_id),
      children: [],
      prs: prs(project_id, DeliveryStore.get_feature_publication(project_id, flow.id)),
      runs: runs(project_id, DeliveryStore.dispatch_runs_for_flow(project_id, flow.id))
    )
  end

  defp origin(%{blocked_origin_kind: kind, blocked_origin_gate: gate}),
    do: Positions.from_columns(kind, gate)

  defp sequence_rail(positions, marker, workflow) do
    marker_index = Enum.find_index(positions, &(&1 == marker))

    positions
    |> Enum.with_index()
    |> Enum.map(fn {position, index} ->
      %{
        key: Positions.key(position),
        label: Positions.label(position),
        kind: Positions.kind(position),
        role: Positions.role(position, workflow),
        state: state_at(index, marker_index)
      }
    end)
  end

  defp state_at(_index, nil), do: :upcoming
  defp state_at(index, marker_index) when index < marker_index, do: :passed
  defp state_at(index, marker_index) when index == marker_index, do: :current
  defp state_at(_index, _marker_index), do: :upcoming

  defp gate_action({:gate, _name} = position, workflow, project_id, flow_id) do
    %{
      role: Positions.role(position, workflow),
      href: "/projects/#{project_id}/tickets/#{flow_id}/review"
    }
  end

  defp gate_action(_resting, _workflow, _project_id, _flow_id), do: nil

  defp blocked({:kind, :blocked}, lifecycle, positions, project_id) do
    origin = origin(lifecycle)

    %{
      flavor: EventFacts.blocked_flavor(project_id),
      origin_label: origin && Positions.label(origin),
      return_options: return_options(origin, positions)
    }
  end

  defp blocked(_resting, _lifecycle, _positions, _project_id), do: nil

  defp return_options(nil, _positions), do: []

  defp return_options(origin, positions) do
    case Enum.find_index(positions, &(&1 == origin)) do
      nil ->
        []

      origin_index ->
        earlier = positions |> Enum.take(origin_index) |> Enum.reverse()

        [origin | earlier]
        |> Enum.map(&%{label: Positions.label(&1), target: Positions.key(&1)})
    end
  end

  defp current_label(%{assigns: %{sequence: sequence, blocked: blocked}}) do
    case Enum.find(sequence, &(&1.state == :current)) do
      %{label: label} -> label
      nil -> (blocked && "blocked (#{blocked.flavor})") || "an earlier position"
    end
  end

  defp prs(_project_id, nil), do: []

  defp prs(project_id, publication) do
    [
      %{
        number: publication.pr_number,
        status: "published",
        href: github_url(project_id, "pull/#{publication.pr_number}")
      }
    ]
  end

  defp runs(project_id, runs) do
    Enum.map(runs, fn run ->
      href =
        if run.github_run_id,
          do: github_url(project_id, "actions/runs/#{run.github_run_id}"),
          else: "#"

      %{id: run.id, status: to_string(run.status), href: href}
    end)
  end

  defp github_url(project_id, path) do
    case DeliveryStore.get_project_binding(project_id) do
      %{repo_owner: owner, repo_name: repo} -> "https://github.com/#{owner}/#{repo}/#{path}"
      nil -> "#"
    end
  end
end
