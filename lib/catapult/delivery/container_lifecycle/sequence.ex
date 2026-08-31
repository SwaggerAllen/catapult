defmodule Catapult.Delivery.ContainerLifecycle.Sequence do
  @moduledoc """
  A container's declared sequence, navigated (dsl-syntax.md §15.2-§15.8)
  — pure functions over a loaded `Catapult.Dsl.Workflow.t()`, the same
  "take the loaded bundle as a parameter" shape
  `Catapult.Delivery.FeatureLifecycle.Sequence` already uses for the
  ticket axis.

  **The array index is the only ordering mechanism** (§15.3). There is
  no `after:` to follow and no bundle-wide order to consult: "what
  comes next" is literally the next element, and the identical gate may
  sit at different relative positions in two types without either being
  wrong.

  Nothing here branches on the words "ticket", "container" or
  "milestone" (§15.2), or on an anchor's name. `setup` and `retro` get
  their behaviour from what their entries *are* — non-queue-shaped,
  non-review-shaped agent-balled entries with no `flow:` (ORC-148) — not
  from what they are called, which is the fact the grammar spent four
  passes removing and this module is careful not to put back.

  **`next_step/3`, `step/3` and `earlier?/4` resolve a name against its
  own namespace-qualified identity, not the bare name `name/1` returns
  — the identical fix `Catapult.Dsl.Workflow` already gives the ticket
  axis at §15.12, extended to this one at ORC-116** (`systems
  /delivery.md`'s own entry).

  **`identified_steps/2`, `first_identified_step/2` and
  `next_identified_step/3` are the canonical-identity half of that same
  fix, threaded through at ORC-171.** `steps/2`, `first_step/2` and
  `next_step/3` stay exactly what they were — a bare `step()`, no
  identity attached — but `Catapult.Delivery.ContainerLifecycle`'s own
  dispatcher no longer asks for a bare step and reduces it to a display
  name to populate `container.current_queue`: it asks for the
  *identified* pair instead, so what a container's own position field
  carries is `Type.namespaced_positions/1`'s own `canonical` string,
  never `Sequence.name/1`'s display label. The two stay distinct even
  once this lands — `name/1` is display, canonical is identity — and
  the ordinary case (every `types/*.yaml` this system ships avoids a
  recurring bare name across two sub-arrays) is unaffected either way:
  canonical and display coincide whenever a name does not recur.
  """

  alias Catapult.Dsl.Status
  alias Catapult.Dsl.Type
  alias Catapult.Dsl.Workflow

  @typedoc """
  What sits at one position: a queue to run, a gate waiting on a human,
  or the fixed end kind.

  An `environment:` citation is none of these — it configures the
  `deploy` entry after it (§15.5) rather than being a position anything
  rests at — so `entries/2` drops it and it never appears here.
  """
  @type step ::
          {:queue, Status.t()}
          | {:gate, String.t()}
          | :terminal

  @doc """
  The navigable steps of `type_name`'s declared array, in order.

  `[]` when the type does not resolve — a workflow cutover can retire a
  type out from under a live instance, and the caller's answer is to
  leave the container where it stands (v5 §7.19's re-resolution is
  Phase 7's, and guessing here would pre-empt it).
  """
  @spec steps(Workflow.t(), String.t()) :: [step()]
  def steps(%Workflow{} = workflow, type_name) do
    workflow |> identified_steps(type_name) |> Enum.map(&elem(&1, 1))
  end

  @doc """
  `steps/2`, each step paired with its own namespace-qualified
  canonical identity (§15.12) — `<anchor>.<name>` when this step's own
  bare name recurs elsewhere in `type_name`'s own array, bare
  otherwise. What `Catapult.Delivery.ContainerLifecycle` reads instead
  of `steps/2`'s bare list, so `container.current_queue` carries an
  identity rather than a display label (`systems/delivery.md`'s own
  ORC-171 entry).
  """
  @spec identified_steps(Workflow.t(), String.t()) :: [{String.t(), step()}]
  def identified_steps(%Workflow{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, %Type{statuses: statuses} = type} ->
        canonical_by_index =
          type |> Type.namespaced_positions() |> Map.new(&{&1.index, &1.canonical})

        statuses
        |> Enum.with_index()
        |> Enum.map(fn {entry, index} -> {to_step(entry), index} end)
        |> Enum.reject(fn {step, _index} -> is_nil(step) end)
        |> Enum.map(fn {step, index} -> {Map.fetch!(canonical_by_index, index), step} end)

      :error ->
        []
    end
  end

  @doc """
  The step a freshly activated instance starts at — its own first
  declared position (§15.8's "`setup` **is** the position, first in the
  minted instance's own sequence").

  `nil` for a type that resolves to no steps at all.
  """
  @spec first_step(Workflow.t(), String.t()) :: step() | nil
  def first_step(%Workflow{} = workflow, type_name) do
    case first_identified_step(workflow, type_name) do
      nil -> nil
      {_canonical, step} -> step
    end
  end

  @doc "`first_step/2`, paired with its own canonical identity (see `identified_steps/2`)."
  @spec first_identified_step(Workflow.t(), String.t()) :: {String.t(), step()} | nil
  def first_identified_step(%Workflow{} = workflow, type_name) do
    workflow |> identified_steps(type_name) |> List.first()
  end

  @doc """
  The step immediately after the one named `current`, or `nil` when
  `current` is the last (or is not in this type's array at all).

  `current` is matched against this type's own namespace-qualified
  identity (§15.12), not the bare `name/1` a step reads — an
  unambiguous name (the ordinary case; every `types/*.yaml` this
  system ships today) resolves exactly as before, and a name that
  recurs across more than one sub-array — indistinguishable to a bare
  lookup, `systems/delivery.md`'s own ORC-116 entry — resolves
  correctly once `current` is itself qualified `<anchor>.<name>`.
  """
  @spec next_step(Workflow.t(), String.t(), String.t()) :: step() | nil
  def next_step(%Workflow{} = workflow, type_name, current) do
    case next_identified_step(workflow, type_name, current) do
      nil -> nil
      {_canonical, step} -> step
    end
  end

  @doc """
  `next_step/3`, paired with its own canonical identity — what a caller
  dispatching *to* the next occurrence needs, not merely what kind of
  step it is (`container.current_queue`, `systems/delivery.md`'s own
  ORC-171 entry).
  """
  @spec next_identified_step(Workflow.t(), String.t(), String.t()) :: {String.t(), step()} | nil
  def next_identified_step(%Workflow{} = workflow, type_name, current) do
    identified = identified_steps(workflow, type_name)

    case Enum.find_index(identified, &(elem(&1, 0) == current)) do
      nil -> nil
      index -> Enum.at(identified, index + 1)
    end
  end

  @doc "The step named `name` (bare or namespace-qualified, `next_step/3`'s own note), or `nil`."
  @spec step(Workflow.t(), String.t(), String.t()) :: step() | nil
  def step(%Workflow{} = workflow, type_name, name) do
    workflow |> identified_steps(type_name) |> Enum.find_value(&step_if(&1, name))
  end

  defp step_if({canonical, step}, name) when canonical == name, do: step
  defp step_if(_identified, _name), do: nil

  @doc """
  The name a step is addressed by — a queue's own `status:`, a gate's
  own declared name, or `"terminal"`.
  """
  @spec name(step()) :: String.t()
  def name({:queue, %Status{status: status}}), do: status
  def name({:gate, gate}), do: gate
  def name(:terminal), do: "terminal"

  @doc """
  Whether `target` sits strictly earlier than `from` in this type's
  array — what a gate's `throwback:` has to satisfy at dispatch time
  (§15.4, §15.8).

  The loader already checked each `throwback:` target against every
  *citing* type's array (§13), so this is not a re-run of that check:
  it is the live half, answering "is this particular container's
  current position actually after the target it is being thrown back
  to," which only a running instance can be asked.
  """
  @spec earlier?(Workflow.t(), String.t(), String.t(), String.t()) :: boolean()
  def earlier?(%Workflow{} = workflow, type_name, from, target) do
    names = workflow |> identified_steps(type_name) |> Enum.map(&elem(&1, 0))

    case {Enum.find_index(names, &(&1 == from)), Enum.find_index(names, &(&1 == target))} do
      {nil, _} -> false
      {_, nil} -> false
      {from_index, target_index} -> target_index < from_index
    end
  end

  # `terminal` is matched before the generic queue clause: it is a
  # `status:` entry like any other structurally, but it carries no
  # `flow:` (§15.6 — "a fixed terminal kind, not a further queue
  # name"), so treating it as a queue would ask the dispatcher to run
  # something that does not exist.
  defp to_step(%Status{status: "terminal"}), do: :terminal
  defp to_step(%Status{status: status} = entry) when not is_nil(status), do: {:queue, entry}
  defp to_step(%Status{review: gate}) when not is_nil(gate), do: {:gate, gate}
  defp to_step(%Status{environment: env}) when not is_nil(env), do: nil
end
