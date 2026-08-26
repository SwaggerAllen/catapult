defmodule CatapultWeb.DocumentReviewLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.DocumentReview.document_review/1`
  (`screens/document-review.md`): the design-gate action at sentence
  granularity. Shows whatever the chain produced at the ticket's
  current gate position — the entry node, Phase 4's own single
  node-per-gate mapping (`systems/dashboard.md`'s ORC-34 entry) — and
  issues `ApproveGate`/`DeclineGate`/`PostComment`.

  **The sentence locator is unset in v1** (`screens/document-review.md`):
  every `PostComment` carries `locator: nil`, so which sentence a
  comment sits beside on screen is this render's own local grouping,
  never round-tripped. Comments loaded fresh — `Catapult.Engine
  .Projections.CommentFeedback.since_last_resolution/2`, this pass's
  comments only — carry no real per-sentence position and are bucketed
  at sentence 0, together; a comment posted during this connected
  session is appended at the sentence its own "comment" button was
  clicked from, for the rest of this session only. A fresh mount always
  re-buckets to 0, which is what "reload this screen and every comment
  on a node renders together, undifferentiated by sentence" means in
  practice.

  The diff is a **reading aid**, not the anchoring mechanism (`screens/
  document-review.md`): `List.myers_difference/2` over each body's own
  sentence split, never sent anywhere — the aggregate never sees which
  sentence a comment sat beside.
  """
  use CatapultWeb, :live_view

  alias Catapult.Config
  alias Catapult.Delivery.FeatureLifecycle
  alias Catapult.Delivery.Store, as: DeliveryStore
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.ApproveGate
  alias Catapult.Engine.Commands.DeclineGate
  alias Catapult.Engine.Commands.PostComment
  alias Catapult.Engine.Projections.CommentFeedback
  alias Catapult.Engine.Projections.GateComments
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store, as: EngineStore
  alias CatapultWeb.Live.Actor

  @impl true
  def mount(%{"project_id" => project_id, "flow_id" => flow_id}, _session, socket) do
    {:ok, assign(socket, project_id: project_id, flow_id: flow_id, commenting_at: nil)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, load(socket)}

  @impl true
  def handle_event("open_comment_form", %{"index" => index}, socket) do
    {:noreply, assign(socket, commenting_at: String.to_integer(index))}
  end

  def handle_event("cancel_comment", _params, socket) do
    {:noreply, assign(socket, commenting_at: nil)}
  end

  def handle_event("post_comment", %{"index" => index, "body" => body}, socket) do
    body = String.trim(body)

    if body == "" do
      {:noreply, assign(socket, decline_error: "A comment needs a body.")}
    else
      cmd = %PostComment{
        project_id: socket.assigns.project_id,
        node_id: socket.assigns.node_id,
        body_sha: socket.assigns.body_sha,
        locator: nil,
        author_id: Actor.id(),
        body: body,
        posted_at: Catapult.Clock.System.utc_now()
      }

      case Router.dispatch(cmd, consistency: :strong) do
        :ok ->
          comment = %{sentence_index: String.to_integer(index), author: Actor.id(), body: body}

          {:noreply,
           socket
           |> update(:comments, &(&1 ++ [comment]))
           |> assign(commenting_at: nil, decline_error: nil)}

        {:error, {:engine_stale_comment, _}} ->
          {:noreply, assign(socket, decline_error: stale_body_message())}

        {:error, {:engine_comment_unknown_node, _}} ->
          {:noreply, assign(socket, decline_error: stale_body_message())}
      end
    end
  end

  def handle_event("approve", _params, socket) do
    cmd = %ApproveGate{
      project_id: socket.assigns.project_id,
      flow_id: socket.assigns.flow_id,
      gate: socket.assigns.gate.name,
      node_id: socket.assigns.node_id,
      body_sha: socket.assigns.body_sha,
      actor_id: Actor.id()
    }

    dispatch_gate_command(socket, cmd)
  end

  def handle_event("decline", %{"target" => target}, socket) do
    gate_name = socket.assigns.gate.name

    cmd = %DeclineGate{
      project_id: socket.assigns.project_id,
      flow_id: socket.assigns.flow_id,
      gate: gate_name,
      throwback_to: target,
      since_sequence: GateComments.last_resolution_sequence(socket.assigns.project_id, gate_name),
      node_id: socket.assigns.node_id,
      body_sha: socket.assigns.body_sha,
      actor_id: Actor.id()
    }

    dispatch_gate_command(socket, cmd)
  end

  defp dispatch_gate_command(socket, cmd) do
    case Router.dispatch(cmd, consistency: :strong) do
      :ok ->
        {:noreply,
         push_navigate(socket,
           to: "/projects/#{socket.assigns.project_id}/tickets/#{socket.assigns.flow_id}"
         )}

      {:error, {:engine_gate_decline_without_comment, _}} ->
        {:noreply,
         assign(socket,
           decline_error:
             "Throwing back needs at least one comment since this gate's last resolution."
         )}

      {:error, {:engine_gate_already_resolved, disposition: disposition, gate: _gate}} ->
        {:noreply,
         assign(socket,
           decline_error: "Already #{disposition} — refresh to see the current state."
         )}

      {:error, {:engine_stale_gate_resolution, _}} ->
        {:noreply, assign(socket, decline_error: stale_body_message())}
    end
  end

  defp stale_body_message,
    do: "This document changed since you loaded it — refresh to see the current version."

  @impl true
  def render(%{found?: false} = assigns) do
    ~H"""
    <div class="p-6">
      No design gate is currently open on ticket <span class="font-mono">{@flow_id}</span>
      in project <span class="font-mono">{@project_id}</span>.
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Catapult.Storybook.Screens.DocumentReview.document_review
      node_id={@node_id}
      tier={@tier}
      body_sha={@body_sha}
      sentences={@sentences}
      comments={@comments}
      gate_exits={@gate_exits}
      decline_error={@decline_error}
      commenting_at={@commenting_at}
    />
    """
  end

  defp load(socket) do
    project_id = socket.assigns.project_id
    flow_id = socket.assigns.flow_id
    flow = EngineStore.get_flow(project_id, flow_id)
    lifecycle = DeliveryStore.get_feature_lifecycle(project_id, flow_id)
    workflow_load = Dsl.load(Config.fetch!(:engine, :bundles_root))

    with %{} = flow <- flow,
         %{} = lifecycle <- lifecycle,
         {:ok, %{workflow: %{} = workflow}} <- workflow_load,
         {:gate, gate_name} <- FeatureLifecycle.status(lifecycle),
         %{} = gate <- Map.get(workflow.gates, gate_name),
         node_id when not is_nil(node_id) <- flow.entry_node_id,
         %{} = node <- EngineStore.get_node(project_id, node_id) do
      assign_review(socket, gate, node)
    else
      _not_at_an_open_design_gate -> assign(socket, found?: false)
    end
  end

  defp assign_review(socket, gate, node) do
    project_id = socket.assigns.project_id
    current_body = DeliveryStore.get_draft_body(project_id, node.id) || ""
    previous_body = DeliveryStore.get_previous_draft_body(project_id, node.id)

    assign(socket,
      found?: true,
      gate: gate,
      node_id: node.id,
      tier: node.tier,
      body_sha: node.body_sha,
      sentences: diff_sentences(previous_body, current_body),
      comments: load_comments(project_id, node.id),
      gate_exits: Enum.map(gate.throwback, &%{label: &1, target: &1}),
      decline_error: nil
    )
  end

  defp load_comments(project_id, node_id) do
    project_id
    |> CommentFeedback.since_last_resolution(node_id)
    |> Enum.map(&%{sentence_index: 0, author: &1.author_id, body: &1.body})
  end

  defp diff_sentences(previous_body, current_body) do
    previous_sentences = split_sentences(previous_body)
    current_sentences = split_sentences(current_body)

    previous_sentences
    |> List.myers_difference(current_sentences)
    |> Enum.flat_map(&tag_change/1)
    |> Enum.with_index()
    |> Enum.map(fn {{text, change}, index} -> %{index: index, text: text, change: change} end)
  end

  defp tag_change({:eq, sentences}), do: Enum.map(sentences, &{&1, :unchanged})
  defp tag_change({:ins, sentences}), do: Enum.map(sentences, &{&1, :added})
  defp tag_change({:del, sentences}), do: Enum.map(sentences, &{&1, :removed})

  defp split_sentences(nil), do: []
  defp split_sentences(""), do: []
  defp split_sentences(body), do: Regex.split(~r/(?<=[.!?])\s+/, String.trim(body), trim: true)
end
