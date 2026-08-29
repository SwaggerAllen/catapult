defmodule Catapult.Storybook.Screens.DocumentReview do
  @moduledoc """
  Presentational shell for the `document-review` screen (`screens/document-review.md`). Stateless:
  every assign is handed down whole, and every write this screen can issue —
  `ApproveGate`/`DeclineGate`/`PostComment` — is a `phx-click`/`phx-submit` this module only wires,
  never dispatches: the LiveView owns loading the sentence-aligned diff, grouping comments by
  sentence for display only — `PostComment` always sends `locator: nil` in v1 (`screens/
  document-review.md`'s "The sentence locator is unset in v1"), so this grouping is a local
  rendering concern, not a protocol fact — and handling the events these controls emit
  (`"approve"`, `"decline"` with `phx-value-target`, `"open_comment_form"`/`"cancel_comment"`/
  `"post_comment"` with `phx-value-index`/the form's own `index`/`body` fields).

  `sentences`: `%{index:, text:, change: :unchanged | :added | :removed}`, in body order.
  `comments`: `%{sentence_index:, author:, body:}` — this render's own sentence grouping, this
  pass's comments only (`screens/document-review.md`'s "Deferred beyond v1"). `commenting_at`:
  `nil` or the sentence index whose inline compose form is open. No `stale` shape:
  stale marking does not ship in v1 (`screens/document-review.md`'s "Stale marking does not ship
  in v1", ORC-114) — `GateApproved`/`GateDeclined` carry no content identity to derive it from.
  `decline_error`: set when the last throw-back was rejected by `DeclineGate` for naming no
  comment since the gate's last resolution, or by the compare-and-swap for racing another writer
  or resolving a body this screen's own view has fallen behind (`{:engine_gate_already_resolved,
  ...}` / `{:engine_stale_gate_resolution, ...}`, ORC-114) — one rendering slot, three possible
  causes, since all three are the aggregate refusing to produce `GateApproved`/`GateDeclined` and
  this screen renders the refusal the identical synchronous way regardless of which one fired.

  `gate_exits`: `[%{label:, target:}]` — the name predates ORC-115 and is kept to avoid an
  unrelated churn to `document_review_live.ex` (dev's, outside this pass's reach); what it holds
  is no longer a declared exit list. `Catapult.Dsl.Workflow.throwback_default/3` already narrows
  this to at most one entry — whatever it resolves, `nil` when it resolves nothing
  (`docs/dsl-syntax.md` §15.10, ORC-115; the derivation itself is rendered here, not restated) —
  so the one entry present, if any, renders as the primary button.

  `throwback_targets`: `[%{label:, target:, leaves_group: boolean}]`, default `[]` — every other
  legal earlier position (`Catapult.Dsl.Workflow.throwback_targets/3`, minus the default above),
  offered behind a secondary disclosure rather than as a flat list of equally-weighted buttons
  (ORC-116, `screens/document-review.md`'s "Approve or throw back"); `leaves_group` marks a target
  outside the gate's own sub-array, the identical annotation `screens/ticket.md`'s own
  Blocked-return control draws. Defaults to `[]` because `document_review_live.ex` computes the
  raw target list already but does not yet label or wire it through (its own comment: "the
  `docs/ui-spec.md` §3.2 picker over `throwback_targets` is what covers that case, and it is
  unbuilt") — this screen renders whatever it is handed, including nothing.
  """

  use Phoenix.Component

  attr :node_id, :string, required: true
  attr :tier, :string, required: true
  attr :body_sha, :string, required: true
  attr :sentences, :list, default: []
  attr :comments, :list, default: []
  attr :gate_exits, :list, default: []
  attr :throwback_targets, :list, default: []
  attr :decline_error, :string, default: nil
  attr :commenting_at, :integer, default: nil

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
          commenting_at={@commenting_at}
        />
      </div>

      <div class="card bg-base-100 border border-base-300 shadow-sm">
        <div class="card-body gap-2">
          <h2 class="card-title text-sm">Gate action</h2>
          <div class="flex flex-wrap items-center gap-2">
            <button phx-click="approve" class="btn btn-sm btn-primary">Approve</button>
            <button
              :for={exit_ <- @gate_exits}
              phx-click="decline"
              phx-value-target={exit_.target}
              class="btn btn-sm btn-outline"
            >
              Throw back to <%= exit_.label %>
            </button>
          </div>
          <details :if={@throwback_targets != []} class="text-xs">
            <summary class="cursor-pointer opacity-70">Choose a different target</summary>
            <div class="flex flex-wrap gap-2 mt-2">
              <button
                :for={target <- @throwback_targets}
                phx-click="decline"
                phx-value-target={target.target}
                class="btn btn-xs btn-ghost"
              >
                <%= target.label %><span :if={Map.get(target, :leaves_group, false)} class="opacity-60"> (leaves this loop)</span>
              </button>
            </div>
          </details>
          <p class="text-xs opacity-60">Throwing back requires at least one comment below.</p>
        </div>
      </div>
    </div>
    """
  end

  attr :sentence, :map, required: true
  attr :comments, :list, required: true
  attr :commenting_at, :integer, default: nil

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
        <button
          :if={@sentence.change != :removed}
          phx-click="open_comment_form"
          phx-value-index={@sentence.index}
          class="btn btn-ghost btn-xs shrink-0"
        >
          comment
        </button>
      </div>

      <div :if={@comments != []} class="ml-6 mt-1 flex flex-col gap-1">
        <div :for={comment <- @comments} class="rounded-box bg-base-200 px-2 py-1 text-xs">
          <span class="font-semibold"><%= comment.author %>:</span> <%= comment.body %>
        </div>
      </div>

      <form
        :if={@commenting_at == @sentence.index}
        phx-submit="post_comment"
        class="ml-6 mt-1 flex flex-col gap-1"
      >
        <input type="hidden" name="index" value={@sentence.index} />
        <textarea
          name="body"
          class="textarea textarea-bordered textarea-xs w-full"
          rows="2"
          placeholder="Leave a comment..."
        ></textarea>
        <div class="flex gap-2">
          <button type="submit" class="btn btn-xs btn-primary">Post</button>
          <button type="button" phx-click="cancel_comment" class="btn btn-xs btn-ghost">Cancel</button>
        </div>
      </form>
    </div>
    """
  end
end
