defmodule Catapult.Dsl.Status do
  @moduledoc """
  One `statuses:` array entry of a `types.<name>` declaration
  (`workflow.md` #5): exactly one of a skeleton anchor (`status:`), a
  gate reference (`review:`) or an environment reference
  (`environment:`) — position is the array index the entry sits at in
  its own declaration, never a separate field (#7).

  `tiers:` is legal on a `generation` entry (required — #21, #22) and
  optionally on `setup`/`retro` (#19); `flow:`/`blocks:` are legal only
  on a **population anchor** — `prep`, `main` or `cleanup`, or any
  `status:` entry in a skeleton-less type's array (#17, #30); `fills:`
  is legal only on `setup`/`retro` (#17); `depth:` is legal only on a
  `review:` entry (#33) — it moved off `critique` here, since a gate
  citation is what it now describes.

  Structural parsing only; every cross-reference (`review:`/
  `environment:` resolving in the loaded union, `flow:` resolving in
  the type registry, `tiers:` resolving against the paired chain,
  `blocks:` scoped to the same array) is `Catapult.Dsl.Workflow`'s job.

  **A `status:` entry carries an optional `name:`, distinct from its
  kind, defaulting to the kind when omitted** (#7): what a bundle
  authors is what to *call* a given occurrence of a kind, never a new
  kind — every load-time predicate and every plane branch keeps
  reading `status` (the kind), never `name`.
  """

  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.SystemStatus

  defstruct [
    :status,
    :name,
    :review,
    :environment,
    :flow,
    :depth,
    blocks: [],
    fills: [],
    tiers: []
  ]

  @type t :: %__MODULE__{
          status: String.t() | nil,
          name: String.t() | nil,
          review: String.t() | nil,
          environment: String.t() | nil,
          flow: String.t() | nil,
          blocks: [String.t()],
          fills: [String.t()],
          tiers: [String.t()],
          depth: Fields.depth() | nil
        }

  @entry_keys ~w(status review environment)
  @population_anchor_names ~w(prep main cleanup)
  @tiered_kinds ~w(generation setup retro)
  @fills_kinds ~w(setup retro)

  @doc """
  Parses one `statuses:` array entry. `path` is the entry's own
  position rendered as the author wrote it — `"statuses[3]"` at the
  top level, `"statuses[1][2]"` inside a sub-array — so a problem
  points at the YAML the author has open rather than at the flattened
  index `Catapult.Dsl.Type` stores the entry under.
  """
  @spec parse(String.t(), String.t(), term(), String.t() | nil) ::
          {:ok, t()} | {:error, [String.t()]}
  def parse(where, path, raw, skeleton) do
    do_parse("#{where} #{path}", raw, skeleton)
  end

  defp do_parse(where, %{} = raw, skeleton) do
    case Enum.filter(@entry_keys, &Map.has_key?(raw, &1)) do
      ["status"] ->
        parse_status_entry(where, raw, skeleton)

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

  defp do_parse(where, other, _skeleton) do
    {:error, ["#{where} is #{inspect(other)}, expected a YAML mapping"]}
  end

  # A population anchor (#17, #30): named `prep`/`main`/`cleanup`,
  # whatever skeleton the citing type declares or omits, or any
  # `status:` entry at all when the citing type declares no skeleton.
  defp population_anchor?(name, skeleton) do
    is_nil(skeleton) or name in @population_anchor_names
  end

  defp parse_status_entry(where, raw, skeleton) do
    {kind, kind_problems} = Fields.require_string(raw, "status", where)
    {name, name_problems} = Fields.optional_string(raw, "name", where)
    queue_shaped? = population_anchor?(kind, skeleton)

    {flow, blocks, queue_problems} =
      if queue_shaped? do
        {flow, fp} = Fields.require_string(raw, "flow", where)
        {blocks, bp} = Fields.optional_string_list(raw, "blocks", where)
        {flow, blocks, fp ++ bp}
      else
        {nil, [], []}
      end

    {fills, fills_problems} =
      if kind in @fills_kinds,
        do: Fields.optional_string_list(raw, "fills", where),
        else: {[], []}

    {tiers, tiers_problems} = parse_tiers(raw, kind, where)

    known =
      ["status", "name"] ++
        if(queue_shaped?, do: ["flow", "blocks"], else: []) ++
        if(kind in @fills_kinds, do: ["fills"], else: []) ++
        if(kind in @tiered_kinds, do: ["tiers"], else: [])

    unknown = Fields.unknown_keys(raw, known, where)

    problems =
      kind_problems ++
        name_problems ++ queue_problems ++ fills_problems ++ tiers_problems ++ unknown

    if problems == [] do
      {:ok,
       %__MODULE__{
         status: kind,
         name: name,
         flow: flow,
         blocks: blocks,
         fills: fills,
         tiers: tiers
       }}
    else
      {:error, problems}
    end
  end

  # `tiers:` is required on `generation` (#21, #22) and optional on
  # `setup`/`retro` (#19); anything else carries none.
  defp parse_tiers(_raw, kind, _where) when kind not in @tiered_kinds, do: {[], []}

  defp parse_tiers(raw, "generation", where), do: Fields.require_string_list(raw, "tiers", where)
  defp parse_tiers(raw, _kind, where), do: Fields.optional_string_list(raw, "tiers", where)

  defp parse_review_entry(where, raw) do
    {name, name_problems} = Fields.require_string(raw, "review", where)
    {depth, depth_problems} = Fields.depth(raw, where)
    unknown = Fields.unknown_keys(raw, ["review", "depth"], where)
    problems = name_problems ++ depth_problems ++ unknown

    if problems == [],
      do: {:ok, %__MODULE__{review: name, depth: depth}},
      else: {:error, problems}
  end

  defp parse_environment_entry(where, raw) do
    {name, name_problems} = Fields.require_string(raw, "environment", where)
    unknown = Fields.unknown_keys(raw, ["environment"], where)
    problems = name_problems ++ unknown

    if problems == [], do: {:ok, %__MODULE__{environment: name}}, else: {:error, problems}
  end

  @doc """
  The bare name this entry is addressed by — a `status:` entry's own
  authored `name:`, defaulting to its `status:` (kind) when omitted, or
  a `review:`/`environment:` entry's citation value.
  """
  @spec name(t()) :: String.t()
  def name(%__MODULE__{status: s, name: n}) when not is_nil(s), do: n || s
  def name(%__MODULE__{review: r}) when not is_nil(r), do: r
  def name(%__MODULE__{environment: e}) when not is_nil(e), do: e

  @doc """
  Whether this entry is #7's sub-array anchor: a non-review-shaped
  agent-balled `status:` entry — `generation`, `setup` or `retro` under
  `workflow.md` #10's `ball` column. `critique` and `reconcile` are
  excluded because each reviews a generation rather than standing as
  one — review-shaped. A `review:`/`environment:` entry is excluded by
  construction.
  """
  @spec non_review_shaped_agent_step?(t()) :: boolean()
  def non_review_shaped_agent_step?(%__MODULE__{status: nil}), do: false

  def non_review_shaped_agent_step?(%__MODULE__{status: status}),
    do: SystemStatus.agent_balled?(status) and not SystemStatus.review_shaped?(status)

  @doc "Whether this entry is a `status:` (skeleton-anchor) entry, as opposed to `review:`/`environment:`."
  @spec anchor?(t()) :: boolean()
  def anchor?(%__MODULE__{status: name}), do: not is_nil(name)

  @doc "Whether this entry carries a `flow:` — i.e. is a queue-shaped anchor (#17, #30)."
  @spec queue_shaped?(t()) :: boolean()
  def queue_shaped?(%__MODULE__{flow: flow}), do: not is_nil(flow)
end
