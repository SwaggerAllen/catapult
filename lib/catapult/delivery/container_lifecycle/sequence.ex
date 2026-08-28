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
  non-critique agent-balled entries with no `flow:` (ORC-148) — not
  from what they are called, which is the fact the grammar spent four
  passes removing and this module is careful not to put back.
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
  def steps(%Workflow{types: types}, type_name) do
    case Map.fetch(types, type_name) do
      {:ok, %Type{statuses: statuses}} ->
        statuses |> Enum.map(&to_step/1) |> Enum.reject(&is_nil/1)

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
    workflow |> steps(type_name) |> List.first()
  end

  @doc """
  The step immediately after the one named `current`, or `nil` when
  `current` is the last (or is not in this type's array at all).
  """
  @spec next_step(Workflow.t(), String.t(), String.t()) :: step() | nil
  def next_step(%Workflow{} = workflow, type_name, current) do
    steps = steps(workflow, type_name)

    case Enum.find_index(steps, &(name(&1) == current)) do
      nil -> nil
      index -> Enum.at(steps, index + 1)
    end
  end

  @doc "The step named `name`, or `nil`."
  @spec step(Workflow.t(), String.t(), String.t()) :: step() | nil
  def step(%Workflow{} = workflow, type_name, name) do
    workflow |> steps(type_name) |> Enum.find(&(name(&1) == name))
  end

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
    names = workflow |> steps(type_name) |> Enum.map(&name/1)

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
