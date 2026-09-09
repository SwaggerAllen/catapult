defmodule Catapult.Delivery.Oidc.StrategyTest do
  @moduledoc """
  `init_opts/1` is all a default-suite test can reach here: the
  strategy runs with `should_start: false` in test, so it never fetches
  and the adapter is never exercised (conventions §9's no-network
  rule). That is exactly why the adapter defect this asserts against
  shipped — the module's own comment carries the argument.
  """
  use ExUnit.Case, async: true

  alias Catapult.Delivery.Oidc.Strategy

  # `JokenJwks.HttpFetcher` defaults to `Tesla.Adapter.Hackney`, which
  # `joken_jwks` declares optional and this project never took, so the
  # module is absent from the release and every fetch raises
  # `UndefinedFunctionError`. Pinning an adapter that is actually
  # present is the whole of the fix, and this is the assertion that
  # fails if a later pass drops the line as an arbitrary preference.
  test "init_opts/1 pins an HTTP adapter the release actually contains" do
    assert Strategy.init_opts([])[:http_adapter] == Tesla.Adapter.Mint
    assert Code.ensure_loaded?(Tesla.Adapter.Mint)
  end

  test "init_opts/1 still supplies the jwks url and the autostart flag" do
    opts = Strategy.init_opts([])

    assert is_binary(opts[:jwks_url])
    assert opts[:should_start] == false
  end
end
