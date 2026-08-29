defmodule Catapult.Storybook.Screens.Ticket do
  @moduledoc """
  Presentational shell for the `ticket` screen (`screens/ticket.md`). Stateless: every assign is
  handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading the ticket, resolving `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` into
  `sequence`, and issuing the blocked-return command under optimistic concurrency — this module
  only renders the shape that produces, including a rejected command's conflict.

  `sequence` entries: `%{key:, label:, kind: :status | :gate, role: String.t() | nil, state:
  :passed | :current | :upcoming}` — `key` is opaque, plane-supplied and never parsed here
  (`systems/dashboard.md`'s lane-key entry has what disambiguates two same-named positions), plus
  two fields `Catapult.Delivery.FeatureLifecycle.Sequence.positions/2` does not compute yet and
  this render treats as optional, `Map.get`-style, rather than required — `group_key: String.t() |
  nil` and `group_anchor: boolean`, the identical pair `board`'s lanes carry (`screens/board.md`'s
  "Sub-arrays render as a bounded box around their own lanes," ORC-116). Contiguous entries sharing
  a `group_key` render inside one bounded box on this rail too, with the group's own `group_anchor`
  entry badged as whatever `Catapult.Dsl.Workflow.throwback_default/3` resolves for the group —
  rendered, not restated (`screens/ticket.md`'s "Where the sequence declares a sub-array"); an
  entry carrying neither renders exactly as it did before grouping existed. `gate_action`: `nil`
  off this ticket's current position, else `%{role:, href:}` — a pointer, not a control: every
  Phase 4 gate reviews prose, so this screen links to `document-review` rather than dispatching
  `ApproveGate`/`DeclineGate` itself (`screens/ticket.md`, ORC-114). `blocked`: `nil` or
  `%{flavor:, origin_label:, return_options: [%{label:, target:, leaves_group: boolean}]}` —
  `return_options` is the origin plus every earlier position, never a later one (`screens/
  ticket.md`), the first entry is always the one primary choice (the origin, unchanged from
  before this pass), and `leaves_group` — optional, `Map.get`-style, same reason as above — marks
  an option outside the origin's own sub-array (`screens/ticket.md`'s "An earlier option that sits
  outside the origin's own sub-array is marked as leaving it," ORC-116). Choosing one
  (`phx-click="resume"`, `phx-value-target={opt.target}`) dispatches `ResumeFlow` under the
  identical compare-and-swap. `conflict`: `nil` or `%{to:}`, set when this screen's own last
  dispatch (the
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
            <a href={@gate_action.href} class="btn btn-sm btn-outline">Review in document-review →</a>
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
              phx-click="resume"
              phx-value-target={opt.target}
              class={["btn btn-sm", i == 0 && "btn-primary", i != 0 && "btn-outline"]}
            >
              Return to <%= opt.label %><span
                :if={Map.get(opt, :leaves_group, false)}
                class="opacity-60"
              > (leaves this loop)</span>
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
    assigns =
      assigns
      |> assign(:last_key, assigns.sequence |> List.last() |> then(&(&1 && &1.key)))
      |> assign(:segments, rail_segments(assigns.sequence))

    ~H"""
    <ol class="flex flex-wrap items-center gap-1 text-xs">
      <.rail_segment :for={segment <- @segments} segment={segment} last_key={@last_key} />
    </ol>
    """
  end

  # Groups the flat, ordered `sequence` the same way `board`'s own `segments/1` groups lanes
  # (`screens/board.md`'s "Sub-arrays render as a bounded box") — a pure grouping of what was
  # already handed down, not a resolution of anything. `group_key` is read with `Map.get/2`
  # because `Sequence.positions/2` does not supply it yet (moduledoc) — a missing key groups
  # exactly like an explicit `nil`.
  defp rail_segments(sequence) do
    sequence
    |> Enum.chunk_by(&Map.get(&1, :group_key))
    |> Enum.flat_map(fn [pos | _] = chunk ->
      if Map.get(pos, :group_key), do: [{:group, chunk}], else: Enum.map(chunk, &{:pos, &1})
    end)
  end

  attr :segment, :any, required: true
  attr :last_key, :any, required: true

  defp rail_segment(%{segment: {:pos, pos}} = assigns) do
    assigns = assign(assigns, :pos, pos)

    ~H"""
    <li class="flex items-center gap-1">
      <.rail_badge pos={@pos} />
      <span :if={@pos.key != @last_key} class="opacity-30">→</span>
    </li>
    """
  end

  defp rail_segment(%{segment: {:group, positions}} = assigns) do
    assigns =
      assigns
      |> assign(:positions, positions)
      |> assign(:group_last_key, positions |> List.last() |> Map.fetch!(:key))

    ~H"""
    <li class="flex items-center gap-1">
      <span class="flex items-center gap-1 rounded-box border border-dashed border-primary/40 bg-primary/5 px-2 py-1">
        <%= for pos <- @positions do %>
          <.rail_badge pos={pos} />
          <span :if={pos.key != @group_last_key} class="opacity-30">→</span>
        <% end %>
      </span>
      <span :if={@group_last_key != @last_key} class="opacity-30">→</span>
    </li>
    """
  end

  attr :pos, :map, required: true

  defp rail_badge(assigns) do
    ~H"""
    <span class={[
      "badge",
      @pos.state == :passed && "badge-success",
      @pos.state == :current && "badge-primary",
      @pos.state == :upcoming && "badge-ghost"
    ]}>
      <%= @pos.label %><%= if @pos.kind == :gate and @pos.role, do: " (#{@pos.role})" %>
      <span
        :if={Map.get(@pos, :group_anchor, false)}
        title="Default throwback landing point for this group"
      >↺</span>
    </span>
    """
  end
end
