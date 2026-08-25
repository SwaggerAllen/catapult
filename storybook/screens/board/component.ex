defmodule Catapult.Storybook.Screens.Board do
  @moduledoc """
  Presentational shell for the `board` screen (`screens/board.md`). Stateless: every assign is
  handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading `lanes` and `cards` for the selected project, applying `filters`, toggling
  `show_all_lanes`, and issuing the pass-forward/pass-back commands under optimistic concurrency —
  this module only renders the shape those produce, including a rejected command's conflict.

  `lanes`: `%{key:, label:, kind: :status | :gate}`, in effective-sequence order (`screens/
  board.md`). `cards`: `%{id:, title:, type:, lane_key:, children: [%{id:, lane_key:,
  lane_label:}], blocked: nil | %{flavor:, origin_label:}, conflict: nil | %{by:, to:}}` — a card's
  own lane is `blocked.origin_label`'s lane when `blocked` is set, never a separate "blocked" lane.
  `conflict` is set when this card's last pass-forward/pass-back was rejected: `by` and `to` are
  who moved it and where, rendered in place rather than as an after-the-fact revert (v5 §7.16).
  """

  use Phoenix.Component

  attr :project_name, :string, required: true
  attr :lanes, :list, default: []
  attr :cards, :list, default: []
  attr :filters, :map, default: %{type: nil, label: nil, assignee: nil}
  attr :show_all_lanes, :boolean, default: false

  def board(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 p-6">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Board — <%= @project_name %></h1>
        <label class="label cursor-pointer gap-2">
          <span class="label-text text-sm">Show all lanes</span>
          <input type="checkbox" checked={@show_all_lanes} class="toggle toggle-sm" />
        </label>
      </div>

      <.filter_bar filters={@filters} />

      <div class="flex gap-4 overflow-x-auto pb-2">
        <div :for={lane <- @lanes} class="flex w-72 shrink-0 flex-col gap-2">
          <div class="flex items-center gap-2">
            <h2 class="font-semibold text-sm"><%= lane.label %></h2>
            <span :if={lane.kind == :gate} class="badge badge-ghost badge-sm">gate</span>
          </div>

          <div class="flex flex-col gap-2">
            <.card :for={card <- Enum.filter(@cards, &(&1.lane_key == lane.key))} card={card} />
          </div>

          <div
            :if={Enum.filter(@cards, &(&1.lane_key == lane.key)) == []}
            class="rounded-box border border-dashed border-base-300 p-3 text-center text-xs opacity-50"
          >
            empty
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :filters, :map, required: true

  defp filter_bar(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-sm opacity-70">Filters:</span>
      <span :if={@filters.type} class="badge badge-outline gap-1">type <%= @filters.type %></span>
      <span :if={@filters.label} class="badge badge-outline gap-1">label <%= @filters.label %></span>
      <span :if={@filters.assignee} class="badge badge-outline gap-1">
        assignee <%= @filters.assignee %>
      </span>
      <span :if={!@filters.type and !@filters.label and !@filters.assignee} class="text-sm opacity-50">
        none
      </span>
    </div>
    """
  end

  attr :card, :map, required: true

  defp card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm">
      <div class="card-body gap-2 p-4">
        <div class="flex items-center justify-between">
          <span class="font-mono text-xs opacity-60"><%= @card.id %></span>
          <span class="badge badge-ghost badge-sm"><%= @card.type %></span>
        </div>

        <p class="text-sm font-medium"><%= @card.title %></p>

        <div :if={@card.blocked} class="alert alert-warning py-1 px-2 text-xs">
          <span>
            Blocked (<%= @card.blocked.flavor %>) — from <%= @card.blocked.origin_label %>
          </span>
        </div>

        <div :if={@card.conflict} class="alert alert-error py-1 px-2 text-xs">
          <span>
            Rejected — <%= @card.conflict.by %> already moved this to <%= @card.conflict.to %>.
            Refresh and retry.
          </span>
        </div>

        <div :if={@card.children != []} class="flex flex-wrap gap-1">
          <span :for={child <- @card.children} class="badge badge-outline badge-sm font-mono">
            <%= child.id %> · <%= child.lane_label %>
          </span>
        </div>

        <div class="card-actions justify-end pt-1">
          <button class="btn btn-xs btn-outline">Throw back</button>
          <button class="btn btn-xs btn-primary">Approve</button>
        </div>
      </div>
    </div>
    """
  end
end
