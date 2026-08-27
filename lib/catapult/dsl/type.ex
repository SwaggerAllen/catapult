defmodule Catapult.Dsl.Type do
  @moduledoc """
  One `types/<name>.yaml` declaration (dsl-syntax.md §15.2): a work
  item, ticket or container alike — "a container is any work item
  whose skeleton has queues, a ticket is any work item whose skeleton
  has a generation, and the grammar gives them one declaration shape,
  not three." `type:` names the declaration; `skeleton:` optionally
  picks `ticket` or `container` (omitted: no anchors at all, the
  project's own shape, §15.1); `statuses:` is the one ordered array
  both the skeleton's own fixed anchors (§15.1) and whatever gates,
  environments or `critique` entries the author interleaves live in —
  array index is the only position (§15.3).

  **Sub-arrays are stored flattened, with their spans beside them**
  (§15.10). A `statuses:` entry may itself be a bare, unnamed array
  grouping a contiguous run of the entries §15.2 already allows;
  `statuses` holds the *effective sequence* — every entry, groups
  spliced in at the position their sub-array occupied — and `groups`
  holds one `Range` per sub-array over that sequence.

  Two representations were available and this is the one that keeps
  §15.10's own promises literal rather than by convention. A sub-array
  "carries no key of its own — no `name:`, no `id:`, nothing a later
  declaration or a cutover could reference," and it never nests, so a
  contiguous index range *is* the whole of what a group is: nothing is
  lost by flattening, and there is no second identity for a cutover to
  re-resolve against (§15.1). It also means every consumer that reads
  a type's array as an ordered sequence — `Catapult.Delivery
  .FeatureLifecycle.Sequence`, `Catapult.Delivery.ContainerLifecycle
  .Composition`, and the position/order/adjacency checks in
  `Catapult.Dsl.Workflow` — keeps holding because the sequence it
  reads is unchanged, not because each was edited to flatten a nested
  list correctly.

  Structural parsing only; every cross-reference and skeleton-shape
  check (§13) is `Catapult.Dsl.Workflow`'s job, since most of them
  (uniqueness across the loaded union, the declaration graph, `entry:`)
  are facts about more than one declaration at once. §15.10's three
  sub-array checks are the exception and live here: each is a fact
  about one declaration's own array, answerable while parsing it.
  """

  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.Status

  @enforce_keys [:name, :file]
  defstruct [:name, :file, :skeleton, statuses: [], groups: []]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          skeleton: String.t() | nil,
          statuses: [Status.t()],
          groups: [Range.t()]
        }

  @skeletons ~w(ticket container)
  @core_keys ~w(type skeleton statuses)

  @doc "Parses one type declaration from its YAML map."
  @spec parse(String.t(), map()) :: {:ok, t()} | {:error, [String.t()]}
  def parse(file, %{} = raw) do
    where = "type declaration #{file}"
    {name, name_problems} = Fields.require_string(raw, "type", where)
    type_where = if name, do: "type #{inspect(name)} (#{file})", else: where

    {skeleton, skeleton_problems} = parse_skeleton(raw, type_where)
    {raw_statuses, statuses_field_problems} = require_status_list(raw, type_where)

    {statuses, groups, statuses_problems} = parse_statuses(type_where, raw_statuses, skeleton)

    unknown = Fields.unknown_keys(raw, @core_keys, type_where)

    problems =
      name_problems ++
        skeleton_problems ++ statuses_field_problems ++ statuses_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         name: name,
         file: file,
         skeleton: skeleton,
         statuses: statuses,
         groups: groups
       }}
    else
      {:error, problems}
    end
  end

  def parse(file, other) do
    {:error, ["type declaration #{file} is #{inspect(other)}, expected a YAML mapping"]}
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

  defp require_status_list(raw, where) do
    case Map.fetch(raw, "statuses") do
      {:ok, value} when is_list(value) -> {value, []}
      {:ok, value} -> {[], ["#{where} statuses is #{inspect(value)}, expected a list"]}
      :error -> {[], ["#{where} is missing required field \"statuses\""]}
    end
  end

  # A `container`-skeleton type's own `status:` entries are all
  # queue-shaped (its five anchors); so is every `status:` entry in a
  # skeleton-less type's array (§15.7). A `ticket`-skeleton type's
  # `status:` entries never are — those anchors dispatch by chain-side
  # tiers (§13).
  #
  # A sub-array's entries are parsed under the *same* queue-shapedness
  # as the array that holds them, deliberately: a container type's
  # `retro` still has to declare the `flow:` §15.7 requires of it, and
  # then §15.10's own check refuses it for having one. Parsing group
  # members as never-queue-shaped would instead let a container quietly
  # drop `flow:` to slip an anchor into a group — the milestone
  # retirement, arrived at by omission rather than by decision.
  defp parse_statuses(where, raw_statuses, skeleton) do
    queue_shaped? = skeleton in [nil, "container"]

    {statuses, groups, problems} =
      raw_statuses
      |> Enum.with_index()
      |> Enum.reduce({[], [], []}, fn {raw, index}, {statuses, groups, problems} ->
        {entries, entry_problems, group?} = parse_entry(where, raw, index, queue_shaped?)

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

  # A sub-array (§15.10). Its own §15.10 checks run only once every
  # member parsed: a group half of whose entries are malformed would
  # otherwise also be reported as holding the wrong number of anchors,
  # which is a consequence of the first problem rather than a second
  # one to fix.
  defp parse_entry(where, raw, index, queue_shaped?) when is_list(raw) do
    results =
      raw
      |> Enum.with_index()
      |> Enum.map(fn {inner, j} ->
        {j, parse_group_member(where, inner, index, j, queue_shaped?)}
      end)

    parse_problems = for {_j, {:error, problems}} <- results, problem <- problems, do: problem

    if parse_problems == [] do
      entries = for {_j, {:ok, entry}} <- results, do: entry
      {entries, sub_array_problems(where, index, results), true}
    else
      {[], parse_problems, true}
    end
  end

  defp parse_entry(where, raw, index, queue_shaped?) do
    case Status.parse(where, "statuses[#{index}]", raw, queue_shaped?) do
      {:ok, entry} -> {[entry], [], false}
      {:error, problems} -> {[], problems, false}
    end
  end

  # §15.10's first check. Reported here rather than left to `Status
  # .parse/4`'s "expected a YAML mapping" clause: a reader who nested
  # two sub-arrays needs to know nesting is refused, not that a list is
  # not a map.
  defp parse_group_member(where, inner, index, j, _queue_shaped?) when is_list(inner) do
    {:error,
     [
       "#{where} statuses[#{index}][#{j}] is itself a sub-array — sub-arrays do not nest " <>
         "(§15.10); a sub-array's entries are status:/review:/environment: only"
     ]}
  end

  defp parse_group_member(where, inner, index, j, queue_shaped?) do
    Status.parse(where, "statuses[#{index}][#{j}]", inner, queue_shaped?)
  end

  # §15.10's second and third checks, over a sub-array whose members
  # all parsed.
  defp sub_array_problems(where, index, results) do
    queue_problems =
      for {j, {:ok, entry}} <- results, Status.queue_shaped?(entry) do
        "#{where} statuses[#{index}][#{j}] is a queue-shaped anchor (flow:/blocks:), which may " <>
          "not sit inside a sub-array (§15.10) — that is the singleton-flow retirement the " <>
          "section leaves open, not something this grammar accepts"
      end

    queue_problems ++ anchor_count_problems(where, index, results)
  end

  # Exactly one non-critique agent-balled entry per sub-array — the
  # fact §15.10's whole derived default rests on. Which entries qualify
  # is `Status.non_critique_agent_step?/1`'s to answer and is not
  # restated here: this check and the derivation that depends on it
  # (`Catapult.Dsl.Workflow.throwback_default/3`) must agree, and they
  # agree by asking the same function rather than by both being right.
  defp anchor_count_problems(where, index, results) do
    anchors =
      for {_j, {:ok, entry}} <- results,
          Status.non_critique_agent_step?(entry),
          do: Status.name(entry)

    case anchors do
      [_exactly_one] ->
        []

      [] ->
        [
          "#{where} statuses[#{index}] is a sub-array with no non-critique agent-balled entry " <>
            "(§15.10 requires exactly one) — a group with nothing for a throwback to fall back " <>
            "to groups nothing"
        ]

      many ->
        [
          "#{where} statuses[#{index}] is a sub-array with #{length(many)} non-critique " <>
            "agent-balled entries #{inspect(many)} (§15.10 requires exactly one) — there is no " <>
            "unambiguous anchor between them, and none is invented for a shape no bundle needs"
        ]
    end
  end

  @doc """
  The sub-array containing effective-sequence index `index`, as a
  `Range` over `statuses`, or `nil` when that entry sits in no group
  (§15.10).
  """
  @spec group_at(t(), non_neg_integer()) :: Range.t() | nil
  def group_at(%__MODULE__{groups: groups}, index) do
    Enum.find(groups, &(index in &1))
  end

  @doc """
  Effective-sequence index `index` rendered as the path the author
  actually wrote — `"statuses[3]"`, or `"statuses[1][2]"` for an entry
  inside a sub-array (§15.10).

  Flattening buys every sequence consumer an unchanged array (see the
  moduledoc) and costs exactly this: past the first group, an effective
  index no longer names a line in the file. A load error that printed
  the raw index would send a reader to a `statuses[4]` their YAML does
  not have, so every message that cites a position goes through here.
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
