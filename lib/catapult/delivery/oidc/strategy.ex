defmodule Catapult.Delivery.Oidc.Strategy do
  @moduledoc """
  The JWKS-fetching half of GitHub Actions OIDC verification (v5
  §7.12.1): `joken_jwks`'s own polling/caching strategy, pointed at
  GitHub's published keys. Supervised (`Catapult.Delivery.children/0`,
  `processes/0`) — this library's own moduledoc: "must be under your
  apps' supervision tree."

  `should_start: false` in test (`oidc_jwks_autostart`, `config/0`):
  the process still exists (registered, structurally exercised) but
  never fetches over the network, honoring "no network in per-ticket
  CI. Ever." (conventions §9) — a real fetch is `:live` territory, and
  nothing in the default suite's chain (the fake host port) ever calls
  through this strategy, since it never makes a real HTTP round trip.
  """

  use JokenJwks.DefaultStrategyTemplate

  alias Catapult.Config

  def init_opts(opts) do
    Keyword.merge(opts,
      jwks_url: Config.fetch!(:delivery, :oidc_jwks_url),
      should_start: Config.fetch!(:delivery, :oidc_jwks_autostart)
    )
  end
end
