defmodule Catapult.Generation.ContextAssembly do
  @moduledoc """
  Evaluates a tier's effective context and renders its Liquid prompt
  (`chain.md` #20, #21, #35) — one path for generation and review
  alike, so "the reviewer sees exactly the generator's context plus
  the draft" (`systems/generation.md`'s per-tier triad invariant) is
  enforced by sharing this module, not by convention. A review is a
  block on the tier it reviews now, not a tier of its own (`chain.md`
  #14) — `Catapult.Engine.Projections.ReadyScopes.review_tier_name/1`'s
  synthetic `"<tier>:review"` is what a dispatch job's `tier` arg
  carries for one, and `resolve_dispatch/2` is the one place that
  string is read back into a tier plus a rendering mode.

  Variable naming follows `chain.md` #20, #21: a context entry's
  Liquid variable is exactly its name in the tier's own
  `effective_context` — the edge name (or its `as:`) for a derived
  read, the declared key for an explicit one. A bare `self`/`self
  .parent` projection with no edge hop (`parent`, and `self`/`draft`
  below) renders as one object; every other walk — a hop through an
  edge, or an `all.<tier>` read — renders as a list, even where it
  currently holds one entry, since the chain declares it a collection
  regardless of how many instances exist right now.

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
  reserved word `raft` for `input.*` (`chain.md` #19). A role with no
  pinned documents is left out of the variables map entirely, the same
  omission-is-the-contract shape `feedback`/`prior_review` use below —
  never `""`.

  `feedback`/`prior_review` (ORC-34, `systems/generation.md`'s own
  entry) are two direct engine reads, unconditional — unlike `draft`,
  neither is review-tier-only (`chain.md` #35, #14): `feedback` is
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
  alias Catapult.Engine.Projections.ReadyScopes
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
  Builds the dispatch request for `dispatch_name`/`node` (a
  `ReadyScopes` result): renders the Liquid prompt and returns
  `Catapult.Delivery.HostPort.request()`. `dispatch_name` is either a
  bare tier name (generation) or `ReadyScopes.review_tier_name/1`'s
  synthetic form (a review of that tier's current draft).
  """
  @spec build(Chain.t(), binary(), String.t(), Node.t()) ::
          {:ok, Catapult.Delivery.HostPort.request()} | {:error, failure()}
  def build(chain, project_id, dispatch_name, node) do
    with {:ok, tier, mode} <- resolve_dispatch(chain, dispatch_name),
         variables = build_variables(chain, project_id, tier, node, mode),
         {:ok, prompt_path} <- resolve_prompt(chain, tier, mode),
         {:ok, template} <- parse_template(prompt_path),
         {:ok, rendered} <- render(template, variables, chain),
         {:ok, credential_names} <- bound_credential_names() do
      {:ok,
       %{
         project_id: project_id,
         node_id: NodeId.resolve(node),
         tier: dispatch_name,
         scope_key: node.scope_key,
         root_tag: root_tag(tier, mode),
         rendered_prompt: rendered,
         credential_names: credential_names,
         stub_mode: Delivery.stub_mode?(project_id)
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

  # A review is a block on the tier it reviews (`chain.md` #14), not a
  # tier of its own — `ReadyScopes.base_tier_name/1` reverses the
  # synthetic dispatch name back to the tier it addresses.
  defp resolve_dispatch(%Chain{tiers: tiers}, dispatch_name) do
    case ReadyScopes.base_tier_name(dispatch_name) do
      nil ->
        case Map.fetch(tiers, dispatch_name) do
          {:ok, tier} -> {:ok, tier, :generation}
          :error -> {:error, {:unknown_tier, dispatch_name}}
        end

      base ->
        case Map.fetch(tiers, base) do
          {:ok, %{review: review} = tier} when not is_nil(review) -> {:ok, tier, :review}
          _not_reviewable -> {:error, {:unknown_tier, dispatch_name}}
        end
    end
  end

  defp root_tag(_tier, :review), do: "review"
  defp root_tag(%{draft: %{root_tag: root_tag}}, :generation), do: root_tag

  defp build_variables(chain, project_id, tier, node, mode) do
    context = context_for(tier, mode)

    base =
      context
      |> Enum.reduce(%{}, fn {name, walk}, acc ->
        put_variable(acc, name, resolved_variable(chain, walk, node, project_id))
      end)
      |> Map.put("self", render_node(chain, node))
      |> feedback_variable(project_id, node)
      |> prior_review_variable(project_id, node)

    if mode == :review, do: Map.put(base, "draft", draft_variable(project_id, node)), else: base
  end

  defp context_for(tier, :generation), do: tier.effective_context
  defp context_for(%{review: %{context: context}}, :review), do: context

  # `:input`-sourced walks are a second, direct read of delivery, never
  # through `ContextResolver` (moduledoc above) — `raft` is `input.*`'s
  # own reserved content (`chain.md` #35), and `input.<role>`'s content
  # is a plain string, keyed by this entry's own declared name rather
  # than by the role, exactly like every other context variable.
  #
  # A bare `self`/`self.parent` projection with no edge hop (`parent`)
  # resolves to exactly one node and renders as one object; every other
  # walk — a hop through an edge, or an `all.<tier>` read — is a
  # collection the chain declares regardless of how many instances
  # exist right now, and renders as a list even when that list holds
  # one entry.
  defp resolved_variable(_chain, %ContextWalk{source: :input, wildcard: true}, _node, project_id) do
    project_id |> Delivery.get_raft() |> join_input()
  end

  defp resolved_variable(_chain, %ContextWalk{source: :input, role: role}, _node, project_id)
       when is_binary(role) do
    project_id |> Delivery.get_input_documents(role) |> join_input()
  end

  defp resolved_variable(chain, %ContextWalk{source: :self, hops: []} = walk, node, _project_id) do
    case ContextResolver.resolve(walk, node) do
      {:ok, [target]} -> render_node(chain, target, walk.projection)
      {:ok, []} -> nil
      {:error, :unsupported} -> nil
    end
  end

  defp resolved_variable(chain, walk, node, _project_id) do
    case ContextResolver.resolve(walk, node) do
      {:ok, targets} -> Enum.map(targets, &render_node(chain, &1, walk.projection))
      {:error, :unsupported} -> []
    end
  end

  defp join_input([]), do: nil
  defp join_input(docs), do: Enum.join(docs, "\n\n")

  # Omitted entirely rather than set to `nil`/`""`/`[]` — a role with
  # no pinned documents, and a `self.parent` read on a tier with no
  # scope parent, are both the honest "nothing here" shape (moduledoc).
  defp put_variable(variables, _name, nil), do: variables
  defp put_variable(variables, name, value), do: Map.put(variables, name, value)

  defp draft_variable(project_id, %Node{id: node_id}) do
    Delivery.get_draft_body(project_id, node_id) || ""
  end

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

  # The bare "self"/"draft" bindings are never resolved through a
  # context walk's own projection — always the full node (both fields
  # and fragments), unchanged from before this ticket.
  defp render_node(chain, %Node{} = node), do: render_node(chain, node, :full)

  # A context walk's own `projection` decides what this emits
  # (`chain.md` #19, `systems/generation.md`'s ORC-236 entry): a
  # `:handle`-typed walk emits `handle_fields` only (`fragments` present
  # but empty, the same map shape either way so no template needs a
  # conditional); a `{:fragments, kind}`-typed walk emits that one
  # fragment's content under `fragments` and no `handle_fields`; `:full`
  # (the bare "self"/"draft" bindings above) emits both, the behavior
  # every context-walk-resolved target had before this projection
  # distinction existed.
  defp render_node(chain, %Node{} = node, projection) do
    tier = Map.get(chain.tiers, node.tier)
    handle_fields = if tier, do: tier.handle_fields, else: []
    handle_fragments = if tier, do: tier.handle_fragments, else: []

    fields =
      if projection == :handle or projection == :full do
        for name <- handle_fields, into: %{} do
          {name, Map.get(node.fields || %{}, name)}
        end
      else
        %{}
      end

    fragments = render_fragments(node, handle_fragments, projection)

    fields
    |> Map.put("id", NodeId.resolve(node))
    |> Map.put("fragments", fragments)
  end

  defp render_fragments(_node, _handle_fragments, :handle), do: %{}

  defp render_fragments(node, handle_fragments, :full) do
    for kind <- handle_fragments, into: %{} do
      {kind, fragment_content(node.id, kind)}
    end
  end

  defp render_fragments(node, handle_fragments, {:fragments, kind}) do
    if kind in handle_fragments, do: %{kind => fragment_content(node.id, kind)}, else: %{}
  end

  defp fragment_content(node_id, kind),
    do: node_id |> Store.fragments(kind) |> Enum.map_join("\n\n", & &1.content)

  defp resolve_prompt(%Chain{name: bundle_name}, tier, mode) do
    dir = Path.join(bundles_root(), bundle_name)

    case prompt_for(tier, mode) do
      prompt when is_binary(prompt) ->
        case BundlePath.resolve(dir, prompt) do
          nil -> {:error, {:prompt_not_found, prompt}}
          path -> {:ok, path}
        end

      nil ->
        {:error, {:prompt_not_found, inspect(tier)}}
    end
  end

  defp prompt_for(tier, :generation), do: tier.prompt
  defp prompt_for(%{review: %{prompt: prompt}}, :review), do: prompt

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
  # (`chain.md` #35: "one source for shared framing") — resolved
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
