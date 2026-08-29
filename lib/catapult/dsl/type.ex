defmodule Catapult.Dsl.Type do
  @moduledoc """
  One `types/<name>.yaml` declaration (dsl-syntax.md §15.2): a work
  item, ticket or container alike, one declaration shape rather than
  three. A skeleton fixes a required backbone, never an exclusive
  membership (a seventh-pass reversal, ORC-148): `type:` names the
  declaration; `skeleton:` optionally picks `ticket` or `container`
  (omitted: no anchors at all, the project's own shape, §15.1);
  `statuses:` is the one ordered array both the skeleton's own required
  backbone (§15.1) and whatever else the closed vocabulary allows —
  gates, environments, `critique` entries, a bare generation, a
  population anchor of its own — live in, array index the only
  position (§15.3).

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
  are facts about more than one declaration at once. §15.10's own
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

  # Population-anchor legality is a fact about an entry's own name (and
  # whether the citing type declares a skeleton at all), never about
  # which skeleton it declares (§15.7, a seventh-pass reversal,
  # ORC-148) — `Catapult.Dsl.Status.parse/4` resolves it per entry, so
  # this module only threads the citing type's own `skeleton:` through.
  #
  # A sub-array's entries are parsed under the identical `skeleton:` as
  # the array that holds them — there is no separate rule for group
  # members.
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

  # A sub-array (§15.10). Its own §15.10 checks run only once every
  # member parsed: a group half of whose entries are malformed would
  # otherwise also be reported as holding the wrong number of anchors,
  # which is a consequence of the first problem rather than a second
  # one to fix.
  defp parse_entry(where, raw, index, skeleton) when is_list(raw) do
    results =
      raw
      |> Enum.with_index()
      |> Enum.map(fn {inner, j} ->
        {j, parse_group_member(where, inner, index, j, skeleton)}
      end)

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

  # §15.10's first check. Reported here rather than left to `Status
  # .parse/4`'s "expected a YAML mapping" clause: a reader who nested
  # two sub-arrays needs to know nesting is refused, not that a list is
  # not a map.
  defp parse_group_member(where, inner, index, j, _skeleton) when is_list(inner) do
    {:error,
     [
       "#{where} statuses[#{index}][#{j}] is itself a sub-array — sub-arrays do not nest " <>
         "(§15.10); a sub-array's entries are status:/review:/environment: only"
     ]}
  end

  defp parse_group_member(where, inner, index, j, skeleton) do
    Status.parse(where, "statuses[#{index}][#{j}]", inner, skeleton)
  end

  # Exactly one non-review-shaped agent-balled entry per sub-array — the
  # fact §15.10's whole derived default rests on, and the whole of what
  # this section still checks over a sub-array's own contents. (The
  # check that once refused a queue-shaped/population-anchor entry
  # inside a sub-array is retired at ORC-148: §15.2's unification means
  # a sub-array's one non-review-shaped agent-balled entry no longer
  # needs a `flow:` to exist inside a container's array in the first
  # place, so the case it refused doesn't arise from the shape this
  # grammar now gives `setup`/`retro`.) Which entries qualify is
  # `Status.non_review_shaped_agent_step?/1`'s to answer and is not
  # restated here: this check and the derivation that depends on it
  # (`Catapult.Dsl.Workflow.throwback_default/3`) must agree, and they
  # agree by asking the same function rather than by both being right.
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
            "entry (§15.10 requires exactly one) — a group with nothing for a throwback to " <>
            "fall back to groups nothing"
        ]

      many ->
        [
          "#{where} statuses[#{index}] is a sub-array with #{length(many)} non-review-shaped " <>
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
