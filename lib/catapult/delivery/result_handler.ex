defmodule Catapult.Delivery.ResultHandler do
  @moduledoc """
  The seam `Catapult.Delivery.Dispatch` calls into once a result-report
  is authenticated and correlated, without `delivery` ever naming
  `generation` in source (`Catapult.Generation` already depends on
  `Catapult.Delivery` for dispatch — a literal reference back would
  close the cycle `mix xref graph --format cycles --fail-above 0`
  refuses). The handler module is configured, not aliased
  (`config :catapult, :generation_result_handler`, `config/config.exs`)
  — an ordinary atom read from `Application.get_env/2` at call time,
  the same seam `Catapult.Boot`'s own `@config_source` and
  `Catapult.Application`'s `serve_health` already use, so this is
  precedent rather than a new mechanism.
  """

  @type payload :: %{
          required(:project_id) => binary(),
          required(:node_id) => binary(),
          required(:tier) => String.t(),
          required(:scope_key) => map(),
          required(:run_key) => binary(),
          required(:status) => :success | :limit_class_failure | :other_failure,
          required(:credential_used) => String.t(),
          optional(:body) => String.t() | nil,
          optional(:reason) => String.t() | nil
        }

  @callback handle_result(payload()) :: :ok | {:error, term()}
end
