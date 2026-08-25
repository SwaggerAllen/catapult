defmodule Catapult.Dsl.Status do
  @moduledoc """
  One `statuses:` array entry of a `types/<name>.yaml` declaration
  (dsl-syntax.md §15.2-§15.7): exactly one of a skeleton anchor
  (`status:`), a gate reference (`review:`) or an environment
  reference (`environment:`) — position is the array index the entry
  sits at in its own declaration, never a separate field (§15.3).

  `flow:`, `blocks:` and `singleton:` are legal only on a queue-shaped
  `status:` entry — a `container`-skeleton type's five anchors, or any
  `status:` entry in a skeleton-less type's array (§15.7); `depth:` is
  legal only on a `status: critique` entry, immediately after a
  `generation` entry (§15.5). Whether a given `status:` entry is
  queue-shaped depends on the *citing type's* own `skeleton:`, which
  this module does not know — `Catapult.Dsl.Type` resolves that first
  and passes it in.

  **`terminal` is never queue-shaped, whatever skeleton cites it.**
  §15.7 opens by describing a queue-shaped entry as "any `status:`
  entry belonging to a `container`-skeleton type's array," which read
  literally would require a `flow:` on `terminal` too; §15.2's own
  worked `types/milestone.yaml` declares `- status: terminal` with no
  `flow:`, and §15.6 settles which reading is meant — after `cleanup`
  resolves a container "reaches a fixed `terminal` kind, **not a
  further queue name**." A kind that dispatches nothing has nothing
  for `flow:` to name, so the blanket sentence is read as scoped to
  the queue anchors it is actually about and the example is honored
  rather than rejected.

  Structural parsing only; every cross-reference (`review:`/
  `environment:` resolving in the loaded union, `flow:` resolving in
  the type registry, `blocks:` scoped to the same array, the
  skeleton's own fixed anchor set and relative order) is
  `Catapult.Dsl.Workflow`'s job (dsl-syntax.md §13).
  """

  alias Catapult.Dsl.Fields

  defstruct [:status, :review, :environment, :flow, :depth, blocks: [], singleton: false]

  @type t :: %__MODULE__{
          status: String.t() | nil,
          review: String.t() | nil,
          environment: String.t() | nil,
          flow: String.t() | nil,
          blocks: [String.t()],
          singleton: boolean(),
          depth: Fields.depth() | nil
        }

  @entry_keys ~w(status review environment)

  @doc "Parses one `statuses:` array entry."
  @spec parse(String.t(), non_neg_integer(), term(), boolean()) ::
          {:ok, t()} | {:error, [String.t()]}
  def parse(where, index, raw, queue_shaped?) do
    entry_where = "#{where} statuses[#{index}]"
    do_parse(entry_where, raw, queue_shaped?)
  end

  defp do_parse(where, %{} = raw, queue_shaped?) do
    case Enum.filter(@entry_keys, &Map.has_key?(raw, &1)) do
      ["status"] ->
        parse_status_entry(where, raw, queue_shaped?)

      ["review"] ->
        parse_review_entry(where, raw)

      ["environment"] ->
        parse_environment_entry(where, raw)

      [] ->
        {:error, ["#{where} carries none of status/review/environment (exactly one required)"]}

      present ->
        {:error,
         ["#{where} carries more than one of status/review/environment: #{inspect(present)}"]}
    end
  end

  defp do_parse(where, other, _queue_shaped?) do
    {:error, ["#{where} is #{inspect(other)}, expected a YAML mapping"]}
  end

  defp parse_status_entry(where, raw, type_queue_shaped?) do
    {name, name_problems} = Fields.require_string(raw, "status", where)
    queue_shaped? = type_queue_shaped? and name != "terminal"

    {flow, blocks, singleton, shape_problems} =
      if queue_shaped? do
        {flow, fp} = Fields.require_string(raw, "flow", where)
        {blocks, bp} = Fields.optional_string_list(raw, "blocks", where)
        {singleton, sp} = Fields.optional_boolean(raw, "singleton", where, false)
        {flow, blocks, singleton, fp ++ bp ++ sp}
      else
        {nil, [], false, []}
      end

    {depth, depth_problems} =
      if name == "critique", do: Fields.depth(raw, where), else: {nil, []}

    known =
      ["status"] ++
        if(queue_shaped?, do: ["flow", "blocks", "singleton"], else: []) ++
        if(name == "critique", do: ["depth"], else: [])

    unknown = Fields.unknown_keys(raw, known, where)
    problems = name_problems ++ shape_problems ++ depth_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{status: name, flow: flow, blocks: blocks, singleton: singleton, depth: depth}}
    else
      {:error, problems}
    end
  end

  defp parse_review_entry(where, raw) do
    {name, name_problems} = Fields.require_string(raw, "review", where)
    unknown = Fields.unknown_keys(raw, ["review"], where)
    problems = name_problems ++ unknown

    if problems == [], do: {:ok, %__MODULE__{review: name}}, else: {:error, problems}
  end

  defp parse_environment_entry(where, raw) do
    {name, name_problems} = Fields.require_string(raw, "environment", where)
    unknown = Fields.unknown_keys(raw, ["environment"], where)
    problems = name_problems ++ unknown

    if problems == [], do: {:ok, %__MODULE__{environment: name}}, else: {:error, problems}
  end

  @doc "Whether this entry is a `status:` (skeleton-anchor) entry, as opposed to `review:`/`environment:`."
  @spec anchor?(t()) :: boolean()
  def anchor?(%__MODULE__{status: name}), do: not is_nil(name)

  @doc "Whether this entry carries a `flow:` — i.e. is a queue-shaped anchor (§15.7)."
  @spec queue_shaped?(t()) :: boolean()
  def queue_shaped?(%__MODULE__{flow: flow}), do: not is_nil(flow)
end
