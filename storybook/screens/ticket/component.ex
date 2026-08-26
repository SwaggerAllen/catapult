defmodule Catapult.Storybook.Screens.Ticket do
  @moduledoc """
  Presentational shell for the `ticket` screen (`screens/ticket.md`). Stateless: every assign is
  handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading the ticket, resolving `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` into
  `sequence`, and issuing the blocked-return command under optimistic concurrency — this module
  only renders the shape that produces, including a rejected command's conflict.

  `sequence` entries: `%{key:, label:, kind: :status | :gate, role: String.t() | nil, state:
  :passed | :current | :upcoming}`. `gate_action`: `nil` off this ticket's current position, else
  `%{role:}` — a pointer, not a control: every Phase 4 gate reviews prose, so this screen links to
  `document-review` rather than dispatching `ApproveGate`/`DeclineGate` itself (`screens/
  ticket.md`, ORC-114). `blocked`: `nil` or `%{flavor:, origin_label:, return_options: [%{label:,
  target:}]}` — `return_options` is the origin plus every earlier position, never a later one
  (`screens/ticket.md`), and choosing one dispatches `ResumeFlow` under the identical
  compare-and-swap. `conflict`: `nil` or `%{to:}`, set when this screen's own last dispatch (the
  blocked-return control — the gate action is never dispatched from here) was rejected: `to` names
  the value the rejection recorded (the position someone else already resumed it to, or the
  disposition a raced gate already carries), not an actor — neither `ResumeFlow` nor the gate
  commands' own compare-and-swap carries who made the winning write (v5 §7.16,
  `systems/dashboard.md`'s own standing decision).
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
          Rejected — this ticket already moved to <span class="font-semibold"><%= @conflict.to %></span>.
          Refresh to see the current state before trying again.
        </span>
      </div>

      <.sequence_rail sequence={@sequence} />

      <div :if={@gate_action} class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body gap-2">
          <h2 class="card-title text-sm">
            Awaiting sign-off <span class="badge badge-ghost badge-sm"><%= @gate_action.role %></span>
          </h2>
          <div class="flex flex-wrap gap-2">
            <button class="btn btn-sm btn-outline">Review in document-review →</button>
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
