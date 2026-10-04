defmodule CatapultWeb.ExplainWhyLive do
  @moduledoc """
  Mounts `Catapult.Storybook.Screens.ExplainWhy.explain_why/1`
  (`screens/explain-why.md`): loads the node
  (`Catapult.Engine.Store.get_node/2`, project-scoped per ORC-87) and
  the chain (`Catapult.Dsl.load/2`, the same pattern
  `lib/catapult/generation/**` and `lib/catapult/delivery/**` already
  use), calls `Catapult.Engine.Projections.ReadyScopes.explain/2`
  **verbatim**, and hands the report straight down — no readiness
  recomputation here, ever (`screens/explain-why.md`'s own non-goal).

  `review_tier?` is not part of `explain/2`'s own report; it is read
  off the tier's `review:` block (`Catapult.Dsl.Tier`, non-nil only on
  a tier that reviews its own draft, `chain.md` #14) and handed down so
  the component can render the caveat an ordinary empty `blocking` list
  can't distinguish on its own.

  `passes_scope_filter` is always `true`: `chain.md` retires
  `scope_filter:` from the grammar entirely (`systems/core_dsl.md`'s
  #45 entry), so nothing excludes a candidate at enumeration any more.
  `screens/explain-why.md` and the storybook component still describe
  it as a meaningful signal — flagged in this ticket's hand-back rather
  than rewritten here, since that screen's own prose is design's to
  amend.
  """
  use CatapultWeb, :live_view

  alias Catapult.Config
  alias Catapult.Dsl
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Store
  alias Catapult.Storybook.Screens.ExplainWhy

  @impl true
  def mount(%{"project_id" => project_id, "node_id" => node_id}, _session, socket) do
    {:ok, load(socket, project_id, node_id)}
  end

  defp load(socket, project_id, node_id) do
    with node when not is_nil(node) <- Store.get_node(project_id, node_id),
         {:ok, %{chain: chain}} <- Dsl.load(Config.fetch!(:engine, :bundles_root)) do
      report = ReadyScopes.explain(chain, node)

      assign(socket,
        found?: true,
        project_id: project_id,
        node_id: node_id,
        tier: report.tier,
        scope_key: report.scope_key,
        passes_scope_filter: true,
        blocking: report.blocking,
        review_tier?: review_tier?(chain, node.tier)
      )
    else
      _ -> assign(socket, found?: false, project_id: project_id, node_id: node_id)
    end
  end

  defp review_tier?(chain, tier_name) do
    case Map.fetch(chain.tiers, tier_name) do
      {:ok, tier} -> not is_nil(tier.review)
      :error -> false
    end
  end

  @impl true
  def render(%{found?: false} = assigns) do
    ~H"""
    <div class="p-6">
      No node <span class="font-mono">{@node_id}</span> in project <span class="font-mono">{@project_id}</span>.
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <ExplainWhy.explain_why
      project_id={@project_id}
      node_id={@node_id}
      tier={@tier}
      scope_key={@scope_key}
      passes_scope_filter={@passes_scope_filter}
      blocking={@blocking}
      review_tier?={@review_tier?}
    />
    """
  end
end
