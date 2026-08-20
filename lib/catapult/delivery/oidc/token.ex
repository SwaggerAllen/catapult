defmodule Catapult.Delivery.Oidc.Token do
  @moduledoc """
  The claim-shape half of GitHub Actions OIDC verification: signature
  and freshness only (issuer, audience, expiry). Repository and
  `run_id` matching against the plane's own dispatch record is
  `Catapult.Delivery.Oidc.verify/4`'s job, over the claims this module
  returns — those two are per-request facts this static config cannot
  see.
  """

  use Joken.Config

  alias Catapult.Config

  add_hook(JokenJwks, strategy: Catapult.Delivery.Oidc.Strategy)

  @github_issuer "https://token.actions.githubusercontent.com"

  @impl Joken.Config
  def token_config do
    default_claims(iss: @github_issuer, aud: Config.fetch!(:delivery, :oidc_audience))
  end
end
