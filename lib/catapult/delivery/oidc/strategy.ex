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

  # `http_adapter` is pinned because the library's default is a module
  # this release does not contain. `JokenJwks.HttpFetcher` defaults to
  # `Tesla.Adapter.Hackney` and `joken_jwks` declares `:hackney`
  # *optional*, so every JWKS fetch on the reference instance raised
  # `UndefinedFunctionError` — leaving `Catapult.Delivery.Oidc.verify/4`
  # unable to ever return `{:ok, _}` and both OIDC-authenticated routes
  # (`GET /dispatch/context/:run_key`, `POST /dispatch/report/:run_key`)
  # dead in dev and prod. The default suite cannot see this: the
  # `should_start: false` above means the strategy never fetches in
  # test, which is conventions §9's no-network rule working as intended
  # rather than a gap to close here.
  #
  # Mint over Finch because Tesla's Finch adapter needs a named,
  # supervised pool and its Mint adapter needs none; `:tesla` and
  # `:mint` are already in `mix.exs`'s boundary `apps:` and `castore`
  # is already resolved, so certificates are verified and no dependency
  # is added. Taking `:hackney` instead would also work and is what the
  # library documents, but it puts a second HTTP client in the release
  # and adds a module `Catapult.Foundation.Policies.ErlangHttp` names
  # among the clients no plane module may call.
  #
  # `HttpFetcher.new/1` reads this ahead of both `config :tesla,
  # JokenJwks.HttpFetcher` and the global `config :tesla, :adapter`, so
  # it is the one setting for this that nothing else can silently
  # override.
  def init_opts(opts) do
    Keyword.merge(opts,
      jwks_url: Config.fetch!(:delivery, :oidc_jwks_url),
      should_start: Config.fetch!(:delivery, :oidc_jwks_autostart),
      http_adapter: Tesla.Adapter.Mint
    )
  end
end
