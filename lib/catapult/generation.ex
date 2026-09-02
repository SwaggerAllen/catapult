defmodule Catapult.Generation do
  @moduledoc """
  The plane's design-dialect coordination (`systems/generation.md`):
  takes ready `(tier, scope)` pairs from `ready_scopes`, assembles and
  renders context, dispatches an agent run via the host port, and
  validates the committed body against the tier's grammar when the
  agent reports.
  """

  use Catapult.Component, slug: :generation

  alias Catapult.Generation.Runtime

  @impl Catapult.Component
  def licensing, do: [distribution: :service, license: "AGPL-3.0-only"]

  @impl Catapult.Component
  def config do
    [
      # The bundle root generation renders context from — the same
      # value engine's own sweeper reads (`Catapult.Engine`'s
      # `config/0`), duplicated here rather than cross-read because
      # each component owns its own copy of a build-shape constant
      # (`systems/foundation.md`'s build-shape/instance-shape line);
      # both default identically.
      {:bundles_root, "GENERATION_BUNDLES_ROOT", cast: :string, default: "."},
      # The sweep cadence (v5 §7.15: "resume is re-asking the
      # readiness question") — `tunable` as a config constant, the
      # same accepted-for-now shape `ENGINE_SWEEPER_INTERVAL_MS`
      # already carries (`Catapult.Engine`'s own `config/0`): no
      # plane-state/bindings storage exists anywhere in this codebase
      # yet to hold a true per-instance tunable.
      {:sweep_interval_ms, "GENERATION_SWEEP_INTERVAL_MS", cast: :integer, default: "10000"},
      # The bindings entry for the `:generation` kind (v5 §7.10,
      # generalized here — `systems/generation.md`'s ORC-215 entry):
      # which agent implementation runs every generation dispatch,
      # project-wide. `Catapult.Generation.Runtime` is the kind →
      # runtime map; adding a second implementation is a new entry
      # there, not a new config key here.
      {:runtime, "GENERATION_RUNTIME", cast: &Runtime.cast/1, default: "claude_code"},
      # The model-credential pair's order (v5 §7.12.1's bindings
      # `tunable`) — instance-wide rather than per-project for the
      # same reason: no `projects` entity exists anywhere in this
      # store to hang a per-project override on
      # (`systems/engine.md`'s own "a different, not-yet-built
      # concern"). The full ordered pair is sent on every dispatch as
      # of ORC-215 — Catapult's own runner harness classifies
      # limit-class failures itself, retiring ORC-9's
      # no-failover workaround.
      {:credential_order, "GENERATION_CREDENTIAL_ORDER",
       cast: &__MODULE__.cast_credential_order/1,
       default: "claude_code_oauth_token,anthropic_api_key"},
      # The command edge's injected clock (conventions §9 — no
      # `DateTime.utc_now/0` in domain code): real-vs-fake selection
      # rides config like every other adapter choice (v5 §2.12), the
      # same shape `Catapult.Delivery`'s `host_port_adapter` already
      # is.
      {:clock, "GENERATION_CLOCK", cast: &__MODULE__.cast_clock/1, default: "system"}
    ]
  end

  @doc "Casts a comma-separated credential-name list, validated against `Catapult.Generation.Runtime`'s known names."
  @spec cast_credential_order(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def cast_credential_order(raw) do
    names = raw |> String.split(",") |> Enum.map(&String.trim/1)

    if names != [] and Enum.all?(names, &Runtime.known_credential_name?/1) do
      {:ok, names}
    else
      {:error,
       "is #{inspect(raw)}, expected a comma-separated list from " <>
         inspect(Runtime.known_credential_names())}
    end
  end

  @doc "Casts the configured clock name to its module."
  @spec cast_clock(String.t()) :: {:ok, module()} | {:error, String.t()}
  def cast_clock("system"), do: {:ok, Catapult.Clock.System}
  def cast_clock("fake"), do: {:ok, Catapult.Generation.Clock.Fake}
  def cast_clock(other), do: {:error, "is #{inspect(other)}, expected \"system\" or \"fake\""}

  @impl Catapult.Component
  def oban_queues, do: [:generation_dispatch]

  @impl Catapult.Component
  def processes do
    [{:generation_sweeper, :singleton}]
  end

  @impl Catapult.Component
  def children do
    [Catapult.Generation.Sweeper]
  end
end
