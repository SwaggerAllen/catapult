defmodule Catapult.Config.Env do
  @moduledoc """
  The shipped config source: process environment variables (12-factor,
  and the transport every deployment has).

  It takes no settings, and it cannot fail — the environment always
  answers, so every problem this source can produce is a problem about
  a *value*, which the layer reports per declaration. `Map.take/2` is
  load-bearing rather than tidy: the source answers only for names that
  were declared, so nothing enters the system that the registry does not
  name.

  This is also, entire, what a config library would have contributed to
  the path this platform actually needs — the reason Vapor is not a
  substrate dependency (systems/substrate.md).
  """

  @behaviour Catapult.Config.Source

  @impl Catapult.Config.Source
  def load(names, _opts) do
    {:ok, Map.take(System.get_env(), names)}
  end
end
