import Config

if config_env() == :prod do
  config :catapult, Catapult.Repo,
    url: System.fetch_env!("DATABASE_URL"),
    pool_size: String.to_integer(System.get_env("POOL_SIZE", "10"))

  config :catapult,
    serve_health: true,
    health_port: String.to_integer(System.get_env("PORT", "4000"))
end
