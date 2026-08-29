defmodule Catapult.Storybook.Screens.Board do
  @moduledoc """
  Presentational shell for the `board` screen (`screens/board.md`). Stateless: every assign is
  handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading `lanes` and `cards` for the selected project and applying `filters`/`show_all_lanes`.

  `lanes`: `%{key:, label:, kind: :status | :gate}`, in effective-sequence order (`screens/
  board.md`) — `key` is an opaque, plane-supplied string; this render never parses it, since what
  disambiguates two same-named positions is `systems/dashboard.md`'s own lane-key entry, not a
  rendering concern. Plus three fields `board_live.ex` does not compute yet and this render treats
  as optional, `Map.get`-style, rather than required — `group_key: String.t() | nil`,
  `group_anchor: boolean` and `group_collapsed: boolean`. `group_key` is shared by every lane a
  declared sub-array groups (`docs/dsl-syntax.md` §15.10) and absent (or `nil`) for a lane no
  sub-array cites; `group_anchor` marks the one lane inside a group that is where a throwback in
  that group falls back to by default — whatever `Catapult.Dsl.Workflow.throwback_default/3`
  resolves, rendered rather than restated here. Contiguous lanes sharing a `group_key` render
  inside one bounded box (`screens/board.md`'s "Sub-arrays render as a bounded box around their
  own lanes," ORC-116); a lane carrying none of the three renders exactly as it did before
  grouping existed. `group_collapsed` (default `false` when absent, so an existing caller that
  never sends it keeps rendering expanded) switches a group between its ordinary per-lane columns
  and the collapsed summary box (`screens/board.md`'s "A group is collapsible, and collapsed is
  the default"). This render computes the runs from the flat, ordered list handed down; it does
  not resolve grouping or collapse state itself — a `phx-click="toggle_group"`/
  `phx-value-key={group_key}` is emitted for the eventual LiveView to wire.

  `cards`: `%{id:, title:, type:, lane_key:, children: [%{id:, lane_key:, lane_label:}],
  child_summary: nil | %{count:, label:}, blocked: nil | %{flavor:, origin_label:}, gate: nil |
  %{role:}}` — a card's own lane is `blocked.origin_label`'s lane when `blocked` is set, never a
  separate "blocked" lane. `children` is same-type roll-up only (a subcomponent inside a
  component, `docs/dsl-syntax.md` §15.11) since only same-type nesting shares this board's own
  lane set, each carrying its own `lane_label`; `child_summary`, when set, is a single aggregate
  count for children of a different declared type (a feature's own components) — there is no lane
  of theirs on this board to attach a `lane_label` to, so it renders as a plain chip instead of a
  per-lane list (`screens/board.md`'s "Grouping is per lane, not per card — and only within one
  shared lane set"). `gate` is set when the card's lane is a review gate: `%{role:, href:}`,
  rendered as a link out to `document-review` (or `ticket`) rather than an Approve/Throw-back pair,
  since neither command a card could dispatch would carry a real `body_sha` to compare against
  (`screens/board.md`'s "Cards link to where pass-forward and pass-back are issued" — ORC-114, and
  still true after ORC-115's node derivation — see that section). No `conflict` shape: a
  stale-transition rejection is rendered where the command is actually issued, not here.
  """

  use Phoenix.Component

  attr :project_name, :string, required: true
  attr :lanes, :list, default: []
  attr :cards, :list, default: []
  attr :filters, :map, default: %{type: nil, label: nil}
  attr :show_all_lanes, :boolean, default: false

  def board(assigns) do
    assigns = assign(assigns, :segments, segments(assigns.lanes))

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
        <.segment :for={segment <- @segments} segment={segment} cards={@cards} />
      </div>
    </div>
    """
  end

  # A contiguous run of lanes sharing a `group_key` (`docs/dsl-syntax.md` §15.10) renders inside
  # one bounded box; a lane with no `group_key` renders on its own, exactly as before grouping
  # existed. This is a pure grouping of the flat, ordered list already handed down — it resolves
  # no data, only which box a lane's column draws inside. `group_key` is read with `Map.get/2`
  # because `board_live.ex` does not supply it yet (moduledoc) — a missing key groups exactly
  # like an explicit `nil`.
  defp segments(lanes) do
    lanes
    |> Enum.chunk_by(&Map.get(&1, :group_key))
    |> Enum.flat_map(fn [lane | _] = chunk ->
      if Map.get(lane, :group_key), do: [{:group, chunk}], else: Enum.map(chunk, &{:lane, &1})
    end)
  end

  attr :segment, :any, required: true
  attr :cards, :list, required: true

  defp segment(%{segment: {:lane, _lane}} = assigns) do
    ~H"""
    <.lane_column lane={elem(@segment, 1)} cards={@cards} />
    """
  end

  defp segment(%{segment: {:group, [lane | _]}} = assigns) do
    assigns =
      assigns
      |> assign(:collapsed, Map.get(lane, :group_collapsed, false))
      |> assign(:group_key, Map.get(lane, :group_key))
      |> assign(:group_lanes, elem(assigns.segment, 1))

    ~H"""
    <.collapsed_group :if={@collapsed} lanes={@group_lanes} cards={@cards} />
    <div
      :if={!@collapsed}
      class="flex gap-4 rounded-box border border-dashed border-primary/40 bg-primary/5 p-2"
    >
      <.lane_column :for={lane <- @group_lanes} lane={lane} cards={@cards} />
      <button
        phx-click="toggle_group"
        phx-value-key={@group_key}
        class="btn btn-ghost btn-xs self-start"
        title="Collapse this loop"
      >
        ⇤
      </button>
    </div>
    """
  end

  attr :lanes, :list, required: true
  attr :cards, :list, required: true

  # Collapsed: a group renders as one box, still at its full lane-count width, carrying the
  # default-landing badge on the box itself (not on one lane inside it, since the lanes aren't
  # drawn) plus the ids of every ticket currently sitting anywhere in the group — the two facts
  # grouping exists to explain (`screens/board.md`'s "A group is collapsible, and collapsed is the
  # default"). Expanding trades this summary for the ordinary per-lane columns above.
  defp collapsed_group(assigns) do
    anchor = Enum.find(assigns.lanes, &Map.get(&1, :group_anchor, false))
    lane_keys = Enum.map(assigns.lanes, fn lane -> lane.key end)
    group_cards = Enum.filter(assigns.cards, &(&1.lane_key in lane_keys))

    assigns =
      assigns
      |> assign(:anchor, anchor)
      |> assign(:group_key, Map.get(hd(assigns.lanes), :group_key))
      |> assign(:group_cards, group_cards)

    ~H"""
    <button
      phx-click="toggle_group"
      phx-value-key={@group_key}
      class="flex w-72 shrink-0 flex-col items-start gap-2 rounded-box border border-dashed border-primary/40 bg-primary/5 p-3 text-left"
      title="Expand this loop"
    >
      <div class="flex items-center gap-2">
        <span class="font-semibold text-sm">
          <%= length(@lanes) %> lanes<%= if @anchor, do: " · #{@anchor.label}" %>
        </span>
        <span
          :if={@anchor}
          class="badge badge-primary badge-sm"
          title="Default throwback landing point for this group"
        >
          ↺
        </span>
      </div>

      <div :if={@group_cards != []} class="flex flex-wrap gap-1">
        <span :for={card <- @group_cards} class="badge badge-outline badge-sm font-mono">
          <%= card.id %>
        </span>
      </div>

      <div :if={@group_cards == []} class="text-xs opacity-50">empty</div>
    </button>
    """
  end

  attr :lane, :map, required: true
  attr :cards, :list, required: true

  defp lane_column(assigns) do
    assigns =
      assign(assigns, :lane_cards, Enum.filter(assigns.cards, &(&1.lane_key == assigns.lane.key)))

    ~H"""
    <div class="flex w-72 shrink-0 flex-col gap-2">
      <div class="flex items-center gap-2">
        <h2 class="font-semibold text-sm"><%= @lane.label %></h2>
        <span :if={@lane.kind == :gate} class="badge badge-ghost badge-sm">gate</span>
        <span
          :if={Map.get(@lane, :group_anchor, false)}
          class="badge badge-primary badge-sm"
          title="Default throwback landing point for this group"
        >
          ↺
        </span>
      </div>

      <div class="flex flex-col gap-2">
        <.card :for={card <- @lane_cards} card={card} />
      </div>

      <div
        :if={@lane_cards == []}
        class="rounded-box border border-dashed border-base-300 p-3 text-center text-xs opacity-50"
      >
        empty
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
      <span :if={!@filters.type and !@filters.label} class="text-sm opacity-50">
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

        <div :if={@card.children != []} class="flex flex-wrap gap-1">
          <span :for={child <- @card.children} class="badge badge-outline badge-sm font-mono">
            <%= child.id %> · <%= child.lane_label %>
          </span>
        </div>

        <div :if={Map.get(@card, :child_summary)} class="flex gap-1">
          <span class="badge badge-outline badge-sm">
            <%= @card.child_summary.count %> <%= @card.child_summary.label %>
          </span>
        </div>

        <div :if={@card.gate} class="card-actions justify-end pt-1">
          <a href={@card.gate.href} class="btn btn-xs btn-outline">
            Review (<%= @card.gate.role %>) →
          </a>
        </div>
      </div>
    </div>
    """
  end
end
