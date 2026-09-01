defmodule Catapult.Storybook.Screens.ExplainWhy do
  @moduledoc """
  Presentational shell for the `explain-why` screen (`screens/explain-why.md`). Renders
  `Catapult.Engine.Projections.ReadyScopes.explain/2`'s report verbatim — `passes_scope_filter`,
  `scope_key`, and `blocking` (each entry `%{walk:, satisfied:, targets:, reason:}`, `reason:
  :unsupported` present only on a `ticket.<source>` walk — v5 §7.11's validation loop, Phase 7.
  `input.<role>`/`input.*` walks resolve satisfied with no targets since ORC-107 and never reach
  `blocking` at all, `screens/explain-why.md`'s own entry). No
  readiness is recomputed here; every assign is handed down whole and there is no socket.

  `review_tier?` is not part of `explain/2`'s own report — it is a fact the eventual LiveView
  already has (it looked the tier up to call `explain/2` in the first place) and hands down so
  this component can render the caveat `screens/explain-why.md` requires rather than staying
  silent the way an ordinary empty `blocking` list would.
  """

  use Phoenix.Component

  attr :project_id, :string, required: true
  attr :node_id, :string, required: true
  attr :tier, :string, required: true
  attr :scope_key, :map, default: %{}
  attr :passes_scope_filter, :boolean, required: true
  attr :blocking, :list, default: []
  attr :review_tier?, :boolean, default: false

  def explain_why(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 p-6" data-project-id={@project_id}>
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">Why is this blocked?</h1>
        <span class="badge badge-outline">project <%= @project_id %></span>
      </div>

      <div class="flex items-center gap-2 text-sm">
        <span class="badge badge-neutral"><%= @tier %></span>
        <span class="font-mono opacity-70"><%= @node_id %></span>
        <span :if={@scope_key != %{}} class="font-mono opacity-50"><%= inspect(@scope_key) %></span>
      </div>

      <div :if={!@passes_scope_filter} class="alert alert-error">
        <span>
          Excluded by this tier's <code>scope_filter</code> — this node is not a generation
          candidate at all, whatever its context looks like below.
        </span>
      </div>

      <div :if={@passes_scope_filter and @review_tier?} class="alert alert-info">
        <span>
          This is a review tier. It has no <code>context:</code> of its own, so an empty blocking
          list here only means there is nothing to walk — it is not a claim that the reviewed
          draft has been reviewed. That fact isn't on this screen yet.
        </span>
      </div>

      <div :if={@passes_scope_filter and @blocking == []} class="alert alert-success">
        <span>Nothing in scope is blocking this node.</span>
      </div>

      <ul :if={@passes_scope_filter and @blocking != []} class="flex flex-col gap-3">
        <li :for={entry <- @blocking} class="rounded-box border border-base-300 p-4">
          <.blocking_entry entry={entry} />
        </li>
      </ul>

      <div class="pt-2">
        <a href={"/projects/#{@project_id}/event-log?node=#{@node_id}"} class="link link-primary text-sm">
          See what happened to this node in the event log →
        </a>
      </div>
    </div>
    """
  end

  attr :entry, :map, required: true

  defp blocking_entry(assigns) do
    ~H"""
    <div :if={Map.get(@entry, :reason) == :unsupported} class="flex flex-col gap-1">
      <div class="flex items-center gap-2">
        <span class="badge badge-warning">not wired up yet</span>
        <span class="font-mono text-sm"><%= @entry.walk %></span>
      </div>
      <p class="text-sm opacity-70">
        This walk has no resolution today — nothing to approve here. It is a gap in what the
        engine can read, not a pending decision; chasing an approver for it will not unblock
        anything.
      </p>
    </div>

    <div :if={Map.get(@entry, :reason) != :unsupported} class="flex flex-col gap-2">
      <span class="font-mono text-sm"><%= @entry.walk %></span>
      <ul class="flex flex-col gap-1">
        <li :for={target <- @entry.targets} class="flex items-center gap-2 text-sm">
          <span class={["badge badge-sm", status_badge_class(target.status)]}><%= target.status %></span>
          <span class="opacity-70"><%= target.tier %></span>
          <span class="font-mono"><%= target.node_id %></span>
        </li>
      </ul>
    </div>
    """
  end

  defp status_badge_class(:approved), do: "badge-success"
  defp status_badge_class(:drafted), do: "badge-warning"
  defp status_badge_class(:absent), do: "badge-ghost"
end
