defmodule Catapult.Generation.ContextAssembly do
  @moduledoc """
  Evaluates a tier's context walks and renders its Liquid prompt
  (`dsl-syntax.md` §7, §9) — one path for generation and review tiers
  alike, so "the reviewer sees exactly the generator's context plus
  the draft" (`systems/generation.md`'s per-tier triad invariant) is
  enforced by sharing this module, not by convention. A review tier
  carries no `context:` of its own (§3.3 — it is fixed equal to the
  reviewed tier's at load time); this module reads the *reviewed*
  tier's walks in that case and adds `draft`.

  Variable naming follows §9: a context entry's variable name is its
  *resolved* target tier's name, and entries landing on the same tier
  combine into one collection — grouped here by each resolved node's
  own `tier` field rather than re-derived from the walk's parsed
  shape, which handles a bare self-hop and an explicit `-> tier`
  target identically because both are read off the same place.

  **`input.<role>`/`input.*` are a second, direct read of delivery —
  never through `ContextResolver.resolve/2`'s node-collection fold**
  (ORC-107, `systems/generation.md`'s own entry). `ContextResolver`
  answers `{:ok, []}` for every `:input` walk (correct for readiness
  and staleness, `Catapult.Engine.Projections.ContextResolver`'s own
  moduledoc) and useless for rendering: an input document has no
  `handle:` for `render_node/2` to project, it is pinned prose. So
  `input_variables/3` below reads the pinned document(s) straight off
  `Catapult.Delivery` — the same cross-boundary shape `draft_variable/2`
  already uses for `get_draft_body/2` — and sets the result as a
  **plain string**, keyed by role name for `input.<role>` or the
  reserved word `raft` for `input.*` (dsl-syntax.md §9). A role with no
  pinned documents is left out of the variables map entirely, the same
  omission-is-the-contract shape `feedback`/`prior_review` use below —
  never `""`.

  `feedback`/`prior_review` (ORC-34, `systems/generation.md`'s own
  entry) are two direct engine reads, unconditional — unlike `draft`,
  neither is review-tier-only (`dsl-syntax.md` §9/§3.3): `feedback` is
  `Catapult.Engine.Projections.CommentFeedback.since_last_resolution/2`
  and `prior_review` is `Catapult.Engine.Store.reviews_for_node/2`.
  Both are left out of the variables map entirely — never set to `[]`
  or an empty map — where nothing has been posted or reviewed yet. The
  omission is the contract: absent means nothing was posted, which is
  the honest shape and the one this module guarantees.

  It is deliberately not the only thing holding the line, because
  Liquid's truthiness would punish it. Only `nil` and `false` are
  falsy there, so an empty list is **truthy** and a bare
  `{% if feedback %}` would fire on every render the moment any caller
  set `[]` instead of omitting. The five shipped prompts that gate a
  revision section therefore guard on `feedback.size > 0` rather than
  on bare truthiness (ORC-134), which is correct under either shape.
  Keep both halves: this module and `bundles/**` are edited by
  different passes, and a guard that only works because of a promise
  made in another tree is one refactor away from silently opening.
  """

  alias Catapult.Delivery
  alias Catapult.Dsl.BundlePath
  alias Catapult.Dsl.Chain
  alias Catapult.Dsl.ContextWalk
  alias Catapult.Engine.Projections.CommentFeedback
  alias Catapult.Engine.Projections.ContextResolver
  alias Catapult.Engine.Store
  alias Catapult.Engine.Store.Node
  alias Catapult.Engine.Store.Review
  alias Catapult.Generation.NodeId
  alias Catapult.Generation.Runtime

  @type failure ::
          {:unknown_tier, String.t()}
          | {:prompt_not_found, String.t()}
          | {:template_invalid, term()}
          | {:render_failed, term()}
          | {:unknown_credential_names, atom(), [String.t()]}

  @doc """
  Builds the dispatch request for `tier_name`/`node` (a `ReadyScopes`
  result — either a generation-tier candidate or, for a review tier,
  the *reviewed* tier's own node): renders the Liquid prompt and
  returns `Catapult.Delivery.HostPort.request()`.
  """
  @spec build(Chain.t(), binary(), String.t(), Node.t()) ::
          {:ok, Catapult.Delivery.HostPort.request()} | {:error, failure()}
  def build(chain, project_id, tier_name, node) do
    with {:ok, tier} <- fetch_tier(chain, tier_name),
         {:ok, generator_tier, review?} <- resolve_generator_tier(chain, tier),
         variables = build_variables(chain, project_id, generator_tier, node, review?),
         {:ok, prompt_path} <- resolve_prompt(chain, tier),
         {:ok, template} <- parse_template(prompt_path),
         {:ok, rendered} <- render(template, variables, chain),
         {:ok, credential_names} <- bound_credential_names() do
      {:ok,
       %{
         project_id: project_id,
         node_id: NodeId.resolve(node),
         tier: tier_name,
         scope_key: node.scope_key,
         root_tag: root_tag(tier),
         rendered_prompt: rendered,
         credential_names: credential_names
       }}
    end
  end

  # The bindings entry for the `:generation` kind decides which
  # runtime's credential names are legal (`systems/generation.md`'s
  # ORC-215 entry: "keyed by whichever runtime is bound to the
  # :generation kind") — `Catapult.Generation.cast_credential_order/1`
  # only checks the value is drawn from *some* known runtime's set at
  # boot (catching a typo before the first dispatch); this is the
  # narrower, runtime-scoped check, run at request-build time because
  # only here are both config values loaded and read together.
  defp bound_credential_names do
    runtime = Catapult.Config.fetch!(:generation, :runtime)
    names = Catapult.Config.fetch!(:generation, :credential_order)
    known = Runtime.credential_names(runtime)

    case Enum.reject(names, &(&1 in known)) do
      [] -> {:ok, names}
      unknown -> {:error, {:unknown_credential_names, runtime, unknown}}
    end
  end

  defp fetch_tier(%Chain{tiers: tiers}, tier_name) do
    case Map.fetch(tiers, tier_name) do
      {:ok, tier} -> {:ok, tier}
      :error -> {:error, {:unknown_tier, tier_name}}
    end
  end

  # A review tier reads its context off the tier it reviews (§3.3 —
  # load-time-checked equal); a generation tier reads its own.
  defp resolve_generator_tier(chain, %{reviews: reviewed}) when not is_nil(reviewed) do
    with {:ok, reviewed_tier} <- fetch_tier(chain, reviewed) do
      {:ok, reviewed_tier, true}
    end
  end

  defp resolve_generator_tier(_chain, tier), do: {:ok, tier, false}

  defp root_tag(%{reviews: reviewed}) when not is_nil(reviewed), do: "review"
  defp root_tag(%{draft: %{root_tag: root_tag}}), do: root_tag

  defp build_variables(chain, project_id, generator_tier, node, review?) do
    base =
      generator_tier.context
      |> Enum.flat_map(fn walk ->
        case ContextResolver.resolve(walk, node) do
          {:ok, targets} -> targets
          {:error, :unsupported} -> []
        end
      end)
      |> Enum.group_by(& &1.tier)
      |> Map.new(fn {tier_name, nodes} ->
        {tier_name, Enum.map(nodes, &render_node(chain, &1))}
      end)
      |> Map.put("self", render_node(chain, node))
      |> input_variables(project_id, generator_tier.context)
      |> feedback_variable(project_id, node)
      |> prior_review_variable(project_id, node)

    if review?, do: Map.put(base, "draft", draft_variable(project_id, node)), else: base
  end

  defp draft_variable(project_id, %Node{id: node_id}) do
    Delivery.get_draft_body(project_id, node_id) || ""
  end

  # Direct delivery reads, one per `:input` walk — never through
  # `ContextResolver` (moduledoc above). `raft` is the wildcard's own
  # reserved variable name (dsl-syntax.md §9); an `input.<role>` walk's
  # variable is the role name itself.
  defp input_variables(variables, project_id, context_walks) do
    Enum.reduce(context_walks, variables, fn
      %ContextWalk{source: :input, wildcard: true}, acc ->
        put_input_variable(acc, "raft", Delivery.get_raft(project_id))

      %ContextWalk{source: :input, role: role}, acc when is_binary(role) ->
        put_input_variable(acc, role, Delivery.get_input_documents(project_id, role))

      _walk, acc ->
        acc
    end)
  end

  defp put_input_variable(variables, _name, []), do: variables

  defp put_input_variable(variables, name, docs),
    do: Map.put(variables, name, Enum.join(docs, "\n\n"))

  # `CommentFeedback` itself returns atom-keyed entries (an ordinary
  # Elixir map, useful to an Elixir caller); Solid's own template
  # variables are always string-keyed (`render_node/2`'s own "id"/
  # "fragments" below), so this is where the two conventions meet. The
  # key is left out of `variables` entirely on `[]` rather than set to
  # an empty list — the moduledoc has why, and why the templates guard
  # on `feedback.size > 0` instead of trusting that omission.
  defp feedback_variable(variables, project_id, %Node{id: node_id}) do
    case CommentFeedback.since_last_resolution(project_id, node_id) do
      [] ->
        variables

      entries ->
        rendered =
          Enum.map(entries, fn entry ->
            %{
              "body" => entry.body,
              "locator" => entry.locator,
              "author_id" => entry.author_id,
              "posted_at" => entry.posted_at
            }
          end)

        Map.put(variables, "feedback", rendered)
    end
  end

  defp prior_review_variable(variables, project_id, %Node{id: node_id}) do
    case Store.reviews_for_node(project_id, node_id) do
      %Review{} = review ->
        Map.put(variables, "prior_review", %{
          "score" => review.score,
          "findings" => review.findings,
          "kind" => review.kind,
          "body_sha" => review.body_sha
        })

      nil ->
        variables
    end
  end

  defp render_node(chain, %Node{} = node) do
    tier = Map.get(chain.tiers, node.tier)
    handle_fields = if tier, do: tier.handle_fields, else: []
    handle_fragments = if tier, do: tier.handle_fragments, else: []

    fields =
      for name <- handle_fields, into: %{} do
        {name, Map.get(node.fields || %{}, name)}
      end

    fragments =
      for kind <- handle_fragments, into: %{} do
        content = node.id |> Store.fragments(kind) |> Enum.map_join("\n\n", & &1.content)
        {kind, content}
      end

    fields
    |> Map.put("id", NodeId.resolve(node))
    |> Map.put("fragments", fragments)
  end

  defp resolve_prompt(%Chain{name: bundle_name}, %{prompt: prompt}) when is_binary(prompt) do
    dir = Path.join(bundles_root(), bundle_name)

    case BundlePath.resolve(dir, prompt) do
      nil -> {:error, {:prompt_not_found, prompt}}
      path -> {:ok, path}
    end
  end

  defp resolve_prompt(_chain, tier), do: {:error, {:prompt_not_found, inspect(tier)}}

  defp bundles_root,
    do: Catapult.Config.fetch!(:generation, :bundles_root) |> Path.join("bundles")

  # sobelow_skip ["Traversal.FileModule"]
  #
  # `path` cannot leave the bundle: `Catapult.Dsl.BundlePath.resolve/2`
  # is the only thing that produces it, and it refuses any candidate
  # that expands outside the bundle directory — covered by
  # `Catapult.Dsl.BundlePathTest`'s containment cases, including the
  # escape this annotation would otherwise be hiding. The skip is here
  # because sobelow reads the call site and cannot see the guard
  # upstream of it, not because the finding was waved through: it was a
  # real traversal, reproduced against /etc/passwd, and fixed at the
  # resolver rather than suppressed here.
  defp parse_template(path) do
    case path |> File.read!() |> Solid.parse() do
      {:ok, template} -> {:ok, template}
      {:error, error} -> {:error, {:template_invalid, error}}
    end
  end

  # Shared framing across tiers rides `{% render "partials/<name>" %}`
  # (dsl-syntax.md §9: "one source for shared framing") — resolved
  # against the leaf bundle's own `prompts/` directory (this repo's
  # actual layout: partials live beside the prompts that render them,
  # in `default/prompts/partials/`, not layered per-prompt). Solid's
  # own naming convention (`Solid.LocalFileSystem`, `"_%s.liquid"`
  # default) doesn't match this bundle's `_name.md.liquid` files —
  # `"%s.md.liquid"` does, since the render call already spells the
  # leading underscore itself (`"partials/_architecture_framing"`).
  defp render(template, variables, %Chain{name: bundle_name}) do
    prompts_root = Path.join([bundles_root(), bundle_name, "prompts"])
    file_system = Solid.LocalFileSystem.new(prompts_root, "%s.md.liquid")

    case Solid.render(template, variables, file_system: {Solid.LocalFileSystem, file_system}) do
      {:ok, iolist, _errors} -> {:ok, IO.iodata_to_binary(iolist)}
      {:error, errors, _partial} -> {:error, {:render_failed, errors}}
    end
  end
end
