defmodule Catapult.Storybook.Screens.Ticket do
  @moduledoc """
  Presentational shell for the `ticket` screen (`screens/ticket.md`). Stateless: every assign is
  handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading the ticket, resolving `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` into
  `sequence`, and issuing the gate/blocked-return commands under optimistic concurrency — this
  module only renders the shape those produce, including a rejected command's conflict.

  `sequence` entries: `%{key:, label:, kind: :status | :gate, role: String.t() | nil, state:
  :passed | :current | :upcoming}`. `gate_action`: `nil` when the viewer holds no role at the
  current position, else `%{exits: [%{label:, target:}]}`. `blocked`: `nil` or `%{flavor:,
  origin_label:, return_options: [%{label:, target:}]}` — `return_options` is the origin plus every
  earlier position, never a later one (`screens/ticket.md`). `conflict`: `nil` or `%{by:, to:}`,
  set when the last command this screen issued was rejected by the compare-and-swap (v5 §7.16).
  """

  use Phoenix.Component

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :argument, :string, required: true
  attr :sequence, :list, default: []
  attr :gate_action, :map, default: nil
  attr :blocked, :map, default: nil
  attr :conflict, :map, default: nil
  attr :children, :list, default: []
  attr :prs, :list, default: []
  attr :runs, :list, default: []

  def ticket(assigns) do
    ~H"""
    <div class="flex flex-col gap-6 p-6 max-w-3xl">
      <div>
        <div class="flex items-center gap-2">
          <span class="font-mono text-sm opacity-60"><%= @id %></span>
          <h1 class="text-xl font-semibold"><%= @title %></h1>
        </div>
        <p class="mt-2 text-sm leading-relaxed"><%= @argument %></p>
      </div>

      <div :if={@conflict} class="alert alert-error">
        <span>
          Rejected — <span class="font-semibold"><%= @conflict.by %></span> already moved this
          ticket to <span class="font-semibold"><%= @conflict.to %></span>. Refresh to see the
          current state before trying again.
        </span>
      </div>

      <.sequence_rail sequence={@sequence} />

      <div :if={@gate_action} class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body gap-2">
          <h2 class="card-title text-sm">Gate action</h2>
          <div class="flex flex-wrap gap-2">
            <button class="btn btn-sm btn-primary">Approve</button>
            <button :for={exit_ <- @gate_action.exits} class="btn btn-sm btn-outline">
              Throw back to <%= exit_.label %>
            </button>
          </div>
        </div>
      </div>

      <div :if={@blocked} class="card bg-base-100 border border-warning shadow-sm">
        <div class="card-body gap-2">
          <h2 class="card-title text-sm">
            Blocked <span class="badge badge-warning badge-sm"><%= @blocked.flavor %></span>
          </h2>
          <p class="text-sm opacity-70">From <%= @blocked.origin_label %></p>
          <div class="flex flex-wrap gap-2">
            <button
              :for={{opt, i} <- Enum.with_index(@blocked.return_options)}
              class={["btn btn-sm", i == 0 && "btn-primary", i != 0 && "btn-outline"]}
            >
              Return to <%= opt.label %>
            </button>
          </div>
        </div>
      </div>

      <div :if={@children != []}>
        <h2 class="text-sm font-semibold mb-2">Children</h2>
        <ul class="flex flex-col gap-1">
          <li :for={child <- @children} class="flex items-center gap-2 text-sm">
            <span class="font-mono opacity-60"><%= child.id %></span>
            <span><%= child.title %></span>
            <span class="badge badge-outline badge-sm ml-auto"><%= child.position_label %></span>
          </li>
        </ul>
      </div>

      <div :if={@prs != [] or @runs != []} class="grid grid-cols-2 gap-4">
        <div>
          <h2 class="text-sm font-semibold mb-2">Linked PRs</h2>
          <ul class="flex flex-col gap-1">
            <li :for={pr <- @prs} class="text-sm">
              <a href={pr.href} class="link link-hover">#<%= pr.number %></a>
              <span class="badge badge-ghost badge-sm ml-1"><%= pr.status %></span>
            </li>
          </ul>
        </div>
        <div>
          <h2 class="text-sm font-semibold mb-2">Runs</h2>
          <ul class="flex flex-col gap-1">
            <li :for={run <- @runs} class="text-sm">
              <a href={run.href} class="link link-hover"><%= run.id %></a>
              <span class="badge badge-ghost badge-sm ml-1"><%= run.status %></span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :sequence, :list, required: true

  defp sequence_rail(assigns) do
    assigns = assign(assigns, :last_key, assigns.sequence |> List.last() |> then(&(&1 && &1.key)))

    ~H"""
    <ol class="flex flex-wrap items-center gap-1 text-xs">
      <li :for={pos <- @sequence} class="flex items-center gap-1">
        <span class={[
          "badge",
          pos.state == :passed && "badge-success",
          pos.state == :current && "badge-primary",
          pos.state == :upcoming && "badge-ghost"
        ]}>
          <%= pos.label %><%= if pos.kind == :gate and pos.role, do: " (#{pos.role})" %>
        </span>
        <span :if={pos.key != @last_key} class="opacity-30">→</span>
      </li>
    </ol>
    """
  end
end
