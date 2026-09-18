defmodule Catapult.Generation.CommitPath do
  @moduledoc """
  The command edge (`Catapult.Engine.Events.DraftCommitted`'s own
  moduledoc: "extraction... happens at the command edge... a later
  ticket's commit path" — this ticket): grammar-validates a reported
  result and gates the engine event on that validation, atomically —
  `Catapult.Delivery.ResultHandler`'s configured implementation
  (`config/config.exs`), called once a result-report is authenticated
  and correlated.

  **One atomic commit per scope, at the end** (v5 §7.15's second
  invariant): every id/timestamp this module hands to `CommitDraft`/
  `RecordRunFailure` is generated here, at the edge, never inside the
  aggregate or reducer (the purity floor) — and nothing is written
  until validation already passed, so a scope that fails leaves no
  partial commit for the readiness query to trip over.
  """

  @behaviour Catapult.Delivery.ResultHandler

  alias Catapult.Config
  alias Catapult.Delivery
  alias Catapult.Dsl
  alias Catapult.Engine.Commands.CommitDraft
  alias Catapult.Engine.Commands.RecordRunFailure
  alias Catapult.Engine.Projections.ReadyScopes
  alias Catapult.Engine.Router
  alias Catapult.Engine.Store
  alias Catapult.Generation.Extraction

  @impl Catapult.Delivery.ResultHandler
  def handle_result(%{status: :limit_class_failure} = payload), do: record_failure(payload)
  def handle_result(%{status: :other_failure}), do: :ok
  def handle_result(%{status: :success} = payload), do: commit(payload)

  # Platform-wide (`chain.md` #14): every review body validates against
  # the one shared schema, never a per-tier restatement of the identical
  # grammar the way seventeen separate review tiers each used to.
  @review_grammar "schemas/review.xsd"

  defp commit(%{body: body} = payload) when is_binary(body) do
    with {:ok, loaded} <- load_bundle(),
         {:ok, base_tier_name, mode} <- resolve_dispatch_tier(payload.tier),
         {:ok, tier} <- fetch_tier(loaded.chain, base_tier_name) do
      case mode do
        :review -> commit_review(loaded.chain, tier, payload)
        :generation -> commit_draft(loaded.chain, tier, payload)
      end
    end
  end

  defp commit(%{body: nil}), do: {:error, :missing_body}

  ## -- generation-tier commit ---------------------------------------------

  defp commit_draft(chain, tier, payload) do
    with :ok <-
           Dsl.validate_draft(
             bundles_root(),
             chain.name,
             tier.draft.root_tag,
             tier.draft.grammar,
             payload.body
           ),
         {element, _rest} <- :xmerl_scan.string(String.to_charlist(payload.body)) do
      node = Store.get_node(payload.project_id, payload.node_id)
      parent_node_id = node && node.parent_node_id

      resolver = fn target_tier, value ->
        resolve_target(payload.project_id, target_tier, value)
      end

      # A minted node's fields are set once, at mint time
      # (`Reducer.apply_mint/2`, off `tier.mint_fields`); its own
      # committed draft only ever adds `tier.draft_fields`-sourced
      # values, so merging rather than replacing is what keeps a tier
      # that is both a mint target and a draft-committer (`vocab`, the
      # one tier in `bundles/default` that is both) from losing its
      # mint-set fields the moment its own draft commits
      # (`systems/engine.md`'s ORC-236 entry).
      own_fields =
        Map.merge(
          (node && node.fields) || %{},
          Extraction.fields(element, draft_field_sources(tier))
        )

      own_produces = Extraction.produces(element, tier.produces, parent_node_id)
      own_produces_by_kind = Map.new(own_produces, &{&1.kind, &1.content})

      mint_result =
        Extraction.mints(
          element,
          payload.tier,
          chain,
          own_fields,
          own_produces_by_kind,
          parent_node_id,
          resolver
        )

      cmd = %CommitDraft{
        project_id: payload.project_id,
        node_id: payload.node_id,
        tier: payload.tier,
        scope_key: payload.scope_key,
        parent_node_id: parent_node_id,
        draft_id: Ecto.UUID.generate(),
        body_sha: body_sha(payload.body),
        committed_at: clock().utc_now(),
        fields: own_fields,
        mints: mint_result.mints,
        edges:
          mint_result.edges ++
            Extraction.references(
              element,
              payload.tier,
              chain,
              payload.node_id,
              parent_node_id,
              resolver
            ),
        produces: own_produces
      }

      dispatch_and_cache(cmd, payload)
    end
  rescue
    error -> {:error, {:malformed_xml, Exception.format(:error, error, __STACKTRACE__)}}
  end

  defp dispatch_and_cache(%CommitDraft{} = cmd, payload) do
    case Router.dispatch(cmd, consistency: :strong) do
      :ok ->
        Delivery.put_draft_body(payload.project_id, payload.node_id, payload.body, cmd.body_sha)
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  ## -- review-tier commit ---------------------------------------------

  defp commit_review(chain, _tier, payload) do
    with :ok <-
           Dsl.validate_draft(bundles_root(), chain.name, "review", @review_grammar, payload.body),
         {element, _rest} <- :xmerl_scan.string(String.to_charlist(payload.body)),
         {:ok, node} <- fetch_node(payload.project_id, payload.node_id),
         draft_id when is_binary(draft_id) <- node.current_draft_id || {:error, :no_pending_draft} do
      cmd = %Catapult.Engine.Commands.WriteReview{
        project_id: payload.project_id,
        draft_id: draft_id,
        review_id: Ecto.UUID.generate(),
        score: review_score(element),
        body_sha: body_sha(payload.body),
        findings: review_findings(element),
        kind: :ai
      }

      Router.dispatch(cmd, consistency: :strong)
    end
  rescue
    error -> {:error, {:malformed_xml, Exception.format(:error, error, __STACKTRACE__)}}
  end

  defp review_score(element) do
    element
    |> Extraction.text("score")
    |> case do
      nil -> 0
      raw -> raw |> String.trim() |> String.to_integer()
    end
  end

  defp review_findings(element) do
    for finding_el <- Extraction.navigate_list(element, ["finding"]) do
      %{id: Extraction.attribute(finding_el, "id"), message: Extraction.own_text(finding_el)}
    end
  end

  ## -- limit-class failure ---------------------------------------------

  defp record_failure(payload) do
    cmd = %RecordRunFailure{
      project_id: payload.project_id,
      node_id: payload.node_id,
      tier: payload.tier,
      scope_key: payload.scope_key,
      run_id: payload.run_key,
      reason: payload[:reason] || "limit_class_failure",
      occurred_at: clock().utc_now()
    }

    Router.dispatch(cmd, consistency: :strong)
  end

  ## -- shared -----------------------------------------------------------

  # `tier.draft_fields` is `name => tag`, read off this same commit
  # (`Catapult.Dsl.DeclaredInSchema.mints_and_fields/2`); `Extraction
  # .fields/2` expects `name => "draft.<tag>"`.
  defp draft_field_sources(%{draft_fields: draft_fields}) do
    Map.new(draft_fields, fn {name, tag} -> {name, "draft." <> tag} end)
  end

  defp load_bundle, do: Dsl.load(Config.fetch!(:generation, :bundles_root))
  defp bundles_root, do: Config.fetch!(:generation, :bundles_root) |> Path.join("bundles")
  defp clock, do: Config.fetch!(:generation, :clock)

  # A review is a block on the tier it reviews now, not a tier of its
  # own (`chain.md` #14) — `ReadyScopes.base_tier_name/1` reverses the
  # dispatched `payload.tier` back to the tier it addresses.
  defp resolve_dispatch_tier(dispatched_name) do
    case ReadyScopes.base_tier_name(dispatched_name) do
      nil -> {:ok, dispatched_name, :generation}
      base -> {:ok, base, :review}
    end
  end

  defp fetch_tier(%{tiers: tiers}, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, tier} -> {:ok, tier}
      :error -> {:error, {:unknown_tier, tier_name}}
    end
  end

  defp fetch_node(project_id, node_id) do
    case Store.get_node(project_id, node_id) do
      nil -> {:error, {:unknown_node, node_id}}
      node -> {:ok, node}
    end
  end

  # `value` is `nil` for a `scope: singleton` endpoint (`chain.md`
  # #27's locator forms) — there is exactly one node to mean, so
  # the lookup carries no `"id"` key at all, matching that scope's own
  # flat `%{}` scope_key (`ReadyScopes.candidates/3`).
  defp resolve_target(project_id, target_tier, nil) do
    case Store.get_node_by_scope(project_id, target_tier, %{}) do
      nil -> nil
      node -> node.id
    end
  end

  defp resolve_target(project_id, target_tier, value) do
    case Store.get_node_by_scope(project_id, target_tier, %{"id" => value}) do
      nil -> nil
      node -> node.id
    end
  end

  defp body_sha(body), do: :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
end
