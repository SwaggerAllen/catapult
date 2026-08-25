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

  Structural parsing only; every cross-reference and skeleton-shape
  check (§13) is `Catapult.Dsl.Workflow`'s job, since most of them
  (uniqueness across the loaded union, the declaration graph, `entry:`)
  are facts about more than one declaration at once.
  """

  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.Status

  @enforce_keys [:name, :file]
  defstruct [:name, :file, :skeleton, statuses: []]

  @type t :: %__MODULE__{
          name: String.t(),
          file: String.t(),
          skeleton: String.t() | nil,
          statuses: [Status.t()]
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

    {statuses, statuses_problems} = parse_statuses(type_where, raw_statuses, skeleton)

    unknown = Fields.unknown_keys(raw, @core_keys, type_where)

    problems =
      name_problems ++
        skeleton_problems ++ statuses_field_problems ++ statuses_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{name: name, file: file, skeleton: skeleton, statuses: statuses}}
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
  defp parse_statuses(where, raw_statuses, skeleton) do
    queue_shaped? = skeleton in [nil, "container"]

    results =
      raw_statuses
      |> Enum.with_index()
      |> Enum.map(fn {raw, index} -> Status.parse(where, index, raw, queue_shaped?) end)

    problems =
      Enum.flat_map(results, fn
        {:ok, _} -> []
        {:error, p} -> p
      end)

    parsed = for {:ok, status} <- results, do: status
    {parsed, problems}
  end
end
