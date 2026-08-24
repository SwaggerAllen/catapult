defmodule Catapult.Delivery.FeatureLifecycle.Sequence do
  @moduledoc """
  The feature-ticket lifecycle's effective sequence (v5 §7.10,
  `systems/delivery.md`'s ORC-32 design pass): `queue → generation →
  [critique] → [gate] → … → fanout`, built from a loaded
  `Catapult.Dsl.Workflow.t()` rather than resolved by this module —
  the same "take the loaded bundle as a parameter" shape
  `Catapult.Engine.Projections.ReadyScopes.ready/3` and
  `Catapult.Engine.Scheduler.trigger/2` already establish for the
  chain axis.

  Written against `Catapult.Dsl.SystemStatus` and `Catapult.Dsl
  .Workflow` as they stand on this branch — twelve system-status
  kinds, gates positioned by a named `after:` predecessor — not
  against `dsl-syntax.md`'s own target shape (`pending`, container
  skeletons, inline `statuses:` arrays), which is unbuilt
  (`systems/delivery.md`'s own reachability bullet records this
  explicitly, so the divergence is on purpose here too).

  **Reachability, settled** (`systems/delivery.md`, ORC-32 design
  pass): `fanout` (Building) is this phase's last reachable status.
  `checks`, `merge`, `deploy`, `validating` and `terminal` are real
  kinds (`Catapult.Dsl.SystemStatus`'s closed table fixes all twelve
  up front) but sit behind the child lifecycle/mutex/dispatch/
  reconciliation machinery Phase 7 builds, so this module never
  places one in the sequence it returns — a workflow bundle declaring
  gates or environments after `deploy` still loads and validates
  (dsl-syntax.md §13); this module simply never reaches them.

  Environments are absent from the sequence for the same reason:
  every declared environment's own `after:` sits at `merge` or later
  (dsl-syntax.md §15.4's own example — a deploy target has to be
  configured before anything can deploy into it), which is already
  past this phase's reachable range.
  """

  alias Catapult.Dsl.Critique
  alias Catapult.Dsl.SystemStatus
  alias Catapult.Dsl.Workflow

  @typedoc "One stop in the effective sequence: a fixed system-status kind, or a declared gate by its own name."
  @type position :: {:kind, SystemStatus.kind()} | {:gate, String.t()}

  @doc """
  The ordered, reachable positions for `workflow`: `:queue`,
  `:generation`, `:critique` (only when the loaded workflow declares
  `critique.yaml` — presence is participation, dsl-syntax.md §15.5),
  every gate reachable by following `after:` from `"generation"`, in
  order, and finally `:fanout`.

  A gate whose `after:` chain does not lead back to `"generation"`
  (e.g. one anchored on `checks` or later) is outside this phase's
  reachable range and is not included — this module recognizes the
  later kinds (`SystemStatus.kinds/0` still lists them) without ever
  routing a ticket into one, exactly as `systems/delivery.md`'s
  reachability bullet settles.
  """
  @spec positions(Workflow.t()) :: [position()]
  def positions(%Workflow{} = workflow) do
    [{:kind, :queue}, {:kind, :generation}] ++
      critique_position(workflow) ++
      gate_positions(workflow) ++
      [{:kind, :fanout}]
  end

  defp critique_position(%Workflow{critique: nil}), do: []
  defp critique_position(%Workflow{critique: %Critique{}}), do: [{:kind, :critique}]

  defp gate_positions(%Workflow{gates: gates}) do
    by_after = Map.new(gates, fn {name, gate} -> {gate.after, name} end)

    "generation"
    |> walk_gates(by_after, [])
    |> Enum.reverse()
    |> Enum.map(&{:gate, &1})
  end

  defp walk_gates(anchor, by_after, acc) do
    case Map.fetch(by_after, anchor) do
      {:ok, name} -> walk_gates(name, by_after, [name | acc])
      :error -> acc
    end
  end
end
