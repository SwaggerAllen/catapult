defmodule Catapult.Delivery.FlagSet do
  @moduledoc """
  The port a milestone's aggregated flag flip goes out through (v5
  §2.10, §7.8) — behaviour plus the two-implementation shape
  conventions §9 requires of every external, selected by config
  exactly as `Catapult.Delivery.host_port_adapter/0` already is.

  **Aggregation, not machinery.** What ships here is the union of the
  flags a container's member work items registered, enabled together
  once the container closes clean — "features merge dark as they
  complete; the milestone lights up together." It is deliberately not
  percentage rollout, actor targeting or ops kill-switches, which
  `docs/non-goals.md` refuses outright as machinery without a customer
  at this scale.

  **Why the default implementation flips nothing yet, and why that is
  the correct behaviour rather than a stub.** Conventions §13 records a
  standing deferral — "feature flags arrive when the delivery loop
  lands multi-ticket features on the reference deployment, not
  before" — and no component in this tree declares a
  `feature_flags/0` entry today, so the aggregate is empty for every
  project that exists. `Catapult.Delivery.FlagSet.Deferred` enables an
  empty set successfully (there is nothing to enable, and reporting
  failure would hold a milestone open over a no-op) and refuses a
  non-empty one, which is the honest answer while §13's deferral
  stands: the intent is recorded, no effect is claimed, and the
  container sits visibly at `:requested` rather than being marked
  flipped on the plane's own word (v5 §7.1). Binding the real backend
  is a one-module change here when §13 lifts; nothing above this port
  changes.
  """

  @doc """
  Enables every flag in `flags`, idempotently.

  Idempotence is required of the implementation, not merely hoped for:
  this runs from an Oban worker that may retry, and §7.1's
  effect-without-record case heals by re-observation only if a second
  enable is harmless.
  """
  @callback enable([String.t()]) :: :ok | {:error, term()}

  @doc "The configured implementation — `Deferred` by default, `Fake` in test."
  @spec adapter() :: module()
  def adapter, do: Catapult.Config.fetch!(:delivery, :flag_set_adapter)

  @doc "Enables `flags` through the configured implementation."
  @spec enable([String.t()]) :: :ok | {:error, term()}
  def enable(flags), do: adapter().enable(flags)
end
