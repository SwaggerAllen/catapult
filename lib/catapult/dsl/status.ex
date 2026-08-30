defmodule Catapult.Dsl.Status do
  @moduledoc """
  One `statuses:` array entry of a `types/<name>.yaml` declaration
  (dsl-syntax.md §15.2-§15.7): exactly one of a skeleton anchor
  (`status:`), a gate reference (`review:`) or an environment
  reference (`environment:`) — position is the array index the entry
  sits at in its own declaration, never a separate field (§15.3).

  `flow:` and `blocks:` are legal only on a **population anchor**: a
  `status:` entry named `prep`, `main` or `cleanup`, or any `status:`
  entry in a skeleton-less type's array (§15.7) — never on `pending`,
  `generation`, `design`, `architecture`, `implementation`, `critique`,
  `checks`, `reconcile`, `merge`, `deploy`, `setup`, `retro` or
  `terminal`, whatever type's array cites them (a seventh-pass
  reversal, ORC-148: a skeleton fixes
  a required backbone, never an exclusive membership, so this is a
  fact about the *entry's own name* and the citing type's `skeleton:`
  being absent or not, never about which skeleton a `container`- or
  `ticket`-skeleton type happens to declare — `Catapult.Dsl.Type`
  resolves the citing type's `skeleton:` first and passes it in).
  `depth:` is legal only on a `status: critique` entry, immediately
  after a generation-shaped entry (§15.5).

  **`singleton:` is retired (ORC-148, §15.7): it bounded a queue's own
  cardinality, and once `setup`/`retro` fold inline as ordinary
  agent-balled entries with no `flow:` of their own, neither is a
  queue any more — there is no cardinality left for a field to
  bound.**

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

  **A `status:` entry carries an optional `name:`, distinct from its
  kind, defaulting to the kind when omitted** (§15.12, ORC-155): what a
  bundle authors is what to *call* a given occurrence of a kind, never
  a new kind — every load-time predicate and every plane branch keeps
  reading `status` (the kind), never `name`. Namespacing positions by
  their sub-array anchor and resolving a `blocks:`/`throwback:`
  reference against that namespace is `Catapult.Dsl.Workflow`'s job,
  the identical division this module already draws for every other
  cross-reference.
  """

  alias Catapult.Dsl.Fields
  alias Catapult.Dsl.SystemStatus

  defstruct [:status, :name, :review, :environment, :flow, :depth, blocks: []]

  @type t :: %__MODULE__{
          status: String.t() | nil,
          name: String.t() | nil,
          review: String.t() | nil,
          environment: String.t() | nil,
          flow: String.t() | nil,
          blocks: [String.t()],
          depth: Fields.depth() | nil
        }

  @entry_keys ~w(status review environment)

  @doc """
  Parses one `statuses:` array entry. `path` is the entry's own
  position rendered as the author wrote it — `"statuses[3]"` at the
  top level, `"statuses[1][2]"` inside a sub-array (§15.10) — so a
  problem points at the YAML the author has open rather than at the
  flattened index `Catapult.Dsl.Type` stores the entry under.
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

  @population_anchor_names ~w(prep main cleanup)

  # A population anchor (§15.7): named `prep`/`main`/`cleanup`,
  # whatever skeleton the citing type declares or omits, or any
  # `status:` entry at all when the citing type declares no skeleton
  # (its whole array is author-declared queue positions, §15.1). This
  # is a fact about the entry's own name, never about whether the
  # citing type is `ticket`- or `container`-skeleton (ORC-148, §15.2).
  defp population_anchor?(name, skeleton) do
    is_nil(skeleton) or name in @population_anchor_names
  end

  defp parse_status_entry(where, raw, skeleton) do
    {kind, kind_problems} = Fields.require_string(raw, "status", where)
    {name, name_problems} = Fields.optional_string(raw, "name", where)
    queue_shaped? = population_anchor?(kind, skeleton)

    {flow, blocks, shape_problems} =
      if queue_shaped? do
        {flow, fp} = Fields.require_string(raw, "flow", where)
        {blocks, bp} = Fields.optional_string_list(raw, "blocks", where)
        {flow, blocks, fp ++ bp}
      else
        {nil, [], []}
      end

    # `depth:` is legal on a `critique` *kind*, whatever a bundle
    # authors as its own `name:` (§15.12, ORC-155) — this reads `kind`,
    # never `name`, so a renamed critique entry keeps admitting it.
    {depth, depth_problems} =
      if kind == "critique", do: Fields.depth(raw, where), else: {nil, []}

    known =
      ["status", "name"] ++
        if(queue_shaped?, do: ["flow", "blocks"], else: []) ++
        if(kind == "critique", do: ["depth"], else: [])

    unknown = Fields.unknown_keys(raw, known, where)
    problems = kind_problems ++ name_problems ++ shape_problems ++ depth_problems ++ unknown

    if problems == [] do
      {:ok, %__MODULE__{status: kind, name: name, flow: flow, blocks: blocks, depth: depth}}
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

  @doc """
  The bare name this entry is addressed by — a `status:` entry's own
  authored `name:`, defaulting to its `status:` (kind) when omitted
  (§15.12, ORC-155), or a `review:`/`environment:` entry's citation
  value. This is the *bare* form only: whether a reference to it must
  be namespace-qualified `<anchor>.<name>` because this bare name
  recurs elsewhere in the citing type's own array is
  `Catapult.Dsl.Workflow`'s job to resolve, not this module's.
  """
  @spec name(t()) :: String.t()
  def name(%__MODULE__{status: s, name: n}) when not is_nil(s), do: n || s
  def name(%__MODULE__{review: r}) when not is_nil(r), do: r
  def name(%__MODULE__{environment: e}) when not is_nil(e), do: e

  @doc """
  Whether this entry is §15.10's sub-array anchor: a non-review-shaped
  agent-balled `status:` entry — `generation`, `design`, `architecture`,
  `implementation`, `retro` or `setup` under §15.1's `ball` column.
  `merge` left this set at ORC-151: its own `ball` is now `plane` (§15.1,
  §15.11), so it was never a candidate for this predicate to exclude by
  name — it fails `SystemStatus.agent_balled?/1` before review-shapedness
  is ever asked.

  `critique` and `reconcile` are excluded because each reviews a
  generation rather than standing as one — review-shaped,
  `SystemStatus.review_shaped?/1` — the identical exclusion §15.5
  already draws for `critique` alone, generalized rather than
  duplicated at ORC-151. A `review:` or `environment:` entry is
  excluded by construction: only a `status:` entry names a fixed
  system-status kind, so a gate that happened to be named `reconcile`
  is not one of these.

  Exactly one per sub-array is a load error to violate
  (`Catapult.Dsl.Type`), and that one entry is the fallback
  `Catapult.Dsl.Workflow.throwback_default/3` derives.
  """
  @spec non_review_shaped_agent_step?(t()) :: boolean()
  def non_review_shaped_agent_step?(%__MODULE__{status: nil}), do: false

  def non_review_shaped_agent_step?(%__MODULE__{status: status}),
    do: SystemStatus.agent_balled?(status) and not SystemStatus.review_shaped?(status)

  @doc "Whether this entry is a `status:` (skeleton-anchor) entry, as opposed to `review:`/`environment:`."
  @spec anchor?(t()) :: boolean()
  def anchor?(%__MODULE__{status: name}), do: not is_nil(name)

  @doc "Whether this entry carries a `flow:` — i.e. is a queue-shaped anchor (§15.7)."
  @spec queue_shaped?(t()) :: boolean()
  def queue_shaped?(%__MODULE__{flow: flow}), do: not is_nil(flow)
end
