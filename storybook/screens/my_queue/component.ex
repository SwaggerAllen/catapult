defmodule Catapult.Storybook.Screens.MyQueue do
  @moduledoc """
  Presentational shell for the `my-queue` screen (`screens/my-queue.md`). Stateless: every assign
  is handed down whole, nothing is fetched here, and there is no socket. The eventual LiveView owns
  loading `rows`, switching `tab`, and navigating on row click — this module only renders the shape
  those produce. In Phase 4 both tabs' rows come from the identical read (`screens/my-queue.md`'s
  "In Phase 4 both tabs show the identical set" — no assignee or role-holder projection exists
  yet); `tab` still switches, since the two questions are protocol-real and will diverge once
  identity ships one.

  `rows` entries: `%{id:, project_id:, project_name:, title:, status:, kind: :sign_off | :unblock
  | :triage, href:}`. `kind` is the fixed action-needed vocabulary (`screens/my-queue.md`) — no
  other value is legal. Rows are not scoped to one project (`screens/my-queue.md`'s "Cross-project,
  deliberately"), so `project_name` is always shown.
  """

  use Phoenix.Component

  attr :tab, :atom, default: :assigned, values: [:assigned, :my_roles]
  attr :rows, :list, default: []

  def my_queue(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 p-6">
      <div class="flex items-center justify-between">
        <h1 class="text-xl font-semibold">My queue</h1>
      </div>

      <div role="tablist" class="tabs tabs-boxed w-fit">
        <a role="tab" href="?tab=assigned" class={["tab", @tab == :assigned && "tab-active"]}>
          Assigned
        </a>
        <a role="tab" href="?tab=my_roles" class={["tab", @tab == :my_roles && "tab-active"]}>
          My roles
        </a>
      </div>

      <div :if={@rows == []} class="rounded-box border border-base-300 p-8 text-center opacity-70">
        <p>Nothing needs you right now — the machine has the ball.</p>
        <a href="#" class="link link-primary text-sm">See what it's waiting on →</a>
      </div>

      <div :if={@rows != []} class="overflow-x-auto rounded-box border border-base-300">
        <table class="table">
          <thead>
            <tr>
              <th>Ticket</th>
              <th>Project</th>
              <th>Status</th>
              <th>Needs</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} class="hover:bg-base-200 cursor-pointer">
              <td class="font-mono text-sm">
                <a href={row.href} class="link link-hover"><%= row.id %></a>
                <div class="text-xs opacity-60 font-sans"><%= row.title %></div>
              </td>
              <td class="text-sm"><%= row.project_name %></td>
              <td><span class="badge badge-outline"><%= row.status %></span></td>
              <td><.kind_badge kind={row.kind} /></td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  attr :kind, :atom, required: true

  defp kind_badge(assigns) do
    ~H"""
    <span :if={@kind == :sign_off} class="badge badge-primary gap-1">sign off</span>
    <span :if={@kind == :unblock} class="badge badge-warning gap-1">unblock</span>
    <span :if={@kind == :triage} class="badge badge-secondary gap-1">triage</span>
    """
  end
end
