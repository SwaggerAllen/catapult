import Config

if config_env() == :prod do
  # DO managed Postgres injects a URL ending in `?sslmode=require`.
  # Ecto's URL parser rejects `sslmode` as an option, so the query
  # string is stripped and TLS configured explicitly. verify_none is
  # deliberate for now: the bindable URL points at the cluster over
  # DO's network, and certificate pinning is recorded follow-up work
  # (the maintenance lane), not a boot blocker.
  db_url = System.fetch_env!("DATABASE_URL")
  [base_url | _query] = String.split(db_url, "?", parts: 2)
  ssl? = String.contains?(db_url, "sslmode=require")

  config :catapult, Catapult.Repo,
    url: base_url,
    ssl: if(ssl?, do: [verify: :verify_none], else: false),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  # Deliberately HEALTH_PORT, not PORT: this is the app's HTTP
  # listener (the health endpoint). App Platform routes public
  # traffic to 8080 and that isn't changeable in its UI, so 8080 is
  # the prod default; HEALTH_PORT exists as the explicit override.
  config :catapult,
    serve_health: true,
    health_port: String.to_integer(System.get_env("HEALTH_PORT", "8080"))
end
