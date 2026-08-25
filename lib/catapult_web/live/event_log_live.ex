defmodule CatapultWeb.EventLogLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.EventLog.event_log/1`
  (`screens/event-log.md`): loads `events` from
  `Commanded.EventStore.stream_forward/3` against the project's own
  stream, applies the three named filters plus the unnamed node match,
  and hands the whole shape down whole — the component fetches
  nothing and recomputes nothing (`screens/event-log.md`'s own
  moduledoc).

  Filters and the selected event both live in the query string, not in
  socket-only state: `?container=&actor=&node=&selected=`. That is
  what makes `explain-why`'s own node link
  (`/projects/:project_id/event-log?node=...`) resolvable on a dead
  render with no client-side interactivity required — v0 has none
  wired (`systems/dashboard.md`'s scope limit).
  """
  use CatapultWeb, :live_view

  alias Catapult.Engine.Events
  alias Catapult.Engine.Store
  alias Catapult.Storybook.Screens.EventLog

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    {:ok, assign(socket, project_id: project_id)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters = %{
      container_id: presence(params["container"]),
      actor_id: presence(params["actor"]),
      node_query: presence(params["node"])
    }

    events =
      socket.assigns.project_id
      |> load_events()
      |> apply_filters(filters)

    selected = params["selected"] && Enum.find(events, &(&1.id == params["selected"]))

    {:noreply, assign(socket, events: events, filters: filters, selected: selected)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <EventLog.event_log
      project_id={@project_id}
      events={@events}
      filters={@filters}
      selected={@selected}
    />
    """
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp load_events(project_id) do
    case Commanded.EventStore.stream_forward(
           Catapult.Engine.Application,
           "project-" <> project_id
         ) do
      {:error, :stream_not_found} -> []
      stream -> stream |> Enum.map(&to_row(&1, project_id)) |> Enum.sort_by(& &1.occurred_at)
    end
  end

  defp apply_filters(events, filters) do
    events
    |> filter_by(:container_id, filters.container_id)
    |> filter_by(:actor_id, filters.actor_id)
    |> filter_by(:node_id, filters.node_query)
  end

  defp filter_by(events, _field, nil), do: events
  defp filter_by(events, field, value), do: Enum.filter(events, &(Map.get(&1, field) == value))

  # `event.event_type` is the *recorded* type's own serialized name
  # (Commanded's upcast replaces only `data`, never `event_type` —
  # `screens/event-log.md`'s "The version, always"), so the reverse
  # lookup below recovers the `{type, version}` pair the payload was
  # actually stored at, independent of what `data` upcast to.
  defp to_row(%Commanded.EventStore.RecordedEvent{} = event, project_id) do
    {type, recorded_version} = recorded_identity(event)
    current_version = current_version(type)

    %{
      id: event.event_id,
      type: Atom.to_string(type),
      recorded_version: recorded_version,
      current_version: current_version,
      occurred_at: DateTime.to_string(event.created_at),
      actor_id: Map.get(event.data, :actor_id),
      container_id: Map.get(event.data, :container_id),
      node_id: node_id(type, event.data, project_id),
      summary: summary(type, event.data),
      payload: event.data
    }
  end

  defp recorded_identity(event) do
    Enum.find_value(Events.registry(), {:unknown, 0}, fn {type, version} ->
      module = Events.module(type, version)
      if module && Atom.to_string(module) == event.event_type, do: {type, version}
    end)
  end

  defp current_version(type) do
    Events.registry()
    |> Enum.filter(fn {t, _v} -> t == type end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.max(fn -> 0 end)
  end

  # Every event but `review_written` carries its own `node_id`
  # directly; that one carries `draft_id`, resolvable through the
  # draft it was written against (`screens/event-log.md`'s "a
  # draft/review id resolvable to one").
  defp node_id(:review_written, %{draft_id: draft_id}, project_id) do
    case Store.get_draft(project_id, draft_id) do
      nil -> nil
      draft -> draft.node_id
    end
  end

  defp node_id(_type, data, _project_id), do: Map.get(data, :node_id)

  defp summary(:container_minted, data), do: "Container minted for #{data.container_id}"
  defp summary(:container_activated, data), do: "Container activated on #{data.queue}"

  defp summary(:container_queue_advanced, data),
    do: "Queue advanced #{data.from_queue} -> #{data.to_queue}"

  defp summary(:container_closed, data), do: "Container #{data.container_id} closed"
  defp summary(:draft_committed, data), do: "#{data.tier} draft committed"
  defp summary(:draft_approved, _data), do: "Draft approved"
  defp summary(:draft_discarded, data), do: "Draft discarded: #{data.reason}"
  defp summary(:review_written, data), do: "Review written, score #{data.score}"
  defp summary(:run_failed, data), do: "Dispatch run failed: #{data.reason}"

  defp summary(:active_bundle_flipped, data),
    do: "#{data.axis} bundle flipped to #{data.bundle_name} v#{data.version}"

  defp summary(:finding_adjudicated, data), do: "Finding #{data.disposition}: #{data.finding_id}"
  defp summary(:flag_set_flip_requested, data), do: "Flag flip requested: #{inspect(data.flags)}"
  defp summary(:flag_set_flipped, data), do: "Flags flipped: #{inspect(data.flags)}"
  defp summary(:flow_opened, data), do: "Flow #{data.flow_name} opened"
  defp summary(:flow_completed, _data), do: "Flow completed"
  defp summary(type, _data), do: Atom.to_string(type)
end
