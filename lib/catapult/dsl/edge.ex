defmodule Catapult.Dsl.Edge do
  @moduledoc """
  One `edges.<name>` entry of `chain.yaml` (`chain.md` #25): a `type`,
  a `context` projection every instance gets by default, an optional
  `graph_constraint`, and a list of **instances** — there is no
  single-instance flat form any more (#27: "an edge with one instance
  writes a list of one").

  Structural parsing only; whether an instance's `source`/`target` name
  declared tiers, whether `declared_in` resolves against that tier's
  schema, and the type-level acyclicity of the whole edge-instance
  graph are `Catapult.Dsl.Chain`'s job.
  """

  alias Catapult.Dsl.Fields

  @enforce_keys [:name, :type, :context_raw]
  defstruct [
    :name,
    :type,
    :context_raw,
    :consistency,
    instances: [],
    graph_constraint: [],
    navigation: false
  ]

  @typedoc "One `source -> target` site sharing this edge's name and mechanism."
  @type instance :: %{
          source: String.t(),
          target: String.t() | [String.t()],
          declared_in: String.t(),
          source_ref: String.t() | nil,
          target_ref: String.t() | nil,
          context_raw: String.t() | nil,
          as: String.t() | nil,
          when: String.t() | nil
        }

  @type t :: %__MODULE__{
          name: String.t(),
          type: String.t(),
          context_raw: String.t(),
          instances: [instance()],
          graph_constraint: [String.t()],
          consistency: String.t() | nil,
          navigation: boolean()
        }

  @types ~w(fanout reference dependency policy_application synthesis)
  @graph_constraints ~w(acyclic no_self_loop)
  @consistencies ~w(eventual transactional)
  @core_keys ~w(type context graph_constraint consistency navigation instances)
  @instance_keys ~w(source target declared_in source_ref target_ref context as when)

  @doc "Parses one `edges.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "edge #{inspect(name)}"

    {type, type_problems} = Fields.require_one_of(raw, "type", @types, where)
    {context_raw, context_problems} = Fields.require_string(raw, "context", where)
    {instances, instances_problems} = parse_instances(raw, where)
    {graph_constraint, gc_problems} = parse_graph_constraint(raw, where)
    {consistency, consistency_problems} = parse_consistency(raw, type, where)
    {navigation, nav_problems} = Fields.optional_boolean(raw, "navigation", where, false)

    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems =
      type_problems ++
        context_problems ++
        instances_problems ++
        gc_problems ++
        consistency_problems ++
        nav_problems ++
        unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         type: type,
         context_raw: context_raw,
         instances: instances,
         graph_constraint: graph_constraint,
         consistency: consistency,
         navigation: navigation
       }}
    else
      {:error, problems}
    end
  end

  def parse(name, other) do
    {:error, ["edge #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_instances(raw, where) do
    case Map.fetch(raw, "instances") do
      {:ok, entries} when is_list(entries) and entries != [] ->
        results =
          for {entry, index} <- Enum.with_index(entries) do
            parse_instance(entry, "#{where}'s instances[#{index}]")
          end

        problems = Enum.flat_map(results, &elem(&1, 1))
        instances = for {instance, []} <- results, do: instance
        {instances, problems}

      {:ok, []} ->
        {[], ["#{where}'s instances is empty, expected at least one instance"]}

      {:ok, other} ->
        {[], ["#{where}'s instances is #{inspect(other)}, expected a list"]}

      :error ->
        {[], ["#{where} is missing required field \"instances\""]}
    end
  end

  defp parse_instance(%{} = entry, where) do
    unknown = Fields.unknown_keys(entry, @instance_keys, where)
    {source, sp} = Fields.require_string(entry, "source", where)
    {target, tp} = parse_target(entry, where)
    {declared_in, dp} = Fields.require_string(entry, "declared_in", where)
    {source_ref, srp} = optional_ref(entry, "source_ref", where)
    {target_ref, trp} = optional_ref(entry, "target_ref", where)
    {context_raw, cp} = parse_context_raw(entry, "context", where)
    {as, ap} = Fields.optional_string(entry, "as", where)
    {when_pred, wp} = Fields.optional_string(entry, "when", where)

    problems = sp ++ tp ++ dp ++ srp ++ trp ++ cp ++ ap ++ wp ++ unknown

    if problems == [] do
      {%{
         source: source,
         target: target,
         declared_in: declared_in,
         source_ref: source_ref,
         target_ref: target_ref,
         context_raw: context_raw,
         as: as,
         when: when_pred
       }, []}
    else
      {nil, problems}
    end
  end

  defp parse_instance(other, where) do
    {nil, ["#{where} is #{inspect(other)}, expected a YAML mapping"]}
  end

  # `target:` is a single tier name, or a list for a `synthesis`
  # instance (chain.md #27) — accepted structurally for either type
  # here; that only a `synthesis` edge actually uses the list form is
  # `Catapult.Dsl.Chain`'s cross-reference to enforce.
  defp parse_target(entry, where) do
    case Map.fetch(entry, "target") do
      {:ok, value} when is_binary(value) and value != "" ->
        {value, []}

      {:ok, [_ | _] = values} ->
        if Enum.all?(values, &(is_binary(&1) and &1 != "")) do
          {values, []}
        else
          {nil, ["#{where} target #{inspect(values)} has a non-string entry"]}
        end

      {:ok, other} ->
        {nil, ["#{where} target is #{inspect(other)}, expected a tier name or a list of names"]}

      :error ->
        {nil, ["#{where} is missing required field \"target\""]}
    end
  end

  # Explicit source_ref:/target_ref: values are free-form locator
  # strings (chain.md #27) — `self`, `self.parent`, or an `@<attr>`
  # path; `Catapult.Dsl.EdgeLocator` is the closed-vocabulary parser for
  # what one of these actually means, at cross-reference time.
  defp optional_ref(entry, key, where), do: Fields.optional_string(entry, key, where)

  # `context: none` is a literal meaning "no context at all" (chain.md
  # #19, #25); any other value is a walk-shaped projection string
  # (`handle` or `handle.fragments[<kind>]`), left unparsed here since
  # it is meaningful only alongside the rest of the bundle.
  defp parse_context_raw(raw, key, where) do
    Fields.optional_string(raw, key, where)
  end

  defp parse_graph_constraint(raw, where) do
    {values, problems} = Fields.optional_string_list(raw, "graph_constraint", where)

    invalid =
      for value <- values, value not in @graph_constraints do
        "#{where}'s graph_constraint #{inspect(value)} is not one of #{inspect(@graph_constraints)}"
      end

    {values, problems ++ invalid}
  end

  defp parse_consistency(raw, "dependency", where) do
    Fields.optional_one_of(raw, "consistency", @consistencies, where, "eventual")
  end

  defp parse_consistency(raw, _type, where) do
    case Map.fetch(raw, "consistency") do
      :error ->
        {nil, []}

      {:ok, _value} ->
        {nil, ["#{where} declares consistency:, which only a dependency edge may carry"]}
    end
  end
end
