defmodule Catapult.Dsl.Tier do
  @moduledoc """
  One `tiers.<name>` entry of `chain.yaml` (`chain.md` #5): a **generating
  tier** has a draft an agent writes; a **join target** declares
  `draft: none`, its nodes minted by a parent's draft; a **supplied
  tier** declares `generator: supplied` and a `source:`, with no scope
  at all.

  Structural parsing only. Node identity, a node's own fields and plain
  cardinality are the schema's now (`bundle.md` #10, `chain.md` #32) —
  `Catapult.Dsl.DeclaredInSchema.mints_and_fields/2` reads a generating
  tier's own schema to fill in `identity`, `draft_fields` and every
  join target it mints; a raw `context:`/`produces:`/`fields:` entry
  here is parsed as a string or `Catapult.Dsl.ContextWalk` but not yet
  cross-referenced — the effective-context derivation (`chain.md` #20,
  #21) and every other cross-reference are `Catapult.Dsl.Chain`'s job,
  since they need the rest of the bundle (and the schema) in view.

  `draft_fields` and `mint_fields` are both schema-derived, and both
  answer "field name -> the actual element/attribute tag", never a
  bare name list: a field's declared name and the tag that carries it
  can differ (`is_foundation` on a `<foundation/>` marker), so
  extraction at commit time has to navigate by the schema's own tag.
  They differ in *when* that tag is read: `draft_fields` comes from
  this tier's own root (read from this tier's own committed draft,
  `chain.md` #10's "a field"), `mint_fields` from the element that
  mints this tier on whichever tier's draft is its fanout source (read
  at mint time, `chain.md` #12's "a mint element's own attributes") —
  a join target only ever has the second; a tier that is both a fanout
  target and a draft-committer (`vocab`) has both, and its `handle`
  exposes the union of both plus `fields:`'s own `mint.parent.<kind>`
  names.
  """

  alias Catapult.Dsl.ContextWalk
  alias Catapult.Dsl.Fields

  @enforce_keys [:name]
  defstruct [
    :name,
    :scope,
    :draft,
    :prompt,
    :executor,
    :review,
    :reconcile,
    :source_raw,
    identity: nil,
    draft_fields: %{},
    mint_fields: %{},
    handle_narrow: nil,
    handle_fields: [],
    handle_fragments: [],
    generator: "llm",
    context_raw: %{},
    effective_context: %{},
    produces: [],
    fields: %{},
    enforcement: []
  ]

  @type scope :: {:singleton} | {:per, String.t()} | {:child_of, String.t()} | {:cascade_visit}

  @type produced :: %{kind: String.t(), draft_path: String.t()}

  @typedoc """
  `context_raw` is the block's own additive walks, as written;
  `context` is those same walks parsed and merged with the tier's own
  `effective_context` (`chain.md` #14, #20) — filled by
  `Catapult.Dsl.Chain`, empty until then.
  """
  @type review_or_reconcile :: %{
          prompt: String.t(),
          context_raw: %{String.t() => String.t()},
          context: %{String.t() => Catapult.Dsl.ContextWalk.t()}
        }

  @type t :: %__MODULE__{
          name: String.t(),
          scope: scope() | nil,
          draft: %{root_tag: String.t(), grammar: String.t()} | nil,
          identity: String.t() | nil,
          draft_fields: %{String.t() => String.t()},
          mint_fields: %{String.t() => String.t()},
          handle_narrow: [String.t()] | nil,
          handle_fields: [String.t()],
          handle_fragments: [String.t()],
          generator: String.t(),
          source_raw: String.t() | nil,
          prompt: String.t() | nil,
          executor: map() | nil,
          context_raw: %{String.t() => String.t()},
          effective_context: %{String.t() => ContextWalk.t()},
          produces: [produced()],
          fields: %{String.t() => String.t()},
          review: review_or_reconcile() | nil,
          reconcile: review_or_reconcile() | nil,
          enforcement: [String.t()]
        }

  @generators ~w(llm supplied external template git_commit webhook)
  @generation_keys ~w(scope draft generator prompt review reconcile executor handle context produces enforcement)
  @join_keys ~w(scope draft fields handle enforcement)
  @supplied_keys ~w(generator source)

  @doc "Kind of tier this declaration is, from its own already-parsed shape."
  @spec kind(t()) :: :generating | :join | :supplied
  def kind(%__MODULE__{generator: "supplied"}), do: :supplied
  def kind(%__MODULE__{draft: :none}), do: :join
  def kind(%__MODULE__{}), do: :generating

  @doc "Parses one `tiers.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "tier #{inspect(name)}"

    case Map.get(raw, "generator") do
      "supplied" -> parse_supplied(name, raw, where)
      _other -> parse_scoped(name, raw, where)
    end
  end

  def parse(name, other) do
    {:error, ["tier #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end

  ## Supplied tiers (chain.md #17): generator + source, no scope at all.

  defp parse_supplied(name, raw, where) do
    {source, source_problems} = Fields.require_string(raw, "source", where)
    unknown = Fields.unknown_keys(raw, @supplied_keys, where)

    problems = source_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{name: name, generator: "supplied", source_raw: source}}
    else
      {:error, problems}
    end
  end

  ## Generating tiers and join targets share `scope:`; `draft: none`
  ## (a literal string) is what makes a join target (chain.md #8).

  defp parse_scoped(name, raw, where) do
    {scope, scope_problems} = parse_scope(raw, where)

    case Map.get(raw, "draft") do
      "none" -> parse_join(name, raw, where, scope, scope_problems)
      _other -> parse_generating(name, raw, where, scope, scope_problems)
    end
  end

  defp parse_join(name, raw, where, scope, scope_problems) do
    {fields, fields_problems} = parse_fields(raw, where)
    {handle_narrow, handle_problems} = parse_handle(raw, where)
    unknown = Fields.unknown_keys(raw, @join_keys, where)

    problems = scope_problems ++ fields_problems ++ handle_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         scope: scope,
         draft: :none,
         fields: fields,
         handle_narrow: handle_narrow
       }}
    else
      {:error, problems}
    end
  end

  defp parse_generating(name, raw, where, scope, scope_problems) do
    {draft, draft_problems} = parse_draft(raw, name, where)

    {generator, generator_problems} =
      Fields.optional_one_of(raw, "generator", @generators, where, "llm")

    {prompt, prompt_problems} = parse_prompt(raw, name, generator, where)
    {executor, _ep} = Fields.optional_map(raw, "executor", where)
    {context_raw, context_problems} = parse_context_map(raw, where)
    {produces, produces_problems} = parse_produces(raw, where)
    {handle_narrow, handle_problems} = parse_handle(raw, where)
    {review, review_problems} = parse_review_or_reconcile(raw, "review", name, where)
    {reconcile, reconcile_problems} = parse_review_or_reconcile(raw, "reconcile", name, where)

    {enforcement, enforcement_problems} =
      Fields.optional_string_list(raw, "enforcement", where)

    unknown = Fields.unknown_keys(raw, @generation_keys, where)

    problems =
      scope_problems ++
        draft_problems ++
        generator_problems ++
        prompt_problems ++
        context_problems ++
        produces_problems ++
        handle_problems ++
        review_problems ++
        reconcile_problems ++
        enforcement_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         scope: scope,
         draft: draft,
         generator: generator,
         prompt: prompt,
         executor: executor,
         context_raw: context_raw,
         produces: produces,
         handle_narrow: handle_narrow,
         review: review,
         reconcile: reconcile,
         enforcement: enforcement
       }}
    else
      {:error, problems}
    end
  end

  ## scope: singleton | per(X) | child_of(X) | cascade_visit (chain.md #6)

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
           "#{where} scope #{inspect(value)} is not singleton, per(<tier>), child_of(<tier>) or cascade_visit"
         ]}
    end
  end

  ## draft: — omitted (defaults), a map (override), never `none` here
  ## (that literal routes to parse_join/5 before this runs).

  defp parse_draft(raw, name, where) do
    case Map.fetch(raw, "draft") do
      :error ->
        {%{root_tag: name, grammar: "schemas/#{name}.xsd"}, []}

      {:ok, %{} = draft} ->
        draft_where = "#{where}'s draft"
        {root_tag, rp} = Fields.optional_string(draft, "root_tag", draft_where, name)

        {grammar, gp} =
          Fields.optional_string(draft, "grammar", draft_where, "schemas/#{name}.xsd")

        unknown = Fields.unknown_keys(draft, ["root_tag", "grammar"], draft_where)
        problems = rp ++ gp ++ unknown

        if problems == [],
          do: {%{root_tag: root_tag, grammar: grammar}, []},
          else: {nil, problems}

      {:ok, other} ->
        {nil,
         ["#{where}'s draft is #{inspect(other)}, expected a mapping or the literal \"none\""]}
    end
  end

  ## prompt: — defaults to prompts/<tier>.md.liquid (chain.md #9),
  ## written only where the file lives elsewhere.

  defp parse_prompt(raw, name, generator, where) do
    default = if generator == "llm", do: "prompts/#{name}.md.liquid"
    Fields.optional_string(raw, "prompt", where, default)
  end

  ## context: — a map from variable name to walk string (chain.md #21).
  ## Parsed as strings only; `ContextWalk.parse/1` and every collision
  ## with a derived read is `Catapult.Dsl.Chain`'s job, once the whole
  ## bundle (and every other tier's edges) is in view.

  defp parse_context_map(raw, where) do
    case string_map(raw, "context", where, "a map of name to walk") do
      {:ok, map} -> {map, []}
      {:error, problem} -> {%{}, [problem]}
    end
  end

  ## produces: (chain.md #13) — fragment kind -> draft path, owner is
  ## always the scope parent (implicit; there is no owner: key anymore).

  defp parse_produces(raw, where) do
    case string_map(raw, "produces", where, "a map of fragment kind to draft path") do
      {:ok, map} -> {for({kind, path} <- map, do: %{kind: kind, draft_path: path}), []}
      {:error, problem} -> {[], [problem]}
    end
  end

  defp string_map(raw, key, where, expected) do
    case Map.fetch(raw, key) do
      :error -> {:ok, %{}}
      {:ok, %{} = map} -> string_map_result(map, key, where, expected)
      {:ok, other} -> {:error, "#{where}'s #{key} is #{inspect(other)}, expected #{expected}"}
    end
  end

  defp string_map_result(map, key, where, expected) do
    if Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end) do
      {:ok, map}
    else
      {:error, "#{where}'s #{key} has a non-string key or value, expected #{expected}"}
    end
  end

  ## fields: — join-target-only, `<name>: mint.parent.<kind>` (chain.md #12)

  defp parse_fields(raw, where) do
    case Map.fetch(raw, "fields") do
      :error ->
        {%{}, []}

      {:ok, %{} = map} ->
        bad = for {k, v} <- map, not (is_binary(k) and is_binary(v)), do: {k, v}

        cond do
          bad != [] ->
            {%{}, ["#{where}'s fields has a non-string key or value"]}

          Enum.all?(map, fn {_k, v} -> String.starts_with?(v, "mint.parent.") end) ->
            {map, []}

          true ->
            {%{},
             [
               "#{where}'s fields names a value that is not mint.parent.<kind> " <>
                 "(chain.md #12: a join target's fields: names only cross-node copies)"
             ]}
        end

      {:ok, other} ->
        {%{}, ["#{where}'s fields is #{inspect(other)}, expected a map"]}
    end
  end

  ## handle: — a narrowing list only (chain.md #11); the default (every
  ## field plus every produced kind) is computed once the schema is read.

  defp parse_handle(raw, where) do
    case Map.fetch(raw, "handle") do
      :error -> {nil, []}
      {:ok, list} when is_list(list) -> Fields.require_string_list(raw, "handle", where)
      {:ok, other} -> {nil, ["#{where}'s handle is #{inspect(other)}, expected a list of names"]}
    end
  end

  ## review:/reconcile: — `default` (a bare string) or a map overriding
  ## prompt/context (chain.md #14, #15).

  defp parse_review_or_reconcile(raw, key, name, where) do
    default_prompt = default_prompt_for(key, name)

    case Map.fetch(raw, key) do
      :error ->
        {nil, []}

      {:ok, "default"} ->
        {%{prompt: default_prompt, context_raw: %{}, context: %{}}, []}

      {:ok, %{} = map} ->
        rw = "#{where}'s #{key}"
        {prompt, pp} = Fields.optional_string(map, "prompt", rw, default_prompt)
        {context_raw, cp} = parse_context_map(map, rw)
        unknown = Fields.unknown_keys(map, ["prompt", "context"], rw)
        problems = pp ++ cp ++ unknown

        if problems == [],
          do: {%{prompt: prompt, context_raw: context_raw, context: %{}}, []},
          else: {nil, problems}

      {:ok, other} ->
        {nil,
         ["#{where}'s #{key} is #{inspect(other)}, expected the literal \"default\" or a mapping"]}
    end
  end

  defp default_prompt_for("review", name), do: "prompts/review/#{name}.md.liquid"
  defp default_prompt_for("reconcile", name), do: "prompts/reconcile/#{name}.md.liquid"
end
