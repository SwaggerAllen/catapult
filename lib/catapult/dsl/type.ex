defmodule Catapult.Dsl.Type do
  @moduledoc """
  One `types.<name>` entry of `workflow.yaml` (`workflow.md` #4): a
  work item, ticket or container alike, one declaration shape rather
  than three. A skeleton fixes a required backbone, never an exclusive
  membership: `skeleton:` optionally picks `ticket` or `container`
  (omitted: no anchors at all, the project's own shape, #30);
  `serves:` (ticket-skeleton types only, #40) says where a chain flow
  opens this type; `statuses:` is the one ordered array everything
  else lives in, array index the only position (#7).

  **Sub-arrays are stored flattened, with their spans beside them**
  (#7). A `statuses:` entry may itself be a bare, unnamed array
  grouping a contiguous run of entries; `statuses` holds the *effective
  sequence* — every entry, groups spliced in at the position their
  sub-array occupied — and `groups` holds one `Range` per sub-array
  over that sequence.

  Structural parsing only; every cross-reference and skeleton-shape
  check is `Catapult.Dsl.Workflow`'s job. #7's own sub-array checks are
  the exception and live here: each is a fact about one declaration's
  own array, answerable while parsing it.
  """

  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.Status

  @enforce_keys [:name]
  defstruct [:name, :skeleton, :serves, statuses: [], groups: []]

  @typedoc "A ticket type's `serves:` (#40): an outright list of flow names, or a predicate over `has_delta`/`no_delta`."
  @type serves :: {:list, [String.t()]} | {:predicate, String.t()} | nil

  @type t :: %__MODULE__{
          name: String.t(),
          skeleton: String.t() | nil,
          serves: serves(),
          statuses: [Status.t()],
          groups: [Range.t()]
        }

  @skeletons ~w(ticket container)
  @serves_predicates ~w(has_delta no_delta)
  @core_keys ~w(skeleton serves statuses)

  @doc "Parses one `types.<name>` entry from its already-keyed YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(name, %{} = raw) do
    where = "type #{inspect(name)}"

    {skeleton, skeleton_problems} = parse_skeleton(raw, where)
    {serves, serves_problems} = parse_serves(raw, where)
    {raw_statuses, statuses_field_problems} = require_status_list(raw, where)
    {statuses, groups, statuses_problems} = parse_statuses(where, raw_statuses, skeleton)

    unknown = Fields.unknown_keys(raw, @core_keys, where)

    problems =
      skeleton_problems ++
        serves_problems ++ statuses_field_problems ++ statuses_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         skeleton: skeleton,
         serves: serves,
         statuses: statuses,
         groups: groups
       }}
    else
      {:error, problems}
    end
  end

  def parse(name, other) do
    {:error, ["type #{inspect(name)} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_skeleton(raw, where) do
    case Map.fetch(raw, "skeleton") do
      :error ->
        {nil, []}

      {:ok, value} when value in @skeletons ->
        {value, []}

      {:ok, value} ->
        {nil, ["#{where} skeleton is #{inspect(value)}, expected one of #{inspect(@skeletons)}"]}
    end
  end

  defp parse_serves(raw, where) do
    case Map.fetch(raw, "serves") do
      :error ->
        {nil, []}

      {:ok, value} when is_binary(value) and value in @serves_predicates ->
        {{:predicate, value}, []}

      {:ok, value} when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          {{:list, value}, []}
        else
          {nil, ["#{where} serves #{inspect(value)} has a non-string entry"]}
        end

      {:ok, other} ->
        {nil,
         [
           "#{where} serves #{inspect(other)} is not one of #{inspect(@serves_predicates)} or a list of flow names"
         ]}
    end
  end

  defp require_status_list(raw, where) do
    case Map.fetch(raw, "statuses") do
      {:ok, value} when is_list(value) -> {value, []}
      {:ok, value} -> {[], ["#{where} statuses is #{inspect(value)}, expected a list"]}
      :error -> {[], ["#{where} is missing required field \"statuses\""]}
    end
  end

  defp parse_statuses(where, raw_statuses, skeleton) do
    {statuses, groups, problems} =
      raw_statuses
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {raw, index}, {statuses, groups, problems} ->
        {entries, entry_problems, group?} = parse_entry(where, raw, index, skeleton)

        groups =
          if group? and entries != [] do
            first = length(statuses)
            [first..(first + length(entries) - 1)//1 | groups]
          else
            groups
          end

        {statuses ++ entries, groups, problems ++ entry_problems}
      end)

    {statuses, Enum.reverse(groups), problems}
  end

  defp parse_entry(where, raw, index, skeleton) when is_list(raw) do
    results =
      raw
      |> Enum.with_index()
      |> Enum.map(fn {inner, j} -> {j, parse_group_member(where, inner, index, j, skeleton)} end)

    parse_problems = for {_j, {:error, problems}} <- results, problem <- problems, do: problem

    if parse_problems == [] do
      entries = for {_j, {:ok, entry}} <- results, do: entry
      {entries, anchor_count_problems(where, index, results), true}
    else
      {[], parse_problems, true}
    end
  end

  defp parse_entry(where, raw, index, skeleton) do
    case Status.parse(where, "statuses[#{index}]", raw, skeleton) do
      {:ok, entry} -> {[entry], [], false}
      {:error, problems} -> {[], problems, false}
    end
  end

  defp parse_group_member(where, inner, index, j, _skeleton) when is_list(inner) do
    {:error,
     [
       "#{where} statuses[#{index}][#{j}] is itself a sub-array — sub-arrays do not nest (#7); " <>
         "a sub-array's entries are status:/review:/environment: only"
     ]}
  end

  defp parse_group_member(where, inner, index, j, skeleton) do
    Status.parse(where, "statuses[#{index}][#{j}]", inner, skeleton)
  end

  defp anchor_count_problems(where, index, results) do
    anchors =
      for {_j, {:ok, entry}} <- results,
          Status.non_review_shaped_agent_step?(entry),
          do: Status.name(entry)

    case anchors do
      [_exactly_one] ->
        []

      [] ->
        [
          "#{where} statuses[#{index}] is a sub-array with no non-review-shaped agent-balled " <>
            "entry (#7 requires exactly one) — a group with nothing for a throwback to fall back to groups nothing"
        ]

      many ->
        [
          "#{where} statuses[#{index}] is a sub-array with #{length(many)} non-review-shaped " <>
            "agent-balled entries #{inspect(many)} (#7 requires exactly one)"
        ]
    end
  end

  @doc "The sub-array containing effective-sequence index `index`, as a `Range` over `statuses`, or `nil`."
  @spec group_at(t(), non_neg_integer()) :: Range.t() | nil
  def group_at(%__MODULE__{groups: groups}, index), do: Enum.find(groups, &(index in &1))

  @doc "`range`'s own anchor — the absolute `statuses` index of its one non-review-shaped agent-balled entry."
  @spec anchor_index(t(), Range.t()) :: non_neg_integer() | nil
  def anchor_index(%__MODULE__{statuses: statuses}, %Range{} = range) do
    Enum.find(range, &Status.non_review_shaped_agent_step?(Enum.at(statuses, &1)))
  end

  @typedoc """
  One `statuses:` entry's own namespaced identity (#7): `index` is its
  absolute position in `statuses`; `bare` is its own authored name;
  `namespace` is `:top_level` for an entry no sub-array cites or that
  is itself its own sub-array's anchor, else the anchor's own bare
  name; `qualified` is always `<anchor>.<bare>` for a non-anchor group
  member, `bare` otherwise; `canonical` is `qualified` when `bare`
  recurs elsewhere in the same type's own array, `bare` otherwise.
  """
  @type namespaced_entry :: %{
          index: non_neg_integer(),
          entry: Status.t(),
          bare: String.t(),
          namespace: String.t() | :top_level,
          qualified: String.t(),
          canonical: String.t(),
          kind_ambiguous: boolean()
        }

  @doc "Every entry in `type`'s own effective sequence, paired with its own namespaced identity (#7)."
  @spec namespaced_positions(t()) :: [namespaced_entry()]
  def namespaced_positions(%__MODULE__{statuses: statuses} = type) do
    raw =
      statuses
      |> Enum.with_index()
      |> Enum.map(fn {entry, index} -> raw_position(type, entry, index) end)

    ambiguous_bares = ambiguous_values(raw, & &1.bare)
    ambiguous_kinds = ambiguous_values(raw, &kind_key(&1.entry))

    Enum.map(raw, fn position ->
      canonical =
        if MapSet.member?(ambiguous_bares, position.bare),
          do: position.qualified,
          else: position.bare

      position
      |> Map.put(:canonical, canonical)
      |> Map.put(:kind_ambiguous, MapSet.member?(ambiguous_kinds, kind_key(position.entry)))
    end)
  end

  defp ambiguous_values(raw, key_fun) do
    raw
    |> Enum.frequencies_by(key_fun)
    |> Enum.filter(fn {_key, count} -> count > 1 end)
    |> Enum.map(fn {key, _count} -> key end)
    |> MapSet.new()
  end

  defp kind_key(%Status{status: s}) when not is_nil(s), do: s
  defp kind_key(%Status{review: r}) when not is_nil(r), do: r
  defp kind_key(%Status{environment: e}) when not is_nil(e), do: e

  defp raw_position(type, entry, index) do
    bare = Status.name(entry)

    case group_at(type, index) do
      nil ->
        top_level_position(index, entry, bare)

      range ->
        anchor_index = anchor_index(type, range)

        if index == anchor_index do
          top_level_position(index, entry, bare)
        else
          anchor_name = Status.name(Enum.at(type.statuses, anchor_index))

          %{
            index: index,
            entry: entry,
            bare: bare,
            namespace: anchor_name,
            qualified: "#{anchor_name}.#{bare}"
          }
        end
    end
  end

  defp top_level_position(index, entry, bare) do
    %{index: index, entry: entry, bare: bare, namespace: :top_level, qualified: bare}
  end

  @doc """
  Effective-sequence index `index` rendered as the path the author
  actually wrote — `"statuses[3]"`, or `"statuses[1][2]"` for an entry
  inside a sub-array.
  """
  @spec declared_path(t(), non_neg_integer()) :: String.t()
  def declared_path(%__MODULE__{groups: groups}, index) do
    {outer, inner} =
      Enum.reduce_while(groups, {index, nil}, fn range, {outer, inner} ->
        cond do
          index < range.first -> {:halt, {outer, inner}}
          index in range -> {:halt, {outer - (index - range.first), index - range.first}}
          true -> {:cont, {outer - (Range.size(range) - 1), inner}}
        end
      end)

    if inner, do: "statuses[#{outer}][#{inner}]", else: "statuses[#{outer}]"
  end
end
