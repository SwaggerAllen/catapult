defmodule Catapult.Storybook.Screens.DocumentReview do
  @moduledoc """
  Presentational shell for the `document-review` screen (`screens/document-review.md`). Stateless:
  every assign is handed down whole, nothing is fetched here, and there is no socket. The eventual
  LiveView owns loading the sentence-aligned diff, grouping comments by sentence for display only
  — `PostComment` always sends `locator: nil` in v1 (`screens/document-review.md`'s "The sentence
  locator is unset in v1"), so this grouping is a local rendering concern, not a protocol fact —
  and issuing `ApproveGate`/`DeclineGate`/`PostComment` — this module only renders the shape those
  produce, including a decline rejected by the aggregate for naming no comment.

  `sentences`: `%{index:, text:, change: :unchanged | :added | :removed}`, in body order.
  `comments`: `%{sentence_index:, author:, body:}` — this render's own sentence grouping, this
  pass's comments only (`screens/document-review.md`'s "Deferred beyond v1"). No `stale` shape:
  stale marking does not ship in v1 (`screens/document-review.md`'s "Stale marking does not ship
  in v1", ORC-114) — `GateApproved`/`GateDeclined` carry no content identity to derive it from.
  `decline_error`: set when the last throw-back was rejected by `DeclineGate` for naming no
  comment since the gate's last resolution, or by the compare-and-swap for racing another writer
  or resolving a body this screen's own view has fallen behind (`{:engine_gate_already_resolved,
  ...}` / `{:engine_stale_gate_resolution, ...}`, ORC-114) — one rendering slot, three possible
  causes, since all three are the aggregate refusing to produce `GateApproved`/`GateDeclined` and
  this screen renders the refusal the identical synchronous way regardless of which one fired.
  """

  use Phoenix.Component

  attr :node_id, :string, required: true
  attr :tier, :string, required: true
  attr :body_sha, :string, required: true
  attr :sentences, :list, default: []
  attr :comments, :list, default: []
  attr :gate_exits, :list, default: []
  attr :decline_error, :string, default: nil

  def document_review(assigns) do
    ~H"""
    <div class="flex flex-col gap-4 p-6 max-w-3xl">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-xl font-semibold"><%= @tier %></h1>
          <p class="text-xs font-mono opacity-60"><%= @node_id %> · <%= @body_sha %></p>
        </div>
      </div>

      <div :if={@decline_error} class="alert alert-error">
        <span><%= @decline_error %></span>
      </div>

      <div class="flex flex-col gap-1">
        <.sentence
          :for={sentence <- @sentences}
          sentence={sentence}
          comments={Enum.filter(@comments, &(&1.sentence_index == sentence.index))}
        />
      </div>

      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body gap-2">
          <h2 class="card-title text-sm">Gate action</h2>
          <div class="flex flex-wrap gap-2">
            <button class="btn btn-sm btn-primary">Approve</button>
            <button :for={exit_ <- @gate_exits} class="btn btn-sm btn-outline">
              Throw back to <%= exit_.label %>
            </button>
          </div>
          <p class="text-xs opacity-60">Throwing back requires at least one comment below.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :sentence, :map, required: true
  attr :comments, :list, required: true

  defp sentence(assigns) do
    ~H"""
    <div class={[
      "rounded-box px-3 py-2 text-sm",
      @sentence.change == :added && "bg-success/10",
      @sentence.change == :removed && "bg-error/10 line-through opacity-60",
      @sentence.change == :unchanged && "bg-transparent"
    ]}>
      <div class="flex items-start gap-2">
        <span class="font-mono text-xs opacity-40 shrink-0"><%= @sentence.index %></span>
        <p class="grow"><%= @sentence.text %></p>
        <button :if={@sentence.change != :removed} class="btn btn-ghost btn-xs shrink-0">
          comment
        </button>
      </div>

      <div :if={@comments != []} class="ml-6 mt-1 flex flex-col gap-1">
        <div :for={comment <- @comments} class="rounded-box bg-base-200 px-2 py-1 text-xs">
          <span class="font-semibold"><%= comment.author %>:</span> <%= comment.body %>
        </div>
      </div>
    </div>
    """
  end
end
