defmodule Catapult.Delivery.FlagSet.Deferred do
  @moduledoc """
  The default `Catapult.Delivery.FlagSet` implementation: there is no
  flag backend to call yet, and this says so rather than pretending.

  Conventions §13 defers flag consumption ("feature flags arrive when
  the delivery loop lands multi-ticket features on the reference
  deployment, not before") and no component declares a
  `feature_flags/0` entry today, so every real aggregate is empty.

  * An **empty** set enables successfully. There is nothing to turn on,
    so the effect genuinely happened, and failing here would hold every
    milestone open over a no-op.
  * A **non-empty** set fails, loudly and with the reason. The intent
    stays recorded and the container sits visibly at `:requested`,
    which is exactly v5 §7.1's intent-without-effect case: visible, and
    escalates. The alternative — logging a warning and returning `:ok`
    — would write `FlagSetFlipped` on the plane's own word about a
    world it never touched, and "the log never says 'done' on the
    plane's own word" is the one thing that discipline exists to
    prevent.
  """

  @behaviour Catapult.Delivery.FlagSet

  require Logger

  @impl Catapult.Delivery.FlagSet
  def enable([]), do: :ok

  def enable(flags) when is_list(flags) do
    Logger.error(
      "flag set flip requested for #{inspect(flags)}, but no flag backend is bound " <>
        "(conventions §13 defers flag consumption) — the intent stays recorded and unflipped",
      component: :delivery
    )

    {:error, :no_flag_backend}
  end
end
