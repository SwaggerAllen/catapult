defmodule Catapult.Dsl.Tier do
  @moduledoc """
  One `tiers/<tier>.yaml` declaration (dsl-syntax.md §3): scope,
  identity, fields, handle, draft grammar, generator, prompt, executor
  hints, context walks, produced fragments, and the extension-provided
  `delivery:` / `enforcement:` annotations. Or, when it carries
  `reviews: <tier>` instead (§3.3), a **review tier**: a much smaller
  declaration whose scope and cardinality are the reviewed tier's own
  by construction, so `scope:`, `identity:`, `handle:`, `fields:`,
  `draft:` and `produces:` are never restated there, and it carries a
  new field a generation tier does not — a top-level `grammar:` (the
  platform-wide review grammar, §10), since it has no `draft:` to nest
  one under.

  `parse/2` is structural only — every field's own shape, and the
  closed sets §3.1/§3.2 fix (`scope`, `generator`). Cross-references
  (does `scope`'s tier exist, does a context walk's edge exist, is a
  fragment kind in the bundle's closed vocabulary, does `delivery:`
  resolve against the platform vocabulary, does `reviews:` name a real
  tier, does a review tier's `context:` match the reviewed tier's) need
  the rest of the bundle in view and are `Catapult.Dsl.Chain`'s job
  (dsl-syntax.md §13).
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :file]
  defstruct [
    :name,
    :file,
    :scope,
    :scope_filter_raw,
    :identity,
    :draft,
    :prompt,
    :executor,
    :delivery,
    :reviews,
    :grammar,
    fields: %{},
    handle_fields: [],
    handle_fragments: [],
    generator: "llm",
    generator_opts: %{},
    context: [],
    produces: [],
    enforcement: [],
    extra: %{}
  ]

  @type scope ::
          {:singleton} | {:per, String.t()} | {:child_of, String.t()} | {:cascade_visit}

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          scope: scope() | nil,
          scope_filter_raw: String.t() | nil,
          identity: String.t() | nil,
          fields: %{String.t() => String.t()},
          handle_fields: [String.t()],
          handle_fragments: [String.t()],
          draft: %{root_tag: String.t(), grammar: String.t()} | nil,
          generator: String.t(),
          generator_opts: map(),
          prompt: String.t() | nil,
          executor: map() | nil,
          context: [ContextWalk.t()],
          produces: [map()],
          delivery: %{phase: String.t(), agent_step: String.t()} | nil,
          reviews: String.t() | nil,
          grammar: String.t() | nil,
          enforcement: [String.t()],
          extra: %{String.t() => term()}
        }

  @identities ~w(id alias name)
  @generators ~w(llm git_commit synthesis webhook external template supplied)
  @core_keys ~w(tier scope scope_filter identity fields handle draft generator prompt
                executor context produces delivery enforcement source)

  # dsl-syntax.md §3.3: everything a generation tier declares that a
  # review tier's cardinality/scope-by-construction makes redundant, and
  # that this loader therefore rejects outright rather than silently
  # ignoring — restating any of them is a second place for the reviewed
  # tier's own scope to drift out of step.
  @review_forbidden ~w(scope scope_filter identity fields handle draft produces)
  @review_keys ~w(tier reviews generator prompt grammar executor context delivery enforcement)

  @doc "Parses one tier declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "tier declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "tier", where)
    tier_where = if name, do: "tier #{inspect(name)} (#{file})", else: where

    case Map.fetch(raw, "reviews") do
      {:ok, reviews} when is_binary(reviews) and reviews != "" ->
        parse_review_tier(file, raw, name, reviews, tier_where, name_problems)

      {:ok, other} ->
        {:error,
         name_problems ++
           ["#{tier_where} \"reviews\" is #{inspect(other)}, expected a non-empty string"]}

      :error ->
        parse_generation_tier(file, raw, name, tier_where, name_problems)
    end
  end

  def parse(file, other) do
    {:error, ["tier declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
  end

  ## Generation tiers — the ordinary case

  defp parse_generation_tier(file, raw, name, tier_where, name_problems) do
    {scope, scope_problems} = parse_scope(raw, tier_where)
    {scope_filter, sf_problems} = Fields.optional_string(raw, "scope_filter", tier_where)

    {identity, identity_problems} =
      Fields.require_one_of(raw, "identity", @identities, tier_where)

    {fields, fields_problems} = parse_string_map(raw, "fields", tier_where)
    {handle_fields, handle_fragments, handle_problems} = parse_handle(raw, tier_where)
    {draft, draft_problems} = parse_draft(raw, tier_where)

    {generator, generator_problems} =
      Fields.optional_one_of(raw, "generator", @generators, tier_where, "llm")

    {generator_opts, opts_problems} = parse_generator_opts(raw, generator, tier_where)
    {prompt, prompt_problems} = parse_prompt(raw, generator, tier_where)
    {executor, _ex_problems} = Fields.optional_map(raw, "executor", tier_where)
    {context, context_problems} = parse_context(raw, tier_where)
    {produces, produces_problems} = parse_produces(raw, tier_where)
    {delivery, delivery_problems} = parse_delivery(raw, tier_where)

    {enforcement, enforcement_problems} =
      Fields.optional_string_list(raw, "enforcement", tier_where)

    unknown = Fields.unknown_keys(raw, @core_keys, tier_where)
    extra = Map.drop(raw, @core_keys)

    problems =
      name_problems ++
        scope_problems ++
        sf_problems ++
        identity_problems ++
        fields_problems ++
        handle_problems ++
        draft_problems ++
        generator_problems ++
        opts_problems ++
        prompt_problems ++
        context_problems ++
        produces_problems ++
        delivery_problems ++
        enforcement_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         scope: scope,
         scope_filter_raw: scope_filter,
         identity: identity,
         fields: fields,
         handle_fields: handle_fields,
         handle_fragments: handle_fragments,
         draft: draft,
         generator: generator,
         generator_opts: generator_opts,
         prompt: prompt,
         executor: executor,
         context: context,
         produces: produces,
         delivery: delivery,
         enforcement: enforcement,
         extra: extra
       }}
    else
      {:error, problems}
    end
  end

  ## Review tiers — dsl-syntax.md §3.3

  defp parse_review_tier(file, raw, name, reviews, tier_where, name_problems) do
    forbidden =
      for key <- @review_forbidden, Map.has_key?(raw, key) do
        "#{tier_where} declares #{inspect(key)}, which a review tier " <>
          "(reviews: #{inspect(reviews)}) may not carry (dsl-syntax.md §3.3)"
      end

    {generator, generator_problems} =
      Fields.optional_one_of(raw, "generator", @generators, tier_where, "llm")

    {prompt, prompt_problems} = parse_prompt(raw, generator, tier_where)
    {grammar, grammar_problems} = Fields.require_string(raw, "grammar", tier_where)
    {executor, _ex_problems} = Fields.optional_map(raw, "executor", tier_where)
    {context, context_problems} = parse_context(raw, tier_where)
    {delivery, delivery_problems} = parse_delivery(raw, tier_where)

    {enforcement, enforcement_problems} =
      Fields.optional_string_list(raw, "enforcement", tier_where)

    unknown = Fields.unknown_keys(raw, @review_keys, tier_where)

    problems =
      name_problems ++
        forbidden ++
        generator_problems ++
        prompt_problems ++
        grammar_problems ++
        context_problems ++
        delivery_problems ++
        enforcement_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         reviews: reviews,
         generator: generator,
         prompt: prompt,
         grammar: grammar,
         executor: executor,
         context: context,
         delivery: delivery,
         enforcement: enforcement
       }}
    else
      {:error, problems}
    end
  end

  ## scope (§3.1) — singleton | per(X) | child_of(X) | cascade_visit

  defp parse_scope(raw, where) do
    case Fields.require_string(raw, "scope", where) do
      {nil, problems} -> {nil, problems}
      {value, []} -> parse_scope_value(value, where)
    end
  end

  defp parse_scope_value("singleton", _where), do: {{:singleton}, []}
  defp parse_scope_value("cascade_visit", _where), do: {{:cascade_visit}, []}

  defp parse_scope_value(value, where) do
    case Regex.run(~r/\A(per|child_of)\(([a-z0-9_]+)\)\z/, value) do
      [_whole, "per", tier] ->
        {{:per, tier}, []}

      [_whole, "child_of", tier] ->
        {{:child_of, tier}, []}

      nil ->
        {nil,
         [
           "#{where} scope #{inspect(value)} is not singleton, per(<tier>), child_of(<tier>), or cascade_visit"
         ]}
    end
  end

  ## fields:, handle:

  defp parse_string_map(raw, key, where) do
    case Map.fetch(raw, key) do
      :error ->
        {%{}, []}

      {:ok, %{} = map} ->
        string_map_result(map, key, where)

      {:ok, other} ->
        {%{}, ["#{where} #{inspect(key)} is #{inspect(other)}, expected a map"]}
    end
  end

  defp string_map_result(map, key, where) do
    if Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end) do
      {map, []}
    else
      {%{},
       [
         "#{where} #{inspect(key)} has a non-string key or value (expected a map of string to string)"
       ]}
    end
  end

  defp parse_handle(raw, where) do
    case Fields.require_map(raw, "handle", where) do
      {nil, problems} ->
        {[], [], problems}

      {handle, []} ->
        handle_where = "#{where}'s handle"
        {fields, fp} = Fields.require_string_list(handle, "fields", handle_where)
        {fragments, gp} = Fields.optional_string_list(handle, "fragments", handle_where)
        unknown = Fields.unknown_keys(handle, ["fields", "fragments"], handle_where)
        {fields, fragments, fp ++ gp ++ unknown}
    end
  end

  ## draft: — omitted entirely for join-target tiers and review tiers

  defp parse_draft(raw, where) do
    case Fields.optional_map(raw, "draft", where) do
      {nil, problems} ->
        {nil, problems}

      {draft, []} ->
        draft_where = "#{where}'s draft"
        {root_tag, rp} = Fields.require_string(draft, "root_tag", draft_where)
        {grammar, gp} = Fields.require_string(draft, "grammar", draft_where)
        unknown = Fields.unknown_keys(draft, ["root_tag", "grammar"], draft_where)
        problems = rp ++ gp ++ unknown

        if problems == [],
          do: {%{root_tag: root_tag, grammar: grammar}, []},
          else: {nil, problems}
    end
  end

  ## generator: (§3.2) and its per-type required opts

  defp parse_generator_opts(raw, "git_commit", where) do
    {url, up} = Fields.require_string(raw, "code_repo_url", where)
    {path, pp} = Fields.require_string(raw, "path_from_handle", where)
    {%{code_repo_url: url, path_from_handle: path}, up ++ pp}
  end

  defp parse_generator_opts(raw, "external", where) do
    {package, pp} = Fields.require_string(raw, "package", where)
    {options, _op} = Fields.optional_map(raw, "options", where)
    {%{package: package, options: options || %{}}, pp}
  end

  defp parse_generator_opts(raw, "template", where) do
    {template, tp} = Fields.require_string(raw, "template", where)
    {%{template: template}, tp}
  end

  defp parse_generator_opts(raw, "supplied", where) do
    case Fields.require_string(raw, "source", where) do
      {nil, problems} ->
        {%{}, problems}

      {source, []} ->
        case ContextWalk.parse(source) do
          {:ok, %ContextWalk{source: :input, role: role}} when is_binary(role) ->
            {%{source: source, role: role}, []}

          _other ->
            {%{}, ["#{where} \"source\" #{inspect(source)} is not input.<role>"]}
        end
    end
  end

  defp parse_generator_opts(_raw, _other, _where), do: {%{}, []}

  ## prompt: — required for the llm generator

  defp parse_prompt(raw, "llm", where) do
    case Fields.require_string(raw, "prompt", where) do
      {nil, problems} -> {nil, problems}
      {value, []} -> {value, []}
    end
  end

  defp parse_prompt(raw, _generator, where), do: Fields.optional_string(raw, "prompt", where)

  ## context: (§7) — a list of walk strings

  defp parse_context(raw, where) do
    case Fields.optional_string_list(raw, "context", where) do
      {[], problems} when problems != [] ->
        {[], problems}

      {entries, []} ->
        results = Enum.map(entries, &ContextWalk.parse/1)
        problems = for {:error, reason} <- results, do: "#{where}'s #{reason}"
        walks = for {:ok, walk} <- results, do: walk
        {walks, problems}
    end
  end

  ## produces: (§3) — fragments this draft writes on other nodes

  defp parse_produces(raw, where) do
    case Map.fetch(raw, "produces") do
      :error ->
        {[], []}

      {:ok, entries} when is_list(entries) ->
        results = Enum.map(entries, &parse_produced_fragment(&1, where))
        problems = Enum.flat_map(results, &elem(&1, 1))
        entries = for {entry, []} <- results, do: entry
        {entries, problems}

      {:ok, other} ->
        {[], ["#{where}'s produces is #{inspect(other)}, expected a list"]}
    end
  end

  defp parse_produced_fragment(%{"fragment" => %{} = fragment}, where) do
    fw = "#{where}'s produces entry"
    {owner, op} = Fields.require_string(fragment, "owner", fw)
    {kind, kp} = Fields.require_string(fragment, "kind", fw)
    {authored, ap} = Fields.require_string(fragment, "authored", fw)
    unknown = Fields.unknown_keys(fragment, ["owner", "kind", "authored"], fw)
    problems = op ++ kp ++ ap ++ unknown

    case {problems, owner} do
      {[], nil} -> {nil, problems}
      {[], owner} -> {%{owner_raw: owner, kind: kind, authored: authored}, []}
      {problems, _owner} -> {nil, problems}
    end
  end

  defp parse_produced_fragment(other, where) do
    {nil,
     ["#{where}'s produces entry #{inspect(other)} is not {fragment: {owner, kind, authored}}"]}
  end

  ## delivery: — dsl-syntax.md §3, §11, §13; v5 §7.10's "an unknown phase
  ## or agent step is a load error" and §11's "platform-fixed vocabulary
  ## only". Structural shape only here — actual membership in
  ## Catapult.Dsl.SystemStatus's closed sets is a bundle-level
  ## cross-reference (Catapult.Dsl.Chain), same as every other §13 check.

  defp parse_delivery(raw, where) do
    case Fields.optional_map(raw, "delivery", where) do
      {nil, problems} ->
        {nil, problems}

      {delivery, []} ->
        dw = "#{where}'s delivery"
        {phase, pp} = Fields.require_string(delivery, "phase", dw)
        {agent_step, ap} = Fields.require_string(delivery, "agent_step", dw)
        unknown = Fields.unknown_keys(delivery, ["phase", "agent_step"], dw)
        problems = pp ++ ap ++ unknown

        if problems == [],
          do: {%{phase: phase, agent_step: agent_step}, []},
          else: {nil, problems}
    end
  end
end
