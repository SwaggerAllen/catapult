defmodule Catapult.Storybook.Screens.EventLog do
  @moduledoc """
  Presentational shell for the `event-log` screen (`screens/event-log.md`). Stateless: every
  assign is handed down whole, nothing is fetched here, and there is no socket. The eventual
  LiveView owns loading `events` from `Commanded.EventStore.stream_forward/3`, applying
  `filters`, and toggling `selected` — this module only renders the shape those produce.

  `events` entries: `%{id:, type:, recorded_version:, current_version:, occurred_at:, actor_id:,
  container_id:, node_id:, summary:, payload:}`. `recorded_version` and `current_version` differ
  exactly when the stored event predates its type's latest shape (`screens/event-log.md`'s "The
  version, always") — every entry carries both, never one.
  """

  use Phoenix.Component

  attr :project_id, :string, required: true
  attr :events, :list, default: []
  attr :filters, :map, default: %{container_id: nil, actor_id: nil, node_query: nil}
  attr :selected, :map, default: nil

  def event_log(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 p-6" data-project-id={@project_id}>
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Event log</h1>
        <span class="badge badge-outline">project <%= @project_id %></span>
      </div>

      <.filter_bar filters={@filters} />

      <div :if={@filters.node_query} class="alert alert-info">
        <span>
          Arrived from <span class="font-mono">explain-why</span> — showing events touching node
          <span class="font-mono"><%= @filters.node_query %></span>.
        </span>
      </div>

      <div :if={@events == []} class="rounded-box border border-base-300 p-8 text-center opacity-70">
        Nothing has happened here yet.
      </div>

      <div :if={@events != []} class="overflow-x-auto rounded-box border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>When</th>
              <th>Type</th>
              <th>Version</th>
              <th>Ticket</th>
              <th>Actor</th>
              <th>Summary</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={event <- @events}
              class={["hover:bg-base-200 cursor-pointer", @selected && @selected.id == event.id && "bg-base-200"]}
            >
              <td class="whitespace-nowrap font-mono text-sm"><%= event.occurred_at %></td>
              <td><%= event.type %></td>
              <td><.version_badge event={event} /></td>
              <td class="font-mono text-sm"><%= event.container_id || "—" %></td>
              <td class="font-mono text-sm"><%= event.actor_id || "—" %></td>
              <td><%= event.summary %></td>
            </tr>
          </tbody>
        </table>
      </div>

      <.detail_pane :if={@selected} event={@selected} />
    </div>
    """
  end

  attr :filters, :map, required: true

  defp filter_bar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm opacity-70">Filters:</span>
      <span :if={@filters.container_id} class="badge badge-primary gap-1">
        ticket <%= @filters.container_id %>
      </span>
      <span :if={@filters.actor_id} class="badge badge-secondary gap-1">
        actor <%= @filters.actor_id %>
      </span>
      <span :if={!@filters.container_id and !@filters.actor_id and !@filters.node_query} class="text-sm opacity-50">
        none — showing the whole stream
      </span>
    </div>
    """
  end

  attr :event, :map, required: true

  defp version_badge(assigns) do
    ~H"""
    <span :if={@event.recorded_version == @event.current_version} class="badge badge-ghost">
      v<%= @event.current_version %>
    </span>
    <span :if={@event.recorded_version != @event.current_version} class="badge badge-warning gap-1" title="Recorded at an earlier shape; shown upcast to the current one.">
      recorded v<%= @event.recorded_version %> → shown v<%= @event.current_version %>
    </span>
    """
  end

  attr :event, :map, required: true

  defp detail_pane(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title"><%= @event.type %></h2>
          <.version_badge event={@event} />
        </div>

        <div :if={@event.recorded_version != @event.current_version} class="alert alert-warning">
          <span>
            Stored as <span class="font-mono">&lbrace;<%= @event.type %>, <%= @event.recorded_version %>&rbrace;</span>.
            Every read upcasts, so the payload below is the current shape (v<%= @event.current_version %>),
            not what was originally written — the fields below are what replay would produce too.
          </span>
        </div>

        <pre class="bg-base-200 rounded-box p-4 text-sm overflow-x-auto"><%= inspect(@event.payload, pretty: true) %></pre>

        <dl class="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt class="opacity-60">Node</dt>
          <dd class="font-mono"><%= @event.node_id || "—" %></dd>
          <dt class="opacity-60">Ticket (container)</dt>
          <dd class="font-mono"><%= @event.container_id || "—" %></dd>
          <dt class="opacity-60">Actor</dt>
          <dd class="font-mono"><%= @event.actor_id || "—" %></dd>
        </dl>
      </div>
    </div>
    """
  end
end
